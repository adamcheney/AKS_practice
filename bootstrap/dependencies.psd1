@{
    RequiredModules = @(
        @{ModuleName = 'Az.Accounts'; ModuleVersion = '5.3.0'}
        @{ModuleName = 'Az.Resources'; ModuleVersion = '8.1.1'}
        @{ModuleName = 'Az.Storage'; ModuleVersion = '9.2.0'}
        @{ModuleName = 'Az.KeyVault'; ModuleVersion = '6.4.0'}
    )
    RequiredProviders = @(
        'Microsoft.Storage',
        'Microsoft.KeyVault',
        'Microsoft.ComntainerService'
    )
}
