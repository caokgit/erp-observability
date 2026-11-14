#!/usr/bin/env python3
"""The log reader of round 2, the observability track. This file ships in the image: it names no repo path.

One run: for each Odoo log file in LOG_DIR written to in the window, read it from its end backwards until its lines are
older than the window, count the worker ends Odoo logs (limits, timeouts, critical errors, workers unregistered with no
clean exit before them), the ERROR lines and Odoo's retries of concurrency errors (a lock timeout tried again, or
failed after its last try) and queue_job's postponed jobs, and send one row per file and kind to the custom table OdooLog_CL through
the Data Collection Rule. A row of kind "scan" is always sent, so rows prove the reader ran. The reader only reads: it
never writes under LOG_DIR, and it sends no log text but the fixed messages of the limit kinds.

Environment:
  OBS_ENV                     dev | stg: written into every row
  LOG_DIR                     the mount of the share's log folder (default /odoo-log)
  WINDOW_MIN                  the window in minutes (default 5), aligned to the schedule: no overlap, no gap
  DCR_ENDPOINT, DCR_IMMUTABLE_ID, AZURE_CLIENT_ID   as the SQL job

  python3 log_scan.py                         one run
  python3 log_scan.py --dry-run               one run, rows printed as JSON lines, nothing sent
  python3 log_scan.py --check                 list the folder (names, sizes, times) and prove a write fails; nothing sent
  python3 log_scan.py --backfill YYYY-MM-DD   15-min bins O1 would have fired on since that date, printed; nothing sent
  python3 log_scan.py --trace YYYY-MM-DD      the server's own lines before the first 5 workers counted as killed
  python3 log_scan.py --retries YYYY-MM-DD    Odoo's retry and failure lines per day since that date; nothing sent
  (or check, dry-run, backfill, trace, retries without dashes, as a started job's arguments)
"""
import collections
import datetime as dt
import json
import os
import re
import sys
import uuid

LINE = re.compile(rb"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d),\d+ (\d+) (DEBUG|INFO|WARNING|ERROR|CRITICAL) (\S+) (\S+): (.*)$")
KINDS = [  # Odoo 19's own messages (odoo/service/server.py); the first four are the limits O1 counts
    ("memory_limit", re.compile(rb"Worker \((\d+)\) virtual memory limit \(.*\) reached")),
    ("cpu_limit", re.compile(rb"Worker \((\d+)\) CPU time limit \(.*\) reached")),
    ("timeout", re.compile(rb"\w+ \((\d+)\) timeout after \d+s")),
    ("critical", re.compile(rb"Critial worker error \((\d+)\)")),
    ("exiting", re.compile(rb"Worker \((\d+)\) exiting\.")),
    ("unregistered", re.compile(rb"Worker \((\d+)\) unregistered")),
]
LIMIT_KINDS = {"memory_limit", "cpu_limit", "timeout", "critical"}
# The master stopping every worker (a container stop or restart, which L7 watches): the workers it then unregisters
# never log their own exit, so for SHUTDOWN_GRACE after one of these lines an unregistered worker is not a kill
SHUTDOWN = re.compile(rb"Multiprocess clean stop|Stopping workers gracefully|Stopping forcefully|Forced shutdown")
SHUTDOWN_GRACE = dt.timedelta(minutes=2)
# Odoo 19 retries a request on a concurrency error (odoo/service/model.py, retrying(): up to 5 tries) and logs each try
# from this logger at INFO; the error is the code's name (LOCK_NOT_AVAILABLE is a lock timeout) or an exception's repr
RETRY_LOGGER = b"odoo.service.model"
RETRY = re.compile(rb"^([A-Z_]+|\w+\(.*?\)), (?:\d+ tries left, try again in|maximum number of tries reached!)")
# queue_job (OCA's queue for Odoo 19: queue_job/controllers/main.py, _runjob; the link is in the spec, since a shipped
# file names no code host) reschedules a job that raised a retryable error, a lock timeout included, and logs
# "<job> postponed" at DEBUG (after "<job> OperationalError, postponed" for a database error, so counting only the
# plain line counts each postponement once)
POSTPONE_LOGGER = b"odoo.addons.queue_job.controllers.main"
POSTPONED = re.compile(rb"^<Job [\w-]+, priority:\d+> postponed$")  # Job.__repr__ (queue_job/job.py)
RETRY_KINDS = ("lock_retry", "lock_failed", "concurrency_retry", "concurrency_failed", "postponed")
CHUNK = 1 << 20  # 1 MiB
STREAM = "Custom-OdooLog"


