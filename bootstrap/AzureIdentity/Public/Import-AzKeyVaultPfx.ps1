function Import-AzKeyVaultPfx {
    <#
    .SYNOPSIS
        Import a PFX certificate into Azure Key Vault as a secret.
    .DESCRIPTION
        Reads a PFX file, encodes it in base64, and stores it as a secret in the specified Azure Key Vault.
    .PARAMETER VaultName
        Name of the Azure Key Vault to import the certificate into.
    .PARAMETER PfxPath
        Path to the PFX file to import.
    .EXAMPLE
        Import-AzKeyVaultPfx -VaultName 'my-vault' -PfxPath 'certificate.pfx'
    .NOTES
        - .
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$VaultName,
        [Parameter(Mandatory)]
        [String]$PfxPath,
        [String]$SecretName = 'cheneyaw-aks-iac'
    )
    
    process {
        if (-not (Test-Path -Path $PfxPath)) {
            throw "PFX file '$PfxPath' does not exist."
        }
        $base64 = ConvertTo-Base64Binary -PfxPath $PfxPath
        $secureValue = ConvertTo-SecureString -String $base64 -AsPlainText -Force
        $SPIdentityItem = Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue $secureValue
        return $SPIdentityItem
    }
}
