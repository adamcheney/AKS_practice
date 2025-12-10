function Ensure-ModuleVersion {
    <#
    .SYNOPSIS
        Ensure a specific module version is imported into the session.
    .DESCRIPTION
        Verifies that the requested module version is installed. If a different
        version is loaded, the loaded module is removed and the requested version
        is imported. Throws an error when the requested version is not installed.
    .PARAMETER ModuleName
        The module name to ensure.
    .PARAMETER ModuleVersion
        The exact module version required (string).
    .EXAMPLE
        Ensure-ModuleVersion -ModuleName 'Az.Accounts' -ModuleVersion '2.0.0'
    .OUTPUTS
        The imported module object (PassThru) when import succeeds.
    .NOTES
        Intended for use by bootstrap scripts to guarantee specific module versions.
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
        return $import
    }
}
