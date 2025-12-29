#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureStorage private helper function New-UniqueStorageAccountName.
.DESCRIPTION
    Mocks to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureStorage/Tests/Unit/New-UniqueStorageAccountName.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureStorage.psm1 from the module root folder.
#>

$ModuleName = 'AzureStorage'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureStorage
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    Describe "New-UniqueStorageAccountName" -Tag 'Unit' {
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
}