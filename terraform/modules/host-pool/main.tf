resource "azurerm_virtual_desktop_host_pool" "this" {
  name                     = var.host_pool_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  type                     = var.host_pool_type
  load_balancer_type       = var.load_balancer_type
  friendly_name            = coalesce(var.friendly_name, var.host_pool_name)
  description              = var.description
  maximum_sessions_allowed = var.host_pool_type == "Pooled" ? var.maximum_sessions_allowed : null
  start_vm_on_connect      = var.start_vm_on_connect
  validate_environment     = var.validate_environment
  preferred_app_group_type = "Desktop"
  custom_rdp_properties    = var.custom_rdp_properties
  tags                     = var.tags

  personal_desktop_assignment_type = var.host_pool_type == "Personal" ? var.personal_desktop_assignment_type : null
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                = var.desktop_application_group_name
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.this.id
  friendly_name       = coalesce(var.desktop_application_group_friendly_name, var.desktop_application_group_name)
  description         = "Desktop application group for ${var.host_pool_name}"
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace" "this" {
  name                = var.workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = coalesce(var.workspace_friendly_name, var.workspace_name)
  description         = var.workspace_description
  tags                = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "desktop" {
  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}
