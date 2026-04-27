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
    jump_host = azurerm_public_ip.jmp_pip.ip_address
    sgw       = azurerm_public_ip.sgw_pip.ip_address
  }
}

output "jump_host_public_ip" {
  description = "Public IP demo-jmp-01 (RDP 3389)"
  value       = azurerm_public_ip.jmp_pip.ip_address
}

output "sgw_public_ip" {
  description = "Public IP demo-sgw-01 (HTTP 80/HTTPS 443)"
  value       = azurerm_public_ip.sgw_pip.ip_address
}

# Bonus: RDP/HTTPS Links (kopierbar)
output "jump_rdp_connection" {
  description = "Direkter RDP Link für demo-jmp-01"
  value       = "mstsc /v:${azurerm_public_ip.jmp_pip.ip_address}"
}

output "sgw_https_url" {
  description = "HTTPS URL für demo-sgw-01"
  value       = "https://${azurerm_public_ip.sgw_pip.ip_address}"
}
