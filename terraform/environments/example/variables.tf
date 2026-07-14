variable "location" {
  description = "Deployment region."
  type        = string
}

variable "control_plane_resource_group_name" {
  description = "Resource group that contains or will contain the AVD host pool, app group, and workspace."
  type        = string
}

variable "session_host_resource_group_name" {
  description = "Resource group that contains the session host generation. Consider one resource group per generation."
  type        = string
}

variable "create_host_pool" {
  description = "Set to true for the first deployment of a host pool and false for later generations."
  type        = bool
  default     = false
}

variable "existing_host_pool_id" {
  description = "Existing host pool resource ID used when create_host_pool is false."
  type        = string
  default     = null
}

variable "existing_host_pool_name" {
  description = "Existing host pool name used when create_host_pool is false."
  type        = string
  default     = null
}

variable "host_pool_name" {
  description = "Host pool name when create_host_pool is true."
  type        = string
  default     = null
}

variable "desktop_application_group_name" {
  description = "Desktop application group name when create_host_pool is true."
  type        = string
  default     = null
}

variable "workspace_name" {
  description = "Workspace name when create_host_pool is true."
  type        = string
  default     = null
}

variable "host_pool_type" {
  description = "Host pool type."
  type        = string
  default     = "Pooled"
}

variable "load_balancer_type" {
  description = "Load balancer type."
  type        = string
  default     = "DepthFirst"
}

variable "generation_name" {
  description = "Release or generation identifier, such as g2407 or r42."
  type        = string
}

variable "host_name_prefix" {
  description = "Short computer name prefix."
  type        = string
}

variable "start_host_number" {
  description = "Starting host number for the generation."
  type        = number
  default     = 1
}

variable "session_host_count" {
  description = "Number of hosts in this deployment."
  type        = number
}

variable "registration_token_expiration_utc" {
  description = "Short-lived host pool registration token expiration in RFC3339 UTC format."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the session hosts."
  type        = string
}

variable "vm_size" {
  description = "VM size."
  type        = string
}

variable "admin_username" {
  description = "Local administrator username."
  type        = string
}

variable "admin_password" {
  description = "Local administrator password supplied securely at apply time."
  type        = string
  sensitive   = true
}

variable "os_disk" {
  description = "OS disk settings."
  type = object({
    storage_account_type = string
    caching              = optional(string, "ReadWrite")
    disk_size_gb         = optional(number)
  })
}

variable "availability_zones" {
  description = "Optional list of zones."
  type        = list(string)
  default     = []
}

variable "accelerated_networking_enabled" {
  description = "Enable accelerated networking."
  type        = bool
  default     = true
}

variable "security_type" {
  description = "Security type for the VMs."
  type        = string
  default     = "TrustedLaunch"
}

variable "secure_boot_enabled" {
  description = "Enable secure boot when using Trusted Launch."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Enable vTPM when using Trusted Launch."
  type        = bool
  default     = true
}

variable "boot_diagnostics_enabled" {
  description = "Enable boot diagnostics."
  type        = bool
  default     = true
}

variable "boot_diagnostics_storage_account_uri" {
  description = "Optional boot diagnostics storage account URI."
  type        = string
  default     = null
}

variable "managed_identity" {
  description = "Managed identity settings."
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = {
    type         = "SystemAssigned"
    identity_ids = []
  }
}

variable "image_source" {
  description = "Pinned shared image gallery or marketplace image reference."
  type = object({
    type                     = string
    gallery_image_version_id = optional(string)
    marketplace = optional(object({
      publisher = string
      offer     = string
      sku       = string
      version   = string
    }))
  })
}

variable "domain_join" {
  description = "Join settings for none, entra, or ad."
  type = object({
    type        = string
    domain_name = optional(string)
    ou_path     = optional(string)
    user_upn    = optional(string)
    password    = optional(string)
    restart     = optional(bool, true)
    options     = optional(number, 3)
  })
  default = {
    type = "none"
  }
  sensitive = true
}

variable "custom_script" {
  description = "Optional post-deployment custom script settings."
  type = object({
    enabled            = optional(bool, false)
    file_uris          = optional(list(string), [])
    command_to_execute = optional(string)
  })
  default = {
    enabled = false
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
