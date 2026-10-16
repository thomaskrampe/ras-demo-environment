output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "subnet_ids" {
  value = {
    jump = azurerm_subnet.jump.id
    sgw  = azurerm_subnet.sgw.id
    ad   = azurerm_subnet.ad.id
  }
}

output "public_ips" {
  description = "Öffentliche IPs der Jump Host & SGW VMs"
  value = {
    jump_host = azurerm_public_ip.pip["jmp"].ip_address
    sgw       = azurerm_public_ip.pip["sgw"].ip_address
  }
}

output "jump_host_public_ip" {
  description = "Public IP demo-jmp-01 (RDP 3389)"
  value       = azurerm_public_ip.pip["jmp"].ip_address
}

output "sgw_public_ip" {
  description = "Public IP demo-sgw-01 (HTTP 80/HTTPS 443)"
  value       = azurerm_public_ip.pip["sgw"].ip_address
}

# Bonus: RDP/HTTPS Links (kopierbar)
output "jump_host_fqdn" {
  description = "Azure DNS FQDN für demo-jmp-01 (z.B. für Zertifikate oder RDP per Hostname)"
  value       = azurerm_public_ip.pip["jmp"].fqdn
}

output "jump_rdp_connection" {
  description = "Direkter RDP Link für demo-jmp-01"
  value       = "mstsc /v:${azurerm_public_ip.pip["jmp"].ip_address}"
}

output "sgw_https_url" {
  description = "HTTPS URL für demo-sgw-01"
  value       = "https://${azurerm_public_ip.pip["sgw"].ip_address}"
}

output "private_ips" {
  description = "Private IPs der internen VMs"
  value = {
    pdc = azurerm_network_interface.nic["pdc"].private_ip_address
    rcb = azurerm_network_interface.nic["rcb"].private_ip_address
    wts = azurerm_network_interface.nic["wts"].private_ip_address
    sgw = azurerm_network_interface.nic["sgw"].private_ip_address
  }
}

resource "local_file" "connection_info" {
  filename        = "${path.module}/connection_info.md"
  file_permission = "0600"
  content         = <<-EOT
# RAS Demo Environment – Connection Info

> Generiert von Terraform am ${timestamp()}

## Public Access

| Service   | Adresse                                                              | Protokoll |
|-----------|----------------------------------------------------------------------|-----------|
| Jump Host | `${azurerm_public_ip.pip["jmp"].ip_address}`                            | RDP 3389  |
| RDP Link  | `mstsc /v:${azurerm_public_ip.pip["jmp"].ip_address}`                   |           |
| Jump FQDN | `${azurerm_public_ip.pip["jmp"].fqdn}`                                  |           |
| SGW       | `https://${azurerm_public_ip.pip["sgw"].ip_address}`                    | HTTPS 443 |

## Private IPs

| VM  | Private IP                                                                          |
|-----|-------------------------------------------------------------------------------------|
| PDC | `${azurerm_network_interface.nic["pdc"].private_ip_address}`                           |
| RCB | `${azurerm_network_interface.nic["rcb"].private_ip_address}`               |
| WTS | `${azurerm_network_interface.nic["wts"].private_ip_address}`               |
| SGW | `${azurerm_network_interface.nic["sgw"].private_ip_address}`                           |

## Credentials

- **Username:** `${var.vm_admin_username}`
- **Password:** siehe `terraform.tfvars`

## Infrastruktur

- **Resource Group:** `${azurerm_resource_group.rg.name}`
- **Location:** `${var.location}`
- **Domain:** `${var.domain_name}`
EOT
}
