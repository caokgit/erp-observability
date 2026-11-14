-- The monitoring role of round 1.
-- Its spec: the round 1 spec. No repo path here: nothing sent to a server names the repo.
-- Run as the server's admin, in each Odoo database the job reads; safe to run again:
--
--   export OBS_MONITOR_VERIFIER=$(terraform -chdir=terraform/envs/dev output -raw obs_monitor_password | python3 sql/scram.py)
--   psql service=<admin service> -X -v ON_ERROR_STOP=1 -f sql/obs_monitor.sql
--
-- The role is server-wide (created once, its settings apply in every database); the grants are per database.
-- Undo: sql/obs_monitor_teardown.sql.

\getenv verifier OBS_MONITOR_VERIFIER
\if :{?verifier}
\else
  \echo 'OBS_MONITOR_VERIFIER is not set: see the header of this file'
  \quit
\endif

SELECT NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'obs_monitor') AS role_is_new \gset
\if :role_is_new
  CREATE ROLE obs_monitor LOGIN NOINHERIT CONNECTION LIMIT 2 PASSWORD :'verifier';
\else
  ALTER ROLE obs_monitor LOGIN NOINHERIT CONNECTION LIMIT 2 PASSWORD :'verifier';
\endif

ALTER ROLE obs_monitor SET default_transaction_read_only = on;
ALTER ROLE obs_monitor SET statement_timeout = '10s';
ALTER ROLE obs_monitor SET lock_timeout = '1s';

SELECT format('GRANT CONNECT ON DATABASE %I TO obs_monitor', current_database()) \gexec
GRANT USAGE ON SCHEMA public TO obs_monitor;
GRANT SELECT ON TABLE public.queue_job, public.ir_cron TO obs_monitor;

-- What the role holds now, for the runbook
SELECT rolname, rolcanlogin, rolinherit, rolconnlimit, rolconfig
  FROM pg_roles WHERE rolname = 'obs_monitor';
SELECT table_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE grantee = 'obs_monitor' ORDER BY 1, 2;
