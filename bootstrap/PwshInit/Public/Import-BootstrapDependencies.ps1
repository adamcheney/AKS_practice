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

    process {
        if (-not (Test-Path -Path $DependencyFile)) {
            throw "Dependency file '$DependencyFile' not found."
        }
        Write-Verbose "Importing dependencies from $DependencyFile"
        Set-PSResourceGetv3 -Version '1.1.1'
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

            # Ensure the required version is installed
            Ensure-ModuleVersionInstall -ModuleName $Name -ModuleVersion $Version
            # Ensure the required version is imported
            Ensure-ModuleVersionImport -ModuleName $Name -ModuleVersion $Version
        }
        Write-Verbose "All dependencies from '$DependencyFile' are installed and imported."
    }
}
