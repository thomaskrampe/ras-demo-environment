# =============================================
# Windows Server 2025 Datacenter Azure Edition
# =============================================
locals {
  vm_common = {
    size               = "Standard_B2ls_v2"
    image_publisher    = "MicrosoftWindowsServer"
    image_offer        = "WindowsServer"
    image_sku          = "2025-datacenter-azure-edition"
    image_version      = "latest"
    admin_username     = "adminazure"
    os_disk_size_gb    = 128
    vm_tags = merge(var.tags, {
      OS      = "WindowsServer2025"
      Tier    = "Compute"
    })
  }
  
  domain_name = "rasdemo.local"
}

# ========================================
# SUBNET 3 NICs (Private: PDC, RCB, WTS)
# ========================================

# PDC NIC: Statische IP, damit er als verlässlicher DNS-Server agieren kann
resource "azurerm_network_interface" "pdc_nic" {
  name                = "nic-${var.prefix}-pdc-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.ad.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.100.3.10" # In der network.tf zeigt vnet dns_servers auf diese IP
  }
  
  tags = local.vm_common.vm_tags
}

# RCB & WTS NICs: Dynamische IPs
resource "azurerm_network_interface" "subnet3_nics" {
  for_each = toset(["rcb", "wts"])
  
  name                = "nic-${var.prefix}-${each.key}-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.ad.id
    private_ip_address_allocation = "Dynamic"
  }
  
  tags = local.vm_common.vm_tags
}

# NSG Subnet 3: ICMP + RDP + AD (KEIN WinRM!)
resource "azurerm_network_security_group" "subnet3_nsg" {
  name                = "nsg-${var.prefix}-subnet-3"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  # ICMP (Ping)
  security_rule {
    name                       = "Allow-ICMP-Internal"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_address_prefixes    = ["10.100.0.0/16"]
    source_port_range          = "*"
    destination_port_range     = "*"
    destination_address_prefix = "*"
  }
  
  # RDP + AD Ports
  security_rule {
    name                       = "Allow-RDP-AD-Internal"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = ["10.100.0.0/16"]
    source_port_range          = "*"
    destination_port_ranges    = ["3389", "53", "88", "389", "445", "636", "3268", "3269"]
    destination_address_prefix = "*"
  }
  
  tags = local.vm_common.vm_tags
}

# NSG Zuordnung für den PDC
resource "azurerm_network_interface_security_group_association" "pdc_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.pdc_nic.id
  network_security_group_id = azurerm_network_security_group.subnet3_nsg.id
}

# NSG Zuordnung für RCB und WTS
resource "azurerm_network_interface_security_group_association" "subnet3_nsg_assoc" {
  for_each = azurerm_network_interface.subnet3_nics
  
  network_interface_id      = each.value.id
  network_security_group_id = azurerm_network_security_group.subnet3_nsg.id
}

# ========================================
# SUBNET 3 VMs (Private: PDC, RCB, WTS)
# ========================================

# PDC VM
resource "azurerm_windows_virtual_machine" "pdc_vm" {
  name                  = "demo-pdc-01"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = local.vm_common.size
  admin_username        = local.vm_common.admin_username
  admin_password        = var.vm_admin_password
  
  network_interface_ids = [azurerm_network_interface.pdc_nic.id]
  
  source_image_reference {
    publisher = local.vm_common.image_publisher
    offer     = local.vm_common.image_offer
    sku       = local.vm_common.image_sku
    version   = local.vm_common.image_version
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = local.vm_common.os_disk_size_gb
  }
  
  patch_mode = "AutomaticByPlatform"
  
  depends_on = [
    azurerm_network_interface_security_group_association.pdc_nsg_assoc
  ]
  
  tags = local.vm_common.vm_tags
}

# RCB & WTS VMs
resource "azurerm_windows_virtual_machine" "subnet3_vms" {
  for_each = {
    "rcb" = { name = "demo-rcb-01" }
    "wts" = { name = "demo-wts-01" }
  }
  
  name                  = each.value.name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = local.vm_common.size
  admin_username        = local.vm_common.admin_username
  admin_password        = var.vm_admin_password
  
  network_interface_ids = [azurerm_network_interface.subnet3_nics[each.key].id]
  
  source_image_reference {
    publisher = local.vm_common.image_publisher
    offer     = local.vm_common.image_offer
    sku       = local.vm_common.image_sku
    version   = local.vm_common.image_version
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = local.vm_common.os_disk_size_gb
  }
  
  patch_mode = "AutomaticByPlatform"
  
  depends_on = [
    azurerm_network_interface_security_group_association.subnet3_nsg_assoc
  ]
  
  tags = local.vm_common.vm_tags
}

# ============================================
# DOMAIN INSTALLATION & JOIN (Custom Scripts)
# ============================================

