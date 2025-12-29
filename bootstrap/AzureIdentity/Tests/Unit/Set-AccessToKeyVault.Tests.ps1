#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity public function Set-AccessToKeyVault.
.DESCRIPTION
    Stubs Get-AzKeyVault, Get-AzADUser, Get-AzADServicePrincipal &n New-AzRoleAssignment
     to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/Tests/Unit/Set-AccessToKeyVault.Tests.ps1
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
        function Get-AzKeyVault {
            param($VaultName, $ResourceGroupName)
        }
        function Get-AzADUser {
            param($UserPrincipalName)
        }
        function Get-AzADServicePrincipal {
            param($ObjectId)
        }
        function New-AzRoleAssignment {
            param($ObjectId, $RoleDefinitionName, $Scope)
        }
    }

    Describe "Set-AccessToKeyVault" -Tag 'Unit' {
        BeforeAll {
            Mock New-AzRoleAssignment {
                param($ObjectId, $RoleDefinitionName, $Scope)
                [PSCustomObject]@{
                    ObjectId           = $ObjectId
                    RoleDefinitionName = $RoleDefinitionName
                    Scope              = $Scope
                }
            }
            Mock Get-AzADUser {
                param($UserPrincipalName)
                [PSCustomObject]@{
                    Id                 = 'user-object-id'
                    UserPrincipalName  = $UserPrincipalName
                }
            }
            Mock Get-AzADServicePrincipal {
                param($ObjectId)
                [PSCustomObject]@{
                    Id          = $ObjectId
                    AppId      = '00000000-0000-0000-0000-000000000001'
                    DisplayName = 'test-sp'
                }
            }
            $roleParams = @{
                VaultName          = 'testvault'
                SignInName         = 'testdude'
                SubscriptionId     = '00000000-0000-0000-0000-000000000001'
                ResourceGroupName  = 'test-rg'
            }
        }
        Context "When setting access to Key Vault" {
            It "Should call New-AzRoleAssignment with correct parameters" {
                Set-AccessToKeyVault @roleParams
                Should -Invoke New-AzRoleAssignment -Times 1 -ParameterFilter {
                    $RoleDefinitionName -eq 'Key Vault Certificates Officer' -and
                    $Scope -eq "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-rg/providers/Microsoft.KeyVault/vaults/testvault"
                }
            }
        }
        Context "When ShouldProcess is used to skip action" {
            It "Should not call New-AzRoleAssignment" {
                { Set-AccessToKeyVault @roleParams -WhatIf }
                Should -Invoke New-AzRoleAssignment -Times 0
            }
        }
        Context "When New-AzRoleAssignment succeeds" {
            It "Should return a role assignment object" {
                $result = Set-AccessToKeyVault @roleParams
                $result | Should -BeOfType [PSCustomObject]
            }
        }
        Context "When New-AzRoleAssignment fails" {
            BeforeAll {
                Mock New-AzRoleAssignment { throw "Role assignment error" }
            }
            It "Should throw an error" {
                { Set-AccessToKeyVault @roleParams } |
                Should -Throw "Role assignment error"
            }
        }
        Context "When the KeyVault does not exist" {
            BeforeAll {
                Mock New-AzRoleAssignment {}
                Mock Get-AzKeyVault {
                    param($VaultName, $ResourceGroupName)
                    throw "Key Vault '$VaultName' not found in Resource Group '$ResourceGroupName'."
                }
            }
            It "Should call Get-AzKeyVault" {
                try {
                    Set-AccessToKeyVault @roleParams -ErrorAction SilentlyContinue
                } catch {
                    # Expected
                }
                Should -Invoke Get-AzKeyVault -Times 1 -ParameterFilter {
                    $VaultName         -eq 'testvault' -and
                    $ResourceGroupName -eq 'test-rg'
                }
            }
            It "Should throw an error indicating Key Vault not found" {
                { Set-AccessToKeyVault @roleParams } |
                Should -Throw "Key Vault 'testvault' not found in Resource Group 'test-rg'."
            }
        }
        Context "When the ServicePrincipalId parameter is not set" {
            BeforeAll {
                Mock Get-AzADServicePrincipal { $null }
                $userParams = $roleParams.Clone()
                $userParams.Remove('ServicePrincipalId')
                $userParams.SignInName = 'testdude@example.com'
            }
            It "Should check a user" {
                Set-AccessToKeyVault @userParams
                Should -Invoke Get-AzADUser -Times 1 -ParameterFilter {
                    $UserPrincipalName -eq 'testdude@example.com'
                }
            }
            It "Should not check for a Service Principal" {
                Set-AccessToKeyVault @userParams
                Should -Invoke Get-AzADServicePrincipal -Times 0
            }
            It "Should throw an error if the user is not found" {
                Mock Get-AzADUser { $null }
                { Set-AccessToKeyVault @userParams } |
                Should -Throw "Azure AD User with SignInName 'testdude@example.com' not found and ServicePrincipalID not supplied."
            }
        }
        Context "When the ServicePrincipalId parameter is set" {
            BeforeAll {
                Mock Get-AzADUser { $null }
                $identParams = $roleParams.Clone()
                $identParams.Remove('SignInName')
                $identParams.ServicePrincipalId = '00000000-0000-0000-0000-000000000001'
            }
            It "Should check for a Service Principal" {
                Set-AccessToKeyVault @identParams
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ParameterFilter {
                    $ObjectId -eq '00000000-0000-0000-0000-000000000001'
                }
            }
            It "Should not check for a User" {
                Set-AccessToKeyVault @identParams
                Should -Invoke Get-AzADUser -Times 0
            }
            It "Should throw an error if the Service Principal is not found" {
                Mock Get-AzADServicePrincipal { $null }
                { Set-AccessToKeyVault @identParams } |
                Should -Throw "Azure AD Service Principal with ObjectId '00000000-0000-0000-0000-000000000001' not found and no SignInName supplied."
            }
        }
    }
}
