#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for PwshInit public function Ensure-ModuleVersionInstall.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/PwshInit/Tests/Unit/Ensure-ModuleVersionInstall.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file PwshInit.psm1 from the module root folder.
#>

$ModuleName = 'PwshInit'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /PwshInit
$modulePath = Join-Path -Path $ModuleDir -ChildPath "$ModuleName.psm1"
# Import the module
Import-Module $modulePath -Force

InModuleScope $ModuleName {
    Describe "Ensure-ModuleVersionInstall" -Tag 'Unit' {
        BeforeAll {
            Mock Get-Module {
                param($Name, $ListAvailable)
                return [PSCustomObject]@{
                    Name = $Name
                    ModuleInfos = @()
                }
            }
            Mock Install-PSResource {
                param($Name, $Version, $Scope, $Repository)
                return [PSCustomObject]@{
                    Name = $Name
                    Version = $Version
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
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return [PSCustomObject]@{}
                }
            }
            It "Should install the requested module version" {
                Ensure-ModuleVersionInstall -ModuleName 'TestModule' -ModuleVersion '1.2.3'
                Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                    $Name -eq 'TestModule' -and $Version -eq '1.2.3'
                }
            }
        }
        Context "When a different version of the module is installed" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return [PSCustomObject]@{
                        Name = $Name
                        ModuleInfos = @(
                            [PSCustomObject]@{
                                Name = $Name
                                Version = '0.9.0'
                            }
                        )
                    }
                }
            }
            It "Should install the requested module version" {
                Ensure-ModuleVersionInstall -ModuleName 'TestModule' -ModuleVersion '1.2.3'
                Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                    $Name -eq 'TestModule' -and $Version -eq '1.2.3'
                }
            }
        }
        Context "When several incorrect versions of the module are installed" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return [PSCustomObject]@{
                        Name = $Name
                        ModuleInfos = @(
                            [PSCustomObject]@{
                                Name = $Name
                                Version = '0.9.0'
                            }
                            [PSCustomObject]@{
                                Name = $Name
                                Version = '1.0.0'
                            }
                            [PSCustomObject]@{
                                Name = $Name
                                Version = '1.1.0'
                            }
                        )
                    }
                }
            }
            It "Should install the requested module version" {
                Ensure-ModuleVersionInstall -ModuleName 'TestModule' -ModuleVersion '1.2.3'
                Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                    $Name -eq 'TestModule' -and $Version -eq '1.2.3'
                }
            }
        }
    }
}
