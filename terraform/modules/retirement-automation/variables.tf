variable "location" {
  description = "Azure region for the Automation Account."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that will contain the Automation Account."
  type        = string
}

variable "automation_account_name" {
  description = "Name of the Azure Automation Account."
  type        = string
}

variable "sku_name" {
  description = "Automation Account SKU."
  type        = string
  default     = "Basic"
}

variable "enable_automatic_retirement" {
  description = "Set to true to enable the automated retirement runbook schedule. Must be explicitly opted in."
  type        = bool
  default     = false
}

variable "host_pool_name" {
  description = "Name of the AVD host pool containing the hosts to retire."
  type        = string
}

variable "host_pool_resource_group_name" {
  description = "Resource group containing the AVD host pool (control-plane RG)."
  type        = string
}

variable "generation_name" {
  description = "Generation identifier of the old hosts to retire, for example g2407."
  type        = string
}

variable "session_host_resource_group_name" {
  description = "Resource group containing the session host VMs to be retired."
  type        = string
}

variable "replacement_generation_validation_marker" {
  description = "Explicit marker confirming the replacement generation is approved, for example the new generation name g2408."
  type        = string
}

variable "host_name_prefix" {
  description = "Optional host name prefix used to narrow the session host pattern match."
  type        = string
  default     = ""
}

variable "drain_retention_hours" {
  description = "Minimum hours a host must be in drain mode before becoming eligible for deletion. Default 30. Range 1-720."
  type        = number
  default     = 30

  validation {
    condition     = var.drain_retention_hours >= 1 && var.drain_retention_hours <= 720
    error_message = "drain_retention_hours must be between 1 and 720."
  }
}

variable "delete_network_interfaces" {
  description = "When true, deletes generation-tagged NICs after the VM is removed."
  type        = bool
  default     = false
}

variable "delete_managed_disks" {
  description = "When true, deletes the managed OS disk after the VM is removed."
  type        = bool
  default     = false
}

variable "max_deletions_per_run" {
  description = "Maximum number of VMs to delete per runbook execution. Range 1-100."
  type        = number
  default     = 10

  validation {
    condition     = var.max_deletions_per_run >= 1 && var.max_deletions_per_run <= 100
    error_message = "max_deletions_per_run must be between 1 and 100."
  }
}

variable "schedule_frequency_hours" {
  description = "How often (in hours) the retirement runbook is triggered. Default 1."
  type        = number
  default     = 1

  validation {
    condition     = var.schedule_frequency_hours >= 1 && var.schedule_frequency_hours <= 24
    error_message = "schedule_frequency_hours must be between 1 and 24."
  }
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
