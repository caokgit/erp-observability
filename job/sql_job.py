#!/usr/bin/env python3
"""The SQL job of round 1, the observability track. This file ships in the image: it names no repo path.

One run: read Odoo's queue_job (round 7: also when each job could run, and the jobs found dead) and ir_cron, and the statistics of the 20 tables with the most dead rows (round 2), with
the read-only role obs_monitor, then send the rows to four custom tables through the Data Collection Rule (Logs
Ingestion API). The heartbeat row goes last and only when every step
succeeded, so a missing heartbeat means the database, the identity or the ingestion failed (rule H).

Environment:
  OBS_ENV                     dev | stg: written into every row, read by the rules
  PGHOST PGDATABASE PGUSER    libpq's own variables; PGPASSWORD from the job's secret
  DCR_ENDPOINT                the DCR's logs ingestion endpoint
  DCR_IMMUTABLE_ID            the DCR's immutable id
  AZURE_CLIENT_ID             the job's user-assigned identity; unset locally, where the Azure CLI's login is used

  python3 sql_job.py            one run
  python3 sql_job.py --dry-run  one run, rows printed as JSON lines, nothing sent
"""
import datetime as dt
import json
import os
import sys
import time
import uuid

JOB_VERSION = "4"

STREAMS = {  # stream name in the DCR -> rows
    "queue": "Custom-OdooQueue",
    "cron": "Custom-OdooCron",
    "tables": "Custom-OdooTables",
    "heartbeat": "Custom-OdooHeartbeat",
}

# Jobs waiting or running, by state and channel, with the oldest creation time (index scan on state)
SQL_BACKLOG = """
SELECT state, coalesce(channel, '') AS channel, count(*) AS n,
       extract(epoch FROM (now() AT TIME ZONE 'UTC') - min(date_created))::float8 AS oldest_age_s
  FROM public.queue_job
 WHERE state IN ('pending', 'enqueued', 'started', 'wait_dependencies')
 GROUP BY 1, 2
"""

# Per channel, jobs that may run now and how long they have waited since they could (a postponed job from its eta),
# and jobs running and their longest current attempt (round 7: the backlog's age above is since creation)
SQL_READY = """
SELECT 'ready' AS state, coalesce(channel, '') AS channel, count(*) AS n,
       extract(epoch FROM max((now() AT TIME ZONE 'UTC') - greatest(date_created, coalesce(eta, date_created))))::float8
  FROM public.queue_job
 WHERE state IN ('pending', 'enqueued') AND (eta IS NULL OR eta <= (now() AT TIME ZONE 'UTC'))
 GROUP BY 2
UNION ALL
SELECT 'running', coalesce(channel, ''), count(*),
       extract(epoch FROM (now() AT TIME ZONE 'UTC') - min(date_started))::float8
  FROM public.queue_job
 WHERE state = 'started'
 GROUP BY 2
"""

# Jobs found dead (their worker ended mid-run; queue_job's runner failed them after too many re-queues) whose last
# attempt started in the last 24 h, by model and method (round 7); queue_job records no time of failure
SQL_DEAD = """
SELECT coalesce(model_name, '') AS model, coalesce(method_name, '') AS method, count(*) AS n
  FROM public.queue_job
 WHERE state = 'failed' AND exc_name = 'JobFoundDead'
   AND date_started >= (now() AT TIME ZONE 'UTC') - interval '24 hours'
 GROUP BY 1, 2
"""

# Jobs that failed in the last hour, by model and method (index scan on state); a failed job keeps date_started
SQL_FAILED = """
SELECT coalesce(model_name, '') AS model, coalesce(method_name, '') AS method, count(*) AS n
  FROM public.queue_job
 WHERE state = 'failed' AND date_started >= (now() AT TIME ZONE 'UTC') - interval '1 hour'
 GROUP BY 1, 2
"""

# Lock waits in progress in this database (round 4): pg_locks is readable by every role and gives each waiting
# process's waitstart (PostgreSQL 14+); pg_stat_activity only for the database name, which every role may read
SQL_LOCKS = """
SELECT count(DISTINCT l.pid) AS waiting,
       coalesce(max(extract(epoch FROM clock_timestamp() - l.waitstart)), 0)::float8 AS longest_s
  FROM pg_locks l
  JOIN pg_stat_activity a ON a.pid = l.pid
 WHERE NOT l.granted AND l.waitstart IS NOT NULL AND a.datname = current_database()
"""

# The table's size from the catalog: no scan
SQL_TABLE = """
SELECT c.reltuples::bigint AS est_rows, pg_total_relation_size(c.oid) AS total_bytes
  FROM pg_class c
 WHERE c.oid = 'public.queue_job'::regclass
"""

# Active scheduled tasks; Odoo stores naive UTC timestamps
SQL_CRON = """
SELECT id, coalesce(cron_name, '') AS name, interval_number, interval_type, nextcall, lastcall,
       coalesce(failure_count, 0) AS failure_count,
       extract(epoch FROM (now() AT TIME ZONE 'UTC') - nextcall)::float8 AS overdue_s
  FROM public.ir_cron
 WHERE active
 ORDER BY id
"""

# The 20 tables with the most dead rows, from the statistics views (no table is read; no grant beyond CONNECT)
SQL_TABLES = """
SELECT s.relname, s.n_live_tup, s.n_dead_tup, s.last_autovacuum, s.autovacuum_count,
       pg_total_relation_size(s.relid) AS total_bytes
  FROM pg_stat_user_tables s
 ORDER BY s.n_dead_tup DESC
 LIMIT 20
"""

