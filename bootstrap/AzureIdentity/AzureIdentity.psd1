@{
    RootModule = 'AzureIdentity.psm1'
    GUID = '00d0cdb0-f137-4642-a8a8-baa28e61cbfc'
    ModuleVersion = '0.1.0'
    Author = 'Adam Cheney'
    Description = 'Azure Identity helpers for managing Azure AD identities in bootstrap scripts.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Set-AzIdentityKeyVault'
        'New-ServicePrincipalIdCredentials'
        'New-AutomationServicePrincipal'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Azure','Bootstrap','Infrastructure')
            ProjectUri = 'https://github.com/adamcheney/AKS_practice/'
            LicenseUri = ''
            ReleaseNotes = 'Initial manifest'
        }
    }
}