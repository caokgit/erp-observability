# A demonstration add-on for the Kubernetes mapping's lab (docs/specs/kubernetes-mapping.md#the-workload): it makes
# the incident patterns the track's rules were built from happen on purpose, on the public Odoo image. Lab only.
{
    "name": "Incident lab",
    "version": "19.0.1.0.0",
    "summary": "Reproduces lock waits, 5xx bursts, a late scheduled task and a memory kill, on request",
    "depends": ["base", "web"],
    "data": ["ir.model.access.csv", "ir_cron.xml"],
    "license": "LGPL-3",
    "installable": True,
}
