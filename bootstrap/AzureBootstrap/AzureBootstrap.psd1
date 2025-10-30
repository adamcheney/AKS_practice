@{
    RootModule = 'AzureBootstrap.psm1'
    GUID = '89d76f0a-327d-442a-a610-e040370750b3'
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
            ProjectUri = 'https://github.com/adamcheney/AKS_practice/'
            LicenseUri = ''
            ReleaseNotes = 'Initial manifest'
        }
    }
}