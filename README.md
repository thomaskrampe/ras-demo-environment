# Parallels RAS Demo Environment (Azure)

This repository contains Terraform configurations to deploy a complete **Parallels Remote Application Server (RAS)** demo environment on Microsoft Azure. It uses **Windows Server 2025 Datacenter Azure Edition** for all virtual machines.

## Architecture Overview

The infrastructure is deployed within a single Virtual Network (`10.100.0.0/16`) divided into three specialized subnets. The VNet DNS is configured to use the PDC's static IP (`10.100.3.10`) as primary and Azure DNS (`168.63.129.16`) as secondary.

### 1. Network Structure

* **Subnet 1 (Jump Host):** `10.100.1.0/24` - Contains the Jump VM for administrative access.
* **Subnet 2 (Gateway):** `10.100.2.0/24` - Contains the RAS Secure Gateway (SGW).
* **Subnet 3 (Backend):** `10.100.3.0/24` - Contains the Core Infrastructure (PDC, RCB, WTS).

### 2. Virtual Machines

| VM Name | Role | Subnet | Private IP | Access |
| :--- | :--- | :--- | :--- | :--- |
| `demo-pdc-01` | Primary Domain Controller (AD DS / DNS) | Subnet 3 | `10.100.3.10` (static) | Internal |
| `demo-rcb-01` | RAS Connection Broker | Subnet 3 | Dynamic | Internal |
| `demo-wts-01` | RD Session Host (Workstation) | Subnet 3 | Dynamic | Internal |
| `demo-sgw-01` | RAS Secure Gateway | Subnet 2 | Dynamic | Public (HTTP/S) |
| `demo-jmp-01` | Jump Host | Subnet 1 | Dynamic | Public (RDP) |

All VMs use:

* **Size:** `Standard_B2ls_v2`
* **OS Disk:** 128 GB StandardSSD_LRS
* **Admin username:** `adminazure` (default, configurable via `vm_admin_username`)
* **Domain:** `rasdemo.local`

## Automation Features

The deployment includes several automated post-installation steps:

* **Active Directory Setup:** Automated forest creation (`rasdemo.local`) on the PDC via Custom Script Extension, followed by automated domain join for RCB and WTS. Each join waits for the domain to become reachable before proceeding.
* **Parallels RAS Installation:** After the RCB domain join and a 3-minute reboot wait, Parallels RAS (version 21.1) is downloaded and installed via `azurerm_virtual_machine_run_command`. Installed components: Connection Broker (`F_Controller`), Console (`F_Console`), and PowerShell module (`F_PowerShell`). The service is set to Automatic start and the RASAdmin PowerShell module is imported.
* **Network Security Groups:**
  * `jmp_nsg`: Allows RDP (3389) from Internet.
  * `sgw_nsg`: Allows HTTP (80) and HTTPS (443) from Internet.
  * `subnet3_nsg`: Allows ICMP, RDP (3389), and AD ports (53, 88, 389, 445, 636, 3268, 3269) from within the VNet.

## Prerequisites

