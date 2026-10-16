# =============================================
# Windows Server 2025 Datacenter Azure Edition
# =============================================
locals {
  vm_common = {
    size            = "Standard_B2ls_v2"
    image_publisher = "MicrosoftWindowsServer"
    image_offer     = "WindowsServer"
    image_sku       = "2025-datacenter-azure-edition"
    image_version   = "latest"
    admin_username  = var.vm_admin_username
    os_disk_size_gb = 128
    vm_tags = merge(var.tags, {
      OS   = "WindowsServer2025"
      Tier = "Compute"
    })
  }

  domain_name = var.domain_name

  # Zentrale VM-Definition. Jeder Eintrag erzeugt NIC, NSG-Zuordnung und VM
  # (public = true zusätzlich eine Public IP).
  # PDC: Statische IP, damit er als verlässlicher DNS-Server agieren kann
  # (vnet dns_servers in network.tf zeigt auf diese IP).
  vms = {
    pdc = { name = "demo-pdc-01", subnet = "ad", nsg = "ad", ip_config = "internal", private_ip = "10.100.3.10", public = false, dns_label = null }
    rcb = { name = "demo-rcb-01", subnet = "ad", nsg = "ad", ip_config = "internal", private_ip = null, public = false, dns_label = null }
    wts = { name = "demo-wts-01", subnet = "ad", nsg = "ad", ip_config = "internal", private_ip = null, public = false, dns_label = null }
    sgw = { name = "demo-sgw-01", subnet = "sgw", nsg = "sgw", ip_config = "public", private_ip = null, public = true, dns_label = null }
    jmp = { name = "demo-jmp-01", subnet = "jump", nsg = "jmp", ip_config = "public", private_ip = null, public = true, dns_label = "${var.prefix}-jmp-01" }
  }

  public_vms = { for k, v in local.vms : k => v if v.public }

  subnet_ids = {
    jump = azurerm_subnet.jump.id
    sgw  = azurerm_subnet.sgw.id
    ad   = azurerm_subnet.ad.id
  }

  nsg_ids = {
    ad  = azurerm_network_security_group.subnet3_nsg.id
    sgw = azurerm_network_security_group.sgw_nsg.id
    jmp = azurerm_network_security_group.jmp_nsg.id
  }
}

# ========================================
# NETWORK SECURITY GROUPS
# ========================================

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
    source_address_prefixes    = var.allowed_rdp_cidrs
    source_port_range          = "*"
    destination_port_range     = "3389"
    destination_address_prefix = "*"
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

# ========================================
# PUBLIC IPs, NICs, NSG-Zuordnung, VMs
# ========================================

resource "azurerm_public_ip" "pip" {
  for_each = local.public_vms

  name                = "pip-${var.prefix}-${each.key}-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
  domain_name_label   = each.value.dns_label

  tags = local.vm_common.vm_tags
}

resource "azurerm_network_interface" "nic" {
  for_each = local.vms

  name                = "nic-${var.prefix}-${each.key}-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = each.value.ip_config
    subnet_id                     = local.subnet_ids[each.value.subnet]
    private_ip_address_allocation = each.value.private_ip == null ? "Dynamic" : "Static"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = each.value.public ? azurerm_public_ip.pip[each.key].id : null
  }

  tags = local.vm_common.vm_tags
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  for_each = local.vms

  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = local.nsg_ids[each.value.nsg]
}

resource "azurerm_windows_virtual_machine" "vm" {
  for_each = local.vms

  name                  = each.value.name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = local.vm_common.size
  admin_username        = local.vm_common.admin_username
  admin_password        = var.vm_admin_password
  patch_mode            = "AutomaticByPlatform"
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

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

  depends_on = [azurerm_network_interface_security_group_association.nsg_assoc]

  tags = local.vm_common.vm_tags
}

# ============================================
# DOMAIN INSTALLATION & JOIN (Custom Scripts)
# ============================================

# AD Installation auf PDC (mit verzögertem Neustart zur Vermeidung von Terraform Errors)
# Custom Script Extension: AD Forest Installation (PDC)
resource "azurerm_virtual_machine_extension" "domain_create_pdc" {
  name                 = "create-ad-forest"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm["pdc"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({})
  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools; $pass = ConvertTo-SecureString '${var.vm_admin_password}' -AsPlainText -Force; Install-ADDSForest -DomainName '${local.domain_name}' -SafeModeAdministratorPassword $pass -InstallDns -Force -NoRebootOnCompletion; shutdown.exe /r /t 15\""
  })
}