def ts(raw: bytes) -> dt.datetime:
    return dt.datetime.strptime(raw.decode(), "%Y-%m-%d %H:%M:%S").replace(tzinfo=dt.timezone.utc)


def iso(t: dt.datetime) -> str:
    return t.isoformat().replace("+00:00", "Z")


def retry_kind(logger: bytes, msg: bytes):
    """lock_retry, lock_failed, concurrency_retry or concurrency_failed for one of Odoo's retry lines, postponed for
    queue_job's, else None. stg's log file ends each line with a space (2026-11-10), so the message is stripped first."""
    msg = msg.rstrip()
    if logger == POSTPONE_LOGGER:
        return "postponed" if POSTPONED.match(msg) else None
    m = RETRY.match(msg) if logger == RETRY_LOGGER else None
    if not m:
        return None
    return ("lock_" if m.group(1) == b"LOCK_NOT_AVAILABLE" else "concurrency_") + \
        ("failed" if msg.endswith(b"maximum number of tries reached!") else "retry")


def lines_since(path: str, start: dt.datetime):
    """The file's lines from the first one at or after start, read from the end backwards in chunks."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        pos = f.tell()
        while pos > 0:
            pos = max(0, pos - CHUNK)
            f.seek(pos)
            head = f.read(min(CHUNK, 4096)).split(b"\n")
            first = next((LINE.match(l) for l in head[1 if pos else 0:] if LINE.match(l)), None)
            if first and ts(first.group(1)) < start:
                break
        f.seek(pos)
        if pos:
            f.readline()  # a partial line
        for raw in f:
            yield raw.rstrip(b"\r\n")


def scan(lines, start, end):
    """Counts per kind in [start, end): kind -> [count, first, last, sample]."""
    found = collections.defaultdict(lambda: [0, None, None, None])
    clean = set()  # pids that exited cleanly or hit a limit (their unregistered is not a kill)
    shutdown_until = None
    def add(kind, t, sample=None):
        k = found[kind]
        k[0] += 1
        k[1] = k[1] or t
        k[2] = t
        k[3] = k[3] or sample
    for raw in lines:
        m = LINE.match(raw)
        if not m:
            continue
        t = ts(m.group(1))
        if t < start:
            continue
        if t >= end:
            break
        add("scan", t)
        if m.group(3) == b"ERROR":
            add("error", t)
        msg = m.group(6)
        rk = retry_kind(m.group(5), msg)
        if rk:
            add(rk, t)
            continue
        if SHUTDOWN.search(msg):
            shutdown_until = t + SHUTDOWN_GRACE
            add("shutdown", t)
            continue
        for kind, rx in KINDS:
            km = rx.search(msg)
            if not km:
                continue
            pid = km.group(1)
            if kind == "unregistered":
                if pid in clean or (shutdown_until and t <= shutdown_until):
                    add("unregistered", t)
                else:
                    add("killed", t)
            else:
                if kind in LIMIT_KINDS or kind == "exiting":
                    clean.add(pid)
                add(kind, t, msg.decode(errors="replace")[:200] if kind in LIMIT_KINDS else None)
            break
    return found


def log_files(log_dir, since=None):
    out = []
    for name in sorted(os.listdir(log_dir)):
        path = os.path.join(log_dir, name)
        if os.path.isfile(path) and not name.endswith((".gz", ".zip")):
            mtime = dt.datetime.fromtimestamp(os.path.getmtime(path), dt.timezone.utc)
            if since is None or mtime >= since:
                out.append((name, path, mtime))
    return out


def check(log_dir):
    for name, path, mtime in log_files(log_dir):
        print(f"file {name} {os.path.getsize(path)} bytes, modified {iso(mtime)}")
    probe = os.path.join(log_dir, f".obs-write-probe-{uuid.uuid4().hex[:8]}")
    try:
        with open(probe, "w") as f:
            f.write("x")
        os.remove(probe)
        print("WRITE SUCCEEDED: the mount is NOT read only")
        return 1
    except OSError as exc:
        print(f"ok: write refused ({type(exc).__name__}: {exc.strerror})")
        return 0


def backfill(log_dir, since):
    """15-minute bins where O1 fires (3 or more stated limits), and the bins of inferred kills apart, over every file
    written to since the date. Only lines that
    can hold a worker message are parsed, so a large DEBUG file is read once, quickly."""
    bins = collections.Counter()
    first_seen = None
    for name, path, _ in log_files(log_dir, since):
        clean = set()
        shutdown_until = None
        with open(path, "rb") as f:
            for raw in f:
                if not (b"Worker" in raw or b"timeout after" in raw or b"Critial" in raw or b"Stopping" in raw
                        or b"clean stop" in raw or b"Forced shutdown" in raw):
                    continue
                m = LINE.match(raw.rstrip(b"\r\n"))
                if not m:
                    continue
                t = ts(m.group(1))
                if t < since:
                    continue
                first_seen = min(first_seen, t) if first_seen else t
                b15 = t.replace(minute=t.minute - t.minute % 15, second=0)
                if SHUTDOWN.search(m.group(6)):
                    shutdown_until = t + SHUTDOWN_GRACE
                    continue
                for kind, rx in KINDS:
                    km = rx.search(m.group(6))
                    if not km:
                        continue
                    pid = km.group(1)
                    if kind == "unregistered":
                        if pid not in clean and not (shutdown_until and t <= shutdown_until):
                            bins[(b15, "killed")] += 1
                    else:
                        clean.add(pid)
                        if kind in LIMIT_KINDS:
                            bins[(b15, kind)] += 1
                    break
    per_bin = collections.Counter()  # O1's condition: the limits Odoo states
    killed_bins = collections.Counter()  # inferred kills: counted, not alerted
    for (b15, kind), n in bins.items():
        if kind in LIMIT_KINDS:
            per_bin[b15] += n
        else:
            killed_bins[b15] += n
    fired = sorted(b15 for b15, n in per_bin.items() if n >= 3)
    print(f"backfill since {since:%Y-%m-%d}: worker lines from {iso(first_seen) if first_seen else 'none'}; "
          f"{len(fired)} bin(s) where O1 fires (3 or more limits); "
          f"{sum(1 for n in killed_bins.values() if n >= 3)} bin(s) with 3 or more inferred kills (not alerted)")
    for b15 in fired[:50]:
        kinds = {k: n for (bb, k), n in bins.items() if bb == b15}
        print(f"  {iso(b15)} {per_bin[b15]} {kinds}")
    by_day = collections.Counter(b15.strftime("%Y-%m-%d") for b15 in fired)
    print("by day: " + (", ".join(f"{d} {n}" for d, n in sorted(by_day.items())) or "none"))
    return 0


def trace(log_dir, since, limit=5):
    """For the first `limit` workers counted as killed since the date, print the server's own lines before it (the
    logger odoo.service.server and worker lines only: no request or user content), to check what an end really was."""
    shown = 0
    for name, path, _ in log_files(log_dir, since):
        recent = collections.deque(maxlen=40)
        clean = set()
        shutdown_until = None
        with open(path, "rb") as f:
            for raw in f:
                if not (b"odoo.service.server" in raw or b"Worker" in raw):
                    continue
                line = raw.rstrip(b"\r\n")
                m = LINE.match(line)
                if not m or ts(m.group(1)) < since:
                    continue
                recent.append(line)
                t = ts(m.group(1))
                if SHUTDOWN.search(m.group(6)):
                    shutdown_until = t + SHUTDOWN_GRACE
                    continue
                for kind, rx in KINDS:
                    km = rx.search(m.group(6))
                    if not km:
                        continue
                    if kind == "unregistered" and km.group(1) not in clean and not (shutdown_until and t <= shutdown_until):
                        print(f"== {name}: worker {km.group(1).decode()} counted as killed")
                        for r in list(recent)[-12:]:
                            print("   " + r.decode(errors="replace")[:220])
                        shown += 1
                        if shown >= limit:
                            return 0
                    elif kind != "unregistered":
                        clean.add(km.group(1))
                    break
    return 0


def retries(log_dir, since):
    """Odoo's retry and failure lines per day and kind, over every file written to since the date; only lines naming
    tries, or queue_job's postponements, are parsed. Prints counts only, no log text."""
    days = collections.Counter()
    for _, path, _ in log_files(log_dir, since):
        with open(path, "rb") as f:
            for raw in f:
                if b"tries" not in raw and b"postponed" not in raw:
                    continue
                m = LINE.match(raw.rstrip(b"\r\n"))
                if not m or ts(m.group(1)) < since:
                    continue
                kind = retry_kind(m.group(5), m.group(6))
                if kind:
                    days[(m.group(1)[:10].decode(), kind)] += 1
    totals = ", ".join(f"{k} {sum(n for (_, kk), n in days.items() if kk == k)}" for k in RETRY_KINDS)
    print(f"retries since {since:%Y-%m-%d}: {totals}")
    for day in sorted({d for d, _ in days}):
        print(f"  {day} " + " ".join(f"{k}={days[(day, k)]}" for k in RETRY_KINDS if days[(day, k)]))
    return 0


