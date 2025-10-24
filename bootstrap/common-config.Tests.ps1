#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for the Set-AzResourceGroup function.
.DESCRIPTION
    Tests:
        1) Ensure Set-AZResourceGroup creates Resource Group when missing
        2) Ensure Set-AZResourceGroup does nothing when Resource Group already exists 
.NOTES
    This script requires the Pester module to be installed.
#>
BeforeAll {
    # Prevent bootstrap side-effects when loading the file under test
    . (Join-Path -Path $PSScriptRoot -ChildPath 'common-config.ps1')
    Mock Write-Verbose {}
    Mock Write-Error {}
}

Describe "Set-AzureContext" -Tag 'Unit' {
    BeforeAll {
        Mock Write-Verbose {}
        Mock Write-Error {}
    }
    It "Should be a defined function" {
        $cmd = Get-Command -Name Set-AzureContext -ErrorAction Stop
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.CommandType | Should -Be 'Function'
        # Ensure it exposes a parameter block (not strictly behavioural, but useful)
        $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
    }
    Context "When no Azure context" {
        BeforeAll {
            Mock Get-AzContext { $null }
            Mock Connect-AzAccount {
                [PSCustomObject]@{
                    Account = "testAccount"
                    Subscription = "testSubscription"
                    Tenant = "testTenant"
                }
            }
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
            Mock Get-AzContext{
                [PSCustomObject]@{
                    Account = "oldTestAccount"
                    Subscription = "oldTestSubscription"
                    Tenant = "oldTestTenant"
                }
            }
            Mock Connect-AzAccount {}
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
                Location = 'testLocation'
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
                    Location = 'testLocation'
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
            Mock Import-PowerShellDataFile{
                @{
                    RequiredModules = @(
                        @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0'}
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
            Mock Import-PowerShellDataFile{
                @{
                    RequiredModules = @(
                        @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0'}
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
    Context "When Register-AzResourceProvider fails" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile{
                @{
                    RequiredModules = @(
                        @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0'}
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
            Mock Import-PowerShellDataFile{
                @{
                    RequiredModules = @(
                        @{ModuleName = 'Az.TestMod'; ModuleVersion = '1.1.0'}
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