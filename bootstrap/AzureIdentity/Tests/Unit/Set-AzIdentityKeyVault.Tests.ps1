#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity public function Set-AzIdentityKeyVault.
.DESCRIPTION
    Stubs Get-AzResourceGroup, Get-AzKeyVault & New-AzKeyVault to ensure
     deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/Tests/Unit/Set-AzIdentityKeyVault.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureIdentity.psm1 from the module root folder.
#>

$ModuleName = 'AzureIdentity'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureIdentity
$modulePath = Join-Path -Path $ModuleDir -ChildPath "$ModuleName.psm1"
# Import the module
Import-Module $modulePath -Force

InModuleScope $ModuleName {
    BeforeAll {
        # Define all Azure cmdlets used across all tests
        function Get-AzResourceGroup {}
        function Get-AzKeyVault {
            param($VaultName, $ResourceGroupName)
        }
        function New-AzKeyVault {
            param($Name, $ResourceGroupName, $Location, $Sku = 'Standard')
        }
    }

    Describe "Set-AzIdentityKeyVault" -Tag 'Unit' {
        BeforeAll {
            Mock Get-AzResourceGroup {
                param($Name)
                [PSCustomObject]@{
                    ResourceGroupName = $Name
                    Location = 'eastus'
                }
            }
            Mock New-AzKeyVault { 
                param($Name, $ResourceGroupName, $Location, $Sku = 'Standard')
                [PSCustomObject]@{ 
                    VaultName         = $Name
                    ResourceGroupName = $ResourceGroupName
                    Location          = $Location
                    Sku               = $Sku
                }
            }
            $vaultParams = @{
                VaultName         = 'testvault'
                ResourceGroupName = 'test-rg'
                Location          = 'eastus'
            }
        }
        Context "When Resource Group does not exist" {
            BeforeAll {
                Mock Get-AzResourceGroup { $null }
                $noRGParams = $vaultParams.Clone()
                $noRGParams.ResourceGroupName = 'non-existent-rg'
            }
            It "Should throw an error" {
                { Set-AzIdentityKeyVault @noRGParams } | Should -Throw "Resource Group 'non-existent-rg' does not exist."
            }
        }
        Context "When Key Vault does not exist" {
            BeforeAll {
                Mock Get-AzKeyVault { $null }
            }
            It "Should create a new Key Vault" {
                $result = Set-AzIdentityKeyVault @vaultParams -Confirm:$false
                Should -Invoke New-AzKeyVault -Times 1 -ParameterFilter {
                    $Name -eq 'testvault' -and
                    $ResourceGroupName -eq 'test-rg' -and
                    $Location -eq 'eastus' -and
                    $Sku -eq 'Standard'
                }
                $result.VaultName | Should -Be 'testvault'
            }
            It "Should return the created Key Vault" {
                $result = Set-AzIdentityKeyVault @vaultParams
                $result | Should -Not -Be $null
                $result.VaultName | Should -Be 'testvault'
            }
            It "Should respect ShouldProcess" {
                { Set-AzIdentityKeyVault @vaultParams -WhatIf }
                Should -Invoke New-AzKeyVault -Times 0
            }
            It "Should return $null when skipped by ShouldProcess" {
                $result = Set-AzIdentityKeyVault @vaultParams -WhatIf
                $result | Should -Be $null
            }
        }
    }
}
