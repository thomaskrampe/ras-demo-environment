# Adressen der VM-Ressourcen nach dem Umbau auf for_each.
# Verhindert, dass bestehende Ressourcen im State neu erstellt werden.

moved {
  from = azurerm_network_interface.pdc_nic
  to   = azurerm_network_interface.nic["pdc"]
}
moved {
  from = azurerm_network_interface.subnet3_nics["rcb"]
  to   = azurerm_network_interface.nic["rcb"]
}
moved {
  from = azurerm_network_interface.subnet3_nics["wts"]
  to   = azurerm_network_interface.nic["wts"]
}
moved {
  from = azurerm_network_interface.sgw_nic
  to   = azurerm_network_interface.nic["sgw"]
}
moved {
  from = azurerm_network_interface.jmp_nic
  to   = azurerm_network_interface.nic["jmp"]
}

moved {
  from = azurerm_public_ip.sgw_pip
  to   = azurerm_public_ip.pip["sgw"]
}
moved {
  from = azurerm_public_ip.jmp_pip
  to   = azurerm_public_ip.pip["jmp"]
}

moved {
  from = azurerm_network_interface_security_group_association.pdc_nsg_assoc
  to   = azurerm_network_interface_security_group_association.nsg_assoc["pdc"]
}
moved {
  from = azurerm_network_interface_security_group_association.subnet3_nsg_assoc["rcb"]
  to   = azurerm_network_interface_security_group_association.nsg_assoc["rcb"]
}
moved {
  from = azurerm_network_interface_security_group_association.subnet3_nsg_assoc["wts"]
  to   = azurerm_network_interface_security_group_association.nsg_assoc["wts"]
}
moved {
  from = azurerm_network_interface_security_group_association.sgw_nsg_assoc
  to   = azurerm_network_interface_security_group_association.nsg_assoc["sgw"]
}
moved {
  from = azurerm_network_interface_security_group_association.jmp_nsg_assoc
  to   = azurerm_network_interface_security_group_association.nsg_assoc["jmp"]
}

moved {
  from = azurerm_windows_virtual_machine.pdc_vm
  to   = azurerm_windows_virtual_machine.vm["pdc"]
}
moved {
  from = azurerm_windows_virtual_machine.subnet3_vms["rcb"]
  to   = azurerm_windows_virtual_machine.vm["rcb"]
}
moved {
  from = azurerm_windows_virtual_machine.subnet3_vms["wts"]
  to   = azurerm_windows_virtual_machine.vm["wts"]
}
moved {
  from = azurerm_windows_virtual_machine.sgw_vm
  to   = azurerm_windows_virtual_machine.vm["sgw"]
}
moved {
  from = azurerm_windows_virtual_machine.jmp_vm
  to   = azurerm_windows_virtual_machine.vm["jmp"]
}
