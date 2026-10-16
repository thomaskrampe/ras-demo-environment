terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-internal"
    storage_account_name = "tfstate4711"
    container_name       = "tfstate"
    key                  = "azure-tf.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}