output "host_pool_id" {
  description = "Host pool resource ID."
  value       = azurerm_virtual_desktop_host_pool.this.id
}

output "host_pool_name" {
  description = "Host pool name."
  value       = azurerm_virtual_desktop_host_pool.this.name
}

output "desktop_application_group_id" {
  description = "Desktop application group resource ID."
  value       = azurerm_virtual_desktop_application_group.desktop.id
}

output "workspace_id" {
  description = "Workspace resource ID."
  value       = azurerm_virtual_desktop_workspace.this.id
}
