#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for PwshInit public function Confirm-ModuleVersionInstall.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/PwshInit/Tests/Unit/Confirm-ModuleVersionInstall.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file PwshInit.psm1 from the module root folder.
#>

$ModuleName = 'PwshInit'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /PwshInit
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    Describe "Confirm-ModuleVersionInstall" -Tag 'Unit' {
        BeforeAll {
            Mock Get-Module {
                param($Name, $ListAvailable)
                return @(
                    [PSCustomObject]@{
                        Name = $Name
                    }
                )
            }
            Mock Install-PSResource {
                param($Name, $Version, $Scope, $Repository)
                return [PSCustomObject]@{
                    Name = $Name
                    Version = [Version]$Version
                }
            }
            Mock Write-Verbose {
                param($Message)
                return $null
            }
            Mock Write-Error {
                param($Message)
                return $null
            }
        }
        Context "When the module is not installed at all" {
            It "Should install the requested module version" {
                Confirm-ModuleVersionInstall -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                    $Name -eq 'Test' -and $Version -eq '4.2.0'
                }
            }
        }
        Context "When a different version of the module is installed" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return @(
                        [PSCustomObject]@{
                            Name = $Name
                            Version = [Version]'3.1.0'
                        }
                    )
                } -ParameterFilter { $ListAvailable }
            }
            It "Should install the requested module version" {
                Confirm-ModuleVersionInstall -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                    $Name -eq 'Test' -and $Version -eq '4.2.0'
                }
            }
        }
        Context "When several incorrect versions of the module are installed" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return @(
                        [PSCustomObject]@{
                            Name = $Name
                            Version = [Version]'3.1.0'
                        }
                        [PSCustomObject]@{
                            Name = $Name
                            Version = [Version]'3.1.1'
                        }
                        [PSCustomObject]@{
                            Name = $Name
                            Version = [Version]'3.1.2'
                        }
                    )
                }
            }
            It "Should install the requested module version" {
                Confirm-ModuleVersionInstall -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                    $Name -eq 'Test' -and $Version -eq '4.2.0'
                }
            }
        }
        Context "When the requested module version is already installed" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return @(
                        [PSCustomObject]@{
                            Name = $Name
                            Version = [Version]'4.2.0'
                        }
                    )
                } -ParameterFilter { $ListAvailable }
            }
            It "Should not attempt to install the module" {
                Confirm-ModuleVersionInstall -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Install-PSResource -Times 0
            }
        }
        Context "When called with -WhatIf" {
            It "Should not attempt to install the module" {
                Confirm-ModuleVersionInstall -ModuleName 'Test' -ModuleVersion '4.2.0' -WhatIf
                Should -Invoke Install-PSResource -Times 0
            }
        }
        Context "When Install-PSResource fails" {
            BeforeAll {
                Mock Install-PSResource {
                    throw "Simulated installation failure."
                }
            }
            It "Should throw an error" {
                { Confirm-ModuleVersionInstall -ModuleName 'Test' -ModuleVersion '4.2.0' } |
                    Should -Throw "Simulated installation failure."
            }
        }
    }
}
