#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity public function New-ServicePrincipalIdCredentials.
.DESCRIPTION
    No stubs required.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/Tests/Unit/New-ServicePrincipalIdCredentials.Tests.ps1
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

    Describe "New-ServicePrincipalIdCredentials" -Tag 'Unit' {
        BeforeAll {
            Mock Get-OpenSSLInfo {
                param($Path)
                # Write-Host " Describe-level Mock Get-OpenSSLInfo called with Path='$Path'"
                return @{
                    Found = $true
                    Path = $Path
                    Version = 'OpenSSL 3.6.0 1 Oct 2025'
                }
            } -ParameterFilter { $Path -eq 'openssl' }
            Mock Get-OpenSSLInfo {
                param($Path)
                # Write-Host " Describe-level Mock Get-OpenSSLInfo called with Path='$Path'"
                return @{
                    Found = $false
                    Path = $Path
                    Version = $null
                }
            } -ParameterFilter { $Path -ne 'openssl' }
            Mock New-PrivateKey {
                param($OpenSSLPath, $OutputPath)
                return '/foo/bar/MySP.temp-pkey.pem'
            }
            Mock New-SelfSignedIdentityCertificate {
                param($OpenSSLPath, $PrivateKeyPath, $OutputPath, $CommonName, $ValidityDays)
                return '/foo/bar/MySP.temp-cert.crt'
            }
            Mock Export-IdentityCertificateFiles {
                @{
                    DerPath = '/foo/bar/MySP.temp-cert.cer'
                    PfxPath = '/foo/bar/MySP.temp-cert.pfx'
                }
            }
            $credsParams = @{
                CommonName     = 'MySP'
                KeyLength      = 2048
                Expiry         = (Get-Date).AddYears(1)
                TempIdFilePath = '/foo/bar'
            }
        }
        Context "When running on macOS" {
            BeforeAll {
                $script:IsMacOS = $true
                $script:IsLinux = $false
                $script:IsWindows = $false
            }
            It "Should use macOS OpenSSL paths" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq '/opt/homebrew/bin/openssl'
                }
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq '/usr/local/bin/openssl'
                }
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq '/usr/bin/openssl'
                }
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq 'openssl'
                }
            }
        }
        Context "When running on Linux" {
            BeforeAll {
                $script:IsMacOS = $false
                $script:IsLinux = $true
                $script:IsWindows = $false
            }
            It "Should use Linux OpenSSL paths" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq '/usr/bin/openssl'
                }
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq 'openssl'
                }
            }
        }
        Context "When running on Windows" {
            BeforeAll {
                $script:IsMacOS = $false
                $script:IsLinux = $false
                $script:IsWindows = $true
            }
            It "Should use Windows OpenSSL paths" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke Get-OpenSSLInfo -Times 1 -ParameterFilter {
                    $Path -eq 'openssl'
                }
            }
        }
        Context "When OpenSSL is not installed at all"  {
            BeforeAll {
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found = $false
                        Path  = $null
                        Version = $null
                    }
                } -ParameterFilter { $true }
            }
            It "Should throw an error" {
                { New-ServicePrincipalIdCredentials @credsParams } | 
                    Should -Throw "OpenSSL not found in PATH. Install OpenSSL or add it to PATH."
            }
        }
        Context "When only LibreSSL is installed" {
            BeforeAll {
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found   = $true
                        Path    = $Path
                        Version = 'LibreSSL 3.3.6'
                    }
                } -ParameterFilter { $Path -eq 'openssl' }
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found   = $false
                        Path    = $null
                        Version = $null
                    }
                } -ParameterFilter { $Path -ne 'openssl' }
                }
            It "Should throw an error about LibreSSL" {
                { New-ServicePrincipalIdCredentials @credsParams } | 
                    Should -Throw "OpenSSL >= 3.0.0 required. Found LibreSSL 3.3.6."
            }
        }
        Context "When OpenSSL installed but too old" {
            BeforeAll {
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found = $true
                        Path = $Path
                        Version = 'OpenSSL 2.8.3'
                    }
                } -ParameterFilter { $true }
            }
            It "Should throw an error about version" {
                { New-ServicePrincipalIdCredentials @credsParams } | 
                    Should -Throw "OpenSSL >= 3.0.0 required. Found OpenSSL 2.8.3."
            }
        }
        Context "When generating a private key" {
            It "Should run the New-PrivateKey helper with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke New-PrivateKey -Times 1 -ParameterFilter {
                    $OpenSSLPath -eq 'openssl' -and
                    $OutputPath -like '*temp-pkey.pem'
                }
            }
        }
        Context "When generating a self-signed certificate" {
            It "Should run the New-SelfSignedIdentityCertificate helper with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke New-SelfSignedIdentityCertificate -Times 1 -ParameterFilter {
                    $OpenSSLPath     -eq 'openssl' -and
                    $PrivateKeyPath  -eq '/foo/bar/MySP.temp-pkey.pem' -and
                    $OutputPath      -eq '/foo/bar/MySP.temp-cert.crt' -and
                    $CommonName      -eq 'MySP' -and
                    $ValidityDays    -eq 364
                }
            }
        }
        Context "When exporting certificate files" {
            It "Should call Export-IdentityCertificateFiles with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke Export-IdentityCertificateFiles -Times 1 -ParameterFilter {
                    $CertPath -eq '/foo/bar/MySP.temp-cert.crt' -and
                    $KeyPath -eq '/foo/bar/MySP.temp-pkey.pem'
                }
            }
            It "Should return expected certificate file paths" {
                $result = New-ServicePrincipalIdCredentials @credsParams
                $result.CommonName | Should -Be 'MySP'
                $result.DerPath | Should -Be '/foo/bar/MySP.temp-cert.cer'
                $result.PfxPath | Should -Be '/foo/bar/MySP.temp-cert.pfx'
            }
        }
    }
}
