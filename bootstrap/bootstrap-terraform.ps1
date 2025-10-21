<#
.SYNOPSIS
    Bootstraps the Azure environment for Terraform.
.DESCRIPTION
    Performs the following steps:
    - creates resource group
    - registers resource providers
    - creates storage account
    - creates storage blob
    - creates keyvault
    - creates self-signed X.509 cert in .pfx and .der format
    - create service principal
    - add certificate to ad app registration corresponding to service principal
    - grant key vault certificates officer role to service principal
    - import the pfx to the keyvault
    - create container for terraform backend
    - grant service principal access to container
    - initialise tf backend
#>

# Dot-source common configuration variables and functions
. .\common-config.ps1

# --- Configuration Variables ---
Set-Variable -Name ContainerName `
             -Value tfstate `
             -Option Constant -Scope Global


# --- Module Installation Start ---
# Set PSGallery as a trusted repository to avoid the trust prompt during module install
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Ensure NuGet is installed to avoid prompt (use -Confirm:$false for no-prompt)
Install-Module -Name NuGet -Force
Get-PackageProvider | where name -eq 'NuGet' | Install-PackageProvider -Force

# Install the Az module for the current user, allowing clobbering to avoid prompts
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# --- Module Installation End ---

# Connect to Azure account
Connect-AzAccount

