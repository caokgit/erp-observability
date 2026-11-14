# What the track costs

What the track adds to the client's Azure bill, estimated and billed, against the owner's ceiling of **$20 a month**
([D8](design.md#decisions)). The estimates are in each round's spec; this page keeps the billed numbers, revised in
place at each reading. The prices behind the estimates: [learn: what each piece costs](learn/azure-monitor-alerts.md#what-each-piece-costs).
Formal check: round 1's [A9](specs/round-1.md#acceptance), from 2026-11-15.

**In one line: billed at about $19.60 a month with the workspace data, against about $19.30 estimated for the same
pieces (the specs rounded it to about $19.50): 1.5 % over, under the ceiling (read 2026-11-14); round 7 adds about $0.10.**

## Billed (REAL, read 2026-11-14)

Cost Management over the resources tagged `owner = observability-track`, in the management, stg and dev
subscriptions ([tools/cost.py](../tools/cost.py)). Cost Management can lag a day, so the last day may be incomplete.

| Resource | 2026-11-07 to 11-14 | 11-12 and 11-13 | A month at that rate | Estimated |
|---|---|---|---|---|
| Log alert rules (`scheduledqueryrules`) | $2.70 | $0.95 | about $14.25 | $15.40 |
| stg's jobs: the SQL job and the log reader, every 5 min (`app/jobs`) | $1.05 | $0.34 | about $5.10 | $3.64 |
| dev's jobs (run by hand while dev is idle) | $0.04 | $0 | about $0 | $0 |
| Logic Apps (the cards), the Terraform state storage | $0.02 | $0 | cents | cents |
| Action groups, metric alerts M1 to M5 | $0 | $0 | $0 (free tiers) | $0 |
| **Total on the bill** | **$3.82** | **$1.30** | **about $19.35** | **$19.04** |
| The track's rows in the workspace ([below](#not-on-the-tracks-bill)) | | | about $0.23 | about $0.30 |
| **All** | | | **about $19.60** | **about $19.30** |

The first days are lower than the rate: round 1 went live on stg on 2026-11-08 and rules were added until 11-09. A month
is the two days times 15. The estimates are the specs' own lines summed exactly (rules: round 1 $9.70, round 2 $3.00,
round 3 $2.20, round 4 $0.50; jobs: two at $1.82). The two lines miss in opposite directions: the jobs cost $1.46 more
than estimated, the rules $1.15 less.

## Not on the track's bill

Two costs land on the platform's own resources, which carry no track tag:

| What | Measured | A month |
|---|---|---|
| The track's rows in the platform's workspace (`Odoo*_CL`: the cron list 12.6 MB, the table statistics 4.3, the queue 0.8, the reader and the heartbeat 0.2) | 17.9 MB from 2026-11-07, 2.57 MB a day over the last 7 days | about 77 MB: $0.23 at $2.99 per GB, $0 inside the billing account's free 5 GB |
| The job's image (`obs/sql-job`, 6 tags) in the platform's registry | | cents |

## By round (estimates)

| Round | Adds | A month | Running total (the specs' own, rounded) | Spec |
|---|---|---|---|---|
| 1 | 11 log rules, 5 metric series, the SQL job, its data | about $12 | $12 | [cost](specs/round-1.md#cost) |
| 2 | Q1, T1, R1, O1, the log reader | about $5 | $17 | [cost](specs/round-2.md#cost) |
| 3 | SLO-fast, SLO-slow | about $2.20 | $19 | [cost](specs/round-3.md#cost) |
| 4 | E1 | about $0.50 | $19.50 | [cost](specs/round-4.md#cost) |
| 5, 6 | Nothing billed (conditions and rows only) | $0 | $19.50 | [5](specs/round-5.md#cost), [6](specs/round-6.md#cost) |
| 7 | Two series on L5-ticket | about $0.10 | $19.60 | [cost](specs/round-7.md#cost) |

What decided the shape: the managed Prometheus and Grafana services were left out for their cost
([D3](design.md#decisions)); since round 5, a new signal joins an existing rule as a series ($0.05 to $0.30 a month)
before it becomes a rule of its own ($0.50 to $1.50).

## Reading it again

```bash
python3 tools/cost.py 2026-11-07 2026-11-14 | python3 tools/mask.py      # the whole period
python3 tools/cost.py 2026-11-12 2026-11-13 | python3 tools/mask.py      # two full days, for the monthly rate
bash tools/obs.sh kq 'Usage | where TimeGenerated > ago(7d) and DataType startswith "Odoo" | summarize MBperDay = round(sum(Quantity)/7, 2)' P8D
```

Output (REAL, 2026-11-14 04:10 UTC, the two days):

```text
management   Azure Monitor                microsoft.insights/scheduledqueryrules               0.95 USD
stg          Azure Container Apps         microsoft.app/jobs                                   0.34 USD
total                                                                                          1.30
```

Check: the monthly rate (two days' total times 15, plus the workspace rows) under $20. If you see `Too Many Requests`: the tool waits and asks
again, up to 5 times; Cost Management answers 429 after a few queries a minute.
