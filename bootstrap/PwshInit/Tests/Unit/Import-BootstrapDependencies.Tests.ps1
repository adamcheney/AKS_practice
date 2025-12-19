#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for PwshInit public function Import-BootstrapDependencies.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/PwshInit/Tests/Unit/Import-BootstrapDependencies.Tests.ps1
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
    Describe "Import-BootstrapDependencies" -Tag 'Unit' {
        BeforeAll {
            Mock Test-Path {
                param($Path)
                return $true
            }
            Mock Write-Verbose {
                param($Message)
                return $null
            }
            Mock Set-PSResourceGetv3 {
                param($Version)
                return $null
            }
            Mock Import-PowerShellDataFile {
                param($Path)
                return [PSCustomObject]@{
                    RequiredModules = @(
                        [PSCustomObject]@{
                            ModuleName    = 'Test1'
                            ModuleVersion = '1.0.0'
                        }
                        [PSCustomObject]@{
                            ModuleName    = 'Test2'
                            ModuleVersion = '2.1.0'
                        }
                    )
                }
            }
            Mock Ensure-ModuleVersionInstall {
                param($ModuleName, $ModuleVersion)
                return [PSCustomObject]@{
                    Name = $ModuleName
                    Version = [Version]$ModuleVersion
                }
            }
            Mock Ensure-ModuleVersionImport {
                param($ModuleName, $ModuleVersion)
                return [PSCustomObject]@{
                    Name = $ModuleName
                    Version = [Version]$ModuleVersion
                }
            }
            Mock Write-Information {
                param($Message)
                return $null
            }
        }
        Context "When it all works" {
            It "Should import dependencies without error" {
                { Import-BootstrapDependencies -DependencyFile "test.psd1" } | Should -Not -Throw
                Should -Invoke Set-PSResourceGetv3 -Times 1 -ParameterFilter {
                    $Version -eq '1.1.1'
                }
                Should -Invoke Import-PowerShellDataFile -Times 1 -ParameterFilter {
                    $Path -eq 'test.psd1'
                }
                Should -Invoke Ensure-ModuleVersionInstall -Times 1 -ParameterFilter {
                    $ModuleName -eq 'Test1' -and $ModuleVersion -eq '1.0.0'
                }
                Should -Invoke Ensure-ModuleVersionInstall -Times 1 -ParameterFilter {
                    $ModuleName -eq 'Test2' -and $ModuleVersion -eq '2.1.0'
                }
                Should -Invoke Ensure-ModuleVersionImport -Times 1 -ParameterFilter {
                    $ModuleName -eq 'Test1' -and $ModuleVersion -eq '1.0.0'
                }
                Should -Invoke Ensure-ModuleVersionImport -Times 1 -ParameterFilter {
                    $ModuleName -eq 'Test2' -and $ModuleVersion -eq '2.1.0'
                }
            }
        }
        Context "When the dependency file is missing" {
            BeforeAll {
                Mock Test-Path {
                    param($Path)
                    return $false
                }
            }
            It "Should throw an error" {
                { Import-BootstrapDependencies -DependencyFile "missing.psd1" } |
                    Should -Throw "Dependency file 'missing.psd1' not found."
            }
        }
        Context "When the dependency file is malformed" {
            BeforeAll {
                Mock Import-PowerShellDataFile {
                    param($Path)
                    throw "Simulated import failure."
                }
            }
            It "Should throw an error" {
                { Import-BootstrapDependencies -DependencyFile "malformed.psd1" } |
                    Should -Throw "Failed to import dependency file 'malformed.psd1'. Error: Simulated import failure."
            }
        }
        Context "When there are no RequiredModules" {
            BeforeAll {
                Mock Import-PowerShellDataFile {
                    param($Path)
                    return [PSCustomObject]@{}
                }
            }
            It "Should complete without error and not attempt installs/imports" {
                { Import-BootstrapDependencies -DependencyFile "empty.psd1" } | 
                    Should -Not -Throw
                Should -Invoke Write-Information -Times 1 -ParameterFilter {
                    $Message -eq "No RequiredModules found in 'empty.psd1'. Nothing to import."
                }
                Should -Invoke Ensure-ModuleVersionInstall -Times 0
                Should -Invoke Ensure-ModuleVersionImport -Times 0
            }
        }
    }
}