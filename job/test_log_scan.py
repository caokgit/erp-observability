"""Unit tests of the log reader's counting, on lines in Odoo 19's own format (docs/specs/round-5.md, G7; postponed: docs/specs/round-6.md, I5).
Run: python3 -m unittest discover -s job -p 'test_*.py'. Not copied into the image (the Dockerfile names its files)."""
import datetime as dt
import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout

import log_scan

START = dt.datetime(2026, 11, 9, 10, 0, tzinfo=dt.timezone.utc)
END = START + dt.timedelta(minutes=5)


def line(sec, logger, msg, level="INFO", pid=42):
    return f"2026-11-09 10:00:{sec:02d},123 {pid} {level} erp {logger}: {msg}".encode()


LINES = [
    line(1, "odoo.service.model", "LOCK_NOT_AVAILABLE, 4 tries left, try again in 1.2345 sec..."),
    line(13, "odoo.service.model", "LOCK_NOT_AVAILABLE, 3 tries left, try again in 3.0001 sec..."),
    line(50, "odoo.service.model", "LOCK_NOT_AVAILABLE, maximum number of tries reached!"),
    line(51, "odoo.service.model", "SERIALIZATION_FAILURE, 4 tries left, try again in 0.5000 sec..."),
    line(52, "odoo.service.model", "DEADLOCK_DETECTED, maximum number of tries reached!"),
    line(53, "odoo.service.model", "ConcurrencyError('a record was changed'), 2 tries left, try again in 2.0 sec..."),
    # the same words from another logger, or a user's text, are not Odoo's retry
    line(54, "odoo.addons.some_module", "LOCK_NOT_AVAILABLE, 4 tries left, try again in 1.0 sec..."),
    line(55, "odoo.service.model", "note: LOCK_NOT_AVAILABLE, maximum number of tries reached!"),
    # queue_job's postponements: the plain line counts, the OperationalError line before it does not (one each)
    line(57, "odoo.addons.queue_job.controllers.main", "<Job fake-job-1, priority:10> OperationalError, postponed", level="DEBUG"),
    line(57, "odoo.addons.queue_job.controllers.main", "<Job fake-job-1, priority:10> postponed", level="DEBUG"),
    line(58, "odoo.addons.queue_job.controllers.main", "<Job fake-job-2, priority:10> postponed", level="DEBUG"),
    line(58, "odoo.addons.other", "<Job fake-job-2, priority:10> postponed", level="DEBUG"),
    # stg's file ends each line with a space (2026-11-10): a final failure and a postponement still count as such
    line(59, "odoo.service.model", "LOCK_NOT_AVAILABLE, maximum number of tries reached! "),
    line(59, "odoo.addons.queue_job.controllers.main", "<Job fake-job-3, priority:10> postponed ", level="DEBUG"),
    # an existing kind still counts
    line(56, "odoo.service.server", "Worker (77) virtual memory limit (2.1GiB) reached.", level="ERROR"),
]


class RetryKinds(unittest.TestCase):
    def test_scan_counts_each_kind(self):
        found = log_scan.scan(LINES, START, END)
        counts = {k: v[0] for k, v in found.items()}
        self.assertEqual(counts["lock_retry"], 2)
        self.assertEqual(counts["lock_failed"], 2)
        self.assertEqual(counts["concurrency_retry"], 2)
        self.assertEqual(counts["concurrency_failed"], 1)
        self.assertEqual(counts["postponed"], 3)
        self.assertEqual(counts["memory_limit"], 1)
        self.assertEqual(counts["scan"], len(LINES))

    def test_outside_the_window_is_not_counted(self):
        found = log_scan.scan(LINES, END, END + dt.timedelta(minutes=5))
        self.assertNotIn("lock_retry", found)

    def test_retries_mode_prints_counts_per_day(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "odoo.log"), "wb") as f:
                f.write(b"\n".join(LINES) + b"\n")
            out = io.StringIO()
            with redirect_stdout(out):
                log_scan.retries(d, dt.datetime(2026, 11, 1, tzinfo=dt.timezone.utc))
        text = out.getvalue()
        self.assertIn("lock_retry 2, lock_failed 2, concurrency_retry 2, concurrency_failed 1", text)
        self.assertIn("2026-11-09 lock_retry=2 lock_failed=2", text)
        self.assertIn("concurrency_failed 1, postponed 3", text)


if __name__ == "__main__":
    unittest.main()
