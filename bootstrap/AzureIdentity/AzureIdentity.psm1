<#
.SYNOPSIS
    Azure Identity management module for AKS bootstrap operations.
.DESCRIPTION
    A PowerShell module providing idempotent functions for managing Azure Active Directory 
    identities, certificates, and Key Vault access for AKS cluster bootstrap scenarios.
    
    The module automatically loads all public functions from the Public/ directory and
    private helper functions from the Private/ directory.
    
    PUBLIC FUNCTIONS:
    - Set-AzIdentityKeyVault            - Ensure Azure Key Vault exists
    - New-ServicePrincipalIdCredentials - Generate self-signed X.509 certificates  
    - New-AutomationServicePrincipal    - Create service principal with certificate auth
    - Import-AzKeyVaultPfx              - Import PFX certificates to Key Vault
    - Set-AccessToKeyVault              - Grant Key Vault access to identities
    
    PRIVATE HELPERS:
    - OpenSSL certificate generation and export utilities
    - Base64 encoding/conversion functions
    
    All state-changing operations support -WhatIf and -Confirm via ShouldProcess.
.EXAMPLE
    # Import the module and create a complete identity setup
    Import-Module "./AzureIdentity.psm1" -Force
    
    $vault = Set-AzIdentityKeyVault -ResourceGroupName "my-rg" -VaultName "my-vault" -Location "East US"
    $certs = New-ServicePrincipalIdCredentials -CommonName "my-sp" -KeyLength 2048
    $sp = New-AutomationServicePrincipal -DisplayName "my-sp" -TempFilePath "/tmp"
    
    # Check what operations would be performed without executing them
    Set-AzIdentityKeyVault -ResourceGroupName "my-rg" -VaultName "my-vault" -Location "East US" -WhatIf
    
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

# Here I might...
    # Read in or create an initial config file and variable
    # Export Public functions ($Public.BaseName) for WIP modules
    # Set variables visible to the module and its functions only

Export-ModuleMember -Function $Public.Basename