# AD Installation auf PDC (mit verzögertem Neustart zur Vermeidung von Terraform Errors)
# Custom Script Extension: AD Forest Installation (PDC)
resource "azurerm_virtual_machine_extension" "domain_create_pdc" {
  name                 = "create-ad-forest"
  virtual_machine_id   = azurerm_windows_virtual_machine.pdc_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  settings = jsonencode({
    # HIER KORRIGIERT: $pass statt $$pass
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools; $pass = ConvertTo-SecureString '${var.vm_admin_password}' -AsPlainText -Force; Install-ADDSForest -DomainName '${local.domain_name}' -SafeModeAdministratorPassword $pass -InstallDns -Force -NoRebootOnCompletion; shutdown.exe /r /t 15\""
  })
}

# Custom Script Extension: Domain Join für RCB
resource "azurerm_virtual_machine_extension" "domain_join_rcb" {
  name                 = "domain-join-rcb"
  virtual_machine_id   = azurerm_windows_virtual_machine.subnet3_vms["rcb"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"$cred = New-Object System.Management.Automation.PSCredential('${local.domain_name}\\${local.vm_common.admin_username}', (ConvertTo-SecureString '${var.vm_admin_password}' -AsPlainText -Force)); while (!(Test-Connection -ComputerName '${local.domain_name}' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Output 'Warte auf Domain...'; Start-Sleep -Seconds 15 }; Add-Computer -DomainName '${local.domain_name}' -Credential $cred -Restart -Force\""
  })
  
  depends_on = [    
    azurerm_virtual_machine_extension.domain_create_pdc
  ]
}

# Custom Script Extension: Domain Join für WTS
resource "azurerm_virtual_machine_extension" "domain_join_wts" {
  name                 = "domain-join-wts"
  virtual_machine_id   = azurerm_windows_virtual_machine.subnet3_vms["wts"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"$cred = New-Object System.Management.Automation.PSCredential('${local.domain_name}\\${local.vm_common.admin_username}', (ConvertTo-SecureString '${var.vm_admin_password}' -AsPlainText -Force)); while (!(Test-Connection -ComputerName '${local.domain_name}' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Output 'Warte auf Domain...'; Start-Sleep -Seconds 15 }; Add-Computer -DomainName '${local.domain_name}' -Credential $cred -Restart -Force\""
  })
  
  depends_on = [    
    azurerm_virtual_machine_extension.domain_create_pdc
  ]
}

# ========================================
# SUBNET 1 VM: demo-jmp-01 (Public RDP)
# ========================================
resource "azurerm_public_ip" "jmp_pip" {
  name                = "pip-${var.prefix}-jmp-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
  
  tags = local.vm_common.vm_tags
}

resource "azurerm_network_interface" "jmp_nic" {
  name                = "nic-${var.prefix}-jmp-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.jump.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jmp_pip.id
  }
  
  tags = local.vm_common.vm_tags
}

resource "azurerm_network_security_group" "jmp_nsg" {
  name                = "nsg-${var.prefix}-jmp-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  security_rule {
    name                       = "Allow-RDP-Public"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_port_range     = "3389"
    destination_address_prefix = "*"
  }
  
  tags = local.vm_common.vm_tags
}

resource "azurerm_network_interface_security_group_association" "jmp_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.jmp_nic.id
  network_security_group_id = azurerm_network_security_group.jmp_nsg.id
}

resource "azurerm_windows_virtual_machine" "jmp_vm" {
  name                  = "demo-jmp-01"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = local.vm_common.size
  admin_username        = local.vm_common.admin_username
  admin_password        = var.vm_admin_password
  
  network_interface_ids = [azurerm_network_interface.jmp_nic.id]
  
  source_image_reference {
    publisher = local.vm_common.image_publisher
    offer     = local.vm_common.image_offer
    sku       = local.vm_common.image_sku
    version   = local.vm_common.image_version
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = local.vm_common.os_disk_size_gb
  }
  
  patch_mode = "AutomaticByPlatform"
  tags       = local.vm_common.vm_tags
}

# ========================================
# SUBNET 2 VM: demo-sgw-01 (Public Web)
# ========================================
resource "azurerm_public_ip" "sgw_pip" {
  name                = "pip-${var.prefix}-sgw-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
  
  tags = local.vm_common.vm_tags
}

resource "azurerm_network_interface" "sgw_nic" {
  name                = "nic-${var.prefix}-sgw-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.sgw.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.sgw_pip.id
  }
  
  tags = local.vm_common.vm_tags
}

resource "azurerm_network_security_group" "sgw_nsg" {
  name                = "nsg-${var.prefix}-sgw-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  security_rule {
    name                       = "Allow-HTTP-HTTPS-Public"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    destination_address_prefix = "*"
  }
  
  tags = local.vm_common.vm_tags
}

