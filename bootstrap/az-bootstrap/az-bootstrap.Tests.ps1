#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for az-bootstrap module helpers.
.DESCRIPTION
    Unit tests for Get-InfraConfig, Set-AzureContext, Set-AzResourceGroup and
    Register-RequiredAzResourceProviders. External Az and filesystem operations
    are mocked to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/az-bootstrap/az-bootstrap.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file az-bootstrap.psm1 from the same folder.
    - Tests clear relevant AZURE_* environment variables to avoid leakage between runs.
#>
$modulePath = Join-Path $PSScriptRoot 'az-bootstrap.psm1'
Import-Module $modulePath -Force

InModuleScope az-bootstrap { 
    Describe "Get-InfraConfig" -Tag 'Unit' {  
        BeforeEach {
            # Remove any existing EVs that may interfere with the test
            Remove-Item -ErrorAction SilentlyContinue `
                Env:\AZURE_RG_NAME, `
                Env:\AZURE_LOCATION, `
                Env:\AZURE_STORAGE_PREFIX
        }
        Context "When no EVs defined" {
            It "Should return default config values" {
                $result = Get-InfraConfig
                $result | Should -Not -BeNullOrEmpty
                $result.resourceGroup.name | Should -Be 'cheneyaw-aks-iac'
                $result.resourceGroup.location | Should -Be 'uksouth'
                $result.storageAccount.namePrefix | Should -Be 'cheneyawiacb'
                $result.storageAccount.sku | Should -Be 'Standard_LRS'
                $result.terraform.containerName | Should -Be 'tfstate'
                $result.terraform.stateFile | Should -Be 'aks.tfstate'
                $result.pulumi.containerName | Should -Be 'pulumistate'
            }
        }
        Context "When EVs are defined" {
            It "Should return config values from EVs" {
                $env:AZURE_RG_NAME = "EnvResourceGroup"
                $env:AZURE_LOCATION = "westus2"
                $env:AZURE_STORAGE_PREFIX = "envstrgacct"
                $result = Get-InfraConfig
                $result | Should -Not -BeNullOrEmpty
                $result.resourceGroup.name | Should -Be 'EnvResourceGroup'
                $result.resourceGroup.location | Should -Be 'westus2'
                $result.storageAccount.namePrefix | Should -Be 'envstrgacct'
            }
        }
        Context "When file path is invalid" {
            BeforeAll {
                Mock Test-Path { $false }
            }
            It "Should throw an error" {
                { Get-InfraConfig -ConfigPath 'duff.json' } |
                    Should -Throw -ExpectedMessage "Config file not found at 'duff.json'.*"
            }
        }
        Context "When file is not valid JSON" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Get-Content { "{ invalid json without closing brace" }
            }
            It "Should throw an error" {
                { Get-InfraConfig -ConfigPath 'guff.json' } |
                    Should -Throw -ExpectedMessage "Invalid JSON in config file 'guff.json'.*"
            }
        }
    }
    Describe "Set-AzureContext" -Tag 'Unit' {
        It "Should be a defined function" {
            $cmd = Get-Command -Name Set-AzureContext -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When no Azure context" {
            BeforeAll {
                Mock Write-Verbose {}
                Mock Write-Error {}
                Mock Get-AzContext { $null }
                Mock Connect-AzAccount {
                    [PSCustomObject]@{
                        Account      = "testAccount"
                        Subscription = "testSubscription"
                        Tenant       = "testTenant"
                    }
                }
            }
            BeforeEach {
                $result = Set-AzureContext
            }
            It "Should run Connect-AzAccount" {
                Assert-MockCalled Connect-AzAccount -Times 1
            }
            It "Should write verbose messages" {
                Assert-MockCalled Write-Verbose -ParameterFilter {
                    $Message -match "No Azure context found. Initiating login..."
                } -Times 1
                Assert-MockCalled Write-Verbose -ParameterFilter {
                    $Message -match "Logged in to Azure successfully."
                } -Times 1
            }
            It "Should NOT write error messages" {
                Assert-MockCalled Write-Error -Times 0
            }
            It "Should return the correct context object" {
                $result.Account | Should -Be "testAccount"
                $result.Subscription | Should -Be "testSubscription"
                $result.Tenant | Should -Be "testTenant"
            }
        }
        Context "When Azure context exists" {    
            BeforeAll {
                Mock Write-Verbose {}
                Mock Write-Error {}
                Mock Get-AzContext {
                    [PSCustomObject]@{
                        Account      = "oldTestAccount"
                        Subscription = "oldTestSubscription"
                        Tenant       = "oldTestTenant"
                    }
                }
                Mock Connect-AzAccount {}
            }
            BeforeEach {
                $result = Set-AzureContext
            }
            It "Should NOT run Connect-AzAccount" {
                Assert-MockCalled Connect-AzAccount -Times 0
            }
            It "Should write verbose message about existing context" {
                Assert-MockCalled Write-Verbose -ParameterFilter {
                    $Message -match "Azure context exists - already logged in."
                } -Times 1
            }
            It "Should NOT write error messages" {
                Assert-MockCalled Write-Error -Times 0
            }
            It "Should return the existing context object" {
                $result.Account | Should -Be "oldTestAccount"
                $result.Subscription | Should -Be "oldTestSubscription"
                $result.Tenant | Should -Be "oldTestTenant"
            }
        }
        Context "When Azure login fails" {
            BeforeAll {
                Mock Write-Verbose {}
                Mock Write-Error {}
                Mock Get-AzContext { $null }
                Mock Connect-AzAccount { throw "Simulated login failure." }
                Mock Write-Error {}
            }
            It "Should throw an error" {
                { Set-AzureContext } | Should -Throw "Simulated login failure."
                Assert-MockCalled Write-Error -ParameterFilter {
                    $Message -match "Azure login failed. Error: Simulated login failure."
                } -Times 1
            }
        }
    }
    Describe "Set-AzResourceGroup" -Tag 'Unit' {
        BeforeAll {
            Mock New-AzResourceGroup {
                [PSCustomObject]@{
                    ResourceGroupName = 'testRG'
                    Location          = 'testLocation'
                }
            }
            Mock Get-AzResourceGroup { $null }
            Mock Write-Verbose {}
        }
        It "Should be a defined function" {
            $cmd = Get-Command -Name Set-AzResourceGroup -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When Resource Group does not exist" {
            It "Should create the Resource Group" {
                Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation'
                Assert-MockCalled New-AzResourceGroup -ParameterFilter {
                    $Name -eq 'testRG' -and $Location -eq 'testLocation'
                } -Times 1
            }
            It "Should return a valid object" {
                $result = Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation'
                $result | Should -Not -BeNullOrEmpty
                $result.ResourceGroupName | Should -Be 'testRG'
                $result.Location | Should -Be 'testLocation'
            }
        }
        Context "When Resource Group already exists (Idempotency)" {
            BeforeAll {
                Mock Get-AzResourceGroup {
                    [PSCustomObject]@{
                        ResourceGroupName = 'testRG'
                        Location          = 'testLocation'
                    }
                }
            }
            It "Should do nothing and return the existing object" {
                $result = Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation'
                $result | Should -Not -BeNullOrEmpty
                $result.ResourceGroupName | Should -Be 'testRG'
                $result.Location | Should -Be 'testLocation'
                Assert-MockCalled New-AzResourceGroup -Times 0
            }
        }
        Context "When Get-AzureResourceGroup fails" {
            BeforeAll {
                Mock Get-AzResourceGroup { throw "Simulated retrieval failure." }
                Mock Write-Error {}
            }
            It "Should throw an error" {
                { Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' } `
                | Should -Throw "Simulated retrieval failure."
            }
        }
        Context "When New-AzureResourceGroup fails" {
            BeforeAll {
                Mock New-AzResourceGroup { throw "Simulated creation failure." }
                Mock Write-Error {}
            }
            It "Should throw an error" {
                { Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' } `
                | Should -Throw "Simulated creation failure."
            }
        }
        Context "When called with -WhatIf" {
            It "Should not create a new Resource Group" {
                Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' -WhatIf
                Assert-MockCalled New-AzResourceGroup -Times 0
            }
            It "Should return $null" {
                $result = Set-AzResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' -WhatIf
                $result | Should -BeNullOrEmpty
            }
        }
    }
    Describe "Register-RequiredAzResourceProviders" -Tag 'Unit' {
        BeforeAll {
            Mock Write-Error {}
            Mock Write-Verbose {}
            Mock Get-AzResourceProvider {}
            Mock Register-AzResourceProvider {}
        }
        It "Should be a defined function" {
            $cmd = Get-Command -Name Register-RequiredAzResourceProviders -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
        }
        Context "When given a valid file list of required providers" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Import-PowerShellDataFile {
                    @{
                        RequiredModules   = @(
                            @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0' }
                        )
                        RequiredProviders = @(
                            'Microsoft.TestProvider1',
                            'Microsoft.TestProvider2',
                            'Microsoft.TestProvider3'
                        )
                    }
                }
                Mock Get-AzResourceProvider {
                    @(
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider1'
                            RegistrationState = 'NotRegistered'
                        },
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider2'
                            RegistrationState = 'NotRegistered'
                        },
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider3'
                            RegistrationState = 'NotRegistered'
                        }
                    )
                }
            }
            BeforeEach {
                Register-RequiredAzResourceProviders -DependencyFile './alldeps.psd1'
            }
            It "Should register each required provider" {
                Assert-MockCalled Register-AzResourceProvider -ParameterFilter {
                    $ProviderNamespace -like 'Microsoft.TestProvider*'
                } -Times 3            
            }
            It "Should write verbose messages" {
                Assert-MockCalled Write-Verbose -ParameterFilter {
                    $Message -like "Registering Resource Provider: 'Microsoft.TestProvider*'..."
                } -Times 3 -Exactly
            }
        }
        Context "When given an invalid file path" {
            BeforeAll {
                Mock Test-Path { $false }
            }
            It "Should throw an error" {
                { Register-RequiredAzResourceProviders -DependencyFile './nonexistent.psd1' } `
                | Should -Throw "Dependency file './nonexistent.psd1' not found."
            }
        }
        Context "When given a file with no RequiredProviders" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Import-PowerShellDataFile {
                    @{
                        RequiredModules   = @(
                            @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0' }
                        )
                        RequiredProviders = @()
                    }
                }
            }
            It "Should throw an error" {
                { Register-RequiredAzResourceProviders -DependencyFile './emptydeps.psd1' } `
                | Should -Throw "No RequiredProviders found in './emptydeps.psd1'. Nothing to register."
            }
        }
        Context "When dependency file import fails" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Import-PowerShellDataFile { throw "Simulated parse error." }
            }
            It "Should throw a descriptive error" {
                { Register-RequiredAzResourceProviders -DependencyFile './badfile.psd1' } |
                Should -Throw "Failed to import dependency file './badfile.psd1'. Error: Simulated parse error."
            }
        }
        Context "When Register-AzResourceProvider fails" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Import-PowerShellDataFile {
                    @{
                        RequiredModules   = @(
                            @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0' }
                        )
                        RequiredProviders = @(
                            'Microsoft.TestProvider1'
                        )
                    }
                }
                Mock Get-AzResourceProvider {
                    @(
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider1'
                            RegistrationState = 'NotRegistered'
                        }
                    )
                }
                Mock Register-AzResourceProvider { throw "Simulated registration failure." }
            }
            It "Should throw an error" {
                { Register-RequiredAzResourceProviders -DependencyFile './deps.psd1' } `
                | Should -Throw "Simulated registration failure."
            }
        }
        Context "When some Resource Providers are already registered" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Import-PowerShellDataFile {
                    @{
                        RequiredModules   = @(
                            @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0' }
                        )
                        RequiredProviders = @(
                            'Microsoft.TestProvider1',
                            'Microsoft.TestProvider2',
                            'Microsoft.TestProvider3'
                        )
                    }
                }
                Mock Get-AzResourceProvider {
                    @(
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider1'
                            RegistrationState = 'Registered'
                        },
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider2'
                            RegistrationState = 'NotRegistered'
                        },
                        [PSCustomObject]@{
                            ProviderNamespace = 'Microsoft.TestProvider3'
                            RegistrationState = 'NotRegistered'
                        }
                    )
                }
            }
            BeforeEach {
                Register-RequiredAzResourceProviders -DependencyFile './somedeps.psd1'
            }
            It "Should not call Register-AzResourceProvider for already registered providers" {
                Assert-MockCalled Register-AzResourceProvider -ParameterFilter {
                    $ProviderNamespace -like 'Microsoft.TestProvider*'
                } -Times 2 -Exactly
            }
            It "Should write verbose messages about registering" {
                Assert-MockCalled Write-Verbose -ParameterFilter {
                    $Message -like "Registering Resource Provider: 'Microsoft.TestProvider*'..."
                } -Times 2 -Exactly
            }
            It "Should write verbose message about not registering" {
                Assert-MockCalled Write-Verbose -ParameterFilter {
                    $Message -like "Resource Provider 'Microsoft.TestProvider1' is already registered."
                } -Times 1 -Exactly
            }
        }
    }
}
