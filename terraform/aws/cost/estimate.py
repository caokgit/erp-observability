#!/usr/bin/env python3
"""Monthly list cost of the client's ERP estate on Azure today and on the AWS design, from both public price lists.

    python3 terraform/aws/cost/estimate.py [--cache .scratch_tf/pricing]

Spec: docs/specs/aws-migration.md#cost. No account is needed on either side:
- AWS: the Price List bulk API (https://pricing.us-east-1.amazonaws.com), the current file per offer for
  ap-southeast-1; each unit price is printed with the file version it came from.
- Azure: the Retail Prices API (https://prices.azure.com/api/retail/prices), southeastasia, Consumption prices.
The footprint (what runs) is the design's; amounts marked ASSUMED are estimates, listed in FOOTPRINT. The NAT gateway
price lives in the 350 MB EC2 file, so it is taken as a constant with its source version (NAT_GATEWAY).
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

AWS = "https://pricing.us-east-1.amazonaws.com"
AZURE = "https://prices.azure.com/api/retail/prices"
REGION, PREFIX, AZ_REGION, HOURS = "ap-southeast-1", "APS1", "southeastasia", 730
# The EC2 offer's NAT gateway prices, version 20261029175634 (read by the lab's estimate on 2026-11-04).
NAT_GATEWAY = {"hour": 0.059, "gb": 0.059, "source": "AmazonEC2 20261029175634"}

# What the ERP runs (docs/platform.md, 2026-11-07); ASSUMED where marked.
FOOTPRINT = {
    # Odoo tasks: (vCPU, GiB, replicas). Azure adds the nginx sidecar (0.25 vCPU, 0.5 GiB) to each app;
    # on AWS the load balancer routes /websocket itself (ADR-2), so the task is Odoo alone.
    "apps": {"stg": [("web", 2, 4, 1), ("cron", 2, 4, 1)], "dev": [("odoo", 1, 2, 1)]},
    "sidecar": (0.25, 0.5),
    # Postgres: stg's Odoo database lives on the server named prd (D2ds_v5, 128 GB, with 19 other databases), which on
    # AWS becomes an RDS instance in the stg account (ADR-3); dev's server (B1ms, 128 GB). The prd account starts empty:
    # prd Odoo is stopped and its database unused today.
    "pg": {"stg": ("D2ds_v5", "db.m7g.large", 128), "dev": ("B1ms", "db.t4g.small", 128)},
    "lcu": 1,                 # ASSUMED: average load balancer capacity units per balancer
    "vpc_attachments": 5,     # network, shared services, prd, stg, dev
    "vpn_connections": 2,     # on-prem, and Azure during the move (wave 1 to 3)
    "tgw_gb": 100,            # ASSUMED: GB a month through the transit gateway
    "nat_gb": 50,             # ASSUMED: GB a month of egress through the one NAT gateway
    "log_gb": 12.4,           # REAL: the workspace's intake, October 2026 (12.37 GB)
    "log_stored_gb": 12.4 * 12,  # ASSUMED: one year kept hot on AWS (Azure keeps 730 days); older to S3
    "alarms": 20,             # the 19 rules on stg today, about one alarm each
    "config_items": 3000,     # ASSUMED: configuration items recorded a month, all accounts
    "config_evals": 20000,    # ASSUMED: rule evaluations a month
    "guardduty_gb": 20,       # ASSUMED: flow and DNS log GB analysed a month
    "guardduty_vcpu": 5,      # Fargate vCPU monitored (stg 4, dev 1)
    "guardduty_rds_vcpu": 4,  # RDS vCPU monitored (prd 2, dev 2)
    "hub_checks": 15000,      # ASSUMED: Security Hub checks a month, all accounts
}


def fetch(url, cache):
    os.makedirs(cache, exist_ok=True)
    local = os.path.join(cache, url.replace(AWS, "").strip("/").replace("/", "_"))
    for attempt in range(4):
        if os.path.exists(local):
            return local
        try:
            urllib.request.urlretrieve(url, local + ".part")  # nosec B310: url is the fixed https price list above
            os.rename(local + ".part", local)
        except OSError as e:
            print(f"retrying {url}: {e}", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    raise SystemExit(f"could not fetch {url}")


def aws_offer(offer, cache):
    index = json.load(open(fetch(f"{AWS}/offers/v1.0/aws/{offer}/current/region_index.json", cache)))
    version_url = index["regions"][REGION]["currentVersionUrl"]
    return json.load(open(fetch(AWS + version_url, cache))), version_url.split("/")[5]


def on_demand(offer, match):
    """Every (attributes, unit price, description) of the offer's on-demand terms whose product matches."""
    for sku, product in offer["products"].items():
        a = product.get("attributes", {})
        if not match(product.get("productFamily"), a):
            continue
        for term in offer["terms"]["OnDemand"].get(sku, {}).values():
            for dim in term["priceDimensions"].values():
                yield a, float(dim["pricePerUnit"]["USD"]), dim["description"]


