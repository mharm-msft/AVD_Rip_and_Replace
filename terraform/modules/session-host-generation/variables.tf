variable "location" {
  description = "Azure region for the session hosts."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that will contain the session host generation resources."
  type        = string
}

variable "host_pool_id" {
  description = "Resource ID of the Azure Virtual Desktop host pool to register against."
  type        = string
}

variable "host_pool_name" {
  description = "Host pool name used for tags and outputs."
  type        = string
}

variable "generation_name" {
  description = "Release or generation identifier used in naming and tags, for example g2026-07 or r42."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.generation_name))
    error_message = "generation_name must use lowercase letters, numbers, and hyphens only."
  }
}

variable "host_name_prefix" {
  description = "Short name prefix used to build deterministic computer names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.host_name_prefix))
    error_message = "host_name_prefix must use lowercase letters, numbers, and hyphens only."
  }
}

variable "start_host_number" {
  description = "Starting host number for the generation."
  type        = number
  default     = 1

  validation {
    condition     = var.start_host_number >= 1
    error_message = "start_host_number must be at least 1."
  }
}

variable "session_host_count" {
  description = "Number of new session hosts to create in this deployment."
  type        = number

  validation {
    condition     = var.session_host_count >= 1 && var.session_host_count <= 100
    error_message = "session_host_count must be between 1 and 100."
  }
}

variable "registration_token_expiration_utc" {
  description = "RFC3339 UTC expiration time for the short-lived host pool registration token."
  type        = string
}

variable "subnet_id" {
  description = "Subnet resource ID for the session host NICs."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
}

variable "admin_username" {
  description = "Local administrator username for the Windows VMs."
  type        = string
}

variable "admin_password" {
  description = "Local administrator password for the Windows VMs. Supply this securely at deploy time."
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

  validation {
    condition     = contains(["Premium_LRS", "PremiumV2_LRS", "StandardSSD_LRS", "Standard_LRS"], var.os_disk.storage_account_type)
    error_message = "os_disk.storage_account_type must be a supported managed disk SKU."
  }
}

variable "availability_zones" {
  description = "Optional list of availability zones used in round-robin order across hosts."
  type        = list(string)
  default     = []
}

variable "accelerated_networking_enabled" {
  description = "Enables accelerated networking on session host NICs when supported by the selected VM size."
  type        = bool
  default     = true
}

variable "security_type" {
  description = "Security type for the VM."
  type        = string
  default     = "TrustedLaunch"

  validation {
    condition     = contains(["Standard", "TrustedLaunch"], var.security_type)
    error_message = "security_type must be Standard or TrustedLaunch."
  }
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
  description = "Optional storage account URI for classic boot diagnostics. Leave null to use managed boot diagnostics."
  type        = string
  default     = null
}

variable "managed_identity" {
  description = "Managed identity configuration for the VMs."
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = {
    type         = "None"
    identity_ids = []
  }

  validation {
    condition     = contains(["None", "SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type)
    error_message = "managed_identity.type must be None, SystemAssigned, UserAssigned, or SystemAssigned, UserAssigned."
  }
}

variable "image_source" {
  description = "Pinned image source definition. Prefer a shared image gallery version ID."
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

  validation {
    condition     = contains(["gallery", "marketplace"], var.image_source.type)
    error_message = "image_source.type must be gallery or marketplace."
  }

  validation {
    condition     = var.image_source.type != "gallery" || try(length(var.image_source.gallery_image_version_id) > 0, false)
    error_message = "gallery image deployments must set image_source.gallery_image_version_id to an immutable image version resource ID."
  }

  validation {
    condition     = var.image_source.type != "marketplace" || try(var.image_source.marketplace.version != "latest", false)
    error_message = "marketplace image deployments must pin a version; latest is not allowed."
  }
}

variable "domain_join" {
  description = "Join configuration. Use entra for Microsoft Entra sign-in support or ad for traditional domain join."
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

  validation {
    condition     = contains(["none", "entra", "ad"], var.domain_join.type)
    error_message = "domain_join.type must be none, entra, or ad."
  }

  validation {
    condition     = var.domain_join.type != "ad" || (try(length(var.domain_join.domain_name) > 0, false) && try(length(var.domain_join.user_upn) > 0, false) && try(length(var.domain_join.password) > 0, false))
    error_message = "Traditional domain join requires domain_name, user_upn, and password."
  }
}

variable "custom_script" {
  description = "Optional custom script extension used for post-deployment validation or final configuration."
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
  description = "Tags applied to generation resources."
  type        = map(string)
  default     = {}
}

variable "avd_agent_extension_version" {
  description = "Type handler version for the Azure Virtual Desktop agent extension."
  type        = string
  default     = "1.0"
}

variable "avd_bootloader_extension_version" {
  description = "Type handler version for the Azure Virtual Desktop bootloader extension."
  type        = string
  default     = "1.0"
}
