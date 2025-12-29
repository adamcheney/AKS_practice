#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity private helper function ConvertTo-Base64Certificate.
.DESCRIPTION
    Mocks to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/Tests/Unit/ConvertTo-Base64Certificate.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file AzureIdentity.psm1 from the module root folder.
#>

$ModuleName = 'AzureIdentity'
$ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /AzureIdentity
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName {
    Describe "ConvertTo-Base64Certificate" -Tag 'Unit' {
        BeforeAll {
            Mock Get-Content {
                param($Path, $Raw)
                return [byte[]](65, 66, 67)  # 'ABC' in bytes
            }
        }
        It "Should return base64-encoded string of certificate file" {
            $result = ConvertTo-Base64Certificate -CertPath '/foo/bar/cert.cer'
            $result | Should -Be 'NjUgNjYgNjc='
        }
        It "Should call Get-Content with correct parameters" {
            ConvertTo-Base64Certificate -CertPath '/foo/bar/cert.cer'
            Should -Invoke Get-Content -Times 1 -ParameterFilter {
                $Path -eq '/foo/bar/cert.cer' -and
                $Raw  -eq $true
            }
        }
    }
}
