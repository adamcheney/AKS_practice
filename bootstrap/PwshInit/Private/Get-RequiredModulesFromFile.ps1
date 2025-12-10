function Get-RequiredModulesFromFile {
    <#
    .SYNOPSIS
        Reads config from a config file.
    .DESCRIPTION
        Reads the config file - path passed in as a paramter - and returns a PSCustomObject.
    .PARAMETER DependencyFile
        Path to the PSD1 file containing a 'RequiredModules' array with ModuleName/ModuleVersion entries.
        Defaults to 'dependencies.psd1' in the same directory as this script.
    .EXAMPLE
        Get-RequiredModulesFromFile -DependencyFile "$PSScriptRoot\dependencies.psd1"
    .NOTES
        Throws when the dependency file is missing or malformed.
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

        if ($PSCmdlet.ShouldProcess("File $DependencyFile", "Read config")) {
            try {
                $Dependencies = (Import-PowerShellDataFile -Path $DependencyFile).RequiredModules
            }
            catch {
                Throw "Failed to import dependency file '$DependencyFile'. Error: $($_.Exception.Message)"
            }
        }
        if (-not $Dependencies.RequiredModules){
            # Might be an empty file of empty list of dependencies
            Write-Information "No RequiredModules found in '$DependencyFile'. Nothing to import."
            return
        }     
        return $Dependencies.RequiredModulesgvvgfr2]   
    }
}


