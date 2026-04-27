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

variable "tags" {
  description = "Ressourcen-Tags"
  type        = map(string)
  default = {
    Environment = "demo"
    Owner       = "t.krampe"
    Project     = "Parallels-RAS-Demo"
  }
}

variable "vm_admin_password" {
  description = "Admin Password für alle VMs (mind. 12 Zeichen, komplex)"
  type        = string
  sensitive   = true
}
