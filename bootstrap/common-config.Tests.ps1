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
Describe "Set-AzResourceGroup Mocked Function Tests" -Tag 'Unit' {
    # --- Setup & Teardown ---
    BeforeAll {
        $script:TestRGName = "Test-RG-Pester-Temp"
        $script:TestLocation = "uksouth"
        # Dot-source the main script
        . (Join-Path -Path $PSScriptRoot -ChildPath 'common-config.ps1')
    }

    AfterAll {
        # Cleanup
         Write-Host "Test environment cleanup complete." -ForegroundColor Green
    }

    Context "When Resource Group Does Not Exist" {
        BeforeEach {
            Mock Get-AzResourceGroup { $null }
            Mock New-AzResourceGroup {
                [PSCustomObject]@{
                    ResourceGroupName = $TestRGName
                    Location = $TestLocation
                }
            }
        }
        It "Should create the Resource Group" {
            # Execute the function
            $result = Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation
            $result.ResourceGroupName | Should -Be $TestRGName
            Assert-MockCalled New-AzResourceGroup -Times 1
            Assert-MockCalled Get-AzResourceGroup -Times 1
    }
    }

    Context "When Resource Group Already Exists (Idempotency Test)" {
        BeforeEach {
            Mock Get-AzResourceGroup {
                [PSCustomObject]@{
                    ResourceGroupName = $TestRGName
                    Location = $TestLocation
                }
            }
            Mock New-AzResourceGroup { throw "This should not be called when RG exists." }
        }

        # Test with -WhatIf
        It "Should NOT create a new Resource Group and return the existing object" {
            # Execute the function again. Since the RG exists, the logic should skip New-AzResourceGroup.
            $result = Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation -WhatIf

            $result.ResourceGroupName | Should -Be $TestRGName
            Assert-MockCalled New-AzResourceGroup -Times 0
            Assert-MockCalled Get-AzResourceGroup -Times 1

        }
    }
}
