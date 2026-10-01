-- Aura: average temperature over a window, for the "hotter / colder than usual" comparison.
--
-- Optional. Without it the thermal card falls back to describing the day on its own terms
-- ("Comfortable", "Warm"), so the app works either way — this just gives it something to
-- compare against.
--
-- Doing the average in Postgres rather than on the phone matters: a week of minute-resolution
-- readings is around ten thousand rows, and the app only needs one number from them.

create or replace function public.aura_average_temperature(
  p_from   timestamptz,
  p_to     timestamptz,
  p_device text default null
)
returns double precision
language sql
stable
security invoker          -- so row level security still scopes this to the caller's rows
set search_path = public
as $$
  select avg(temperature_c)
  from public.readings
  where recorded_at >= p_from
    and recorded_at <  p_to
    and (p_device is null or device_id = p_device);
$$;

comment on function public.aura_average_temperature is
  'Mean temperature_c over [p_from, p_to) for the calling user, optionally one device.';
