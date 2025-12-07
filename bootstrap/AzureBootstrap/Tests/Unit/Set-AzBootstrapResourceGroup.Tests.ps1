#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureBootstrap public function Set-AzBootstrapResourceGroup.
.DESCRIPTION
    Stubs New-AzResourceGroup & Get-AzResourceGroup to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureBootstrap/Tests/Unit/Set-AzBootstrapResourceGroup.Tests.ps1
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
        function New-AzResourceGroup {
            param($Name, $Location)
        }
        function Get-AzResourceGroup {
            param($Name, $ErrorAction)
        }
    }
    Describe "Set-AzBootstrapResourceGroup" -Tag 'Unit' {
        BeforeAll {
            Mock New-AzResourceGroup {
                param($Name, $Location)
                return [PSCustomObject]@{
                    ResourceGroupName = $Name
                    Location          = $Location
                }
            }
            Mock Write-Verbose {}
            Mock Get-AzResourceGroup {
                param($Name)
                return $null
            }
        }
        It "Should be a defined function" {
            $cmd = Get-Command -Name Set-AzBootstrapResourceGroup -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When Resource Group does not exist" {
            It "Should create the Resource Group" {
                Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation'
                Should -Invoke New-AzResourceGroup -ParameterFilter {
                    $Name -eq 'testRG' -and $Location -eq 'testLocation'
                } -Times 1
            }
            It "Should return a valid object" {
                $result = Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation'
                $result | Should -Not -BeNullOrEmpty
                $result.ResourceGroupName | Should -Be 'testRG'
                $result.Location | Should -Be 'testLocation'
            }
        }
        Context "When Resource Group already exists (Idempotency)" {
            BeforeAll{
                Mock Get-AzResourceGroup {
                    param($Name)
                    return [PSCustomObject]@{
                        ResourceGroupName = $Name
                        Location          = 'testLocation'
                    }
                }
            }
            It "Should do nothing and return the existing object" {
                $result = Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation'
                $result | Should -Not -BeNullOrEmpty
                $result.ResourceGroupName | Should -Be 'testRG'
                $result.Location | Should -Be 'testLocation'
                Should -Invoke New-AzResourceGroup -Times 0
            }
        }
        Context "When Get-AzureResourceGroup fails" {
            BeforeAll {
                Mock Get-AzResourceGroup { throw "Simulated retrieval failure." }
                Mock Write-Error {}
            }
            It "Should throw an error" {
                { Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' } |
                  Should -Throw "Simulated retrieval failure."
            }
        }
        Context "When New-AzureResourceGroup fails" {
            BeforeAll {
                Mock New-AzResourceGroup { throw "Simulated creation failure." }
                Mock Write-Error {}
            }
            It "Should throw an error" {
                { Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' } |
                  Should -Throw "Simulated creation failure."
            }
        }
        Context "When called with -WhatIf" {
            It "Should not create a new Resource Group" {
                Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' -WhatIf
                Should -Invoke New-AzResourceGroup -Times 0
            }
            It "Should return $null" {
                $result = Set-AzBootstrapResourceGroup -ResourceGroupName 'testRG' -Location 'testLocation' -WhatIf
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