def first(offer, match, label):
    rows = [p for _, p, _ in on_demand(offer, match) if p > 0]
    if not rows:
        raise SystemExit(f"no price for {label}")
    return max(rows) if len(set(rows)) > 1 else rows[0]  # tiers: the first tier is the highest price


def aws_prices(cache):
    p, src = {}, {}
    ecs, v = aws_offer("AmazonECS", cache)
    usage = lambda t: (lambda fam, a: a.get("usagetype") == f"{PREFIX}-{t}")
    p["fargate_vcpu"] = first(ecs, usage("Fargate-vCPU-Hours:perCPU"), "Fargate vCPU"); src["fargate_vcpu"] = v
    p["fargate_gb"] = first(ecs, usage("Fargate-GB-Hours"), "Fargate GB"); src["fargate_gb"] = v
    elb, v = aws_offer("AWSELB", cache)
    alb = lambda t: (lambda fam, a: fam == "Load Balancer-Application" and a.get("usagetype") == f"{PREFIX}-{t}")
    p["alb_hour"] = first(elb, alb("LoadBalancerUsage"), "ALB hour"); src["alb_hour"] = v
    p["alb_lcu"] = first(elb, alb("LCUUsage"), "ALB LCU"); src["alb_lcu"] = v
    vpc, v = aws_offer("AmazonVPC", cache)
    desc = lambda text: [pr for _, pr, d in on_demand(vpc, lambda f, a: True) if text in d]
    p["tgw_attach"] = desc("Transit Gateway VPC Attachment Hour")[0]; src["tgw_attach"] = v
    p["tgw_vpn_attach"] = desc("Transit Gateway VPN Attachment Hour")[0]; src["tgw_vpn_attach"] = v
    p["tgw_gb"] = desc("Data Processed by Transit Gateway VPC Attachment")[0]; src["tgw_gb"] = v
    p["vpn_hour"] = desc("per VPN Connection-Hour")[0]; src["vpn_hour"] = v
    rds, v = aws_offer("AmazonRDS", cache)
    for cls in ("db.m7g.large", "db.t4g.small"):
        for dep in ("Single-AZ", "Multi-AZ"):
            p[f"{cls} {dep}"] = first(rds, lambda fam, a, c=cls, d=dep: fam == "Database Instance" and a.get("instanceType") == c
                                      and a.get("databaseEngine") == "PostgreSQL" and a.get("deploymentOption") == d, cls)
            src[f"{cls} {dep}"] = v
    p["aurora db.r7g.large"] = first(rds, lambda fam, a: fam == "Database Instance" and a.get("instanceType") == "db.r7g.large"
                                     and a.get("databaseEngine") == "Aurora PostgreSQL" and "IO" not in a.get("storage", "")
                                     and "IOOptimized" not in a.get("usagetype", ""), "aurora")
    src["aurora db.r7g.large"] = v
    for dep in ("Single-AZ", "Multi-AZ"):
        p[f"gp3 {dep}"] = first(rds, lambda fam, a, d=dep: fam == "Database Storage" and a.get("volumeType") == "General Purpose-GP3"
                                and a.get("deploymentOption") == d and a.get("databaseEngine") in ("PostgreSQL", "Any"), "gp3")
        src[f"gp3 {dep}"] = v
    cw, v = aws_offer("AmazonCloudWatch", cache)
    descs = lambda o, text: [pr for _, pr, d in on_demand(o, lambda f, a: True) if text in d]
    p["logs_gb"] = descs(cw, "custom log data ingested in Standard log class")[0]; src["logs_gb"] = v
    p["logs_store"] = descs(cw, "GB-mo of log storage")[0]; src["logs_store"] = v
    p["alarm"] = descs(cw, "per alarm metric month (standard resolution)")[0]; src["alarm"] = v
    cfg, v = aws_offer("AWSConfig", cache)
    p["config_item"] = descs(cfg, "per  Configuration Item recorded")[0]; src["config_item"] = v
    p["config_eval"] = descs(cfg, "for the first 100,000 evaluations")[0]; src["config_eval"] = v
    gd, v = aws_offer("AmazonGuardDuty", cache)
    p["gd_gb"] = descs(gd, "per GB for the first 500 GB")[0]; src["gd_gb"] = v
    p["gd_fargate"] = descs(gd, "for the first 500 Fargate vCPU")[0]; src["gd_fargate"] = v
    p["gd_rds"] = max(descs(gd, "per vCPU / month analyzed")); src["gd_rds"] = v  # a free-trial line lists 0
    hub, v = aws_offer("AWSSecurityHub", cache)
    p["hub_check"] = [pr for a, pr, d in on_demand(hub, lambda f, a: a.get("usagetype") == f"{PREFIX}-PaidComplianceCheck")
                      if "first 100,000" in d][0]; src["hub_check"] = v
    p["nat_hour"], p["nat_gb"] = NAT_GATEWAY["hour"], NAT_GATEWAY["gb"]
    src["nat_hour"] = src["nat_gb"] = NAT_GATEWAY["source"]
    return p, src


