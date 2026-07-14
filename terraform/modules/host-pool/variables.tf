variable "location" {
  description = "Azure region for the host pool control plane resources."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that contains the host pool, application group, and workspace."
  type        = string
}

variable "host_pool_name" {
  description = "Name of the Azure Virtual Desktop host pool."
  type        = string
}

variable "host_pool_type" {
  description = "Host pool type."
  type        = string
  default     = "Pooled"

  validation {
    condition     = contains(["Pooled", "Personal"], var.host_pool_type)
    error_message = "host_pool_type must be Pooled or Personal."
  }
}

variable "load_balancer_type" {
  description = "Load balancer type for the host pool."
  type        = string
  default     = "DepthFirst"

  validation {
    condition     = contains(["BreadthFirst", "DepthFirst", "Persistent"], var.load_balancer_type)
    error_message = "load_balancer_type must be BreadthFirst, DepthFirst, or Persistent."
  }
}

variable "friendly_name" {
  description = "Friendly name shown in Azure Virtual Desktop."
  type        = string
  default     = null
}

variable "description" {
  description = "Host pool description."
  type        = string
  default     = "AVD rip-and-replace host pool"
}

variable "maximum_sessions_allowed" {
  description = "Maximum sessions allowed per host for pooled host pools."
  type        = number
  default     = 16
}

variable "personal_desktop_assignment_type" {
  description = "Assignment type for personal host pools."
  type        = string
  default     = null

  validation {
    condition     = var.personal_desktop_assignment_type == null ? true : contains(["Automatic", "Direct"], var.personal_desktop_assignment_type)
    error_message = "personal_desktop_assignment_type must be null, Automatic, or Direct."
  }
}

variable "start_vm_on_connect" {
  description = "Enables start VM on connect for the host pool."
  type        = bool
  default     = false
}

variable "validate_environment" {
  description = "Whether the host pool is marked as a validation environment."
  type        = bool
  default     = false
}

variable "custom_rdp_properties" {
  description = "Optional custom RDP properties string."
  type        = string
  default     = null
}

variable "desktop_application_group_name" {
  description = "Name of the desktop application group."
  type        = string
}

variable "desktop_application_group_friendly_name" {
  description = "Friendly name of the desktop application group."
  type        = string
  default     = null
}

variable "workspace_name" {
  description = "Name of the Azure Virtual Desktop workspace."
  type        = string
}

variable "workspace_friendly_name" {
  description = "Friendly name of the workspace."
  type        = string
  default     = null
}

variable "workspace_description" {
  description = "Workspace description."
  type        = string
  default     = "Workspace for AVD rip-and-replace deployments"
}

variable "tags" {
  description = "Tags applied to control plane resources."
  type        = map(string)
  default     = {}
}
