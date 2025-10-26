@{
    RootModule = 'az-bootstrap.psm1'
    ModuleVersion = '0.1.0'
    Author = 'Adam Cheney'
    Description = 'Bootstrap helpers for Azure used by repository bootstrap scripts.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Get-InfraConfig'
        'Set-AzureContext'
        'Set-AzResourceGroup'
        'Register-RequiredAzResourceProviders'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Azure','Bootstrap','Infrastructure')
            ProjectUri = ''
            LicenseUri = ''
            ReleaseNotes = 'Initial manifest'
        }
    }
}