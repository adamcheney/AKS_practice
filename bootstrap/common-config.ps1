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
# Dot-source initialise script
. (Join-Path -Path $PSScriptRoot -ChildPath 'initialise.ps1')
# Initilalise dependencies
Initialize-Bootstrap 

# --- Configuration Variables ---

function Get-InfraConfig {
    return @{
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

# --- Initialise ---


function Set-AzureContext {
    <#
    .SYNOPSIS
        Ensures Azure context exists.
    .DESCRIPTION
        Checks if there is an existing Azure context; if not, it initiates a login.
    #>
    [CmdletBinding()]
    param ()

    begin {
        Write-Verbose "Checking Azure context..."
    }

    process {
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
    Write-Host "Azure context exists - already logged in." -ForegroundColor Cyan
}


function Set-PSResourceGetv3 {
    <#
    .SYNOPSIS
        Imports and installs PSResourceGet v3.
    .DESCRIPTION
        Checks to see if the specified version of PSResourceGet is installed, installs it if missing, and imports it.
        This function is idempotent.
    .PARAMETER Verson
        The specific version to Install/Import - defaults to '1.1.1'.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter]
        [String]$Version = '1.1.1'
    )

    begin {
        Write-Verbose "Installing and importing PSResourceGet v3, version $Version"
    }

    process {
        $PSResourceGet = Get-Module -Name Microsoft.PowerShell.PSResourceGet -ListAvailable
        if (-not ($PSResourceGet | Where-Object Version -eq $Version)) {
            if ($PSCmdlet.ShouldProcess("PSResourceGet", "Install version $Version")) {
                Install-Module -Name Microsoft.PowerShell.PSResourceGet `
                            -RequiredVersion $Version `
                            -Force -Scope CurrentUser -Required
            }
        }
        # Ensure I'm using the expected version
        if ($PSCmdlet.ShouldProcess("PSResourceGet","Ensure module version $Version is imported")) {
            $importPSResourceGet = Ensure-ModuleVersion -ModuleName 'Microsoft.PowerShell.PSResourceGet' -ModuleVersion $Version
        }
    }

    end {
        Write-Host "PSResourceGet v$Version is installed and imported." -ForegroundColor Green
        return $importPSResourceGet
    }
}

# --- Dependency Modules ---
function Ensure-ModuleVersion {
    <#
    .SYNOPSIS
        Ensures a specific PowerShell module and version is imported - throws an error if not installed.
    .DESCRIPTION
        Checks if the specified module and version is imported; removes and reimports if a different version is loaded.
        If the module/version is not installed, it throws an error.
        This function is idempotent.
    .PARAMETER ModuleName
        The name of the PowerShell module.
    .PARAMETER ModuleVersion
        The required version of the module.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ModuleName,

        [Parameter(Mandatory=$true)]
        [String]$ModuleVersion
    )

    begin {
        Write-Verbose "Ensuring module '$ModuleName' version '$ModuleVersion' is imported into session."
    }

    process {
        # Check to see if the module is already installed and error if not
        $installed = Get-Module -Name $ModuleName -ListAvailable | Where-Object Version -eq $ModuleVersion
        if (-not $installed) {
            throw "Module '$ModuleName' version '$ModuleVersion' is not installed. Please install it before proceeding."
        }
        # Check the loaded version
        $loadedModule = Get-Module -Name $ModuleName
        if ($loadedModule and ($loadedModule.Version -ne $ModuleVersion)) {
            Write-Verbose "Unloading module '$ModuleName' version $($loadedModule.Version) and importing version $ModuleVersion" -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess("Module $ModuleName", "Remove version $loadedModule.Version")) {
                try {
                    Remove-Module -Name $ModuleName -Force
                }
                catch {
                    Write-Error "Failed to remove module '$ModuleName', version '$loadedModule.Version'. Error: $($_.Exception.Message)"
                }
            }
        }
        if ($PSCmdlet.ShouldProcess("Module $ModuleName", "Import version '$ModuleVersion'")) {
            try {
                # Using $installed as this is the correct module and version already found on the system
                $import = Import-Module $installed -ErrorAction SilentlyContinue -PassThru
            }
            catch {
                Write-Error "Failed to import module '$ModuleName', version '$ModuleVersion'. Error: $($_.Exception.Message)"
                throw
            }
        }
    }

    end {
        Write-Host "Module '$ModuleName' version '$ModuleVersion' is imported successfully." -ForegroundColor Green
        return $import
    }
}

function Import-BootstrapDependencies {
    <#
    .SYNOPSIS
        Imports and installs required PowerShell modules.
    .DESCRIPTION
        Reads the dependencies from a psd1 file and ensures they are installed and imported.
        This function is idempotent.
    .PARAMETER DependencyFile
        The path of the dependencies psd1 file - defaults to 'dependencies.psd1' in the same directory as this script.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter]
        [String]$DependencyFile = (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')
    )

    begin {
        Write-Verbose "Importing dependencies from $DependencyFile"
        Set-PSResourceGetv3 -Version '1.1.1'
    }

    process {
        if (-not (Test-Path -Path $DependencyFile)) {
            throw "Dependency file '$DependencyFile' not found."
        }
        $Dependencies = (Import-PowerShellDataFile -Path $DependencyFile).RequiredModules
        $Dependencies | ForEach-Object {
            $Name = $_.ModuleName
            $Version = $_.ModuleVersion
            # Use -ListAvailable to check if module installed system-wide, not just current session.
            $InstalledModule = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue

            # Compare installed version to required version.
            if (-not ($InstalledModule | Where-Object Version -eq $Version)) {
                Write-Host "Installing module '$Name' version '$Version'..." -ForegroundColor Yellow
                if ($PSCmdlet.ShouldProcess("PSResource $Name", "Install PSResource version '$Version'")) {
                    try {
                        $InstallParams = @{
                            Name = $Name
                            Version = $Version
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
            }
            else {
                Write-Host "Module '$Name' (v$($InstalledModule.Version)) already meets requirement (v$Version). Skipping installation." -ForegroundColor Cyan
            }
            # Ensure the required version is imported
            Ensure-ModuleVersion -ModuleName $Name -ModuleVersion $Version
        }
    }

    end {
        Write-Host "All dependencies from '$DependencyFile' are installed and imported." -ForegroundColor Green
    }
}
function Set-AzureContext {
    <#
    .SYNOPSIS
        Ensures Azure context exists.
    .DESCRIPTION
        Checks if there is an existing Azure context; if not, it initiates a login.
    #>
    [CmdletBinding()]
    param ()

    begin {
        Write-Verbose "Checking Azure context..."
    }

    process {
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
    Write-Host "Azure context exists - already logged in." -ForegroundColor Cyan
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
    }

    process {
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not ($resourceGroup)) {
            if ($PSCmdlet.ShouldProcess("Resource Group '$ResourceGroupName'", "Create")) {
                Write-Host "Creating Resource Group '$ResourceGroupName'..."
                try {
                    $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction Stop
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

    end {
        Write-Output $resourceGroup
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