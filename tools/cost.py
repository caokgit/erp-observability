#!/usr/bin/env python3
"""What Azure billed for the track's resources (docs/specs/round-1.md#acceptance, A9; docs/cost.md). Read only.

Cost Management's query API over the resources tagged owner = observability-track, in the three subscriptions the
track uses, grouped by service and resource type. Prints service names, resource types and amounts only. Names come
from terraform/envs/shared/names.auto.tfvars.json; the read login is the lab's (AGENTS.md).

    python3 tools/cost.py 2026-11-07 2026-11-14     # from the first day to the last, both included
"""
import json
import os
import subprocess  # nosec B404: az, with fixed arguments
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUBSCRIPTIONS = ("management", "stg", "dev")


def query(subscription_id: str, start: str, end: str) -> list:
    body = {"type": "ActualCost", "timeframe": "Custom",
            "timePeriod": {"from": f"{start}T00:00:00Z", "to": f"{end}T23:59:59Z"},
            "dataset": {"granularity": "None",
                        "aggregation": {"cost": {"name": "Cost", "function": "Sum"}},
                        "grouping": [{"type": "Dimension", "name": "ServiceName"},
                                     {"type": "Dimension", "name": "ResourceType"}],
                        "filter": {"tags": {"name": "owner", "operator": "In", "values": ["observability-track"]}}}}
    url = (f"https://management.azure.com/subscriptions/{subscription_id}"
           "/providers/Microsoft.CostManagement/query?api-version=2023-03-01")
    env = dict(os.environ, AZURE_CONFIG_DIR=str(Path.home() / "lab/.scratch_az"))
    for attempt in range(1, 6):  # the API answers 429 after a few queries a minute: wait and ask again
        out = subprocess.run(["az", "rest", "--method", "post", "--url", url, "--body", json.dumps(body)],  # nosec B603 B607
                             env=env, capture_output=True, text=True)
        if out.returncode == 0 or "429" not in out.stderr:
            break
        time.sleep(30 * attempt)
    if out.returncode:
        sys.exit(out.stderr.strip().splitlines()[-1])
    props = json.loads(out.stdout)["properties"]
    cols = [c["name"] for c in props["columns"]]
    return [dict(zip(cols, row)) for row in props["rows"]]


def main(argv: list) -> int:
    if len(argv) != 2:
        sys.exit(__doc__)
    start, end = argv
    subs = json.loads((ROOT / "terraform/envs/shared/names.auto.tfvars.json").read_text())["subscription_ids"]
    total = 0.0
    print(f"{'subscription':12} {'service':28} {'resource type':48} {'cost':>8}")
    for label in SUBSCRIPTIONS:
        for r in sorted(query(subs[label], start, end), key=lambda r: -r["Cost"]):
            total += r["Cost"]
            print(f"{label:12} {r['ServiceName'][:28]:28} {r['ResourceType'][:48]:48} {r['Cost']:8.2f} {r.get('Currency', '')}")
    print(f"{'total':12} {'':28} {'':48} {total:8.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
