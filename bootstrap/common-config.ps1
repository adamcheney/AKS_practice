<#
.SYNOPSIS
    Common parameters and reusable functions.
.DESCRIPTION
    The bootstrapping scripts can dot-source this file to reuse common configuration variables and functions.
    These common, global constants:
    - ResourceGroupName - name of the resource group
    - Location - defaults to 'uksouth'
    - StorageAccountName - name of the backend storage account - made unique with random numeric
    - KeyVaultName - name of the KeyVault used to store ServicePrincipal cert  - made unique with random numeric
    - CertificateName - name of the ServicePrincipal cert
    - AppRegistrationName - name of the AD application for the ServicePrincipal
    These functions:
    - create resource group
    - register resource providers
    - create storage account
    - create storage blob
    - create keyvault
    - create self-signed X.509 cert in .pfx and .der format
    - create service principal
    - add certificate to ad app registration corresponding to service principal
    - grant key vault certificates officer role to service principal
    - import the pfx to the keyvault
    - create container for terraform backend
    - grant service principal access to container
.EXAMPLE
    Example command showing typical usage:
    .\MyScript.ps1 -Name1 "Value" -Name2 10
.NOTES
    Any additional information, like dependencies or version history.
#>

# --- Enforce TLS1.2 ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Configuration Variables ---
$config = @{
    resourceGroup = @{
        name = $env:AZURE_RG_NAME ?? "cheneyaw-aks-iac"
        location = $env:AZURE_LOCATION ?? "uksouth"
    }
    storageAccount = @{
        name = $env:AZURE_STORAGE_NAME ?? "cheneyaw-aks-iacbackend$(Get-Random -Minimum 1000 -Maximum 9999)"
        sku = "Standard_LRS"
    }
    terraform = @{
        containerName = "tfstate"
        stateFile = "aks.tfstate"
    }
    pulumi = @{
        containerName = "pulumistate"
    }
}

# --- Install PSResourceGet v3 ---
if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.PSResourceGet)) {
    Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force -Scope CurrentUser
}
# --- Dependency Modules ---
$Dependencies = (Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')).RequiredModules
$Dependencies | ForEach-Object {
    $Name = $_.ModuleName
    $RequiredVersion = $_.ModuleVersion
    # Check if the module is installed. Use -ListAvailable to check system-wide, not just current session.
    $InstalledModule = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue

    # Compare installed version to required version.
    if (-not ($InstalledModule | Where-Object Version -eq $RequiredVersion)) {
        Write-Host "Installing module '$Name' version '$RequiredVersion'..." -ForegroundColor Yellow
        try {
            $InstallParams = @{
                Name = $Name
                Version = $RequiredVersion
                Scope = 'CurrentUser'
                Repository = 'PSGallery'
            }
            Install-PSResource @InstallParams -ErrorAction Stop
            Write-Host "Module '$Name' installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install module '$Name'. Error: $($_.Exception.Message)"
            throw # Re-throw to stop the script
        }
    }
    else {
        Write-Host "Module '$Name' (v$($InstalledModule.Version)) already meets requirement (v$RequiredVersion). Skipping installation." -ForegroundColor Cyan
    }
}

# --- Log in to Azure if not already ---
if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Write-Host "No Azure context found. Initiating login..." -ForegroundColor Yellow
    try {
        Connect-AzAccount -ErrorAction Stop
        Write-Host "Logged in to Azure successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Azure login failed. Error: $($_.Exception.Message)"
        throw # Re-throw to stop the script
    }
}   
else {
    Write-Host "Azure context found. Already logged in." -ForegroundColor Cyan
}   

# --- Reusable Functions ---
function Set-AzResourceGroup {
    <#
    .SYNOPSIS
        Creates the foundational Azure Resource Group.
    .DESCRIPTION
        Ensures the specified Resource Group exists at the specified location.
        This function is idempotent.
    .PARAMETER ResourceGroupName
        The name of the Resource Group to create or verify.
    .PARAMETER RGLocation
        The Azure location/region where the Resource Group should reside (e.g., 'uksouth').
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$RGLocation
    )

    begin {
        Write-Verbose "Attempting to create or verify Resource Group: $ResourceGroupName in $RGLocation"
    }

    process {
        if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess("Resource Group '$ResourceGroupName'", "Create")) {
                Write-Host "Creating Resource Group '$ResourceGroupName'..."
                try {
                    New-AzResourceGroup -Name $ResourceGroupName -Location $RGLocation -Force -ErrorAction Stop
                    Write-Host "Resource Group '$ResourceGroupName' created successfully." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to create Resource Group '$ResourceGroupName'. Error: $($_.Exception.Message)"
                    throw
                }
            }
        }
        else {
            Write-Host "Resource Group '$ResourceGroupName' already exists. Verified." -ForegroundColor Yellow
        }
    }

    end {}
}

# function Set-AzIaCBackendStorage {
#     <#
#     .SYNOPSIS
#         Sets up storage for IaC backends
#     .DESCRIPTION
#         Registers the Microsoft.Storage provider, creates the Azure Storage Account and a storage blob.
#     #>
#     [CmdletBinding()]
#     param (
#         # OptionalParameters
#     )
# }