* [Terraform](https://www.terraform.io/downloads.html) installed.
* An active Azure Subscription.
* Azure CLI configured (`az login`).
* **Azure Storage Account for Terraform backend:** The state is stored remotely in Azure Blob Storage. The backend is configured in `providers.tf`:
  * Resource Group: `rg-internal`
  * Storage Account: `tfstate4711`
  * Container: `tfstate`
  * Key: `azure-tf.terraform.tfstate`

  Ensure this storage account exists before running `terraform init`.

  ### Create storage account (if not already exists)

  ```bash
    RESOURCE_GROUP_NAME=terraformstate  
    STORAGE_ACCOUNT_NAME=tfstate$RANDOM  
    CONTAINER_NAME=tfstate  

    # Create resource group  
    az group create --name $RESOURCE_GROUP_NAME --location westeurope  

    # Create storage account  
    az storage account create --resource-group $RESOURCE_GROUP_NAME --name $STORAGE_ACCOUNT_NAME --sku Standard_LRS --encryption-services blob  

    # Get storage account key
    ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)  

    # Create blob container  
    az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $ACCOUNT_KEY  
  ```

## Usage

1. **Initialize Terraform:**

    ```bash
    terraform init
    ```

2. **Configure Variables:**
    A `terraform.tfvars` file is already present. Review and adjust the values as needed — especially the admin password and the RAS installer URL if a newer version is available:

    ```hcl
    vm_admin_password = "YourComplexPassword123!"
    location          = "westeurope"
    prefix            = "rasdemo"
    ras_installer_url = "https://download.parallels.com/ras/v21/21.1.1.26691/RASInstaller-21.1.26691.msi"
    ```

3. **Deploy Infrastructure:**

    ```bash
    terraform apply
    ```

4. **Accessing the Environment:**
    * After apply, Terraform outputs RDP and HTTPS connection strings directly.
    * Connect to **`demo-jmp-01`** via RDP using its Public IP (`jump_rdp_connection` output).
    * From the Jump Host, manage internal servers via their private IPs (`private_ips` output).
    * The SGW is reachable at the `sgw_https_url` output once Parallels RAS is configured.

## File Structure

* `providers.tf`: Defines required providers (AzureRM, Time) and the Azure backend for remote state.
* `variables.tf`: Input variables for customization (`location`, `prefix`, `tags`, `vm_admin_username`, `vm_admin_password`, `ras_installer_url`).
* `network.tf`: VNet (`10.100.0.0/16`), three Subnets, and Resource Group. DNS servers: `10.100.3.10` (PDC, primary) and `168.63.129.16` (Azure DNS, secondary).
* `machines.tf`: VM definitions, NICs, NSGs, Custom Script Extensions (AD setup & domain join), and Run Command (RAS installation).
* `outputs.tf`: Public IPs, private IPs (PDC, RCB, WTS, SGW), subnet IDs, direct RDP connection string, and HTTPS URL.
* `terraform.tfvars`: Local variable values (keep this file secure — contains the admin password).

## Azure Cost Estimation (as of May 2026)

All prices in USD, Pay-as-you-go, Region: West Europe. Source: Azure Retail Prices API.

### Price Basis

| Resource | SKU | Price |
| :--- | :--- | :--- |
| VM (Windows) | Standard_B2ls_v2 | $0.0572/h |
| OS Disk | StandardSSD LRS E10 (128 GiB) | $9.60/month |
| Public IP | Standard IPv4 Static | $0.005/h |
| VNet, Subnets, NICs, NSGs | | free |

### Fixed Costs (always, even when VMs are deallocated)

| Resource | Count | Unit | Per Month |
| :--- | :---: | ---: | ---: |
| OS Disks (128 GiB StandardSSD) | 5 | $9.60 | $48.00 |
| Public IPs (Standard Static) | 2 | $3.65 | $7.30 |
| **Total fixed costs** | | | **$55.30** |

### Variable Costs (running VMs only)

| Resource | Count | Hourly rate (total) |
| :--- | :---: | ---: |
| VMs (Standard_B2ls_v2 Windows) | 5 | $0.286/h |

### Total Costs by Usage Scenario

| Scenario | VM runtime | VM costs | Fixed costs | Total/month |
| :--- | ---: | ---: | ---: | ---: |
| 24/7 continuous operation | 730 h | $208.78 | $55.30 | **$264.08** |
| Business hours (8h/day, Mon–Fri) | 173 h | $49.50 | $55.30 | **$104.80** |
| Demo use (4h/day, 10 days/month) | 40 h | $11.44 | $55.30 | **$66.74** |

### Notes

* Deallocated VMs (stopped via Azure portal) incur no compute costs. Disks and Public IPs are still charged.
* Outbound data transfer is free up to 100 GB/month, then from $0.087/GB (Zone 1).
* Prices exclude VAT and USD/EUR exchange rate fluctuations.
* Reserved Instances (1 year) would reduce VM costs by ~35–40%, but are unusual for a demo environment.

## Important Notes

* **Security:** The Jump Host and Gateway have Public IPs. Use strong passwords and consider restricting source IP ranges in the NSG rules for production-like scenarios. The `terraform.tfvars` file contains the admin password and must not be committed to version control.
* **Costs:** This environment deploys five `Standard_B2ls_v2` VMs. Be aware of the associated Azure costs and deallocate VMs when not in use.
* **Provisioning Time:** AD Forest creation and Domain Joins require reboots. The full `terraform apply` — including the 3-minute wait and RAS installation — takes approximately 20-30 minutes.
* **RAS Installer URL:** Defined as the `ras_installer_url` variable in `variables.tf`. Update this variable when upgrading to a new Parallels RAS version.

### Important Parallels RAS Notes

* **Connection Broker:** is not initialized. You need to acquire a valid license or use a trial license first.
* **Secure Gateway:** is not domain joined and Parallels RAS is not installed on it (this is part of the demo).
* **WTS machine:** is domain joined but nothing is installed (this is part of the demo).

### Demo Script

1. Activate the Connection Broker with a license (prepaid or trial)
2. Install Secure Gateway from RAS Console (or PowerShell)
3. Add WTS to the farm (including Agent and RDS Role deployment)
4. All the other stuff you want to show
