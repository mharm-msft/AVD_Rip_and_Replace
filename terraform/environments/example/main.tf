locals {
  use_created_host_pool = var.create_host_pool
  host_pool_id          = local.use_created_host_pool ? module.host_pool[0].host_pool_id : var.existing_host_pool_id
  host_pool_name        = local.use_created_host_pool ? module.host_pool[0].host_pool_name : var.existing_host_pool_name
}

module "host_pool" {
  source = "../../modules/host-pool"
  count  = var.create_host_pool ? 1 : 0

  location                                = var.location
  resource_group_name                     = var.control_plane_resource_group_name
  host_pool_name                          = var.host_pool_name
  host_pool_type                          = var.host_pool_type
  load_balancer_type                      = var.load_balancer_type
  desktop_application_group_name          = var.desktop_application_group_name
  workspace_name                          = var.workspace_name
  desktop_application_group_friendly_name = var.desktop_application_group_name
  workspace_friendly_name                 = var.workspace_name
  tags                                    = var.tags
}

module "session_host_generation" {
  source = "../../modules/session-host-generation"

  location                             = var.location
  resource_group_name                  = var.session_host_resource_group_name
  host_pool_id                         = local.host_pool_id
  host_pool_name                       = local.host_pool_name
  generation_name                      = var.generation_name
  host_name_prefix                     = var.host_name_prefix
  start_host_number                    = var.start_host_number
  session_host_count                   = var.session_host_count
  registration_token_expiration_utc    = var.registration_token_expiration_utc
  subnet_id                            = var.subnet_id
  vm_size                              = var.vm_size
  admin_username                       = var.admin_username
  admin_password                       = var.admin_password
  os_disk                              = var.os_disk
  availability_zones                   = var.availability_zones
  accelerated_networking_enabled       = var.accelerated_networking_enabled
  security_type                        = var.security_type
  secure_boot_enabled                  = var.secure_boot_enabled
  vtpm_enabled                         = var.vtpm_enabled
  boot_diagnostics_enabled             = var.boot_diagnostics_enabled
  boot_diagnostics_storage_account_uri = var.boot_diagnostics_storage_account_uri
  managed_identity                     = var.managed_identity
  image_source                         = var.image_source
  domain_join                          = nonsensitive(var.domain_join)
  custom_script                        = var.custom_script
  tags                                 = var.tags
}

check "host_pool_mode" {
  assert {
    condition     = var.create_host_pool ? (var.host_pool_name != null && var.desktop_application_group_name != null && var.workspace_name != null) : (var.existing_host_pool_id != null && var.existing_host_pool_name != null)
    error_message = "Set host_pool_name/desktop_application_group_name/workspace_name when create_host_pool is true, otherwise provide existing_host_pool_id and existing_host_pool_name."
  }
}
