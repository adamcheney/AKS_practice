#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureStorage public function Set-BackendStorageAccount.
.DESCRIPTION
    Mocks to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureStorage/Tests/Unit/Set-BackendStorageAccount.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureStorage.psm1 from the module root folder.
#>

$ModuleName = 'AzureStorage'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureStorage
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    BeforeAll {
        function Get-AzResourceGroup {
            param($Name)
        }
        function New-AzStorageAccount {
            param($ResourceGroupName, $Name, $Location, $SkuName)
        }
        function Get-AzStorageAccount {
            param($ResourceGroupName)
        }
    }
    Describe "Set-BackendStorageAccount" -Tag 'Unit' {
        BeforeAll {
            Mock Get-AzResourceGroup {
                param($Name)
                return [PSCustomObject]@{
                    ResourceGroupName = $Name
                }
            } -ParameterFilter { $Name -ne 'nonexistent-rg' }
            Mock New-UniqueStorageAccountName { 
                param($Prefix)
                return 'testacct123456789012' 
            } -ParameterFilter { $Prefix -eq 'testacct' }
            Mock New-AzStorageAccount {
                param($ResourceGroupName, $Name, $Location, $SkuName)
                [PSCustomObject]@{
                    StorageAccountName = $Name
                    ResourceGroupName  = $ResourceGroupName
                    Location           = $Location
                    Skuname            = $SkuName
                }
            }
            $baseParams = @{
                ResourceGroupName        = 'test-rg'
                StorageAccountNamePrefix = 'testacct'
                Location                 = 'eastus'
            }
        }
        It "Should be a defined function" {
            $cmd = Get-Command -Name Set-BackendStorageAccount -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When called with non-existent Resource Group" {
            BeforeAll {
                Mock Get-AzResourceGroup {
                    param($Name)
                    return $null
                }  -ParameterFilter { $Name -eq 'nonexistent-rg' }
                $noRGParams = $baseParams.clone()
                $noRGParams.ResourceGroupName = 'nonexistent-rg'
            }
            It "Should throw an error" {
                { Set-BackendStorageAccount @noRGParams } |
                   Should -Throw "Resource Group 'nonexistent-rg' does not exist."
            }
        }
        Context "When no Storage Account exists" {
            BeforeAll {
                Mock Get-AzStorageAccount  { 
                    param($ResourceGroupName)
                    return $null
                } -ParameterFilter { $ResourceGroupName -eq 'nostorage-rg' }
                $noStoreParams = $baseParams.clone()
                $noStoreParams.ResourceGroupName = 'nostorage-rg'
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @noStoreParams } |
                    Should -Not -Throw
            }
            It "Should call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @noStoreParams
                Should -Invoke New-UniqueStorageAccountName -Times 1 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should call New-AzStorageAccount" {
                Set-BackendStorageAccount @noStoreParams
                Should -Invoke New-AzStorageAccount -Times 1 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'nostorage-rg' -and `
                        $Name -eq 'testacct123456789012' -and `
                        $Location -eq 'eastus' -and
                        $SkuName -eq 'Standard_LRS'
                    }
            }
            It "Should create a new Storage Account" {
                $storageAccount = Set-BackendStorageAccount @noStoreParams
                $storageAccount.StorageAccountName | Should -Match '^testacct[0-9]{12}$'
            }
        }
        Context "When a Storage Account with incorrect prefix exists" {
            BeforeAll {
                $wrongPrefixSA = [PSCustomObject]@{
                    StorageAccountName = 'otheracct123456789012'
                    Location           = 'eastus'
                    CreationTime       = (Get-Date).AddDays(-1)
                }
                Mock Get-AzStorageAccount  {
                    param($ResourceGroupName)
                    return @($wrongPrefixSA) 
                } -ParameterFilter { $ResourceGroupName -eq 'wrongsa-rg' }
                $wrongSAParams = $baseParams.clone()
                $wrongSAParams.ResourceGroupName = 'wrongsa-rg'
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @wrongSAParams } |
                    Should -Not -Throw
            }
            It "Should call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @wrongSAParams
                Should -Invoke New-UniqueStorageAccountName -Times 1 -ParameterFilter {
                    $Prefix -eq 'testacct'
                }
            }
            It "Should call New-AzStorageAccount" {
                Set-BackendStorageAccount @wrongSAParams
                Should -Invoke New-AzStorageAccount -Times 1 -ParameterFilter {
                        $ResourceGroupName -eq 'wrongsa-rg' -and
                        $Name -eq 'testacct123456789012' -and
                        $Location -eq 'eastus' -and
                        $SkuName -eq 'Standard_LRS'
                    }
            }
            It "Should create a new Storage Account" {
                $storageAccount = Set-BackendStorageAccount @wrongSAParams
                $storageAccount.StorageAccountName | Should -Match '^testacct[0-9]{12}$'
            }
        }
        Context "When a Storage Account with correct prefix exists" {
            BeforeAll {
                $existingAcct = [PSCustomObject]@{
                    StorageAccountName = 'testacct999999999999'
                    Location           = 'eastus'
                    CreationTime       = (Get-Date).AddDays(-1)
                }
                Mock Get-AzStorageAccount  { @($existingAcct) } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @baseParams } |
                    Should -Not -Throw
            }
            It "Should NOT call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @baseParams
                Should -Invoke New-UniqueStorageAccountName -Times 0 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should NOT call New-AzStorageAccount" {
                Set-BackendStorageAccount @baseParams
                Should -Invoke New-AzStorageAccount -Times 0 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'test-rg' -and `
                        $Location -eq 'eastus' }
            }
            It "Should return the existing Storage Account" {
                $storageAccount = Set-BackendStorageAccount @baseParams
                $storageAccount.StorageAccountName | Should -Be 'testacct999999999999'
            }
        }
        Context "When a Storage Account with correct prefix exists in different location" {
            BeforeAll {
                $diffLocationAcct = [PSCustomObject]@{
                    StorageAccountName = 'testacct999999999999'
                    Location           = 'westus'
                    CreationTime       = (Get-Date).AddDays(-1)
                }
                Mock Get-AzStorageAccount  { @($diffLocationAcct) } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @baseParams } |
                    Should -Not -Throw
            }
            It "Should NOT call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @baseParams
                Should -Invoke New-UniqueStorageAccountName -Times 0 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should NOT call New-AzStorageAccount" {
                Set-BackendStorageAccount @baseParams
                Should -Invoke New-AzStorageAccount -Times 0 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'test-rg' -and `
                        $Location -eq 'eastus' }
            }
            It "Should return the existing Storage Account" {
                $storageAccount = Set-BackendStorageAccount @baseParams
                $storageAccount.StorageAccountName | Should -Be 'testacct999999999999'
            }
        }
        Context "When multiple Storage Accounts with correct prefix exist" {
            BeforeAll {
                $acct1 = [PSCustomObject]@{
                    StorageAccountName = 'testacct111111111111'
                    Location           = 'eastus'
                    CreationTime       = (Get-Date).AddDays(-2)
                }
                $acct2 = [PSCustomObject]@{
                    StorageAccountName = 'testacct222222222222'
                    Location           = 'eastus'
                    CreationTime       = (Get-Date).AddDays(-1)
                }
                Mock Get-AzStorageAccount  { @($acct1, $acct2) } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
                $params = $baseParams.clone()
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @baseParams } |
                    Should -Not -Throw
            }
            It "Should return the most recent Storage Account" {
                $storageAccount = Set-BackendStorageAccount @baseParams
                $storageAccount.StorageAccountName | Should -Be 'testacct222222222222'
            }
        }
        Context "When Get-AzStorageAccount fails" {
            BeforeAll {
                Mock Get-AzStorageAccount {
                    param($ResourceGroupName)
                    throw "Network error"
                } -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
            }
            It "Should throw an error" {
                { Set-BackendStorageAccount @baseParams } |
                   Should -Throw "Network error"
            }
        }
        Context "When New-AzStorageAccount fails" {
            BeforeAll {
                Mock Get-AzStorageAccount {
                    param($ResourceGroupName)
                    return $null
                } -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
                Mock New-AzStorageAccount {
                    param($ResourceGroupName, $Name, $Location, $SkuName)
                    throw "Quota exceeded"
                } -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
            }
            It "Should throw an error" {
                { Set-BackendStorageAccount @baseParams } |
                   Should -Throw "Quota exceeded"
            }
        }
        Context "When called with -WhatIf" {
            BeforeAll {
                Mock Get-AzStorageAccount { $null }
                Mock New-UniqueStorageAccountName { 'test123' }
                Mock New-AzStorageAccount {}
            }
            It "Should not create storage account" {
                Set-BackendStorageAccount -ResourceGroupName 'test-rg' -StorageAccountNamePrefix 'test' -Location 'eastus' -WhatIf
               Should -Invoke New-AzStorageAccount -Times 0
            }
            It "Should return null" {
                $result = Set-BackendStorageAccount -ResourceGroupName 'test-rg' -StorageAccountNamePrefix 'test' -Location 'eastus' -WhatIf
                $result | Should -BeNullOrEmpty
            }
        }
    }
}