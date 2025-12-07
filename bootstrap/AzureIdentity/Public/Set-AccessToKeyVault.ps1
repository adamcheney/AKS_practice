function Set-AccessToKeyVault {
    <#
    .SYNOPSIS
        Grant access to Key Vault for an identity entity.
    .DESCRIPTION
        Grants the specified access policy to a service principal or user for the given Key Vault.
    .PARAMETER VaultName
        Name of the Azure Key Vault.
    .PARAMETER SignInName
        Sign-in name (UPN) of the user or service principal to grant access to.
    .PARAMETER SubscriptionId
        Subscription ID where the Key Vault resides.
    .PARAMETER ResourceGroupName
        Resource group name where the Key Vault resides.
    .EXAMPLE
        Set-AccessToKeyVault -VaultName 'my-vault' -SignInName 'user@domain.com' -SubscriptionId 'sub-id' -ResourceGroupName 'rg-name'
    .NOTES
        - .
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [String]$VaultName,
        [Parameter(Mandatory)]
        [String]$SubscriptionId,
        [Parameter(Mandatory)]
        [String]$ResourceGroupName,
        [Parameter(ParameterSetName='Interactive', Mandatory)]
        [String]$SignInName,
        [Parameter(ParameterSetName='Automated', Mandatory)]
        [String]$ServicePrincipalId
    )

    begin {
        # The role name
        $roleName = 'Key Vault Certificates Officer'        
    }

    process {
        # Confirm Key Vault exists
        $keyVault = Get-AzKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    
        $identityObjectId = $null
        # If ServicePrincipalId not provided, assume this is a request for a user and validate
        if (-not $ServicePrincipalId) {
            $adUser = Get-AzADUser -UserPrincipalName $SignInName
            if (-not $adUser) {
                throw "Azure AD User with SignInName '$SignInName' not found and ServicePrincipalID not supplied."
            }
            $identityObjectId = $adUser.Id
        }
        # Otherwise this is a request for a service principal
        else {
            $adSP = Get-AzADServicePrincipal -ObjectId $ServicePrincipalId
            if (-not $adSP) {
                throw "Azure AD Service Principal with ObjectId '$ServicePrincipalId' not found and no SignInName supplied."
            }
            $identityObjectId = $adSP.Id
        }
        $scopeElements = @(
            '/subscriptions/', $SubscriptionId,
            '/resourceGroups/', $ResourceGroupName,
            '/providers/Microsoft.KeyVault/vaults/', $VaultName
        )
        $scope = ($scopeElements -join '')

        if ($PSCmdlet.ShouldProcess("Key Vault '$VaultName'", "Grant '$roleName' role to $identityObjectId")) {
            $roleAssignment = New-AzRoleAssignment `
                                -ObjectId $identityObjectId `
                                -Scope $scope `
                                -RoleDefinitionName $roleName
            if ($roleAssignment) {
                Write-Verbose "Granted '$roleName' role to identity with ObjectId '$identityObjectId' on Key Vault '$VaultName'."
            }
        }
        return $roleAssignment
    }
}
