-- Aura: push notifications that fire with the app closed.
--
-- The app's own notifications are local — they are evaluated when the app loads data, so they
-- only ever arrive while it is running. These two tables let a scheduled job do the same
-- evaluation server-side and push the result through APNs.
--
-- Run this in the SQL editor, then 0007_push_cron.sql once the function is deployed.

-- ---------------------------------------------------------------------------
-- Device tokens
-- ---------------------------------------------------------------------------
--
-- One row per installation. The token changes when the app is reinstalled or restored onto a
-- new phone, so the app upserts on every launch and APNs tells us which ones have died.

create table if not exists public.push_devices (
  token       text primary key,
  owner_id    uuid        not null references auth.users (id) on delete cascade,
  -- 'sandbox' for a development build, 'production' for TestFlight and the App Store. They
  -- are different APNs hosts and a token is only valid against the one it was issued for.
  environment text        not null default 'sandbox'
                check (environment in ('sandbox', 'production')),
  updated_at  timestamptz not null default now()
);

create index if not exists push_devices_owner_idx on public.push_devices (owner_id);

alter table public.push_devices enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'push_devices' and policyname = 'push_devices_own_rows'
  ) then
    create policy push_devices_own_rows on public.push_devices
      for all
      using (owner_id = auth.uid())
      with check (owner_id = auth.uid());
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Alert state
-- ---------------------------------------------------------------------------
--
-- What each metric was last alerted at, so a value hovering on a threshold can't buzz the
-- phone every time the job runs. The band is the index into the app's own severity bands.

create table if not exists public.push_alert_state (
  owner_id    uuid        not null references auth.users (id) on delete cascade,
  device_id   text        not null,
  metric      text        not null,
  band        integer     not null,
  notified_at timestamptz not null default now(),
  primary key (owner_id, device_id, metric)
);

alter table public.push_alert_state enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'push_alert_state' and policyname = 'push_alert_state_own_rows'
  ) then
    create policy push_alert_state_own_rows on public.push_alert_state
      for all
      using (owner_id = auth.uid())
      with check (owner_id = auth.uid());
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- What the job reads
-- ---------------------------------------------------------------------------
--
-- The alerting function needs two readings per device: the newest, and one from about an hour
-- ago to compare it against. Doing that selection here keeps the function from pulling an
-- hour of 5-second samples across the wire to use two of them.
--
-- `security definer` deliberately: the caller is a scheduled job running as the service role,
-- which has no `auth.uid()`, and the function needs to see every owner's rows to alert them.
-- It returns only aggregates of readings, nothing else.

create or replace function public.aura_alert_candidates()
returns table (
  owner_id     uuid,
  device_id    text,
  recorded_at  timestamptz,
  co2_now      double precision,
  temp_now     double precision,
  humidity_now double precision,
  light_now    double precision,
  co2_then     double precision,
  temp_then    double precision,
  humidity_then double precision,
  light_then   double precision
)
language sql
stable
security definer
set search_path = public
as $$
  with devices as (
    select r.owner_id, r.device_id, max(r.recorded_at) as recorded_at
    from public.readings r
    where r.recorded_at > now() - interval '20 minutes'
    group by r.owner_id, r.device_id
  ),
  -- Averaged over a few minutes rather than taken from one row, so a single odd sample
  -- can't push a band on its own.
  recent as (
    select d.owner_id, d.device_id, d.recorded_at,
           avg(r.co2_ppm)::double precision      as co2_now,
           avg(r.temperature_c)                  as temp_now,
           avg(r.humidity_percent)               as humidity_now,
           avg(r.light_lux)                      as light_now
    from devices d
    join public.readings r
      on r.owner_id = d.owner_id
     and r.device_id = d.device_id
     and r.recorded_at > d.recorded_at - interval '5 minutes'
    group by d.owner_id, d.device_id, d.recorded_at
  ),
  earlier as (
    select d.owner_id, d.device_id,
           avg(r.co2_ppm)::double precision      as co2_then,
           avg(r.temperature_c)                  as temp_then,
           avg(r.humidity_percent)               as humidity_then,
           avg(r.light_lux)                      as light_then
    from devices d
    join public.readings r
      on r.owner_id = d.owner_id
     and r.device_id = d.device_id
     and r.recorded_at between d.recorded_at - interval '65 minutes'
                           and d.recorded_at - interval '55 minutes'
    group by d.owner_id, d.device_id
  )
  select recent.owner_id, recent.device_id, recent.recorded_at,
         recent.co2_now, recent.temp_now, recent.humidity_now, recent.light_now,
         earlier.co2_then, earlier.temp_then, earlier.humidity_then, earlier.light_then
  from recent
  join earlier using (owner_id, device_id);
$$;

-- Only the scheduled job may call it. Nothing signed in through the app has any use for it,
-- and it reads across owners.
revoke all on function public.aura_alert_candidates() from public, anon, authenticated;
grant execute on function public.aura_alert_candidates() to service_role;
