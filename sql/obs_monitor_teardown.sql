-- Teardown of the monitoring role.
-- Its spec: the round 1 spec. No repo path here: nothing sent to a server names the repo.
-- Run as the server's admin in each database where sql/obs_monitor.sql ran; in the last one, add -v drop=1
-- to drop the role itself (DROP ROLE fails while any database still grants it something):
--
--   psql service=<admin service> -X -v ON_ERROR_STOP=1 [-v drop=1] -f sql/obs_monitor_teardown.sql

SELECT EXISTS (SELECT FROM pg_roles WHERE rolname = 'obs_monitor') AS role_exists \gset
\if :role_exists
  REVOKE SELECT ON TABLE public.queue_job, public.ir_cron FROM obs_monitor;
  REVOKE USAGE ON SCHEMA public FROM obs_monitor;
  SELECT format('REVOKE CONNECT ON DATABASE %I FROM obs_monitor', current_database()) \gexec
  \if :{?drop}
    DROP ROLE obs_monitor;
  \endif
\else
  \echo 'no role obs_monitor: nothing to remove'
\endif

SELECT count(*) AS obs_monitor_roles_left FROM pg_roles WHERE rolname = 'obs_monitor';