def azure_query(flt):
    url, items = AZURE + "?" + urllib.parse.urlencode({"$filter": flt}), []
    while url:
        page = json.load(urllib.request.urlopen(url, timeout=60))  # nosec B310: Azure's https Retail Prices API
        items, url = items + page["Items"], page.get("NextPageLink")
    return items


def azure_prices():
    base = f"armRegionName eq '{AZ_REGION}' and priceType eq 'Consumption'"
    aca = {i["meterName"]: i["retailPrice"] for i in azure_query(f"{base} and serviceName eq 'Azure Container Apps' and skuName eq 'Standard'")}
    pg = azure_query(f"{base} and serviceName eq 'Azure Database for PostgreSQL'")
    pick = lambda prod, sku: next(i["retailPrice"] for i in pg if i["productName"] == prod and i["skuName"].lower() == sku.lower())
    vpn = azure_query(f"{base} and serviceName eq 'VPN Gateway' and skuName eq 'VpnGw1AZ'")
    return {
        "aca_vcpu_s": aca["Standard vCPU Active Usage"], "aca_gib_s": aca["Standard Memory Active Usage"],
        "aca_vcpu_idle_s": aca["Standard vCPU Idle Usage"], "aca_gib_idle_s": aca["Standard Memory Idle Usage"],
        "D2ds_v5": pick("Azure Database for PostgreSQL Flexible Server General Purpose Ddsv5 Series Compute", "2 vCore"),
        "B1ms": pick("Azure Database for PostgreSQL Flexible Server Burstable BS Series Compute", "B1MS"),
        "pg_storage": pick("Azure Database for PostgreSQL Flex Server Storage", "Storage"),
        "vpn_gw": next(i["retailPrice"] for i in vpn if i["meterName"] == "VpnGw1AZ"),
    }


def azure_estate(az, rate="active"):
    """Azure today, by environment: (line, USD a month). Container Apps bill the active rate while a replica serves
    and the idle rate otherwise, so the two rates bound the bill (free grants left out)."""
    s, f, out = HOURS * 3600, FOOTPRINT, {}
    cpu, mem = ("aca_vcpu_s", "aca_gib_s") if rate == "active" else ("aca_vcpu_idle_s", "aca_gib_idle_s")
    for env, apps in f["apps"].items():
        for name, vcpu, gib, n in apps:
            v, g = vcpu + f["sidecar"][0], gib + f["sidecar"][1]
            out.setdefault(env, []).append((f"Container App {name} ({v} vCPU, {g} GiB, {rate} rate)", n * s * (v * az[cpu] + g * az[mem])))
    for env, (sku, _, gb) in f["pg"].items():
        out.setdefault(env, []).append((f"PostgreSQL {sku} + {gb} GB", HOURS * az[sku] + gb * az["pg_storage"]))
    out["network"] = [("VPN gateway VpnGw1AZ", HOURS * az["vpn_gw"])]
    out["management"] = [("Log Analytics workspace (REAL, Cost Management, Aug to Oct 2026)", 44.0)]
    return out


