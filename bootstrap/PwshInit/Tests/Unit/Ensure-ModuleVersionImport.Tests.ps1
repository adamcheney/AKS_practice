#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for PwshInit public function Ensure-ModuleVersionImport.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/PwshInit/Tests/Unit/Ensure-ModuleVersionImport.Tests.ps1
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
    Describe "Ensure-ModuleVersionImport" -Tag 'Unit' {
        BeforeAll {
            Mock Get-Module {
                param($Name, $ListAvailable)
                return @(
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'4.2.0'
                    }
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'4.2.1'
                    }
                )
            } -ParameterFilter { $ListAvailable }
            Mock Get-Module {
                param()
                return $null
            } -ParameterFilter { -not $ListAvailable }
            Mock Import-Module {
                param($args)
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
            Mock Remove-Module {
                param($Name) 
                return $null
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
        Context "When installed incorrect version" {
            It "Should throw an error" {
                { Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '5.0.0' } |
                    Should -Throw "Module 'Test' version '5.0.0' not installed."
            }
        }
        Context "When module installed none imported" {
            It "Should import module and not unload" {
                Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Remove-Module -Times 0
                Should -Invoke Import-Module -Times 1
            }
            It "Should return module object" {
                $result = Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                $result.Name | Should -Be 'Test'
                $result.Version | Should -Be '4.2.0'
            }
        }
        Context "When module is not installed" {
            It "Should throw an error" {
                { Ensure-ModuleVersionImport -ModuleName 'Null' -ModuleVersion '1.0' } |
                    Should -Throw "Module 'Null' version '1.0' not installed."
            }
        }
        Context "When module is installed correct version loaded" {
            BeforeAll {
                Mock Get-Module {
                    param($Name, $ListAvailable)
                    return [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'4.2.0'
                    } 
                } -ParameterFilter { -not $ListAvailable }
            }
            It "Should not unload but still import module" {
                Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Remove-Module -Times 0
                Should -Invoke Import-Module -Times 1
            }
            It "Should return module object" {
                $result = Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                $result.Name | Should -Be 'Test'
                $result.Version | Should -Be '4.2.0'
            }
        }
        Context "When module is installed incorrect version loaded" {
            BeforeAll {
                Mock Get-Module {
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'3.1.0'
                    }
                } -ParameterFilter { -not $ListAvailable }
            }
            It "Should unload and import correct module version" {
                Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Remove-Module -Times 1
                Should -Invoke Import-Module -Times 1
            }
            It "Should return module object" {
                $result = Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                $result.Name | Should -Be 'Test'
                $result.Version | Should -Be '4.2.0'
            }
        }
        Context "When Remove-Module fails" {
            BeforeAll {
                Mock Get-Module {
                    [PSCustomObject]@{
                        Name = 'Test';
                        Version = [Version]'3.1.0'
                    }
                } -ParameterFilter { -not $ListAvailable }
                Mock Remove-Module {
                    param($Name)
                    throw "Removal failed"
                }
            }
            It "Should write an error if Remove-Module fails" {
                Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0'
                Should -Invoke Write-Error -Times 1 -ParameterFilter { 
                    $Message -match 'Failed to remove module' 
                }
            }
        }
        Context "When Import-Module fails" {
            BeforeAll {
                Mock Import-Module {
                    param($Name, $Version)
                    throw "Import failed"
                }
            }
            It "Should write an error if Import-Module fails" {
                { Ensure-ModuleVersionImport -ModuleName 'Test' -ModuleVersion '4.2.0' } | Should -Throw "Import failed"
                Should -Invoke Write-Error -Times 1 -ParameterFilter {
                    $Message -match 'Failed to import module'
                }
            }
        }

    }
}
