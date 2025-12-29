#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for BootstrapState public function Set-InfraState.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/BootstrapState/Tests/Unit/Set-InfraState.ps1.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file BootstrapState.psm1 from the module root folder.
#>

$ModuleName = 'BootstrapState'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /BootstrapState
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    Describe "Set-InfraState" {
        BeforeAll {
            $testbootstrapState = [Hashtable]@{
                deployedResources = @("resource1", "resource2")
                configVersion = "1.0.0"
            }
            $validContent = $testbootstrapState | ConvertTo-Json -Depth 5
            Mock Test-Path {
                param($Path)
                return $false
            }
            Mock New-Item {
                param($Path, $ItemType, $Force)
                return [PSCustomObject]@{
                    Name = Split-Path $Path -Leaf
                    Directory = Split-Path $Path -Parent
                    FullName = $Path
                }
            } -ParameterFilter {
                $ItemType -eq 'File'
            }
            Mock Set-Content {
                param($Path, $Value)
                Write-Host "Mock Set-Content called for $Path with value: $Value"
                return $null
            }
            Mock Get-InfraState {
                param($Path)
                Write-Host "Mock Get-InfraState called for $Path"
                return [Hashtable]@{
                    deployedResources = @("resource1", "resource2")
                    configVersion = "1.0.0"
                }
            }
            Mock Merge-Infrastate {
                param($State)
                return $State
            }
        }
        Context "When file path is not specified" {
            It "Should create new state file with default path if not extant" {
                Set-InfraState -State $testbootstrapState
                Should -Invoke New-Item -ParameterFilter {
                    $Path -eq (Get-DefaultStatePath)
                } -Times 1 -Exactly
            }
            It "Should use existing state file with default path if extant" {
                Mock Test-Path {
                    param($Path)
                    return $true
                } -ParameterFilter {
                    $Path -eq (Get-DefaultStatePath)
                }
                Set-InfraState -State $testbootstrapState
                Should -Invoke New-Item -Times 0
            }
            It "Should return the path to the default state file" {
                $result = Set-InfraState -State $testbootstrapState
                $result | Should -Be (Get-DefaultStatePath)
            }
            It "Should get current state from default path if extant" {
                Mock Test-Path {
                    param($Path)
                    Write-Host "Mock Test-Path called for $Path"
                    return $true
                } -ParameterFilter {
                    $Path -eq (Get-DefaultStatePath)
                }
                Set-InfraState -State $testbootstrapState
                Should -Invoke Get-InfraState -ParameterFilter {
                    $Path -eq (Get-DefaultStatePath)
                } -Times 1 -Exactly
            }
        }
        Context "When file path is specified" {
            It "Should create new state file at specified path if not extant" {
                Set-InfraState -State $testbootstrapState -Path './testinfrastate.json'
                Should -Invoke New-Item -ParameterFilter {
                    $Path -eq './testinfrastate.json'
                } -Times 1 -Exactly
            }
            It "Should use existing state file at specified path if extant" {
                Mock Test-Path {
                    param($Path)
                    return $true
                } -ParameterFilter {
                    $Path -eq './testinfrastate.json'
                }
                Set-InfraState -State $testbootstrapState -Path './testinfrastate.json'
                Should -Invoke New-Item -Times 0
            }
            It "Should return the path to the specified state file" {
                $result = Set-InfraState -State $testbootstrapState -Path './testinfrastate.json'
                $result | Should -Be './testinfrastate.json'
            }
            It "Should get current state from specified path if extant" {
                Mock Test-Path {
                    param($Path)
                    return $true
                } -ParameterFilter {
                    $Path -eq './testinfrastate.json'
                }
                Set-InfraState -State $testbootstrapState -Path './testinfrastate.json'
                Should -Invoke Get-InfraState -ParameterFilter {
                    $Path -eq './testinfrastate.json'
                } -Times 1 -Exactly
            }
        }
        Context "When New-Item fails to create file" {
            BeforeAll{
                Mock New-Item {
                    param($Path, $ItemType, $Force)
                    Write-Host "Running New-Item error mock"
                    throw "Simulated failure to create file."
                } -ParameterFilter {
                    $ItemType -eq 'File'
                }
            }
            It "Should throw an error" {
                { Set-InfraState -State $testbootstrapState -Path './testinfrastate.json' } | 
                    Should -Throw "Failed to create state file: ./testinfrastate.json. Simulated failure to create file."
            }
        }
        Context "When not passed any parameters" {
            It "Should return the path to default state file" {
                $result = Set-InfraState
                $result | Should -Be (Get-DefaultStatePath)
            }
            It "Should not write to file" {
                Set-InfraState
                Should -Invoke Set-Content -Times 0
            }
        }
        Context "When passed a valid state hashtable" {
            It "Should process without error" {
                { Set-InfraState -State $testbootstrapState } | 
                    Should -Not -Throw
            }
            It "Should merge with existing state" {}
            It "Should convert to JSON and send to file" {
                Set-InfraState -State $testbootstrapState -Path './testinfrastate.json'
                Should -Invoke Set-Content -ParameterFilter {
                    $Path -eq './testinfrastate.json'
                } -Times 1 -Exactly
            }
        }
    }
}