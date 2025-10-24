#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initialises PowerShell environment
.DESCRIPTION
    The bootstrapping scripts can dot-source this file to initialise.
    Also enforces TLS1.2 for secure connections.
    This function:
    - Get-InfraConfig - returns the config hash
    These cmdlets:
    - Set-PSResourceGetv3 - ensures PSResourceGet v3 is installed and imported
    - Ensure-ModuleVersion - ensures a specific module and version is imported
    - Import-BootstrapDependencies - imports required modules from a psd1 file
    - Set-AzureContext - ensures Azure context exists (logs in if not)
.NOTES
    Any additional information, like dependencies or version history.
#>

# --- Enforce TLS1.2 ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Initialise ---

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
        [Parameter()]
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
                            -Force -Scope CurrentUser
            }
        }
        # Ensure I'm using the expected version
        if ($PSCmdlet.ShouldProcess("PSResourceGet","Ensure module version $Version is imported")) {
            $importPSResourceGet = Ensure-ModuleVersion -ModuleName 'Microsoft.PowerShell.PSResourceGet' -ModuleVersion $Version
        }
    }

    end {
        Write-Verbose "PSResourceGet v$Version is installed and imported."
        $importPSResourceGet
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
            throw "Module '$ModuleName' version '$ModuleVersion' not installed."
        }
        # Check the loaded version
        $loadedModule = Get-Module -Name $ModuleName
        if ($loadedModule -and ($loadedModule.Version -ne $ModuleVersion)) {
            Write-Verbose "Unloading module '$ModuleName' version $($loadedModule.Version) and importing version $ModuleVersion"
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
        Write-Verbose "Module '$ModuleName' version '$ModuleVersion' is imported successfully."
        $import
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
        [Parameter(Mandatory=$false)]
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
        try {
            $Dependencies = (Import-PowerShellDataFile -Path $DependencyFile).RequiredModules
        }
        catch {
            Throw "Failed to import dependency file '$DependencyFile'. Error: $($_.Exception.Message)"
        }
        if (-not $Dependencies){
            # Might be an empty file of empty list of dependencies
            Write-Information "No RequiredModules found in '$DependencyFile'. Nothing to import."
            return
        }
        $Dependencies| ForEach-Object {
            $Name = $_.ModuleName
            $Version = $_.ModuleVersion
            # Use -ListAvailable to check if module installed system-wide, not just current session.
            $InstalledModule = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue

            # Compare installed version to required version.
            if (-not ($InstalledModule | Where-Object Version -eq $Version)) {
                Write-Verbose "Installing module '$Name' version '$Version'..."
                if ($PSCmdlet.ShouldProcess("PSResource $Name", "Install PSResource version '$Version'")) {
                    try {
                        $InstallParams = @{
                            Name = $Name
                            Version = $Version
                            Scope = 'CurrentUser'
                            Repository = 'PSGallery'
                        }
                        Install-PSResource @InstallParams -ErrorAction Stop
                        Write-Verbose "Module '$Name' installed successfully."
                    }
                    catch {
                        Write-Error "Failed to install module '$Name'. Error: $($_.Exception.Message)"
                        throw # Re-throw to stop the script
                    }
                }
            }
            else {
                Write-Verbose "Module '$Name' (v$($InstalledModule.Version)) already meets requirement (v$Version). Skipping installation."
            }
            # Ensure the required version is imported
            Ensure-ModuleVersion -ModuleName $Name -ModuleVersion $Version
        }
    }

    end {
        Write-Verbose "All dependencies from '$DependencyFile' are installed and imported."
    }
}

function Initialize-Bootstrap {
    <#
    .SYNOPSIS
        Initialises bootstrapping process
    .DESCRIPTION
        Downloads PSResourceGet v3.
        Reads dependencies from psd1 file and installs and imports.
    .PARAMETER PSResourceGetVersion
        The version of PSResourceGet to install - defaults to '1.1.1'.
    .PARAMETER DependencyFile
        The path of the dependencies psd1 file - defaults to 'dependencies.psd1' in the same directory as this script.
    #>
    [CmdletBinding()]
    param (
        [String]$PSResourceGetVersion = '1.1.1',
        [String]$DependenciesPath = (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')
    )
    
    Set-PSResourceGetv3 -Version $PSResourceGetVersion
    Import-BootstrapDependencies -DependencyFile $DependenciesPath
}
