-- Aura: schema the ESP32 writes into and the iOS app reads from.
--
-- Safe to run against a project that already has a `readings` table — every statement is
-- guarded, so this fills in whatever is missing rather than replacing what you have.
--
-- Run it in the Supabase SQL editor, or with `supabase db push`.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.readings (
  id            bigint generated always as identity primary key,
  owner_id      uuid        not null references auth.users (id) on delete cascade,
  device_id     text        not null default 'esp32-room-1',
  recorded_at   timestamptz not null default now(),
  co2_ppm       integer,
  temperature_c double precision,
  humidity_percent double precision,
  light_lux     double precision,
  created_at    timestamptz not null default now()
);

-- Backfill for an existing table created before this migration.
alter table public.readings add column if not exists device_id text not null default 'esp32-room-1';
alter table public.readings add column if not exists recorded_at timestamptz not null default now();
alter table public.readings add column if not exists co2_ppm integer;
alter table public.readings add column if not exists temperature_c double precision;
alter table public.readings add column if not exists humidity_percent double precision;
alter table public.readings add column if not exists light_lux double precision;
alter table public.readings add column if not exists created_at timestamptz not null default now();

-- Reject readings that are physically impossible. A disconnected sensor reports wild values,
-- and one bad row rescales every chart in the app.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'readings_plausible_values'
  ) then
    alter table public.readings add constraint readings_plausible_values check (
      (co2_ppm is null or co2_ppm between 0 and 60000)
      and (temperature_c is null or temperature_c between -50 and 100)
      and (humidity_percent is null or humidity_percent between 0 and 100)
      and (light_lux is null or light_lux between 0 and 200000)
    );
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Every query the app makes is "my rows, this device, this time window, newest first".
create index if not exists readings_owner_device_time_idx
  on public.readings (owner_id, device_id, recorded_at desc);

create index if not exists readings_owner_time_idx
  on public.readings (owner_id, recorded_at desc);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.readings enable row level security;

-- Readers only ever see their own rows. The edge function writes with the service role key,
-- which bypasses RLS, so there is deliberately no insert policy for ordinary users: nothing
-- but the device path can add readings.
drop policy if exists "Owners read their readings" on public.readings;
create policy "Owners read their readings"
  on public.readings
  for select
  to authenticated
  using (auth.uid() = owner_id);

drop policy if exists "Owners delete their readings" on public.readings;
create policy "Owners delete their readings"
  on public.readings
  for delete
  to authenticated
  using (auth.uid() = owner_id);

-- ---------------------------------------------------------------------------
-- Device summary
-- ---------------------------------------------------------------------------

-- Backs the device picker in Settings. Declared security_invoker so the caller's RLS applies
-- — without it the view would happily show every account's devices.
create or replace view public.device_summary
with (security_invoker = true) as
  select
    owner_id,
    device_id,
    count(*)            as reading_count,
    min(recorded_at)    as first_seen_at,
    max(recorded_at)    as last_seen_at
  from public.readings
  group by owner_id, device_id;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

-- Lets the app receive new rows over a websocket instead of polling. Realtime still applies
-- the policies above, so a subscriber only receives rows it could have selected.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'readings'
    ) then
      alter publication supabase_realtime add table public.readings;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Retention (optional)
-- ---------------------------------------------------------------------------

-- A reading a minute is about 525k rows a year per device, which is fine for Postgres but
-- adds up on the free tier. Call this from pg_cron if you want a rolling window:
--
--   select cron.schedule('aura-prune', '0 4 * * *', $$ select public.prune_readings(365) $$);

create or replace function public.prune_readings(keep_days integer default 365)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.readings
  where owner_id = auth.uid()
    and recorded_at < now() - make_interval(days => keep_days);

  get diagnostics removed = row_count;
  return removed;
end $$;
