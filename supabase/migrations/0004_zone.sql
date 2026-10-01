-- Aura: where the monitor was when a reading was taken.
--
-- Required for the zone button. Run this BEFORE deploying the updated edge function or
-- flashing the new firmware — the column is nullable, so a device that doesn't send a zone
-- keeps working either side of the change.
--
-- Per reading rather than per device: moving the monitor from a bedroom to a balcony
-- shouldn't retroactively relabel everything it recorded indoors.

alter table public.readings add column if not exists zone text;

comment on column public.readings.zone is
  'Label the device was set to when this reading was taken, e.g. "Outdoor". Null if unset.';
