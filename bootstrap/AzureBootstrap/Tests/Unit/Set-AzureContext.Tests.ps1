#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureBootstrap public function Set-AzBootstrapResourceGroup.
.DESCRIPTION
    Stubs Get-AzContext & Connect-AzAccount to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureBootstrap/Tests/Unit/Set-AzBootstrapResourceGroup.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureBootstrap.psm1 from the module root folder.
#>

$ModuleName = 'AzureBootstrap'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureBootstrap
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    BeforeAll{
        function Get-AzContext {}
        function Connect-AzAccount {}
    }
    Describe "Set-AzureContext" -Tag 'Unit' {
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
        It "Should be a defined function" {
            $cmd = Get-Command -Name Set-AzureContext -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When no Azure context" {
            BeforeEach {
                $result = Set-AzureContext
            }
            It "Should run Connect-AzAccount" {
                Should -Invoke Connect-AzAccount -Times 1
            }
            It "Should write verbose messages" {
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -match "No Azure context found. Initiating login..."
                } -Times 1
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -match "Logged in to Azure successfully."
                } -Times 1
            }
            It "Should NOT write error messages" {
                Should -Invoke Write-Error -Times 0
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
                Should -Invoke Connect-AzAccount -Times 0
            }
            It "Should write verbose message about existing context" {
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -match "Azure context exists - already logged in."
                } -Times 1
            }
            It "Should NOT write error messages" {
                Should -Invoke Write-Error -Times 0
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
                Should -Invoke Write-Error -ParameterFilter {
                    $Message -match "Azure login failed. Error: Simulated login failure."
                } -Times 1
            }
        }
    }
}