resource "azurerm_network_interface_security_group_association" "sgw_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.sgw_nic.id
  network_security_group_id = azurerm_network_security_group.sgw_nsg.id
}

resource "azurerm_windows_virtual_machine" "sgw_vm" {
  name                  = "demo-sgw-01"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = local.vm_common.size
  admin_username        = local.vm_common.admin_username
  admin_password        = var.vm_admin_password
  
  network_interface_ids = [azurerm_network_interface.sgw_nic.id]
  
  source_image_reference {
    publisher = local.vm_common.image_publisher
    offer     = local.vm_common.image_offer
    sku       = local.vm_common.image_sku
    version   = local.vm_common.image_version
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = local.vm_common.os_disk_size_gb
  }
  
  patch_mode = "AutomaticByPlatform"
  tags       = local.vm_common.vm_tags
}

# =========================================================
# Post-Install für RCB
# =========================================================

# Wartezeit, damit der RCB nach dem Domain Join in Ruhe booten kann
resource "time_sleep" "wait_for_rcb_reboot" {
  depends_on      = [azurerm_virtual_machine_extension.domain_join_rcb]
  create_duration = "3m" # Gib der VM 3 Minuten Zeit für den Neustart
}

# Post-Install Script via Run Command
resource "azurerm_virtual_machine_run_command" "post_install_rcb" {
  name               = "install-parallels-ras"
  virtual_machine_id = azurerm_windows_virtual_machine.subnet3_vms["rcb"].id
  location           = azurerm_resource_group.rg.location

  source {
    script = <<-SCRIPT
      $LogFile = "C:\install_parallels_ras.log"
      Start-Transcript -Path $LogFile -Force

      try {
          # 1. Verzeichnis erstellen (wie in Ansible)
          Write-Output "Erstelle Verzeichnis C:\tmp..."
          New-Item -Path "C:\tmp" -ItemType Directory -Force | Out-Null

          # 2. MSI herunterladen
          # $Url = "https://download.parallels.com/ras/v20/20.2.0.25893/RASInstaller-20.2.25893.msi"
          $url = "https://download.parallels.com/ras/v21/21.1.1.26691/RASInstaller-21.1.26691.msi"
          $OutPath = "C:\tmp\RASInstaller.msi"
          Write-Output "Lade Parallels RAS von $Url herunter..."
          Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing

          # 3. Installation ausführen (mit msiexec)
          $InstallArgs = "/i `"$OutPath`" ADDLOCAL=F_Controller,F_Console,F_PowerShell /l*v C:\tmp\RASinstaller.log /qn /norestart"
          Write-Output "Starte Installation..."
          
          $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
          
          # ExitCode 0 = Erfolg, 3010 = Neustart erforderlich (was bei /norestart okay ist)
          if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
              throw "Installation fehlgeschlagen mit ExitCode $($Process.ExitCode). Prüfe C:\tmp\RASinstaller.log"
          }

          # Kurze Pause, damit der Windows Service Control Manager den neuen Dienst erkennt
          Start-Sleep -Seconds 15

          # 4. Dienst konfigurieren und prüfen
          # HINWEIS: Ansible nutzt oft den DisplayName, PowerShell Get-Service bevorzugt den internen Namen. 
          # Wenn "RAS Connection Broker" der interne Name ist, klappt das.
          $ServiceName = "RAS Connection Broker" 
          Write-Output "Setze Dienst '$ServiceName' auf Automatisch und starte ihn..."
          
          Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
          Start-Service -Name $ServiceName -ErrorAction Stop
          
          $Service = Get-Service -Name $ServiceName
          if ($Service.Status -eq 'Running') {
              Write-Output "Erfolg: Dienst '$ServiceName' läuft!"
          } else {
              throw "Fehler: Dienst '$ServiceName' ist im Status $($Service.Status)."
          }

          # 5. PowerShell Modul prüfen & importieren
          $ModulePath = "C:\Program Files (x86)\Parallels\ApplicationServer\Modules\RASAdmin\4.0\RASAdmin.psd1"
          Write-Output "Importiere PowerShell Modul von '$ModulePath'..."
          
          Import-Module -Name $ModulePath -Force -ErrorAction Stop
          Write-Output "Erfolg: Parallels RAS PowerShell Modul erfolgreich importiert."

          Write-Output "+++ Parallels RAS Installation komplett abgeschlossen +++"

      } catch {
          Write-Error $_.Exception.Message
          Stop-Transcript
          exit 1 # Bricht den Terraform-Lauf mit einem Fehler ab
      }

      Stop-Transcript
    SCRIPT
  }

  depends_on = [time_sleep.wait_for_rcb_reboot]
}