#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for PwshInit private helper function Get-RequiredModulesFromFile.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/PwshInit/Tests/Unit/Get-RequiredModulesFromFile.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file PwshInit.psm1 from the module root folder.
#>

$ModuleName = 'PwshInit'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /PwshInit
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    Describe "Get-RequiredModulesFromFile" {
        BeforeAll {
            Mock Test-Path {
                param($Path)
                Write-Host "Mocked Test-Path called with Path: $Path"
                return $true
            }
            Mock Write-Verbose {}
            Mock Write-Information {}
            Mock Import-PowerShellDataFile {
                param($Path)
                return @{
                    RequiredModules = @(
                        @{ ModuleName = 'ModuleA'; ModuleVersion = '1.0.0' }
                        @{ ModuleName = 'ModuleB'; ModuleVersion = '2.0.0' }
                    )
                    RequiredProviders = @(
                        'Microsoft.Provider1'
                        'Microsoft.Provider2'
                    )
                }
            }
        }
        Context "When the dependency file is present" {
            It "Writes a message about the file to verbose stream" {
                Get-RequiredModulesFromFile -DependencyFile 'config.psd1'
                Should -Invoke Write-Verbose -Times 1 -ParameterFilter { 
                    $Message -eq "Importing dependencies from config.psd1" 
                }
            }
        }
        Context "When the dependency file is well-formed" {
            It "Returns the expected RequiredModules array" {
                $result = Get-RequiredModulesFromFile -DependencyFile 'config.psd1'
                $result | Should -HaveCount 2
                $result[0].ModuleName | Should -Be 'ModuleA'
                $result[0].ModuleVersion | Should -Be '1.0.0'
                $result[1].ModuleName | Should -Be 'ModuleB'
                $result[1].ModuleVersion | Should -Be '2.0.0'
            }
        }
        Context "When ShouldProcess is used to skip action" {
            It "Should not call Import-PowerShellDataFile" {
                { Get-RequiredModulesFromFile -DependencyFile 'config.psd1' -WhatIf }
                Should -Invoke Import-PowerShellDataFile -Times 0
            }
        }
        Context "When the dependency file is empty" {
            BeforeAll {
                Mock Import-PowerShellDataFile {
                    param($Path)
                    return @{}
                }
            }
            It "Writes an information message and returns nothing" {
                $result = Get-RequiredModulesFromFile -DependencyFile 'empty.psd1'
                Should -Invoke Write-Information -Times 1 -ParameterFilter {
                    $Message -eq "No RequiredModules found in 'empty.psd1'. Nothing to import."
                }
                $result | Should -Be $null
            }
        }
        Context "When the dependency file has no RequiredModules" {
            BeforeAll {
                Mock Import-PowerShellDataFile {
                    param($Path)
                    return @{ SomeOtherKey = @() }
                }
            }
            It "Writes an information message and returns nothing" {
                $result = Get-RequiredModulesFromFile -DependencyFile 'norequiredmodules.psd1'
                Should -Invoke Write-Information -Times 1 -ParameterFilter {
                    $Message -eq "No RequiredModules found in 'norequiredmodules.psd1'. Nothing to import."
                }
                $result | Should -Be $null
            }
        }
        Context "When the dependency file is missing" {
            BeforeAll {
                Mock Test-Path { $false }
            }
            It "Throws an error" {
                { Get-RequiredModulesFromFile -DependencyFile "nonexistent.psd1" } | 
                Should -Throw "Dependency file 'nonexistent.psd1' not found."
            }
        }
        Context "When the dependency file is malformed" {
            BeforeAll {
                Mock Import-PowerShellDataFile {
                    param($Path)
                    throw "Malformed file error"
                }
            }
            It "Throws an error" {
                { Get-RequiredModulesFromFile -DependencyFile "malformed.psd1" } | 
                Should -Throw "Failed to import dependency file 'malformed.psd1'. Error: Malformed file error"
            }
        }
    }
}