#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initialize PowerShell environment for bootstrap scripts.
.DESCRIPTION
    Prepares the execution environment for the repository bootstrapping scripts.
    - Enforces TLS 1.2.
    - Provides helper functions to ensure and import specific module versions.
    - Installs and imports PSResourceGet v3 when required.
    These helpers are intended for dot-sourcing by bootstrap scripts.
.NOTES
    - Idempotent: functions avoid re-installing or re-importing when not required.
    - Tested on macOS with PowerShell Core.
#>

# --- Enforce TLS1.2 ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Initialise ---



# --- Dependency Modules ---


function Import-IaCAzureBackendModules {
    <#
    .SYNOPSIS
        Import modules required for Azure backend provisioning for IaC.
    .DESCRIPTION
        Installs and imports specific versions of PowerShell modules
        required for provisioning Azure backend resources for Infrastructure as Code (IaC).
        This includes modules for Azure management and storage account handling.
    .EXAMPLE
        Import-IaCAzureBackendModules
    .NOTES
        Uses Confirm-ModuleVersionImport to guarantee specific module versions.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [Object]$Module
    )

    $allModules = @(
        'AzureBootstrap'
        'AzureStorage'
        'AzureIdentity'
    )

    $Modules = if ($Module -is [string]) {
        @($Module)
    } else {
        $Module
    }
    if (-not $Module) {
        $Modules = $allModules
    }
    $Modules | ForEach-Object {
        if (-not ($_ -in $allModules)) {
            Write-Warning "Module '$_'  is not a valid bootstrap module and will be skipped."
        }
        else {
            $fullPath = Join-Path $PSScriptRoot $_
            Import-Module -Name $fullPath -Force -Verbose
        }
    }
}

function Set-InfraTrackingFile {
    param (
        [String]$FilePath = (Join-Path -Path $PSScriptRoot -ChildPath 'infra.json'),
        [Hashtable]$Content
    )

    if (-not (Test-Path -Path $FilePath)) {
        New-Item -Path $FilePath -ItemType File -Force | Out-Null
    }
    $Content.DateTime = (Get-Date).ToString("o")
    $Content | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Force
}

function Initialize-Bootstrap {
    <#
    .SYNOPSIS
        High-level initialization for bootstrap process.
    .DESCRIPTION
        Convenience wrapper that ensures PSResourceGet v3 is available and then
        installs/imports modules defined in the dependencies PSD1 file.
    .PARAMETER PSResourceGetVersion
        Version of PSResourceGet to install/import (default '1.1.1').
    .PARAMETER DependenciesPath
        Path to the dependencies PSD1 file (default: dependencies.psd1 in this script folder).
    .EXAMPLE
        Initialize-Bootstrap -PSResourceGetVersion '1.1.1' -DependenciesPath "$PSScriptRoot\dependencies.psd1"
    .NOTES
        Calls Set-PSResourceGetv3 and Import-BootstrapDependencies.
    #>
    [CmdletBinding()]
    param (
        [String]$PSResourceGetVersion = '1.1.1',
        [String]$DependenciesPath = (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')
    )
    
    # Initialise the Powershell environment for bootstrap
    Set-PSResourceGetv3 -Version $PSResourceGetVersion
    Import-BootstrapDependencies -DependencyFile $DependenciesPath
    Import-IaCAzureBackendModules

    # Get the config from the infra-config.json file
    $config = Get-InfraConfig -ConfigPath './infra-config.json'

    # Ensure we're logged in or request login
    Set-AzureContext

    # All resources need the resource group to exist
    Set-AzBootstrapResourceGroup -Name $config.resourceGroup.Name -Location $config.resourceGroup.Location

    # Register required resource providers
    Register-RequiredAzResourceProviders -DependencyFile $DependenciesPath
    
    # Create the service principal for automation if it doesn't exist
    New-AutomationServicePrincipal -DisplayName $config.ServicePrincipal.DisplayName -KeyLength 2048
}

function Clear-BootstrapEnvironment {
    # Remove any temporary files or resources created during the bootstrap process
    Remove-Item -Path './infra-config.json' -Force -ErrorAction SilentlyContinue
}

function Set-AzureBootstrapResources {
    param ()

    $configParams 
}