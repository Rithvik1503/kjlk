-- Aura: the schedule that drives push notifications.
--
-- Run this LAST — after 0006_push.sql, and after `supabase functions deploy push-alerts`.
--
-- Two values below have to be filled in before you run it. Both are on the Supabase
-- dashboard: Project Settings -> API.
--
--   1. your project ref (the subdomain of your project URL)
--   2. your service role key
--
-- The service role key is a master key for your database. This stores it in Vault rather
-- than inside the job definition, so it isn't sitting in plain text in `cron.job` for anyone
-- with database access to read.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- Fill these in
-- ---------------------------------------------------------------------------

do $$
declare
  project_ref      text := 'YOUR_PROJECT_REF';
  service_role_key text := 'YOUR_SERVICE_ROLE_KEY';
begin
  if project_ref = 'YOUR_PROJECT_REF' or service_role_key = 'YOUR_SERVICE_ROLE_KEY' then
    raise exception 'Fill in project_ref and service_role_key at the top of this file first.';
  end if;

  -- Replaces the secrets if this is re-run, rather than piling up copies.
  delete from vault.secrets where name in ('aura_function_url', 'aura_service_role_key');

  perform vault.create_secret(
    'https://' || project_ref || '.supabase.co/functions/v1/push-alerts',
    'aura_function_url'
  );
  perform vault.create_secret(service_role_key, 'aura_service_role_key');
end $$;

-- ---------------------------------------------------------------------------
-- The job
-- ---------------------------------------------------------------------------
--
-- Every 15 minutes. The function itself won't alert on the same metric twice within an hour,
-- so this sets how quickly a change is noticed, not how often the phone buzzes.

select cron.unschedule('aura-push-alerts')
where exists (select 1 from cron.job where jobname = 'aura-push-alerts');

select cron.schedule(
  'aura-push-alerts',
  '*/15 * * * *',
  $job$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'aura_function_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'aura_service_role_key')
      ),
      body    := '{}'::jsonb,
      timeout_milliseconds := 20000
    );
  $job$
);

-- How it's going:
--
--   select * from cron.job where jobname = 'aura-push-alerts';
--   select * from cron.job_run_details order by start_time desc limit 10;
--   select * from net._http_response order by created desc limit 10;
--
-- To stop it:  select cron.unschedule('aura-push-alerts');
