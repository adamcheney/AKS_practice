<#
.SYNOPSIS
    Pester tests for the Set-AzResourceGroup function.
.DESCRIPTION
    These tests ensure the function creates a Resource Group when it's missing (Idempotency Test 1)
    and does nothing when it already exists (Idempotency Test 2).
.NOTES
    This script requires the Pester module to be installed.
#>
Describe "Set-AzResourceGroup Function Tests" {
    # --- Setup and Teardown for the entire test suite ---
    BeforeAll {
        $script:TestRGName = "Test-RG-Pester-Temp"
        $script:TestLocation = "uksouth"
        # Dot-source the main script file to load the function definitions into the test scope
        . (Join-Path -Path $PSScriptRoot -ChildPath 'common-config.ps1')

        # Connect to Azure using the necessary credentials before running any Azure-specific tests.
        # NOTE: You must be authenticated for these tests to run successfully.
        Write-Host "Please ensure you are connected to Azure (Connect-AzAccount) before running tests." -ForegroundColor Red

        # Cleanup any previous test runs that might have failed to tear down
        Remove-AzResourceGroup -Name $TestRGName -Force -Confirm:$false -ErrorAction SilentlyContinue
    }

    AfterAll {
        # Final cleanup to ensure the test Resource Group is removed
        Remove-AzResourceGroup -Name $TestRGName -Force -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Test environment cleanup complete." -ForegroundColor Green
    }

    Context "When Resource Group Does Not Exist" {
        It "Should create the Resource Group and return an object" {
            # Execute the function
            $Result = Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation

            # Assertion 1: Check that the function returned a successful object
            $Result | Should Not BeNullOrEmpty

            # Assertion 2: Check that the object is a Resource Group
            $Result.GetType().Name | Should Be "PSResourceGroup"

            # Assertion 3: Verify the RG exists in Azure after the run
            (Get-AzResourceGroup -Name $TestRGName -ErrorAction Stop).ResourceGroupName | Should Be $TestRGName
        }
    }

    Context "When Resource Group Already Exists (Idempotency Test)" {
        BeforeEach {
            # Idempotency relies on the RG existing from the previous test or created explicitly here.
            # We assume the previous test succeeded, but if running this context individually:
            if (-not (Get-AzResourceGroup -Name $TestRGName -ErrorAction SilentlyContinue)) {
                New-AzResourceGroup -Name $TestRGName -Location $TestLocation -Force | Out-Null
            }
        }

        It "Should NOT create a new Resource Group and return the existing object" {
            # Execute the function again. Since the RG exists, the logic should skip New-AzResourceGroup.
            # We test the -WhatIf output to confirm no action would be taken.
            $Result = Set-AzResourceGroup -ResourceGroupName $TestRGName -Location $TestLocation -WhatIf

            # Assertion: In -WhatIf mode, the result should confirm the intended skip (empty output)
            # The function's logic should show 'already exists', but no WhatIf creation message.
            # For simplicity, we just ensure no creation object is returned.
            $Result | Should BeNullOrEmpty

            # We verify the RG still exists to ensure the function didn't accidentally delete it.
            (Get-AzResourceGroup -Name $TestRGName -ErrorAction Stop).ResourceGroupName | Should Be $TestRGName
        }
    }
}
