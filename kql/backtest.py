#!/usr/bin/env python3
"""Run a round 1 log rule over the workspace's history, or once as the alert would (docs/specs/round-1.md#acceptance, A3).

The query is rendered exactly as terraform/modules/alerts renders it (render() below and the module's locals must stay
in step): the environment's targets, the time range, the rule's parameters as KQL let statements, then the function
files and the rule's file, comment lines dropped. Only Start and End differ: datetimes here, ago(lookback) and now() in the alert. Names come
from terraform/envs/<env>/names.auto.tfvars.json (terraform/names.sh), never from this file.

    python3 kql/backtest.py L2-5xx                              # stg's targets, 2025-11-01 to now
    python3 kql/backtest.py L1-wait --start 2026-08-01 --end 2026-10-01
    python3 kql/backtest.py L5-page --env dev --alert           # once, over the rule's own window, as the alert
    python3 kql/backtest.py L3 --print                          # the rendered query, for the portal

Output: the rows that would have fired (one per bin), counted by month, then the first rows. Pipe it through
tools/mask.py before it goes into a doc.
"""
import argparse
import collections
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KQL = ROOT / "kql"


def kql_string(value: str) -> str:
    return json.dumps(value)


def kql_dynamic(values) -> str:
    return "dynamic(" + json.dumps(values, separators=(",", ":")) + ")"


def targets(names: dict, env: str, servers=None) -> dict:
    """The environment's targets, as KQL literals (terraform/modules/alerts: var.targets)."""
    return {
        "Apps": kql_dynamic([a["name"] for a in names["apps"]]),
        "Gateway": kql_string(names["gateway"]["name"]),
        "Servers": kql_dynamic(servers or [names["pg_server"]["name"]]),
        "TargetEnv": kql_string(env),
        "TargetDatabaseId": str(deploy(env).get("pg_database_id", -1)),
    }


def deploy(env: str) -> dict:
    """The environment's committed deploy settings (terraform/envs/<env>/deploy.auto.tfvars.json)."""
    path = ROOT / "terraform" / "envs" / env / "deploy.auto.tfvars.json"
    return json.loads(path.read_text()) if path.exists() else {}


def render(rule: dict, target_lets: dict, start: str, end: str, params: dict) -> str:
    lines = [f"let {k} = {target_lets[k]};" for k in sorted(target_lets)]
    lines += [f"let Start = {start};", f"let End = {end};"]
    lines += [f"let {k} = {params[k]};" for k in sorted(params)]
    # comment lines dropped, as the module does: they name repo paths, which never reach Azure (AGENTS.md)
    lines += [re.sub(r"(?m)^[ \t]*//.*\n", "", (KQL / f).read_text()) for f in rule["functions"] + [rule["file"]]]
    return "\n".join(lines)


def run(query: str, workspace: str, start: dt.datetime, end: dt.datetime) -> list:
    timespan = f"{start:%Y-%m-%dT%H:%M:%SZ}/{end:%Y-%m-%dT%H:%M:%SZ}"
    out = subprocess.run(["az", "monitor", "log-analytics", "query", "-w", workspace, "--analytics-query", query,
                          "--timespan", timespan, "-o", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stderr.strip())
    return json.loads(out.stdout)


def utc(text: str) -> dt.datetime:
    return dt.datetime.fromisoformat(text).replace(tzinfo=dt.timezone.utc)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rule")
    ap.add_argument("--env", default="stg", choices=["dev", "stg"])
    ap.add_argument("--start", default="2025-11-01")
    ap.add_argument("--end", default=None, help="default: now")
    ap.add_argument("--alert", action="store_true", help="run once over the rule's lookback, as the alert does")
    ap.add_argument("--print", action="store_true", help="print the rendered query and stop")
    ap.add_argument("--rows", type=int, default=12, help="rows to show, largest first")
    ap.add_argument("--param", action="append", default=[], metavar="K=V",
                    help="override a parameter with a KQL literal (a drill's lowered threshold), repeatable")
    args = ap.parse_args()

    rules = json.loads((KQL / "rules.json").read_text())["rules"]
    rule = rules[args.rule]
    overrides = dict(p.split("=", 1) for p in args.param)
    rule = {**rule, "params": {**rule["params"], **overrides}}
    names = json.loads((ROOT / "terraform" / "envs" / args.env / "names.auto.tfvars.json").read_text())
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)

    if args.alert or args.print:
        query = render(rule, targets(names, args.env), f"ago({rule['lookback']})", "now()", rule["params"])
        if args.print:
            print(query)
            return 0
        rows = run(query, names["workspace_customer_id"], now - dt.timedelta(days=2, minutes=5), now)
        print(f"{args.rule} as the alert, {args.env}: {len(rows)} row(s) -> {'FIRES' if rows else 'quiet'}")
        for row in rows[: args.rows]:
            print("  " + json.dumps({k: v for k, v in row.items() if k != "TableName"}, default=str))
        return 0

    start, end = utc(args.start), utc(args.end) if args.end else now
    params = {**rule["params"], **rule.get("backtest_params", {}), **overrides}
    # Postgres rules follow the database across servers (stg's moved on 2026-08-27); other rules run once
    segments, seg_start = [], start
    history = names["pg_servers_history"] if rule["functions"] else [{"name": None, "until": ""}]
    for server in history:
        seg_end = min(end, utc(server["until"].rstrip("Z"))) if server["until"] else end
        if seg_end > seg_start:
            segments.append((server["name"], seg_start, seg_end))
        seg_start = max(seg_start, seg_end)

    rows = []
    for server, s, e in segments:
        t = targets(names, args.env, [server] if server else None)
        query = render(rule, t, f"datetime({s:%Y-%m-%dT%H:%M:%SZ})", f"datetime({e:%Y-%m-%dT%H:%M:%SZ})", params)
        rows += run(query, names["workspace_customer_id"], s, e)

    by_month = collections.Counter(r["Bin"][:7] for r in rows)
    print(f"{args.rule} backtest, {args.env}, {start:%Y-%m-%d} to {end:%Y-%m-%d %H:%M}: {len(rows)} firing bin(s)")
    print("by month: " + (", ".join(f"{m} {n}" for m, n in sorted(by_month.items())) or "none"))
    def number(value):  # az returns every value as a string
        try:
            return float(value)
        except (TypeError, ValueError):
            return None
    numeric = [k for k in (rows[0] if rows else {}) if k not in ("Bin", "TableName") and number(rows[0][k]) is not None]
    top = sorted(rows, key=lambda r: -(number(r[numeric[0]]) or 0)) if numeric else rows
    for row in top[: args.rows]:
        print("  " + json.dumps({k: v for k, v in row.items() if k != "TableName"}, default=str))
    return 0


if __name__ == "__main__":
    os.environ.setdefault("AZURE_CONFIG_DIR", str(pathlib.Path.home() / "lab/.scratch_az"))
    sys.exit(main())
