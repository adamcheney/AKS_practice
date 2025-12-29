#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity public function New-AutomationServicePrincipal.
.DESCRIPTION
    Stubs Get-AzADApplication, New-AzADApplication, New-AzADAppCredential,
     New-AzADAppCredential, Get-AzADServicePrincipal & New-AzADServicePrincipal
     to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/Tests/Unit/New-AutomationServicePrincipal.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureIdentity.psm1 from the module root folder.
#>

$ModuleName = 'AzureIdentity'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureIdentity
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    BeforeAll {
        # Define all Azure cmdlets used across all tests
        function Get-AzADApplication {}
        function New-AzADApplication {
            param($DisplayName)
        }
        function New-AzADAppCredential {
            param($ObjectId, $CertValue)
        }
        function Get-AzADServicePrincipal {
            param($ObjectId)
        }
        function New-AzADServicePrincipal {
            param($AppId)
        }
    }

    Describe "New-AutomationServicePrincipal" -Tag 'Unit' {
        BeforeAll {
            Mock New-ServicePrincipalIdCredentials {
                @{
                    DerPath = '/foo/bar/cert.cer'
                    PfxPath = '/foo/bar/cert.pfx'
                }
            }
            Mock ConvertTo-Base64Certificate {
                param($CertPath)
                return "BASE64CERTDATA"
            }
            Mock New-AzADAppCredential {
                param($ObjectId, $CertValue)
                [PSCustomObject]@{
                    ObjectId   = $ObjectId
                    CertValue  = $CertValue
                }
            }
            Mock Get-AzADApplication { $null }
            Mock New-AzADApplication {
                param($DisplayName)
                [PSCustomObject]@{
                    AppId       = '00000000-0000-0000-0000-000000000001'
                    DisplayName = $DisplayName
                    Id          = 'new-app-object-id'
                }
            }
            Mock Get-AzADServicePrincipal { $null }
            Mock New-AzADServicePrincipal {
                param($AppId)
                [PSCustomObject]@{
                    AppId       = $AppId
                    Id          = 'sp-object-id'
                }
            }
            Mock Set-AzIdentityKeyVault {
                param($VaultName, $ResourceGroupName, $Location)
                [PSCustomObject]@{
                    VaultName         = $VaultName
                    ResourceGroupName = $ResourceGroupName
                    Location          = $Location
                }
            }
            $identityParams = @{
                DisplayName  = 'test-app'
                KeyLength    = 2048
                CertExpiry   = (Get-Date).AddYears(1)
                TempFilePath = '/foo/bar'
            }
        }
        It "Should be a defined function" {
            $cmd = Get-Command -Name New-AutomationServicePrincipal -ErrorAction Stop
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # Ensure it exposes a parameter block (not strictly behavioural, but useful)
            $cmd.Parameters.Keys | Should -Not -BeNullOrEmpty
        }
        Context "When AD Application already exists" {
            BeforeAll {
                Mock Get-AzADApplication {
                    [PSCustomObject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = 'test-app'
                        Id          = 'app-object-id'
                    }
                }
                Mock New-AzADApplication { $null }
            }
            It "Should not attempt to create a new application" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-AzADApplication -Times 0
            }
            It "Should add the certificate credential to the application" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-AzADAppCredential -Times 1 -ParameterFilter {
                    $ObjectId  -eq '00000000-0000-0000-0000-000000000001' -and
                    $CertValue -eq 'BASE64CERTDATA'
                }
            }
        }
        Context "When AD Application does not exist" {
            BeforeAll {
                Mock Get-AzADApplication { $null }
                Mock New-AzADApplication {
                    param($DisplayName)
                    [PSCustomObject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = $DisplayName
                        Id          = 'new-app-object-id'
                    }
                }
                
                # Mock Set-AccessToKeyVault
            }
            It "Should create a new set of credentials" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-ServicePrincipalIdCredentials -Times 1 -ParameterFilter {
                    $CommonName -eq 'test-app' 
                }
            }

            It "Should create a new application" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-AzADApplication -Times 1 -ParameterFilter {
                    $DisplayName -eq 'test-app'
                }
            }

            It "Should add the certificate credential to the application" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-AzADAppCredential -Times 1 -ParameterFilter {
                    $ObjectId  -eq '00000000-0000-0000-0000-000000000001' -and
                    $CertValue -eq 'BASE64CERTDATA'
                }
            }
        }
        Context "When the corresponding Service Principal does not exist" {
            BeforeAll {
                Mock Get-AzADApplication  {
                    [PSCustomObject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = 'test-app'
                        Id          = 'app-object-id'
                    }
                }
                Mock Get-AzADServicePrincipal { $null }
                Mock New-AzADServicePrincipal {
                    param($AppId)
                    [PSCustomObject]@{
                        AppId       = $AppId
                        DisplayName = 'test-app'
                        Id          = 'sp-object-id'
                    }
                }
            }
            It "Should create the Service Principal for the application" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-AzADServicePrincipal -Times 1 -ParameterFilter {
                    $AppId -eq '00000000-0000-0000-0000-000000000001'
                }
            }
        }
        Context "When the corresponding Service Principal already exists" {
            BeforeAll {
                Mock Get-AzADApplication  {
                    [PSCustomObject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = 'test-app'
                        Id          = 'app-object-id'
                    }
                }
                Mock Get-AzADServicePrincipal {
                    [PSCustomObject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = 'test-app'
                        Id          = 'sp-object-id'
                    }
                }
            }
            It "Should not attempt to create a new Service Principal" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-AzADServicePrincipal -Times 0
            }
        }
        Context "When it all works" {
            BeforeAll {
                Mock Get-AzADServicePrincipal { $null }
                Mock Get-AzADApplication { $null }
                Mock New-AzADApplication {
                    param($DisplayName)
                    [PSCustomObject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = $DisplayName
                        Id          = 'new-app-object-id'
                    }
                }
                Mock New-AzADServicePrincipal {
                    param($AppId)
                    [PSCustomObject]@{
                        AppId       = $AppId
                        DisplayName = 'test-app'
                        Id          = 'sp-object-id'
                    }
                }
            }
            It "Should return an object with AppId and PFXFilePath" {
                $result = New-AutomationServicePrincipal @identityParams
                
                # Get the actual return value (last item in array)
                $actualResult = if ($result -is [array]) { $result[-1] } else { $result }

                $actualResult.AppId | Should -Be '00000000-0000-0000-0000-000000000001'
                $actualResult.PFXFilePath | Should -Be '/foo/bar/cert.pfx'
            }
        }
    }
}
