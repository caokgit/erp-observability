"""Tests of the SQL job's queue rows (docs/specs/round-7.md, N2).

BuildRows: the rows built from each query's results; no database, no driver.
QueriesOnPostgres: the job's own query strings on a throwaway PostgreSQL 17 container that tools/ci.sh's step `sql`
starts (its name in OBS_TEST_PG_CONTAINER), over a small queue_job table with jobs at known states, dates and eta.
Skipped without the container. Run: python3 -m unittest discover -s job -p 'test_*.py'. Not copied into the image."""
import os
import subprocess  # nosec B404: docker exec psql on the test's own container
import unittest

import sql_job

NOW = "2026-11-14T10:00:00Z"
BASE = {"TimeGenerated": NOW, "Env": "stg", "Database": "erp", "RunId": "run-1"}


def results(**over):
    r = {"backlog": [], "ready": [], "failed": [], "dead": [], "table": [], "locks": [], "cron": [], "tables": []}
    r.update(over)
    return r


class BuildRows(unittest.TestCase):
    def rows(self, **over):
        queue, _, _ = sql_job.build_rows(results(**over), "stg", "erp", "run-1", NOW)
        return queue

    def test_ready_and_running_are_backlog_rows_beside_the_states(self):
        queue = self.rows(backlog=[("pending", "root.endpoint", 2, 3840.0)],
                          ready=[("ready", "root.endpoint", 2, 3840.0), ("running", "root.endpoint", 1, 1200.4)])
        self.assertEqual(queue, [
            {**BASE, "Check": "backlog", "State": "pending", "Channel": "root.endpoint", "Count": 2, "OldestAgeSec": 3840.0},
            {**BASE, "Check": "backlog", "State": "ready", "Channel": "root.endpoint", "Count": 2, "OldestAgeSec": 3840.0},
            {**BASE, "Check": "backlog", "State": "running", "Channel": "root.endpoint", "Count": 1, "OldestAgeSec": 1200.4},
        ])

    def test_dead_rows_name_the_model_and_method(self):
        queue = self.rows(dead=[("endpoint.model", "import_batch", 6)])
        self.assertEqual(queue, [{**BASE, "Check": "dead_24h", "Model": "endpoint.model",
                                  "Method": "import_batch", "Count": 6}])

    def test_no_job_means_no_row(self):
        self.assertEqual(self.rows(), [])


CONTAINER = os.environ.get("OBS_TEST_PG_CONTAINER")

# Jobs at known states, relative to the database's clock; only the columns the queries read
FIXTURE = """
DROP TABLE IF EXISTS public.queue_job;
CREATE TABLE public.queue_job (id serial PRIMARY KEY, state varchar, channel varchar, model_name varchar,
  method_name varchar, exc_name varchar, date_created timestamp, eta timestamp, date_started timestamp);
CREATE TEMP VIEW t AS SELECT (now() AT TIME ZONE 'UTC') AS now;
INSERT INTO public.queue_job (state, channel, model_name, method_name, exc_name, date_created, eta, date_started)
SELECT s, c, m, f, x, now - cr * interval '1 minute', now + e * interval '1 minute', now - st * interval '1 minute'
  FROM t, (VALUES
  -- root.a: ready 90 min (no eta); ready 30 min (created 300 min ago, eta 30 min ago); postponed to +10 min: not ready
  ('pending',  'root.a', 'm.a', 'run', NULL, 90,  NULL, NULL),
  ('pending',  'root.a', 'm.a', 'run', NULL, 300, -30,  NULL),
  ('pending',  'root.a', 'm.a', 'run', NULL, 200, 10,   NULL),
  -- root.b: enqueued 5 min ago, so ready
  ('enqueued', 'root.b', 'm.b', 'run', NULL, 5,   NULL, NULL),
  -- root.c: only a postponed job: no ready row
  ('pending',  'root.c', 'm.c', 'run', NULL, 400, 60,   NULL),
  -- running: created 200 min ago, this attempt started 20 min ago; another 3 min ago
  ('started',  'root.a', 'm.a', 'run', NULL, 200, NULL, 20),
  ('started',  'root.b', 'm.b', 'run', NULL, 10,  NULL, 3),
  -- found dead, last attempt 2 h ago: counted; 30 h ago: not; another error 1 h ago: not
  ('failed',   'root.a', 'm.x', 'import_batch', 'JobFoundDead', 600, NULL, 120),
  ('failed',   'root.a', 'm.x', 'import_batch', 'JobFoundDead', 2000, NULL, 1800),
  ('failed',   'root.a', 'm.x', 'import_batch', 'ValueError', 90, NULL, 60),
  -- done and no channel: never in these rows
  ('done',     NULL,     'm.d', 'run', NULL, 30,  NULL, 29)
  ) AS v(s, c, m, f, x, cr, e, st);
"""


def psql(sql):
    out = subprocess.run(  # nosec B603 B607: a fixed command on the test's own container
        ["docker", "exec", "-i", CONTAINER, "psql", "-h", "127.0.0.1", "-U", "postgres", "-X", "-q", "-At", "-F", "|",
         "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True, check=True)
    return [line.split("|") for line in out.stdout.splitlines() if line]


@unittest.skipUnless(CONTAINER, "no PostgreSQL container: tools/ci.sh's step sql starts one")
class QueriesOnPostgres(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        psql(FIXTURE)

    def assertAge(self, seconds, minutes):
        self.assertAlmostEqual(float(seconds), minutes * 60, delta=10)

    def test_ready_counts_from_when_a_job_could_run(self):
        rows = {(r[0], r[1]): r for r in psql(sql_job.SQL_READY)}
        self.assertEqual(sorted(rows), [("ready", "root.a"), ("ready", "root.b"), ("running", "root.a"),
                                        ("running", "root.b")])
        self.assertEqual(rows["ready", "root.a"][2], "2")  # the postponed job is left out
        self.assertAge(rows["ready", "root.a"][3], 90)  # the job without eta waited longest, not the 300-min-old one
        self.assertAge(rows["ready", "root.b"][3], 5)

    def test_running_counts_from_the_attempts_start(self):
        rows = {(r[0], r[1]): r for r in psql(sql_job.SQL_READY)}
        self.assertAge(rows["running", "root.a"][3], 20)  # not 200: its creation
        self.assertAge(rows["running", "root.b"][3], 3)

    def test_dead_counts_jobfounddead_of_the_last_24_hours(self):
        self.assertEqual(psql(sql_job.SQL_DEAD), [["m.x", "import_batch", "1"]])

    def test_the_backlog_still_counts_by_creation(self):
        rows = {(r[0], r[1]): r for r in psql(sql_job.SQL_BACKLOG)}
        self.assertEqual(rows["pending", "root.a"][2], "3")
        self.assertAge(rows["pending", "root.a"][3], 300)


if __name__ == "__main__":
    unittest.main()
