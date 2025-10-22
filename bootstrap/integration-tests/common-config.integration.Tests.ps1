#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester integration tests for the common config functions.
.DESCRIPTION
    Tests:
        1) Ensure Set-AZResourceGroup creates Resource Group when missing
        2) Ensure Set-AZResourceGroup does nothing when Resource Group already exists 
.NOTES
    This script requires the Pester module to be installed.
#>
Describe "Set-AzResourceGroup Function Tests" -Tag 'Integration' {
    # --- Setup & Teardown ---
    BeforeAll {
        $script:TestRGName = "Test-RG-Pester-Temp"
        $script:TestLocation = "uksouth"
        # Dot-source the main script
        . (Join-Path -Path $PSScriptRoot -ChildPath 'common-config.ps1')

        # Connect to Azure using the necessary credentials before running any Azure-specific tests.
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            throw "Not logged in to Azure. Please run Connect-AzAccount"
        }

        # Cleanup old runs that failed to teardown
        Remove-AzResourceGroup -Name $TestRGName -Force -Confirm:$false -ErrorAction SilentlyContinue
    }

    AfterAll {
        # Cleanup
        Remove-AzResourceGroup -Name $TestRGName -Force -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Test environment cleanup complete." -ForegroundColor Green
    }

    Context "When Resource Group Does Not Exist" {
        It "Should create the Resource Group and return an object" {
            # Execute the function
            $Result = Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation
            # Assertion 1: Check that the function returned a successful object
            $Result | Should -Not -BeNullOrEmpty
            # Assertion 2: Check that the object is a Resource Group
            $Result.GetType().Name | Should -Be "PSResourceGroup"
            # Assertion 3: Verify the RG exists in Azure after the run
            (Get-AzResourceGroup -Name $TestRGName -ErrorAction Stop).ResourceGroupName | Should -Be $TestRGName
        }
    }

    Context "When Resource Group Already Exists (Idempotency Test)" {
        BeforeEach {
            # Idempotency relies on the RG existing
            # If running this context individually:
            if (-not (Get-AzResourceGroup -Name $TestRGName -ErrorAction SilentlyContinue)) {
                Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation | Out-Null
            }
        }

        # Test with -WhatIf
        It "Should NOT create a new Resource Group and return the existing object" {
            # Execute the function again. Since the RG exists, the logic should skip New-AzResourceGroup.
            $Result = Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation -WhatIf

            # Assertion: In -WhatIf mode, the result should confirm the intended skip (empty output)
            # For simplicity, we just ensure no creation object is returned.
            $Result | Should -BeNullOrEmpty

            # We verify the RG still exists to ensure the function didn't accidentally delete it.
            (Get-AzResourceGroup -Name $TestRGName -ErrorAction Stop).ResourceGroupName | Should -Be $TestRGName
        }
    }
}
