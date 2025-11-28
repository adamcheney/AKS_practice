function Set-AzIdentityKeyVault {
    <#
    .SYNOPSIS
        Ensure an Azure Key Vault exists.
    .DESCRIPTION
        Searches the specified resource group for a Key Vault with the given name.
        If not found, creates a new Key Vault in the specified location with the given SKU.
    .PARAMETER ResourceGroupName
        Name of the Azure Resource Group to search/create the Key Vault in.
    .PARAMETER VaultName
        Name of the Key Vault to find or create.
    .PARAMETER Location
        Azure region/location for the Key Vault (used if creating a new one).
    .PARAMETER Sku
        SKU for the Key Vault (used if creating a new one). Defaults to 'Standard'.
    .EXAMPLE
        Set-AzIdentityKeyVault -ResourceGroupName 'my-rg' -VaultName 'my-vault' -Location 'eastus'
    .OUTPUTS
        Microsoft.Azure.Commands.KeyVault.Models.PSKeyVault
    .NOTES
        - Uses ShouldProcess for idempotent behavior.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [String]$VaultName,
        
        [Parameter(Mandatory=$true)]
        [String]$Location,
        
        [String]$Sku = 'Standard'
    )
    
    process {
        # Begin by confirming the Resource Group exists and throwing if not
        if ( $null -eq (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) ) {
            throw "Resource Group '$ResourceGroupName' does not exist."
        }

        # Check if the Key Vault already exists
        $keyVaultParams = @{
            Name              = $VaultName
            ResourceGroupName = $ResourceGroupName
        }
        $KeyVault = Get-AzKeyVault @keyVaultParams -ErrorAction SilentlyContinue

        if ($null -eq $KeyVault) {
            if ($PSCmdlet.ShouldProcess("Key Vault '$VaultName' in Resource Group '$ResourceGroupName'", "Create")) {
                # Create the Key Vault since it does not exist
                $keyVaultParams += @{
                    Location = $Location
                    Sku      = $Sku
                }
                $KeyVault = New-AzKeyVault @keyVaultParams
            }
            else
            {
                Write-Verbose "Key Vault '$VaultName' creation skipped by ShouldProcess."
            }
        }
        return $KeyVault
    }
}
