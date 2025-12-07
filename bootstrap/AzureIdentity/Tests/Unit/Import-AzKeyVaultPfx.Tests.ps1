#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity public function Import-AzKeyVaultPfx.
.DESCRIPTION
    Stubs Set-AzKeyVaultSecret to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/Tests/Unit/Import-AzKeyVaultPfx.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureIdentity.psm1 from the module root folder.
#>

$ModuleName = 'AzureIdentity'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureIdentity
$modulePath = Join-Path -Path $ModuleDir -ChildPath "$ModuleName.psm1"
# Import the module
Import-Module $modulePath -Force

InModuleScope $ModuleName {
    BeforeAll {
        # Define all Azure cmdlets used across all tests
        function Set-AzKeyVaultSecret {
            param($VaultName, $Name, $SecretValue)
        }
    }

    Describe "Import-AzKeyVaultPfx" -Tag 'Unit' {
        BeforeAll {
            Mock Set-AzKeyVaultSecret {
                param($VaultName, $Name, $SecretValue)
                return [PSCustomObject]@{
                    Name  = $Name
                    Value = $SecretValue
                    VaultName = $VaultName
                    Expires = (Get-Date).AddYears(1)
                    Id          = "https://$VaultName.vault.azure.net/secrets/$Name"
                }
            }
            Mock ConvertTo-Base64Binary {
                param($PfxPath)
                return "BASE64PFXDATA"
            }
            $keyParams = @{
                VaultName   = 'testvault'
                PfxPath = '/foo/bar/cert.pfx'
                SecretName  = 'cheneyaw-aks-iac'
            }
            $secureValue = ConvertTo-SecureString -String "BASE64PFXDATA" -AsPlainText -Force
        }
        Context "When the PFX file does not exist" {
            BeforeAll {
                Mock Test-Path { $false }
            }
            It "Should throw an error" {
                { Import-AzKeyVaultPfx @keyParams } |
                Should -Throw "PFX file '/foo/bar/cert.pfx' does not exist."
            }
        }
        Context "When the PFX file exists" {
            BeforeAll {
                Mock Test-Path { $true }
            }
            It "Should import the PFX file into the Key Vault" {
                { Import-AzKeyVaultPfx @keyParams } |
                Should -Not -Throw  
            }
            It "Should call ConvertTo-Base64Binary with correct parameters" {
                Import-AzKeyVaultPfx @keyParams
                Should -Invoke ConvertTo-Base64Binary -Times 1 -ParameterFilter {
                    $PfxPath -eq '/foo/bar/cert.pfx'
                }
            }
            It "Should call Set-AzKeyVaultSecret with correct parameters" {
                Import-AzKeyVaultPfx @keyParams
                Should -Invoke Set-AzKeyVaultSecret -Times 1 -ParameterFilter {
                    $VaultName   -eq 'testvault' -and
                    $Name        -eq 'cheneyaw-aks-iac'
                }
            }
        }
    }
}
