#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for PwshInit public function Set-PSResourceGetv3.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/PwshInit/Tests/Unit/Set-PSResourceGetv3.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file PwshInit.psm1 from the module root folder.
#>

$ModuleName = 'PwshInit'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /PwshInit
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    Describe "Set-PSResourceGetv3" -Tag 'Unit' {
        BeforeAll {
            Mock Install-Module { 
                param($args) 
                return $null
            }
            Mock Confirm-ModuleVersionImport {
                return [PSCustomObject]@{
                    Name = 'Microsoft.PowerShell.PSResourceGet'
                    Version = [Version]'1.1.1'
                }
            }
        }
        Context "When not installed" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return @() 
                } -ParameterFilter {
                    $Name -eq 'Microsoft.PowerShell.PSResourceGet' -and
                    $ListAvailable 
                }
            }
            It "Should install and import PSResourceGet v3" {
                # Call the function
                Set-PSResourceGetv3 -Version '1.1.1'
                # Assert that the mocks were called
                Should -Invoke Install-Module -Times 1
                Should -Invoke Confirm-ModuleVersionImport -Times 1
            }
            It "Should return the expected module object" {
                $result = Set-PSResourceGetv3 -Version '1.1.1'
                $result.Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
                $result.Version | Should -Be '1.1.1'
            }
        }
        Context "Correct version already installed" {
            BeforeAll {
                Mock Get-Module {
                    @(
                        [PSCustomObject]@{
                            Name = 'Microsoft.PowerShell.PSResourceGet'
                            Version = [Version]'1.1.1'
                        }
                    )
                }
            }
            It "Should not install PSResourceGet v3" {
                # Call the function
                Set-PSResourceGetv3 -Version '1.1.1'
                # Assert that the mocks were called
                Should -Invoke Install-Module -Times 0
                Should -Invoke Confirm-ModuleVersionImport -Times 1
            }
            It "Should return the expected module object" {
                $result = Set-PSResourceGetv3 -Version '1.1.1'
                $result.Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
                $result.Version | Should -Be '1.1.1'
            }
        }
    }    
}