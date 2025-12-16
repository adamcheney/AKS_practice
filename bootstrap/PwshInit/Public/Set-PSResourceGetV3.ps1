function Set-PSResourceGetV3 {
    <#
    .SYNOPSIS
        Ensure PSResourceGet v3 is installed and imported.
    .DESCRIPTION
        Installs the specified version of Microsoft.PowerShell.PSResourceGet (v3) if missing,
        then imports that exact version into the current session. This function is idempotent.
    .PARAMETER Version
        The exact version of PSResourceGet to ensure is installed and imported. Defaults to '1.1.1'.
    .EXAMPLE
        Set-PSResourceGetv3 -Version '1.1.1'
    .OUTPUTS
        The imported module object (PassThru from Import-Module) when imported.
    .NOTES
        Uses Install-Module to perform installation (CurrentUser scope).
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [String]$Version = '1.1.1'
    )

    process {
        Write-Verbose "Installing and importing PSResourceGet v3, version $Version"
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
            $importPSResourceGet = Ensure-ModuleVersionImport -ModuleName 'Microsoft.PowerShell.PSResourceGet' -ModuleVersion $Version
        }

        Write-Verbose "PSResourceGet v$Version is installed and imported."
        return $importPSResourceGet
    }
}