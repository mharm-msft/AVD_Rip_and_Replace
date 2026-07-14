output "generation_name" {
  value       = module.session_host_generation.generation_name
  description = "Generation deployed by this example."
}

output "session_host_names" {
  value       = module.session_host_generation.session_host_names
  description = "Names of the newly deployed session hosts."
}

output "session_host_ids" {
  value       = module.session_host_generation.session_host_ids
  description = "Resource IDs of the newly deployed session hosts."
}

output "network_interface_ids" {
  value       = module.session_host_generation.network_interface_ids
  description = "NIC IDs for the newly deployed session hosts."
}

output "host_pool_id" {
  value       = module.session_host_generation.host_pool_id
  description = "Host pool used for registration."
}

output "image_reference" {
  value       = module.session_host_generation.image_reference
  description = "Pinned image reference used for the deployment."
}
