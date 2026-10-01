-- Aura: bucketed means for the Trends screen.
--
-- Required by Trends. Six months of minute-resolution readings is a quarter of a million
-- rows; the screen needs six numbers from them. Everything below aggregates in Postgres and
-- returns one row per bucket.
--
-- Buckets are cut in the caller's own time zone, so "Tuesday" means the Tuesday they lived
-- through rather than the one UTC did. The bucket comes back as the absolute instant of local
-- midnight, which is what the app formats and plots against.

create or replace function public.aura_metric_buckets(
  p_from   timestamptz,
  p_to     timestamptz,
  p_unit   text    default 'day',     -- 'day' or 'month'
  p_tz     text    default 'UTC',     -- IANA name, e.g. 'Europe/London'
  p_device text    default null
)
returns table (
  bucket           timestamptz,
  co2_ppm          double precision,
  temperature_c    double precision,
  humidity_percent double precision,
  light_lux        double precision,
  sample_count     bigint
)
language sql
stable
security invoker          -- so row level security still scopes this to the caller's rows
set search_path = public
as $$
  select
    (date_trunc(p_unit, r.recorded_at at time zone p_tz) at time zone p_tz) as bucket,
    avg(r.co2_ppm)::double precision,
    avg(r.temperature_c),
    avg(r.humidity_percent),
    avg(r.light_lux),
    count(*)
  from public.readings r
  where r.recorded_at >= p_from
    and r.recorded_at <  p_to
    and (p_device is null or r.device_id = p_device)
    -- Only 'day' and 'month' are offered, and date_trunc takes the unit as text, so the
    -- value is pinned here rather than passed through to it unchecked.
    and p_unit in ('day', 'month')
  group by 1
  order by 1;
$$;

comment on function public.aura_metric_buckets is
  'Per-day or per-month means of each sensor for the calling user, bucketed in p_tz.';
