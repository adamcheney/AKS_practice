#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Common parameters and reusable functions.
.DESCRIPTION
    The bootstrapping scripts can dot-source this file to reuse common configuration variables and functions.
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

function Get-InfraConfig {
     @{
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
}


function Set-AzureContext {
    <#
    .SYNOPSIS
        Ensures Azure context exists.
    .DESCRIPTION
        Checks if there is an existing Azure context; if not, it initiates a login.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    begin {
        Write-Verbose "Checking Azure context..."
        $currentContext = $null
    }

    process {
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        if (-not ($currentContext)) {
            Write-Verbose "No Azure context found. Initiating login..." 
            try {
                if ($PSCmdlet.ShouldProcess("AzAccount", "Remove version $loadedModule.Version")) {
                    $currentContext = Connect-AzAccount -ErrorAction Stop
                    Write-Verbose "Logged in to Azure successfully." 
                }            
            }
            catch {
                Write-Error "Azure login failed. Error: $($_.Exception.Message)"
                throw # Re-throw to stop the script
            }
        }
        else {
            Write-Verbose "Azure context exists - already logged in." 
        }
    }

    end { $currentContext }
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
    .PARAMETER Location
        The Azure location/region where the Resource Group should reside (e.g., 'uksouth').
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [String]$Location
    )

    begin {
        Write-Verbose "Attempting to create or verify Resource Group: $ResourceGroupName in $Location"
        $resourceGroup = $null
    }

    process {
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not ($resourceGroup)) {
            if ($PSCmdlet.ShouldProcess("Resource Group '$ResourceGroupName'", "Create")) {
                Write-Verbose "Creating Resource Group '$ResourceGroupName'..."
                try {
                    $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction Stop
                    Write-Verbose "Resource Group '$ResourceGroupName' created successfully." 
                }
                catch {
                    Write-Error "Failed to create Resource Group '$ResourceGroupName'. Error: $($_.Exception.Message)"
                    throw
                }
            }
        }
        else {
            Write-Verbose "Resource Group '$ResourceGroupName' already exists. Verified." 
        }
    }

    end { $resourceGroup }
}

function Register-RequiredAzResourceProviders {
    <#
    .SYNOPSIS
        Registers necessary Azure Resource Providers.
    .DESCRIPTION
        Registers required Azure Resource Providers for the deployment.
    .PARAMETER DependencyFile
        Path to the dependencies file listing required resource providers.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$false)]
        [String]$DependencyFile = (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')
    )

    begin {
        Write-Verbose "Loading required Azure Resource Providers from '$DependencyFile'..."
        $requiredProviders = @()
    }

    process {
        if (-not (Test-Path -Path $DependencyFile)) {
            throw "Dependency file '$DependencyFile' not found."
        }
        try {
            $Providers = (Import-PowerShellDataFile -Path $DependencyFile).RequiredProviders
        }
        catch {
            Throw "Failed to import dependency file '$DependencyFile'. Error: $($_.Exception.Message)"
        }
        if (-not $Providers){
            # The list of required providers should not be empty - throw an error
            throw "No RequiredProviders found in '$DependencyFile'. Nothing to register."
        }
        Write-Host "Dependency file: $DependencyFile" # <- DEBUG: remove
        foreach ($providerName in $Providers) {
            $notRegistered = (Get-AzResourceProvider -ListAvailable `
              | Where-Object ProviderNamespace -eq $providerName ).RegistrationState -eq "NotRegistered"
            $temp = (Get-AzResourceProvider -ListAvailable `
              | Where-Object ProviderNamespace -eq $providerName )
            Write-Host "    Provider: $providerName, State: $($temp.RegistrationState)" # <- DEBUG: remove
            if ($notRegistered) {
                Write-Verbose "Registering Resource Provider: '$providerName'..."
                Write-Host "Registering Resource Provider: $providerName" # <- DEBUG: remove
                Register-AzResourceProvider -ProviderNamespace $providerName -ErrorAction Stop
            }
            else {
                Write-Verbose "Resource Provider '$providerName' is already registered."
                Write-Host "Resource Provider '$providerName' is already registered." # <- DEBUG: remove
            }
        }
    }

    end {
        Write-Verbose "All required Azure Resource Providers have been registered."
    }
    
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