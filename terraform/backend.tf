terraform {
  backend "azurerm" {
    resource_group_name  = "AKS-from-Mac"
    storage_account_name = "cheneyawiacbackend"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
