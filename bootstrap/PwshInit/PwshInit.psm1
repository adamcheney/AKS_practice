<#
.SYNOPSIS
    Common bootstrap helpers and shared configuration.
.DESCRIPTION
    A PowerShell module providing idempotent functions for bootstrapping Powershell environment.
    
    The module automatically loads all public functions from the Public/ directory.
    
    PUBLIC FUNCTIONS:
    
     
    All state-changing operations support -WhatIf and -Confirm via ShouldProcess.
.EXAMPLE
    # Import the module and create a complete identity setup
    Import-Module "./PwshInit.psm1" -Force
    
.NOTES
    - Requires PowerShell Core 7.0+ for cross-platform compatibility
    - Loads Az PowerShell modules (Az.Accounts, Az.KeyVault, Az.Resources)
    - All functions support ShouldProcess (-WhatIf, -Confirm)
    - Designed for idempotent operations (safe to run multiple times)
#>

#Get public and private function definition files.
$Public  = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue )

#Dot source the files
Foreach($import in @($Public + $Private))
{
    Try
    {
        . $import.fullname
    }
    Catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

Export-ModuleMember -Function $Public.Basename
