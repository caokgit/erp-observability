# The SQL job of one environment (docs/specs/round-1.md#the-sql-job): a user-assigned identity with two roles only
# (Monitoring Metrics Publisher on the DCR, Repository Reader on the registry limited to obs/sql-job), and the scheduled
# Container Apps job.

resource "azurerm_user_assigned_identity" "job" {
  name                = "${var.name_prefix}-sqljob-uami"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "publish" {
  scope                = var.dcr.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
  principal_type       = "ServicePrincipal"
}

# The registry is in ABAC mode, where AcrPull is not honored: Repository Reader, its reads limited to the job's repository
resource "azurerm_role_assignment" "pull" {
  scope                = var.registry.id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
      AND
      !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
     )
     OR
     (
      @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase 'obs/sql-job'
     )
    )
  EOT
}

resource "azurerm_container_app_job" "sql" {
  count                        = var.image_tag == "" ? 0 : 1
  name                         = "${var.name_prefix}-sqljob-caj"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.environment_id
  workload_profile_name        = var.workload_profile_name
  replica_timeout_in_seconds   = 60
  replica_retry_limit          = 0
  tags                         = var.tags

  dynamic "schedule_trigger_config" {
    for_each = var.schedule_enabled ? [1] : []
    content {
      cron_expression          = "*/5 * * * *"
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  dynamic "manual_trigger_config" {
    for_each = var.schedule_enabled ? [] : [1]
    content {
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.job.id]
  }

  registry {
    server   = var.registry.login_server
    identity = azurerm_user_assigned_identity.job.id
  }

  secret {
    name  = "pg-password"
    value = var.password
  }

  template {
    container {
      name   = "sql-job"
      image  = "${var.registry.login_server}/obs/sql-job:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "OBS_ENV"
        value = var.env
      }
      env {
        name  = "PGHOST"
        value = var.database.host
      }
      env {
        name  = "PGDATABASE"
        value = var.database.name
      }
      env {
        name  = "PGUSER"
        value = "obs_monitor"
      }
      env {
        name        = "PGPASSWORD"
        secret_name = "pg-password"
      }
      env {
        name  = "DCR_ENDPOINT"
        value = var.dcr.endpoint
      }
      env {
        name  = "DCR_IMMUTABLE_ID"
        value = var.dcr.immutable_id
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.job.client_id
      }
    }
  }

  depends_on = [azurerm_role_assignment.pull, azurerm_role_assignment.publish]
}

# Round 2's log reader (docs/specs/round-2.md#the-log-reader): the same image, identity and schedule; the Odoo share's
# log folder only (subPath), read only; never the share's root, so never its config folder
resource "azurerm_container_app_job" "log" {
  count                        = var.image_tag != "" && var.log_storage_name != "" ? 1 : 0
  name                         = "${var.name_prefix}-logscan-caj"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.environment_id
  workload_profile_name        = var.workload_profile_name
  replica_timeout_in_seconds   = 600 # a normal run takes seconds; the one-off backfill reads the whole history
  replica_retry_limit          = 0
  tags                         = var.tags

  dynamic "schedule_trigger_config" {
    for_each = var.schedule_enabled ? [1] : []
    content {
      cron_expression          = "*/5 * * * *"
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  dynamic "manual_trigger_config" {
    for_each = var.schedule_enabled ? [] : [1]
    content {
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.job.id]
  }

  registry {
    server   = var.registry.login_server
    identity = azurerm_user_assigned_identity.job.id
  }

  template {
    volume {
      name          = "odoo-log"
      storage_type  = "AzureFile"
      storage_name  = var.log_storage_name
      mount_options = var.log_mount_options != "" ? var.log_mount_options : null
    }

    container {
      name    = "log-scan"
      image   = "${var.registry.login_server}/obs/sql-job:${var.image_tag}"
      command = ["python3", "/app/log_scan.py"]
      cpu     = 0.25
      memory  = "0.5Gi"

      volume_mounts {
        name     = "odoo-log"
        path     = "/odoo-log"
        sub_path = "log"
      }

      env {
        name  = "OBS_ENV"
        value = var.env
      }
      env {
        name  = "LOG_DIR"
        value = "/odoo-log"
      }
      env {
        name  = "DCR_ENDPOINT"
        value = var.dcr.endpoint
      }
      env {
        name  = "DCR_IMMUTABLE_ID"
        value = var.dcr.immutable_id
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.job.client_id
      }
    }
  }

  depends_on = [azurerm_role_assignment.pull, azurerm_role_assignment.publish]
}
