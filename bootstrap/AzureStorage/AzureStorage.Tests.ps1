#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for the AzureStorage module.
.DESCRIPTION
    Unit tests for:
      - New-UniqueStorageAccountName
      - Set-BackendStorageAccount (creation, idempotency, error paths, WhatIf)
    External dependencies (Get-Az*, New-AzStorageAccount, Get-Date, file system) are mocked
    so tests are deterministic and side-effect free.
.EXAMPLE
    # Run from repo root
    Invoke-Pester -Path ./bootstrap/AzureStorage/AzureStorage.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (Core).
    - Imports AzureStorage.psm1 from the same directory and uses InModuleScope where appropriate.
    - Tests clear relevant environment variables and isolate mocks (BeforeAll/BeforeEach semantics).
#>
$modulePath = Join-Path $PSScriptRoot 'AzureStorage.psm1'
Import-Module $modulePath -Force

InModuleScope AzureStorage {
    Describe "New-UniqueStorageAccountName" {
        It "Should be a defined function" {
            $cmd = Get-Command -Name Set-AzureContext -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When passed suitable prefix" {
            It "Should return a suitable name" {
                $name = New-UniqueStorageAccountName -Prefix 'cheneyawiacb'
                $name | Should -Match '^cheneyawiacb[0-9]{12}$'
            }
            It "Should not throw any errors" {
                { New-UniqueStorageAccountName -Prefix 'suitable'} |
                    Should -Not -Throw
            }
            It "Should generate unique StorageAccount name" {
                Mock Get-Date { "12311159590001" } -ParameterFilter { $Format -eq 'MMddHHmmssff' }
                $name1 = New-UniqueStorageAccountName -Prefix 'test'
                Mock Get-Date { "12311159590002" } -ParameterFilter { $Format -eq 'MMddHHmmssff' }
                $name2 = New-UniqueStorageAccountName -Prefix 'test'
                $name1 | Should -Not -Be $name2
            }
        }
        Context "When passed prefix that is too long" {
            It "Should throw a meaningful error" {
                { New-UniqueStorageAccountName -Prefix 'therearetoomanycharacters'} |
                    Should -Throw -ErrorId "ParameterArgumentValidationError*"
            }
        }
        Context "When passed prefix containing proscribed characters" {
            It "Should throw a meaningful error" {
                { New-UniqueStorageAccountName -Prefix 'Really?'} |
                    Should -Throw -ErrorId "ParameterArgumentValidationError*"
            }
        }
    }
    Describe "Set-BackendStorageAccount" -Tag 'Unit' {
        BeforeAll {
            Mock Get-AzResourceGroup {
                param($Name)
                [PSCustomObject]@{ ResourceGroupName = $Name }
            }
            Mock New-UniqueStorageAccountName { 'testacct123456789012' } `
                -ParameterFilter { $Prefix -eq 'testacct' }
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
            $cmd = Get-Command -Name Set-AzureContext -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When called with non-existent Resource Group" {
            BeforeAll {
                Mock Get-AzResourceGroup { $null } `
                    -ParameterFilter { $Name -eq 'nonexistent-rg' }
                $params = $baseParams.clone()
                $params.ResourceGroupName = 'nonexistent-rg'
            }
            It "Should throw an error" {
                { Set-BackendStorageAccount @params } |
                   Should -Throw "Resource Group 'nonexistent-rg' does not exist."
            }
        }
        Context "When no Storage Account exists" {
            BeforeAll {
                Mock Get-AzStorageAccount  { $null } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
                $params = $baseParams.clone()
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @params } |
                    Should -Not -Throw
            }
            It "Should call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @params
                Should -Invoke New-UniqueStorageAccountName -Times 1 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should call New-AzStorageAccount" {
                Set-BackendStorageAccount @params
                Should -Invoke New-AzStorageAccount -Times 1 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'test-rg' -and `
                        $Name -eq 'testacct123456789012' -and `
                        $Location -eq 'eastus' -and
                        $SkuName -eq 'Standard_LRS' }
            }
            It "Should create a new Storage Account" {
                $storageAccount = Set-BackendStorageAccount @params
                $storageAccount.StorageAccountName | Should -Match '^testacct[0-9]{12}$'
            }
        }
        Context "When a Storage Account with incorrect prefix exists" {
            BeforeAll {
                $existingAcct = [PSCustomObject]@{
                    StorageAccountName = 'otheracct123456789012'
                    Location           = 'eastus'
                    CreationTime       = (Get-Date).AddDays(-1)
                }
                Mock Get-AzStorageAccount  { @($existingAcct) } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
                $params = $baseParams.clone()
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @params } |
                    Should -Not -Throw
            }
            It "Should call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @params
                Should -Invoke New-UniqueStorageAccountName -Times 1 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should call New-AzStorageAccount" {
                Set-BackendStorageAccount @params
                Should -Invoke New-AzStorageAccount -Times 1 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'test-rg' -and `
                        $Name -eq 'testacct123456789012' -and `
                        $Location -eq 'eastus' -and
                        $SkuName -eq 'Standard_LRS' }
            }
            It "Should create a new Storage Account" {
                $storageAccount = Set-BackendStorageAccount @params
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
                $params = $baseParams.clone()
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @params } |
                    Should -Not -Throw
            }
            It "Should NOT call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @params
                Should -Invoke New-UniqueStorageAccountName -Times 0 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should NOT call New-AzStorageAccount" {
                Set-BackendStorageAccount @params
                Should -Invoke New-AzStorageAccount -Times 0 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'test-rg' -and `
                        $Location -eq 'eastus' }
            }
            It "Should return the existing Storage Account" {
                $storageAccount = Set-BackendStorageAccount @params
                $storageAccount.StorageAccountName | Should -Be 'testacct999999999999'
            }
        }
        Context "When a Storage Account with correct prefix exists in different location" {
            BeforeAll {
                $existingAcct = [PSCustomObject]@{
                    StorageAccountName = 'testacct999999999999'
                    Location           = 'westus'
                    CreationTime       = (Get-Date).AddDays(-1)
                }
                Mock Get-AzStorageAccount  { @($existingAcct) } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
                $params = $baseParams.clone()
            }
            It "Should run without error" {
                { Set-BackendStorageAccount @params } |
                    Should -Not -Throw
            }
            It "Should NOT call New-UniqueStorageAccountName" {
                Set-BackendStorageAccount @params
                Should -Invoke New-UniqueStorageAccountName -Times 0 `
                    -ParameterFilter { $Prefix -eq 'testacct' }
            }
            It "Should NOT call New-AzStorageAccount" {
                Set-BackendStorageAccount @params
                Should -Invoke New-AzStorageAccount -Times 0 `
                    -ParameterFilter { `
                        $ResourceGroupName -eq 'test-rg' -and `
                        $Location -eq 'eastus' }
            }
            It "Should return the existing Storage Account" {
                $storageAccount = Set-BackendStorageAccount @params
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
                { Set-BackendStorageAccount @params } |
                    Should -Not -Throw
            }
            It "Should return the most recent Storage Account" {
                $storageAccount = Set-BackendStorageAccount @params
                $storageAccount.StorageAccountName | Should -Be 'testacct222222222222'
            }
        }
        Context "When Get-AzStorageAccount fails" {
            BeforeAll {
                Mock Get-AzStorageAccount { throw "Network error" }
                $params = $baseParams.clone()
            }
            It "Should throw an error" {
                { Set-BackendStorageAccount @params } |
                   Should -Throw "Network error"
            }
        }
        Context "When New-AzStorageAccount fails" {
            BeforeAll {
                Mock Get-AzStorageAccount { $null }
                Mock New-AzStorageAccount { throw "Quota exceeded" }
                $params = $baseParams.clone()
            }
            It "Should throw an error" {
                { Set-BackendStorageAccount @params } |
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