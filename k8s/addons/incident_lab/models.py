import time

from odoo import api, fields, models


class IncidentLabJob(models.Model):
    """The lab's one-minute scheduled task; it sleeps once when asked, so its next run falls behind (L6)."""

    _name = "incident_lab.job"
    _description = "Incident lab job"

    name = fields.Char()

    @api.model
    def _run(self):
        params = self.env["ir.config_parameter"].sudo()
        seconds = int(params.get_param("incident_lab.cron_sleep", "0"))
        if seconds:
            params.set_param("incident_lab.cron_sleep", "0")
            self.env.cr.commit()  # the reset survives the sleep; the task's row stays locked by the scheduler
            time.sleep(seconds)
