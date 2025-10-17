variable "resource_group_name" {
  description = "The name of the Resource Group in which to create the resources."
  type        = string
  default     = "bechong"
}

variable "use_existing_resource_group" {
  description = "Set to true to use an existing Resource Group; set to false to create a new one."
  type        = bool
  default     = true
}

variable "location" {
  description = "The Azure region where all resources will be created."
  type        = string
  default     = "Southeast Asia"
}

variable "aks_count" {
  description = "The number of AKS clusters and associated Blob Storages to provision."
  type        = number
  default     = 2 # Can be changed to 1, 2, or more
  validation {
    condition     = var.aks_count >= 1
    error_message = "The 'aks_count' must be at least 1."
  }
}

variable "vm_admin_username" {
  description = "The Administrator username for the Ubuntu VM."
  type        = string
  default     = "paloaltouser"
}

variable "vm_admin_password" {
  description = "The Administrator password for the Ubuntu VM (minimum 12 characters, complex)."
  type        = string
  sensitive   = true
  default     = "P@loAlto1!"
}

variable "vm_size" {
  description = "The size of the Virtual Machine."
  type        = string
  default     = "Standard_B2s" # Small, cost-effective size for Jenkins testing
}

variable "acr_name" {
  description = "The globally unique name for the Azure Container Registry (must be lowercase, letters/numbers only)."
  type        = string
  default     = "bechongpaloaltotestacr"
}