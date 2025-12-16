function Import-BootstrapDependencies {
    <#
    .SYNOPSIS
        Install and import modules declared in a dependencies psd1 file.
    .DESCRIPTION
        Reads the 'RequiredModules' section from a PowerShell data file (PSD1),
        ensures each specified module/version is available (installs via Install-PSResource
        when missing) and imports the requested version into the session.
        This function calls Set-PSResourceGetv3 to ensure the PSResourceGet helper is available.
    .PARAMETER DependencyFile
        Path to the PSD1 file containing a 'RequiredModules' array with ModuleName/ModuleVersion entries.
        Defaults to 'dependencies.psd1' in the same directory as this script.
    .EXAMPLE
        Import-BootstrapDependencies -DependencyFile "$PSScriptRoot\dependencies.psd1"
    .NOTES
        Throws when the dependency file is missing or malformed.
        Uses Install-PSResource to install modules into the CurrentUser scope.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$false)]
        [String]$DependencyFile = (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')
    )

    begin {
        if (-not (Test-Path -Path $DependencyFile)) {
            throw "Dependency file '$DependencyFile' not found."
        }
        Write-Verbose "Importing dependencies from $DependencyFile"
        Set-PSResourceGetv3 -Version '1.1.1'
    }

    process {
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
            Ensure-ModuleVersionImport -ModuleName $Name -ModuleVersion $Version
        }
    }

    end {
        Write-Verbose "All dependencies from '$DependencyFile' are installed and imported."
    }
}
