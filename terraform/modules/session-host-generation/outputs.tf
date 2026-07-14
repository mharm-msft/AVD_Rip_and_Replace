output "generation_name" {
  description = "Generation identifier deployed by this module."
  value       = var.generation_name
}

output "session_host_names" {
  description = "Names of the deployed session hosts."
  value       = sort(keys(azurerm_windows_virtual_machine.session_host))
}

output "session_host_ids" {
  description = "Resource IDs of the deployed session hosts."
  value       = { for name, vm in azurerm_windows_virtual_machine.session_host : name => vm.id }
}

output "network_interface_ids" {
  description = "Resource IDs of the session host network interfaces."
  value       = { for name, nic in azurerm_network_interface.session_host : name => nic.id }
}

output "image_reference" {
  description = "Pinned image version used for the deployment."
  value = var.image_source.type == "gallery" ? {
    type                     = "gallery"
    gallery_image_version_id = var.image_source.gallery_image_version_id
    } : {
    type      = "marketplace"
    publisher = var.image_source.marketplace.publisher
    offer     = var.image_source.marketplace.offer
    sku       = var.image_source.marketplace.sku
    version   = var.image_source.marketplace.version
  }
}

output "host_pool_id" {
  description = "Resource ID of the host pool used for registration."
  value       = var.host_pool_id
}

output "registration_token_expiration_utc" {
  description = "Registration token expiration used for this deployment."
  value       = var.registration_token_expiration_utc
}
