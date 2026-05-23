variable "location" {
  description = "Azure Region"
  type        = string
  default     = "westeurope"
}

variable "prefix" {
  description = "Prefix für einzigartige Namen"
  type        = string
  default     = "rasdemo"
}

variable "domain_name" {
  description = "Windows AD Domain"
  type        = string
  default     = "rasdemo.local"
}

variable "tags" {
  description = "Ressourcen-Tags"
  type        = map(string)
  default = {
    Environment = "demo"
    Owner       = "t.krampe"
    Project     = "Parallels-RAS-Demo"
  }
}

variable "vm_admin_username" {
  description = "Admin username for all VMs"
  type        = string
  default     = "adminazure"
}

variable "vm_admin_password" {
  description = "Admin Password für alle VMs (mind. 12 Zeichen, komplex)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vm_admin_password) >= 12
    error_message = "The admin password must be at least 12 characters long."
  }

  validation {
    condition     = can(regex("[A-Z]", var.vm_admin_password))
    error_message = "The admin password must contain at least one uppercase letter."
  }

  validation {
    condition     = can(regex("[a-z]", var.vm_admin_password))
    error_message = "The admin password must contain at least one lowercase letter."
  }

  validation {
    condition     = can(regex("[0-9]", var.vm_admin_password))
    error_message = "The admin password must contain at least one digit."
  }

  validation {
    condition     = can(regex("[^a-zA-Z0-9]", var.vm_admin_password))
    error_message = "The admin password must contain at least one special character."
  }
}

variable "ras_installer_url" {
  description = "Download-URL für den Parallels RAS Installer MSI. Bei einem Major-Release hier aktualisieren."
  type        = string
  default     = "https://download.parallels.com/ras/v21/21.1.1.26691/RASInstaller-21.1.26691.msi"
}