def main(argv):
    # plain words work too (check, dry-run, backfill <date>): a job started with arguments passes no leading dashes
    argv = ["--" + a if a in ("check", "dry-run", "backfill", "trace", "retries") else a for a in argv]
    log_dir = os.environ.get("LOG_DIR", "/odoo-log")
    if "--check" in argv:
        return check(log_dir)
    if "--trace" in argv:
        since = dt.datetime.strptime(argv[argv.index("--trace") + 1], "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
        return trace(log_dir, since)
    if "--retries" in argv:
        since = dt.datetime.strptime(argv[argv.index("--retries") + 1], "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
        return retries(log_dir, since)
    if "--backfill" in argv:
        since = dt.datetime.strptime(argv[argv.index("--backfill") + 1], "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
        return backfill(log_dir, since)

    env = os.environ["OBS_ENV"]
    window = int(os.environ.get("WINDOW_MIN", "5"))
    # the last complete window, aligned to the schedule: runs every WINDOW_MIN minutes read back-to-back windows
    now = dt.datetime.now(dt.timezone.utc)
    end = now.replace(minute=now.minute - now.minute % window, second=0, microsecond=0)
    start = end - dt.timedelta(minutes=window)
    run_id = str(uuid.uuid4())
    rows = []
    for name, path, _ in log_files(log_dir, start):
        for kind, (count, first, last, sample) in sorted(scan(lines_since(path, start), start, end).items()):
            rows.append({"TimeGenerated": iso(end), "Env": env, "RunId": run_id, "File": name, "Kind": kind,
                         "Count": count, "FirstAt": iso(first), "LastAt": iso(last), "Sample": sample})
    if not any(r["Kind"] == "scan" for r in rows):
        rows.append({"TimeGenerated": iso(end), "Env": env, "RunId": run_id, "File": "", "Kind": "scan", "Count": 0,
                     "FirstAt": None, "LastAt": None, "Sample": None})

    if "--dry-run" in argv:
        for row in rows:
            print(json.dumps({"stream": STREAM, **row}))
        return 0

    from azure.identity import ManagedIdentityCredential
    from azure.monitor.ingestion import LogsIngestionClient
    with LogsIngestionClient(endpoint=os.environ["DCR_ENDPOINT"],
                             credential=ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])) as client:
        client.upload(rule_id=os.environ["DCR_IMMUTABLE_ID"], stream_name=STREAM, logs=rows)
    kills = sum(r["Count"] for r in rows if r["Kind"] in LIMIT_KINDS | {"killed"})
    print(f"ok env={env} run={run_id} files={len({r['File'] for r in rows if r['File']})} rows={len(rows)} "
          f"lines={sum(r['Count'] for r in rows if r['Kind'] == 'scan')} kills_or_limits={kills}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:
        print(f"error: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
