locals {
  # Build PowerShell parameters for the runbook invocation.
  # The runbook uses -UseAutomationManagedIdentity to authenticate.
  runbook_parameters = merge(
    {
      HostPoolName                          = var.host_pool_name
      ResourceGroupName                     = var.host_pool_resource_group_name
      GenerationName                        = var.generation_name
      SessionHostResourceGroupName          = var.session_host_resource_group_name
      ReplacementGenerationValidationMarker = var.replacement_generation_validation_marker
      DrainRetentionHours                   = tostring(var.drain_retention_hours)
      MaxDeletionsPerRun                    = tostring(var.max_deletions_per_run)
    },
    var.host_name_prefix != "" ? { HostNamePrefix = var.host_name_prefix } : {},
    var.delete_network_interfaces ? { DeleteNetworkInterfaces = "true" } : {},
    var.delete_managed_disks ? { DeleteManagedDisks = "true" } : {},
    var.enable_automatic_retirement ? { EnableAutomaticRetirement = "true" } : {}
  )

  # Embed the retirement script content directly from the repository scripts directory so
  # the runbook is always in sync with the operator script.
  # This module is designed to be used from within the same repository at
  # terraform/modules/retirement-automation/ relative to the repo root; the path
  # is anchored via path.module which resolves to the module's own directory.
  runbook_content = file("${path.module}/../../../scripts/Invoke-AvdAutoRetirement.ps1")
}

resource "azurerm_automation_account" "this" {
  name                = var.automation_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = var.sku_name
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_runbook" "retirement" {
  name                    = "Invoke-AvdAutoRetirement"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = false
  log_progress            = true
  description             = "Automatically retires eligible drained AVD session hosts after the configured retention period."
  runbook_type            = "PowerShell72"
  content                 = local.runbook_content
  tags                    = var.tags
}

resource "azurerm_automation_schedule" "retirement_hourly" {
  count = var.enable_automatic_retirement ? 1 : 0

  name                    = "avd-retirement-hourly"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Hour"
  interval                = var.schedule_frequency_hours
  timezone                = "UTC"
  description             = "Triggers the AVD auto-retirement runbook every ${var.schedule_frequency_hours} hour(s)."
}

resource "azurerm_automation_job_schedule" "retirement" {
  count = var.enable_automatic_retirement ? 1 : 0

  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  schedule_name           = azurerm_automation_schedule.retirement_hourly[0].name
  runbook_name            = azurerm_automation_runbook.retirement.name
  parameters              = local.runbook_parameters
}
