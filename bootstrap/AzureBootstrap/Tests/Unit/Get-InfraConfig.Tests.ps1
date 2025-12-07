#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureBootstrap public function Get-InfraConfig.
.DESCRIPTION
    No stube required to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureBootstrap/Tests/Unit/Get-InfraConfig.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureBootstrap.psm1 from the module root folder.
#>

$ModuleName = 'AzureBootstrap'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureBootstrap
$modulePath = Join-Path -Path $ModuleDir -ChildPath "$ModuleName.psm1"
# Import the module
Import-Module $modulePath -Force

InModuleScope $ModuleName {
    Describe "Get-InfraConfig" -Tag 'Unit' {
        BeforeAll {
            # Remove any existing EVs that may interfere with the test
            $EVs = @{
                'saveRgName' = 'AZURE_RG_NAME'
                'saveLocation' = 'AZURE_LOCATION'  
                'saveStoragePrefix' = 'AZURE_STORAGE_PREFIX'
            }
            $EVs.GetEnumerator() | ForEach-Object {
                Set-Variable -Name $_.Key -Value ${$env:($_.Value)} -Scope Script
                Remove-Item "Env:$($_.Value)" -ErrorAction SilentlyContinue
            }
            Mock Test-Path {
                param($Path)
                Return $true
            } -ParameterFilter { $Path -ne 'duff.json' }
            Mock Get-Content {
                param($Raw, $Path)
                $testConfig = @{
                    ResourceGroup = @{
                        Name = "cheneyaw-aks-iac"
                        Location = "uksouth"
                    }
                    StorageAccount = @{
                        NamePrefix = "cheneyawiacb"
                    }
                }
                return ($testConfig | ConvertTo-Json -Depth 3)
            } -ParameterFilter { $Raw -and $Path -ne 'guff.json' }
        }
        AfterEach {
            $EVs.GetEnumerator() | ForEach-Object {
                Remove-Item "Env:$($_.Value)" -ErrorAction SilentlyContinue
            }
        }
        AfterAll {
            # Restore any EVs that were removed
            $EVs.GetEnumerator() | ForEach-Object {
                $value = Get-Variable -Name $_.Key -Scope Script -ErrorAction SilentlyContinue
                if ($null -ne $value) {
                    Set-Item "Env:$($_.Value)" -Value $value.Value -ErrorAction SilentlyContinue
                } else {
                    Remove-Item "Env:$($_.Value)" -ErrorAction SilentlyContinue
                }
            }
        }
        Context "When no EVs defined" {
            It "Should return default config values" {
                $result = Get-InfraConfig
                $result | Should -Not -BeNullOrEmpty
                $result.resourceGroup.name | Should -Be 'cheneyaw-aks-iac'
                $result.resourceGroup.location | Should -Be 'uksouth'
                $result.storageAccount.namePrefix | Should -Be 'cheneyawiacb'
            }
        }
        Context "When EVs are defined" {
            It "Should return config values from EVs" {
                $env:AZURE_RG_NAME = "EnvResourceGroup"
                $env:AZURE_LOCATION = "westus2"
                $env:AZURE_STORAGE_PREFIX = "envstrgacct"
                $result = Get-InfraConfig
                $result | Should -Not -BeNullOrEmpty
                $result.resourceGroup.name | Should -Be 'EnvResourceGroup'
                $result.resourceGroup.location | Should -Be 'westus2'
                $result.storageAccount.namePrefix | Should -Be 'envstrgacct'
            }
        }
        Context "When file path is invalid" {
            BeforeAll {
                Mock Test-Path {
                    param($Path)
                    Return $false
                } -ParameterFilter { $Path -eq 'duff.json' }
            }
            It "Should throw an error" {
                { Get-InfraConfig -ConfigPath 'duff.json' } |
                   Should -Throw -ExpectedMessage "Config file not found at 'duff.json'.*"
            }
        }
        Context "When file is not valid JSON" {
            BeforeAll {
                Mock Get-Content {
                    param($Raw, $Path)
                    return "{ invalid json without closing brace"
                } -ParameterFilter { $Raw -and $Path -eq 'guff.json' }
            }
            It "Should throw an error" {
                { Get-InfraConfig -ConfigPath 'guff.json' } |
                   Should -Throw -ExpectedMessage "Invalid JSON in config file 'guff.json'.*"
            }
        }
    }
}
