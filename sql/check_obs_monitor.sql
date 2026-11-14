-- Acceptance A1: run AS obs_monitor in the Odoo database.
-- Its spec: the round 1 spec. No repo path here: nothing sent to a server names the repo.
-- Every line it prints starts with "ok:"; any failure stops it with "FAIL:" or a Postgres error.
--
--   PGPASSWORD=$(terraform -chdir=terraform/envs/dev output -raw obs_monitor_password) \
--     psql "host=<server> dbname=<db> user=obs_monitor sslmode=require" -X -v ON_ERROR_STOP=1 -f sql/check_obs_monitor.sql

SET client_min_messages = notice;
DO $$
DECLARE
  n bigint;
BEGIN
  IF current_user <> 'obs_monitor' THEN
    RAISE EXCEPTION 'FAIL: run as obs_monitor, not %', current_user;
  END IF;

  SELECT count(*) INTO n FROM public.queue_job;
  RAISE NOTICE 'ok: SELECT on queue_job (% rows)', n;
  SELECT count(*) INTO n FROM public.ir_cron;
  RAISE NOTICE 'ok: SELECT on ir_cron (% rows)', n;

  BEGIN
    SELECT count(*) INTO n FROM public.res_users;
    RAISE EXCEPTION 'FAIL: SELECT on res_users was allowed';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'ok: SELECT on res_users denied (%)', SQLERRM;
  END;

  BEGIN
    UPDATE public.ir_cron SET active = active WHERE false;
    RAISE EXCEPTION 'FAIL: UPDATE on ir_cron was allowed';
  EXCEPTION WHEN read_only_sql_transaction OR insufficient_privilege THEN
    RAISE NOTICE 'ok: UPDATE on ir_cron denied (%)', SQLERRM;
  END;

  IF current_setting('default_transaction_read_only') <> 'on'
     OR current_setting('statement_timeout') <> '10s'
     OR current_setting('lock_timeout') <> '1s' THEN
    RAISE EXCEPTION 'FAIL: settings read_only=%, statement_timeout=%, lock_timeout=%',
      current_setting('default_transaction_read_only'), current_setting('statement_timeout'),
      current_setting('lock_timeout');
  END IF;
  RAISE NOTICE 'ok: read only, statement_timeout 10s, lock_timeout 1s';

  IF pg_has_role(current_user, 'pg_read_all_data', 'USAGE') OR pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') THEN
    RAISE EXCEPTION 'FAIL: obs_monitor holds pg_read_all_data or pg_read_all_stats';
  END IF;
  RAISE NOTICE 'ok: no pg_read_all_data, no pg_read_all_stats';
END $$;