def aws_estate(p, multi_az_live=True):
    """The AWS design, by account: (line, USD a month)."""
    f, out = FOOTPRINT, {}
    for env, apps in f["apps"].items():
        for name, vcpu, gib, n in apps:
            out.setdefault(env, []).append((f"Fargate {name} ({vcpu} vCPU, {gib} GiB)", n * HOURS * (vcpu * p["fargate_vcpu"] + gib * p["fargate_gb"])))
        if apps:
            out[env].append(("Application Load Balancer", HOURS * (p["alb_hour"] + f["lcu"] * p["alb_lcu"])))
    for env, (_, cls, gb) in f["pg"].items():
        dep = "Multi-AZ" if env == "stg" and multi_az_live else "Single-AZ"
        out.setdefault(env, []).append((f"RDS PostgreSQL {cls} {dep} + {gb} GB gp3", HOURS * p[f"{cls} {dep}"] + gb * p[f"gp3 {dep}"]))
    out["network"] = [
        (f"Transit gateway: {f['vpc_attachments']} VPC attachments", f["vpc_attachments"] * HOURS * p["tgw_attach"]),
        (f"Site-to-site VPN: {f['vpn_connections']} connections and their attachments", f["vpn_connections"] * HOURS * (p["vpn_hour"] + p["tgw_vpn_attach"])),
        (f"Transit gateway data, {f['tgw_gb']} GB", f["tgw_gb"] * p["tgw_gb"]),
        (f"NAT gateway (one, central egress) + {f['nat_gb']} GB", HOURS * p["nat_hour"] + f["nat_gb"] * p["nat_gb"]),
    ]
    out["log-archive"] = [
        (f"CloudWatch Logs: {f['log_gb']} GB ingested", f["log_gb"] * p["logs_gb"]),
        (f"CloudWatch Logs: {f['log_stored_gb']:.0f} GB stored", f["log_stored_gb"] * p["logs_store"]),
        (f"CloudWatch alarms: {f['alarms']}", f["alarms"] * p["alarm"]),
    ]
    out["security"] = [
        (f"Config: {f['config_items']} items, {f['config_evals']} evaluations", f["config_items"] * p["config_item"] + f["config_evals"] * p["config_eval"]),
        (f"GuardDuty: {f['guardduty_gb']} GB logs, {f['guardduty_vcpu']} Fargate vCPU, {f['guardduty_rds_vcpu']} RDS vCPU",
         f["guardduty_gb"] * p["gd_gb"] + f["guardduty_vcpu"] * p["gd_fargate"] + f["guardduty_rds_vcpu"] * p["gd_rds"]),
        (f"Security Hub: {f['hub_checks']} checks", f["hub_checks"] * p["hub_check"]),
    ]
    return out


def table(estate):
    lines, total = ["| Account or scope | Line | USD a month |", "|---|---|---|"], 0.0
    for scope, rows in estate.items():
        for line, usd in rows:
            lines.append(f"| {scope} | {line} | {usd:,.2f} |"); total += usd
    lines.append(f"| **Total** | | **{total:,.2f}** |")
    return "\n".join(lines), total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=".scratch_tf/pricing")
    cache = ap.parse_args().cache
    p, src = aws_prices(cache)
    az = azure_prices()
    print(f"## Unit prices (read {time.strftime('%Y-%m-%d')})\n")
    print("| Item | USD | Source |\n|---|---|---|")
    for k in p:
        print(f"| AWS {k} | {p[k]:.6g} | {src[k]} |")
    for k in az:
        print(f"| Azure {k} | {az[k]:.6g} | Retail Prices API, {AZ_REGION} |")
    for title, estate in [("Azure today, list prices, apps at the active rate (upper bound)", azure_estate(az)),
                          ("Azure today, list prices, apps at the idle rate (lower bound)", azure_estate(az, "idle")),
                          ("AWS design, the live database Multi-AZ", aws_estate(p, True)),
                          ("AWS design, every database Single-AZ (like for like)", aws_estate(p, False))]:
        text, total = table(estate)
        print(f"\n## {title}: USD {total:,.2f} a month\n\n{text}")
    print("\n## Database options for the live database (USD a month, 730 h, compute only)\n")
    print("| Option | USD |\n|---|---|")
    for k in ("db.m7g.large Single-AZ", "db.m7g.large Multi-AZ", "aurora db.r7g.large"):
        print(f"| {k} | {HOURS * p[k]:,.2f} |")
    print(f"| Azure D2ds_v5 (today) | {HOURS * az['D2ds_v5']:,.2f} |")


if __name__ == "__main__":
    main()
