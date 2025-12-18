function Ensure-ModuleVersionInstall {
    <#
    .SYNOPSIS
        Ensure a specific module version is installed locally.
    .DESCRIPTION
        Checks to see if the requested module version is installed. If not, installs it
        using Install-PSResource into the CurrentUser scope.
    .PARAMETER ModuleName
        The module name.
    .PARAMETER ModuleVersion
        The exact module version required (string).
    .EXAMPLE
        Ensure-ModuleVersionInstall -ModuleName 'Az.Accounts' -ModuleVersion '2.0.0'
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

    process {
        Write-Verbose "Ensuring module '$ModuleName' version '$ModuleVersion' is installed locally."
        # Use -ListAvailable to check if module installed system-wide, not just current session.
        $InstalledModule = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue
        # Compare installed version to required version.
        if (-not ($InstalledModule | Where-Object { $_.Version -eq [Version]$ModuleVersion })) {
            Write-Verbose "Installing module '$ModuleName' version '$ModuleVersion'..."
            if ($PSCmdlet.ShouldProcess("PSResource $ModuleName", "Install PSResource version '$ModuleVersion'")) {
                try {
                    $InstallParams = @{
                        Name = $ModuleName
                        Version = $ModuleVersion
                        Scope = 'CurrentUser'
                        Repository = 'PSGallery'
                    }
                    Install-PSResource @InstallParams -ErrorAction Stop
                    Write-Verbose "Module '$ModuleName' installed successfully."
                }
                catch {
                    Write-Error "Failed to install module '$ModuleName'. Error: $($_.Exception.Message)"
                    throw # Re-throw to stop the script
                }
            }
        }
        else {
            Write-Verbose "Module '$ModuleName' (v$($InstalledModule.Version)) already meets requirement (v$ModuleVersion). Skipping installation."
        }
    }
}