#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for the az-storage module functions.
.DESCRIPTION
    Tests:
        1) 
        REWORK this whole comment block
.NOTES
    This script requires the Pester module to be installed.
#>
$modulePath = Join-Path $PSScriptRoot 'az-storage.psm1'
Import-Module $modulePath -Force

InModuleScope az-bootstrap {
    Describe "New-UniqueStorageAccountName" {
        Context "When passed suitable prefix" {
            It "Should return a suitable name" {
                $name = New-UniqueStorageAccountName -Prefix 'cheneyawiacb'
                $name | Should -Match '^cheneyawiacb[0-9]{12}$'
            }
            It "Should not throw any errors" {
                { New-UniqueStorageAccountName -Prefix 'suitable'} `
                  | Should -Not -Throw
            }
            It "Should generate unique StorageAccount name" {
                Mock Get-Date { "12311159590001" } -ParameterFilter { $Format -eq 'MMddHHmmssff' }
                $name1 = New-UniqueStorageAccountName -Prefix 'test'
                Mock Get-Date { "12311159590002" } -ParameterFilter { $Format -eq 'MMddHHmmssff' }
                $name2 = New-UniqueStorageAccountName -Prefix 'test'
                $name1 | Should -Not -Be $result2
            }
        }
        Context "When passed prefix that is too long" {
            It "Should throw a meaningful error" {
                { New-UniqueStorageAccountName -Prefix 'therearetoomanycharacters'} `
                  | Should -Throw -ErrorId "ParameterArgumentValidationError*"
            }
        }
        Context "When passed prefix containing proscribed characters" {
            It "Should throw a meaningful error" {
                { New-UniqueStorageAccountName -Prefix 'Really?'} `
                  | Should -Throw -ErrorId "ParameterArgumentValidationError*"
            }
        }
    }
    Describe "Set-BackendStorageAccount" -Tag 'Unit' {
        Context "When no Storage Account exists" {
            BeforeAll {
                Mock Get-AzStorageAccount  { $null } `
                    -ParameterFilter { $ResourceGroupName -eq 'test-rg' }
                Mock New-UniqueStorageAccountName { 'testacct123456789012' } `
                    -ParameterFilter { $Prefix -eq 'testacct' }
                Mock New-AzStorageAccount { 
                    [PSCustomObject]@{
                        StorageAccountName = 'testacct123456789012'
                        ResourceGroupName  = 'testrg'
                        Location           = 'uksouth'
                        Sku                = [PSCustomObject]@{ Name = 'Standard_LRS' }
                        Kind               = 'StorageV2'
                        PrimaryEndpoints   = [PSCustomObject]@{ Blob = 'https://teststorageacct.blob.core.windows.net/' }
                    }
                }
            }
            It "Should run without error" {
                { Set-BackendStorageAccount `
                    -ResourceGroupName 'test-rg' `
                    -StorageAccountNamePrefix 'testacct' `
                    -Location 'eastus' } `
                  | Should -Not -Throw
            }
        #     It "Should call New-UniqueStorageAccountName" {
        #         Set-BackendStorageAccount `
        #             -ResourceGroupName 'test-rg' `
        #             -StorageAccountNamePrefix 'testacct' `
        #             -Location 'eastus'
        #         Assert-MockCalled New-UniqueStorageAccountName -Times 1 `
        #             -ParameterFilter { $Prefix -eq 'testacct' }
        #     }
        #     It "Should call New-AzStorageAccount" {
        #         Set-BackendStorageAccount `
        #             -ResourceGroupName 'test-rg' `
        #             -StorageAccountNamePrefix 'testacct' `
        #             -Location 'eastus'
        #         Assert-MockCalled New-AzStorageAccount -Times 1 `
        #             -ParameterFilter { `
        #                 $ResourceGroupName -eq 'test-rg' -and `
        #                 $Name -eq 'testacct123456789012' -and `
        #                 $Location -eq 'eastus' -and `
        #                 $Sku -eq 'Standard_LRS' -and `
        #                 $Kind -eq 'StorageV2' }
        #     }
        #     It "Should create a new Storage Account" {
        #         $storageAccount = Set-BackendStorageAccount `
        #             -ResourceGroupName 'test-rg' `
        #             -StorageAccountNamePrefix 'testacct' `
        #             -Location 'eastus'
        #         $storageAccount.StorageAccountName | Should -Match '^testacct[0-9]{12}$'
        #     }
        # }
        # Context "When a Storage Account with incorrect prefix exists" {
        #     #
        # }
        # Context "When a Storage Account with correct prefix exists" {
        #     #
        }
    }
}