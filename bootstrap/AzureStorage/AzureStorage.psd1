@{
    RootModule = 'AzureStorage.psm1'
    GUID = 'd349caa0-45c8-4a8c-9fd2-f05b6a05655d'
    ModuleVersion = '0.1.0'
    Author = 'Adam Cheney'
    Description = 'Azure Storage helpers for backend storage account provisioning in bootstrap scripts.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'New-UniqueStorageAccountName'
        'Set-BackendStorageAccount'
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