locals {
  host_numbers = [for offset in range(var.session_host_count) : var.start_host_number + offset]

  host_definitions = {
    for index, host_number in local.host_numbers :
    format("%s-%s-%03d", var.host_name_prefix, var.generation_name, host_number) => {
      host_number = host_number
      zone        = length(var.availability_zones) == 0 ? null : var.availability_zones[index % length(var.availability_zones)]
    }
  }

  base_tags = merge(var.tags, {
    "avd.generation" = var.generation_name
    "avd.hostpool"   = var.host_pool_name
    "avd.role"       = "session-host"
  })

  user_assigned_identity_ids = contains(var.managed_identity.type, "UserAssigned") ? var.managed_identity.identity_ids : null
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  hostpool_id     = var.host_pool_id
  expiration_date = var.registration_token_expiration_utc
}

resource "azurerm_network_interface" "session_host" {
  for_each                       = local.host_definitions
  name                           = "${each.key}-nic"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = var.accelerated_networking_enabled
  tags                           = local.base_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "session_host" {
  for_each            = local.host_definitions
  name                = each.key
  computer_name       = each.key
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.session_host[each.key].id
  ]
  provision_vm_agent = true
  patch_mode         = "AutomaticByOS"
  tags               = local.base_tags

  source_image_id = var.image_source.type == "gallery" ? var.image_source.gallery_image_version_id : null

  dynamic "source_image_reference" {
    for_each = var.image_source.type == "marketplace" ? [var.image_source.marketplace] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  os_disk {
    caching              = var.os_disk.caching
    storage_account_type = var.os_disk.storage_account_type
    disk_size_gb         = try(var.os_disk.disk_size_gb, null)
  }

  dynamic "identity" {
    for_each = var.managed_identity.type == "None" ? [] : [var.managed_identity]
    content {
      type         = identity.value.type
      identity_ids = local.user_assigned_identity_ids
    }
  }

  zone = each.value.zone

  secure_boot_enabled = var.security_type == "TrustedLaunch" ? var.secure_boot_enabled : null
  vtpm_enabled        = var.security_type == "TrustedLaunch" ? var.vtpm_enabled : null

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics_enabled ? [1] : []
    content {
      storage_account_uri = var.boot_diagnostics_storage_account_uri
    }
  }

  lifecycle {
    precondition {
      condition     = length(each.key) <= 15
      error_message = "Generated computer names must be 15 characters or fewer. Shorten host_name_prefix or generation_name."
    }
  }
}

resource "azurerm_virtual_machine_extension" "domain_join" {
  for_each = var.domain_join.type == "ad" ? azurerm_windows_virtual_machine.session_host : {}

  name                       = "domainJoin"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    Name    = var.domain_join.domain_name
    OUPath  = try(var.domain_join.ou_path, null)
    User    = var.domain_join.user_upn
    Restart = tostring(try(var.domain_join.restart, true))
    Options = tostring(try(var.domain_join.options, 3))
  })

  protected_settings = jsonencode({
    Password = var.domain_join.password
  })
}

resource "azurerm_virtual_machine_extension" "entra_login" {
  for_each = var.domain_join.type == "entra" ? azurerm_windows_virtual_machine.session_host : {}

  name                       = "entraLogin"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true
}

resource "azurerm_virtual_machine_extension" "avd_bootloader" {
  for_each = azurerm_windows_virtual_machine.session_host

  name                       = "avdBootLoader"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.VirtualDesktop"
  type                       = "WindowsVirtualDesktopAgentBootLoader"
  type_handler_version       = var.avd_bootloader_extension_version
  auto_upgrade_minor_version = true
  settings                   = jsonencode({})
  protected_settings = jsonencode({
    registrationToken = azurerm_virtual_desktop_host_pool_registration_info.this.token
  })

  depends_on = [
    azurerm_virtual_machine_extension.domain_join,
    azurerm_virtual_machine_extension.entra_login
  ]
}

resource "azurerm_virtual_machine_extension" "avd_agent" {
  for_each = azurerm_windows_virtual_machine.session_host

  name                       = "avdAgent"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.VirtualDesktop"
  type                       = "WindowsVirtualDesktopAgent"
  type_handler_version       = var.avd_agent_extension_version
  auto_upgrade_minor_version = true
  settings                   = jsonencode({})
  protected_settings = jsonencode({
    registrationToken = azurerm_virtual_desktop_host_pool_registration_info.this.token
  })

  depends_on = [
    azurerm_virtual_machine_extension.avd_bootloader
  ]
}

resource "azurerm_virtual_machine_extension" "custom_script" {
  for_each = try(var.custom_script.enabled, false) ? azurerm_windows_virtual_machine.session_host : {}

  name                       = "customScript"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = try(var.custom_script.file_uris, [])
  })

  protected_settings = jsonencode({
    commandToExecute = try(var.custom_script.command_to_execute, null)
  })

  depends_on = [
    azurerm_virtual_machine_extension.avd_agent
  ]
}
