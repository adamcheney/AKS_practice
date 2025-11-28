#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity private helper functions dealing with OpenSSL.
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
$modulePath = Join-Path -Path $ModuleDir -ChildPath "$ModuleName.psm1"
# Import the module
Import-Module $modulePath -Force

InModuleScope $ModuleName {
    Describe "Get-OpenSSLInfo" -Tag 'Unit' {
        BeforeAll {
            Mock Get-Command { @{ Source = 'openssl' } }
            Mock Invoke-Expression { "OpenSSL 3.3.1" }
        }
        Context "When OpenSSL is found" {
            It "Should return found=true and version text" {
                $r = Get-OpenSSLInfo -Path 'openssl'
                $r.Found | Should -BeTrue
                $r.Version | Should -Match '3\.3\.1'
            }
        }
        Context "When OpenSSL is not found" {
            BeforeEach {
                Mock Get-Command { throw "not found" }
            }
            It "Should return found=false" {
                $r = Get-OpenSSLInfo -Path 'missing'
                $r.Found | Should -BeFalse
            }
        }
    }

    Describe "New-PrivateKey" -Tag 'Unit' {
        BeforeAll {
            $params = @{
                OpenSSLPath = 'openssl'
                OutputPath  = './private.pem'
                KeySize     = 4096
            }
        }
        Context "When OpenSSL runs successfully" {
            BeforeEach {
                Mock Invoke-Expression { "OK" }
                Mock Resolve-Path {
                    [PSCustomObject]@{ 
                        Path = (Join-Path (Get-Location) 'private.pem')
                    }
                }
                $global:LASTEXITCODE = 0
            }
            It "Should return the resolved output path" {
                $result = New-PrivateKey @params
                $result | Should -Match 'private\.pem'
            }
            It "Should call Invoke-Expression with expected arguments" {
                New-PrivateKey @params
                Should -Invoke Invoke-Expression -Times 1 -Exactly -Scope It
            }
        }
        Context "When OpenSSL fails" {
            BeforeEach {
                Mock Invoke-Expression { "error" }
                $global:LASTEXITCODE = 1
            }
            It "Should throw an error including OpenSSL output" {
                { New-PrivateKey @params } |
                Should -Throw "Failed to generate private key: error"
            }
        }
    }

    Describe "New-SelfSignedIdentityCertificate" -Tag 'Unit' {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Resolve-Path {
                [PSCustomObject]@{
                    Path = (Join-Path (Get-Location) 'cert.pem')
                }
            }
            $params = @{
                OpenSSLPath    = 'openssl'
                PrivateKeyPath = './key.pem'
                OutputPath     = './cert.pem'
                ValidityDays   = 364
                CommonName     = 'test'
            }
        }
        BeforeEach { $global:LASTEXITCODE = 0 }
        Context "When OpenSSL is installed and works" {
            BeforeAll {
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 0
                    return "OK"
                }
            }
            It "Should return resolved output path on success" {
                $result = New-SelfSignedIdentityCertificate -OpenSSLPath 'openssl' -PrivateKeyPath './key.pem' -OutputPath './cert.pem' -CommonName 'test'
                $result | Should -Match 'cert\.pem'
            }
        }
        Context "When OpenSSL fails" {
            BeforeAll {
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 1
                    return "error"
                }
            }
            It "Should throw an error" {
                { New-SelfSignedIdentityCertificate @params } |
                    Should -Throw "Failed to generate certificate: error"
            }
        }
        Context "When private key file does not exist" {
            BeforeAll {
                Mock Test-Path { $false }
            }
            It "Should throw an error about missing key file" {
                { New-SelfSignedIdentityCertificate @params } |
                    Should -Throw "Private key file './key.pem' does not exist."
            }
        }
    }

    Describe "Export-IdentityCertificateFiles" -Tag 'Unit' {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Resolve-Path {
                param($Path)
                [PSCustomObject]@{
                    Path = $Path
                }
            }
            $exportParams = @{
                OpenSSLPath = 'openssl'
                CertPath    = '/foo/bar/cert.crt'
                KeyPath     = '/foo/bar/key.pem'
            }
        }
        Context "When OpenSSL exports successfully" {
            BeforeAll {
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 0
                    return "OK"
                }
            }
            It "Should return expected file paths" {
                $result = Export-IdentityCertificateFiles @exportParams
                $result.DerPath | Should -Be '/foo/bar/certificate.der'
                $result.PfxPath | Should -Be '/foo/bar/certificate.pfx'
            }
            It "Should call OpenSSL twice (once for each export)" {
                Export-IdentityCertificateFiles @exportParams
                Should -Invoke Invoke-Expression -Times 2
            }
        }
        Context "When OpenSSL fails to generate .der file" {
            BeforeEach {
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 1
                    return ".der export error" 
                } -ParameterFilter { $Command -like '*x509*' }
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 0
                    return "OK"
                } -ParameterFilter { $Command -like '*pkcs12*' }
            }
            It "Should throw with the OpenSSL output" {
                { Export-IdentityCertificateFiles @exportParams } |
                Should -Throw "Failed to export .der file: .der export error"
            }
        }
        Context "When OpenSSL fails to generate .pfx file" {
            BeforeEach {
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 0
                    return "OK"
                } -ParameterFilter { $Command -like '*x509*' }
                Mock Invoke-Expression {
                    $script:LASTEXITCODE = 1
                    return ".pfx export error"
                } -ParameterFilter { $Command -like '*pkcs12*' }
            }
            It "Should throw with the OpenSSL output" {
                { Export-IdentityCertificateFiles @exportParams } |
                Should -Throw "Failed to export .pfx file: .pfx export error"
            }
        }
    }
}