# Custom Script Extension: Domain Join für RCB
resource "azurerm_virtual_machine_extension" "domain_join_rcb" {
  name                 = "domain-join-rcb"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm["rcb"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({})
  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"$cred = New-Object System.Management.Automation.PSCredential('${local.domain_name}\\${local.vm_common.admin_username}', (ConvertTo-SecureString '${var.vm_admin_password}' -AsPlainText -Force)); while (!(Test-Connection -ComputerName '${local.domain_name}' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Output 'Warte auf Domain...'; Start-Sleep -Seconds 15 }; Add-Computer -DomainName '${local.domain_name}' -Credential $cred -Restart -Force\""
  })

  depends_on = [
    azurerm_virtual_machine_extension.domain_create_pdc
  ]
}

# Custom Script Extension: Domain Join für WTS
resource "azurerm_virtual_machine_extension" "domain_join_wts" {
  name                 = "domain-join-wts"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm["wts"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({})
  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"$cred = New-Object System.Management.Automation.PSCredential('${local.domain_name}\\${local.vm_common.admin_username}', (ConvertTo-SecureString '${var.vm_admin_password}' -AsPlainText -Force)); while (!(Test-Connection -ComputerName '${local.domain_name}' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Output 'Warte auf Domain...'; Start-Sleep -Seconds 15 }; Add-Computer -DomainName '${local.domain_name}' -Credential $cred -Restart -Force\""
  })

  depends_on = [
    azurerm_virtual_machine_extension.domain_create_pdc
  ]
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
  virtual_machine_id = azurerm_windows_virtual_machine.vm["rcb"].id
  location           = azurerm_resource_group.rg.location

  source {
    script = <<-SCRIPT
      $LogFile = "C:\install_parallels_ras.log"
      Start-Transcript -Path $LogFile -Force

      try {
          # 1. Verzeichnis erstellen (wie in Ansible)
          Write-Output "Erstelle Verzeichnis c:\temp..."
          New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null

          # 2. MSI herunterladen
          $Url = "${var.ras_installer_url}"
          $OutPath = "C:\temp\RASInstaller.msi"
          Write-Output "Lade Parallels RAS von $Url herunter..."

          # MSI herunterladen mit Retry (WebClient streamt direkt auf Disk,
          # Invoke-WebRequest lädt alles in den RAM - unzuverlässig bei großen Dateien)
          $maxRetries = 5
          $retryInterval = 30
          $downloaded = $false
          for ($i = 1; $i -le $maxRetries; $i++) {
              try {
                  Write-Output "Download-Versuch $i/$($maxRetries)..."
                  $webClient = New-Object System.Net.WebClient
                  $webClient.DownloadFile($Url, $OutPath)
                  $downloaded = $true
                  Write-Output "Download erfolgreich abgeschlossen."
                  break
              } catch {
                  Write-Output "Versuch $i/$($maxRetries) fehlgeschlagen: $($_.Exception.Message)"
                  if ($i -lt $maxRetries) { Start-Sleep -Seconds $retryInterval }
              }
          }
          if (-not $downloaded) {
              throw "Download nach $($maxRetries) Versuchen fehlgeschlagen. Abbruch."
          }

          # 3. Installation ausführen (mit msiexec)
          $InstallArgs = "/i `"$OutPath`" ADDLOCAL=F_Controller,F_Console,F_PowerShell /l*v C:\temp\RASinstaller.log /qn /norestart"
          Write-Output "Starte Installation..."
          
          $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
          
          # ExitCode 0 = Erfolg, 3010 = Neustart erforderlich (was bei /norestart okay ist)
          if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
              throw "Installation fehlgeschlagen mit ExitCode $($Process.ExitCode). Prüfe C:\temp\RASinstaller.log"
          }

          # Kurze Pause, damit der Windows Service Control Manager den neuen Dienst erkennt
          Start-Sleep -Seconds 15

          # 4. Dienst konfigurieren und prüfen
          # HINWEIS: Ansible nutzt oft den DisplayName, PowerShell Get-Service bevorzugt den internen Namen. 
          # Der Service Name wird dynamisch ermittelt.
          $ServiceName = (Get-Service | Where-Object { $_.DisplayName -like "*RAS Connection Broker*" }).Name
          Write-Output "Setze Dienst '$ServiceName' auf Automatisch und starte ihn..."
          
          Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
          Start-Service -Name $ServiceName -ErrorAction Stop
          
          $Service = Get-Service -Name $ServiceName
          if ($Service.Status -eq 'Running') {
              Write-Output "Erfolg: Dienst '$ServiceName' läuft!"
          } else {
              throw "Fehler: Dienst '$ServiceName' ist im Status $($Service.Status)."
          }

          # 5. PowerShell Modul dynamisch prüfen & importieren
          $ModulePath = Get-ChildItem "C:\Program Files (x86)\Parallels\ApplicationServer\Modules\RASAdmin" -Recurse -Filter "RASAdmin.psd1" | Select-Object -First 1 -ExpandProperty FullName
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
