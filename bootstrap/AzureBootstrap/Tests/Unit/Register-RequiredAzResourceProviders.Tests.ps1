#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureBootstrap public function Register-RequiredAzResourceProviders.
.DESCRIPTION
    Stubs Get-AzResourceProvider & Register-AzResourceProvider to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureBootstrap/Tests/Unit/Register-RequiredAzResourceProviders.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureBootstrap.psm1 from the module root folder.
#>

$ModuleName = 'AzureBootstrap'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureBootstrap
$modulePath = Join-Path -Path $ModuleDir -ChildPath "$ModuleName.psm1"
# Import the module
Import-Module $modulePath -Force

InModuleScope $ModuleName {
    BeforeAll{
        function Get-AzResourceProvider {
            param([Switch]$ListAvailable)
        }
        function Register-AzResourceProvider {
            param ($ProviderNamespace)
        }
    }
    Describe "Register-RequiredAzResourceProviders" -Tag 'Unit' {
        BeforeAll {
            Mock Write-Error {}
            Mock Write-Verbose {}
            Mock Get-AzResourceProvider {
            param([Switch]$ListAvailable)
                return @(
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
            } -ParameterFilter { $ListAvailable }
            Mock Register-AzResourceProvider {}
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
 
        }
        It "Should be a defined function" {
            $cmd = Get-Command -Name Register-RequiredAzResourceProviders -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
        }
        Context "When given a valid file list of required providers" {
            BeforeEach {
                Register-RequiredAzResourceProviders -DependencyFile './alldeps.psd1'
            }
            It "Should register each required provider" {
                Should -Invoke Register-AzResourceProvider -ParameterFilter {
                    $ProviderNamespace -like 'Microsoft.TestProvider*'
                } -Times 2            
            }
            It "Should write verbose messages" {
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -like "Registering Resource Provider: 'Microsoft.TestProvider*'..."
                } -Times 2 -Exactly
            }
        }
        Context "When given an invalid file path" {
            BeforeAll {
                Mock Test-Path { $false }
            }
            It "Should throw an error" {
                { Register-RequiredAzResourceProviders -DependencyFile './nonexistent.psd1' } |
                  Should -Throw "Dependency file './nonexistent.psd1' not found."
            }
        }
        Context "When given a file with no RequiredProviders" {
            BeforeAll {
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
                { Register-RequiredAzResourceProviders -DependencyFile './emptydeps.psd1' } |
                  Should -Throw "No RequiredProviders found in './emptydeps.psd1'. Nothing to register."
            }
        }
        Context "When dependency file import fails" {
            BeforeAll {
                Mock Import-PowerShellDataFile { throw "Simulated parse error." }
            }
            It "Should throw a descriptive error" {
                { Register-RequiredAzResourceProviders -DependencyFile './badfile.psd1' } |
               Should -Throw "Failed to import dependency file './badfile.psd1'. Error: Simulated parse error."
            }
        }
        Context "When Register-AzResourceProvider fails" {
            BeforeAll {
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
                { Register-RequiredAzResourceProviders -DependencyFile './deps.psd1' } |
                  Should -Throw "Simulated registration failure."
            }
        }
        Context "When some Resource Providers are already registered" {
            BeforeEach {
                Register-RequiredAzResourceProviders -DependencyFile './somedeps.psd1'
            }
            It "Should not call Register-AzResourceProvider for already registered providers" {
                Should -Invoke Register-AzResourceProvider -ParameterFilter {
                    $ProviderNamespace -like 'Microsoft.TestProvider*'
                } -Times 2 -Exactly
            }
            It "Should write verbose messages about registering" {
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -like "Registering Resource Provider: 'Microsoft.TestProvider*'..."
                } -Times 2 -Exactly
            }
            It "Should write verbose message about not registering" {
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -like "Resource Provider 'Microsoft.TestProvider1' is already registered."
                } -Times 1 -Exactly
            }
        }
    }
}
