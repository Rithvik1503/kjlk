-- Aura: bucketed means split by zone, for the Trends screen's Areas section.
--
-- Required by that section. `aura_metric_buckets` groups across every zone, which answers
-- "how has the air been" but not "how has the bedroom been" — this adds the second axis.
--
-- Only CO2 and humidity: those are what the section shows, and a narrower row keeps six
-- months of several zones to something a phone wants to parse.
--
-- Rows recorded before the zone column existed group under 'Unlabelled' rather than being
-- dropped, so a project with history still has something to show here.

create or replace function public.aura_zone_buckets(
  p_from   timestamptz,
  p_to     timestamptz,
  p_unit   text    default 'day',     -- 'day' or 'month'
  p_tz     text    default 'UTC',     -- IANA name, e.g. 'Europe/London'
  p_device text    default null
)
returns table (
  bucket           timestamptz,
  zone             text,
  co2_ppm          double precision,
  humidity_percent double precision,
  sample_count     bigint
)
language sql
stable
security invoker          -- so row level security still scopes this to the caller's rows
set search_path = public
as $$
  select
    (date_trunc(p_unit, r.recorded_at at time zone p_tz) at time zone p_tz) as bucket,
    coalesce(nullif(trim(r.zone), ''), 'Unlabelled') as zone,
    avg(r.co2_ppm)::double precision,
    avg(r.humidity_percent),
    count(*)
  from public.readings r
  where r.recorded_at >= p_from
    and r.recorded_at <  p_to
    and (p_device is null or r.device_id = p_device)
    -- date_trunc takes its unit as text, so the value is pinned here rather than passed
    -- through unchecked.
    and p_unit in ('day', 'month')
  group by 1, 2
  order by 2, 1;
$$;

comment on function public.aura_zone_buckets is
  'Per-day or per-month CO2 and humidity means per zone, for the calling user, bucketed in p_tz.';