INTERVAL_SECONDS = {"minutes": 60, "hours": 3600, "days": 86400, "weeks": 604800, "months": 2592000}


def iso(value):
    """Odoo's naive UTC timestamp as ISO 8601 with Z, or None."""
    return value.replace(tzinfo=dt.timezone.utc).isoformat().replace("+00:00", "Z") if value else None


def read(conn):
    """Run the queries; return the rows of each and the database time in ms."""
    db_ms = 0.0
    results = {}
    with conn.cursor() as cur:
        for name, sql in (("backlog", SQL_BACKLOG), ("ready", SQL_READY), ("failed", SQL_FAILED), ("dead", SQL_DEAD),
                          ("table", SQL_TABLE), ("cron", SQL_CRON), ("tables", SQL_TABLES), ("locks", SQL_LOCKS)):
            start = time.perf_counter()
            cur.execute(sql)
            results[name] = cur.fetchall()
            db_ms += (time.perf_counter() - start) * 1000
    return results, db_ms


def build_rows(results, env, database, run_id, now):
    base = {"TimeGenerated": now, "Env": env, "Database": database, "RunId": run_id}
    queue = []
    for state, channel, n, oldest_age_s in results["backlog"] + results["ready"]:  # ready, running: round 7
        queue.append({**base, "Check": "backlog", "State": state, "Channel": channel, "Count": n,
                      "OldestAgeSec": round(oldest_age_s or 0.0, 1)})
    for model, method, n in results["failed"]:
        queue.append({**base, "Check": "failed_1h", "Model": model, "Method": method, "Count": n})
    for model, method, n in results["dead"]:
        queue.append({**base, "Check": "dead_24h", "Model": model, "Method": method, "Count": n})
    for est_rows, total_bytes in results["table"]:
        queue.append({**base, "Check": "table", "Rows": est_rows, "Bytes": total_bytes})
    for waiting, longest_s in results["locks"]:  # one row every run, 0 when nothing waits: L1 reads it (round 4)
        queue.append({**base, "Check": "lock_wait", "Count": waiting, "OldestAgeSec": round(longest_s or 0.0, 1)})
    cron = []
    for cron_id, name, number, unit, nextcall, lastcall, failures, overdue_s in results["cron"]:
        cron.append({**base, "CronId": cron_id, "CronName": name,
                     "IntervalSec": (number or 0) * INTERVAL_SECONDS.get(unit, 0),
                     "NextCall": iso(nextcall), "LastCall": iso(lastcall),
                     "OverdueSec": round(overdue_s or 0.0, 1), "FailureCount": failures})
    tables = []
    for name, live, dead, last_av, av_count, total_bytes in results["tables"]:
        tables.append({**base, "TableName": name, "LiveRows": live, "DeadRows": dead,
                       "DeadPct": round(100.0 * dead / max(live, 1), 1), "LastAutovacuum": iso_tz(last_av),
                       "AutovacuumCount": av_count, "Bytes": total_bytes})
    return queue, cron, tables


def iso_tz(value):
    """A timezone-aware timestamp (the statistics views) as ISO 8601 with Z, or None."""
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z") if value else None


def credential():
    if os.environ.get("AZURE_CLIENT_ID"):
        from azure.identity import ManagedIdentityCredential
        return ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])
    from azure.identity import AzureCliCredential
    return AzureCliCredential()


def main(argv):
    dry_run = "--dry-run" in argv
    env = os.environ["OBS_ENV"]
    started = time.perf_counter()
    run_id = str(uuid.uuid4())
    now = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")

    import psycopg  # here, so the tests of build_rows need no driver

    with psycopg.connect(connect_timeout=10, application_name="obs-sql-job", autocommit=True) as conn:
        database = conn.info.dbname
        results, db_ms = read(conn)
    queue, cron, tables = build_rows(results, env, database, run_id, now)
    heartbeat = [{"TimeGenerated": now, "Env": env, "Database": database, "RunId": run_id,
                  "JobVersion": JOB_VERSION, "DbMs": round(db_ms, 1), "QueueRows": len(queue), "CronRows": len(cron),
                  "TableRows": len(tables), "DurationMs": None}]

    if dry_run:
        heartbeat[0]["DurationMs"] = round((time.perf_counter() - started) * 1000, 1)
        for stream, rows in (("queue", queue), ("cron", cron), ("tables", tables), ("heartbeat", heartbeat)):
            for row in rows:
                print(json.dumps({"stream": STREAMS[stream], **row}, default=str))
        return 0

    from azure.monitor.ingestion import LogsIngestionClient
    rule_id = os.environ["DCR_IMMUTABLE_ID"]
    with LogsIngestionClient(endpoint=os.environ["DCR_ENDPOINT"], credential=credential()) as client:
        for stream, rows in (("queue", queue), ("cron", cron), ("tables", tables)):
            if rows:
                client.upload(rule_id=rule_id, stream_name=STREAMS[stream], logs=rows)
        heartbeat[0]["DurationMs"] = round((time.perf_counter() - started) * 1000, 1)
        client.upload(rule_id=rule_id, stream_name=STREAMS["heartbeat"], logs=heartbeat)

    print(f"ok env={env} run={run_id} queue_rows={len(queue)} cron_rows={len(cron)} table_rows={len(tables)} "
          f"db_ms={heartbeat[0]['DbMs']} duration_ms={heartbeat[0]['DurationMs']}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:  # one line in the console log; no heartbeat, so rule H fires
        print(f"error: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
