import time

from odoo import SUPERUSER_ID, api, http, sql_db
from odoo.http import Response
from odoo.modules.registry import Registry

DB = "erp"
LOCK = 4242  # the advisory lock both lock routes use; no table is touched


class IncidentLab(http.Controller):
    @http.route("/incident_lab/status/<int:code>", type="http", auth="none", csrf=False)
    def status(self, code):
        """Answer with the status asked for: 5xx bursts (L2) and the SLO's bad requests."""
        return Response(f"incident lab: {code}\n", status=code)

    @http.route("/erp/tv/data", type="http", auth="none", csrf=False)
    def tv_data(self):
        """The TV dashboards' poll, the SLO's second journey."""
        return Response("{}", status=200, content_type="application/json")

    @http.route("/incident_lab/hold_lock/<int:seconds>", type="http", auth="none", csrf=False)
    def hold_lock(self, seconds):
        """Hold the advisory lock for the given seconds inside one transaction."""
        with sql_db.db_connect(DB).cursor() as cr:
            cr.execute("SELECT pg_advisory_xact_lock(%s), pg_sleep(%s)", [LOCK, seconds])
        return Response("released\n")

    @http.route("/incident_lab/wait_lock", type="http", auth="none", csrf=False)
    def wait_lock(self):
        """Wait for the advisory lock: the session shows wait_event_type 'Lock' until the holder ends (L1)."""
        start = time.monotonic()
        with sql_db.db_connect(DB).cursor() as cr:
            cr.execute("SELECT pg_advisory_xact_lock(%s)", [LOCK])
        return Response(f"waited {time.monotonic() - start:.1f} s\n")

    @http.route("/incident_lab/cron_sleep/<int:seconds>", type="http", auth="none", csrf=False)
    def cron_sleep(self, seconds):
        """Ask the one-minute task to sleep once (L6)."""
        with Registry(DB).cursor() as cr:
            api.Environment(cr, SUPERUSER_ID, {})["ir.config_parameter"].set_param("incident_lab.cron_sleep", str(seconds))
        return Response(f"the next run sleeps {seconds} s\n")

    @http.route("/incident_lab/allocate/<int:mib>", type="http", auth="none", csrf=False)
    def allocate(self, mib):
        """Touch the given MiB of memory: past the container's limit, the kernel kills it (L7, M1)."""
        blocks = [b"x" * (1 << 20) for _ in range(mib)]
        time.sleep(5)
        return Response(f"held {len(blocks)} MiB\n")
