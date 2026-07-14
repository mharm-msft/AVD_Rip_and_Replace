output "automation_account_id" {
  description = "Resource ID of the Azure Automation Account."
  value       = azurerm_automation_account.this.id
}

output "automation_account_name" {
  description = "Name of the Azure Automation Account."
  value       = azurerm_automation_account.this.name
}

output "automation_account_principal_id" {
  description = "Object ID of the Automation Account system-assigned managed identity. Grant this identity the required RBAC roles."
  value       = azurerm_automation_account.this.identity[0].principal_id
}

output "runbook_name" {
  description = "Name of the retirement runbook."
  value       = azurerm_automation_runbook.retirement.name
}
