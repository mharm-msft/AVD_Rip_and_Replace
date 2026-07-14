variable "subscription_id" {
  description = "Subscription ID used by the example environment."
  type        = string
  default     = null
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
