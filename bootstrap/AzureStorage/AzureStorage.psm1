<#
.SYNOPSIS
    Azure Storage management module for AKS bootstrap operations.
.DESCRIPTION
    A PowerShell module providing idempotent functions for managing Azure Storage Accounts.
    
    The module automatically loads all public functions from the Public/ directory and
    private helper functions from the Private/ directory.
    
    PUBLIC FUNCTIONS:
    - Set-BackendStorageAccount - Ensure Azure Storage Account exists
    
    PRIVATE HELPERS:
    - Unique name generator
    
    All state-changing operations support -WhatIf and -Confirm via ShouldProcess.
.EXAMPLE
    # Import the module for production or automated usage
    Import-Module "$PSScriptRoot/AzureStorage.psm1" -Force
    $storageAccount = Set-BackendStorageAccount -ResourceGroupName "my-rg" -StorageAccountNamePrefix "myacct" -Location "East US"
    $saName = New-UniqueStorageAccountName -Prefix 'testacct'
.NOTES
    - Requires PowerShell Core 7.0+ for cross-platform compatibility
    - Requires Az PowerShell modules (Az.Accounts, Az.KeyVault, Az.Resources)
    - Requires OpenSSL for certificate generation operations
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

