# Parallels RAS Demo Environment (Azure)

This repository contains Terraform configurations to deploy a complete **Parallels Remote Application Server (RAS)** demo environment on Microsoft Azure. It uses **Windows Server 2025 Datacenter Azure Edition** for all virtual machines.

## Architecture Overview

The infrastructure is deployed within a single Virtual Network (`10.100.0.0/16`) divided into three specialized subnets:

### 1. Network Structure

* **Subnet 1 (Jump Host):** `10.100.1.0/24` - Contains the Jump VM for administrative access.
* **Subnet 2 (Gateway):** `10.100.2.0/24` - Contains the RAS Secure Gateway (SGW).
* **Subnet 3 (Backend):** `10.100.3.0/24` - Contains the Core Infrastructure (PDC, RCB, WTS).

### 2. Virtual Machines

| VM Name | Role | Subnet | Access |
| :--- | :--- | :--- | :--- |
| `demo-pdc-01` | Primary Domain Controller (AD DS / DNS) | Subnet 3 | Internal |
| `demo-rcb-01` | RAS Connection Broker | Subnet 3 | Internal |
| `demo-wts-01` | RD Session Host (Workstation) | Subnet 3 | Internal |
| `demo-sgw-01` | RAS Secure Gateway | Subnet 2 | Public (HTTP/S) |
| `demo-jmp-01` | Jump Host | Subnet 1 | Public (RDP) |

## Automation Features

The deployment includes several automated post-installation steps:

* **Active Directory Setup:** Automated forest creation on the PDC and automated domain join for RCB and WTS.
* **Parallels RAS Installation:** Automated download and installation of Parallels RAS (version 21.1) on the Connection Broker (`demo-rcb-01`), including service configuration and PowerShell module import.
* **Network Security:** Automated provisioning of Network Security Groups (NSGs) with predefined rules for RDP, Active Directory communication, and Web traffic.

## Prerequisites

* [Terraform](https://www.terraform.io/downloads.html) installed.
* An active Azure Subscription.
* Azure CLI configured (`az login`).

## Usage

1. **Initialize Terraform:**
    ```bash
    terraform init
    ```

2. **Configure Variables:**
    Create a `terraform.tfvars` file (or use the existing one) and provide the required values, especially the sensitive admin password:
    
    ```hcl
    vm_admin_password = "YourComplexPassword123!"
    location          = "westeurope"
    prefix            = "rasdemo"
    ```

3. **Deploy Infrastructure:**
    ```
    terraform apply
    ```

4. **Accessing the Environment:**
    * Connect to the **Jump Host** via RDP using its Public IP (found in outputs).
    * From the Jump Host, you can manage the internal servers via their private IPs.

## File Structure

* `providers.tf`: Defines required providers (AzureRM, Time).
* `variables.tf`: Input variables for customization.
* `network.tf`: VNet, Subnets, and basic RG definition.
* `machines.tf`: VM definitions, NICs, NSGs, and Custom Script Extensions for AD and RAS setup.
* `outputs.tf`: (If present) Important information like Public IPs.
* `terraform.tfvars`: Local variable values (Should be kept secure).

## Important Notes

* **Security:** The Jump Host and Gateway have Public IPs. Ensure you use strong passwords and restrict source IP ranges in the NSG rules for production-like scenarios.
* **Costs:** This environment deploys `Standard_B2ls_v2` VMs. Be aware of the associated Azure costs.
* **Provisioning Time:** AD Forest creation and Domain Joins require reboots; the Terraform apply might take 15-20 minutes to complete fully.
