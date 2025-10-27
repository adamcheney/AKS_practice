#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for az-identity module helpers.
.DESCRIPTION
    Unit tests for 
    . External Az and filesystem operations
    are mocked to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/az-identity/az-identity.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file identity.psm1 from the same folder.
    - Tests clear relevant AZURE_* environment variables to avoid leakage between runs.
#>
$modulePath = Join-Path $PSScriptRoot 'az-identity.psm1'
Import-Module $modulePath -Force

InModuleScope az-identity {
    Describe "Set-AzIdentityKeyVault" {
        BeforeAll {
            Mock Get-AzResourceGroup {
                param($Name)
                [PSCustomObject]@{
                    ResourceGroupName = $Name
                    Location = 'eastus'
                }
            }
            Mock New-AzKeyVault { 
                param($Name, $ResourceGroupName, $Location, $Sku = 'Standard')
                [PSCustomObject]@{ 
                    VaultName         = $Name
                    ResourceGroupName = $ResourceGroupName
                    Location          = $Location
                    Sku               = $Sku
                }
            }
            $baseParams = @{
                VaultName         = 'testvault'
                ResourceGroupName = 'test-rg'
                Location          = 'eastus'
            }
        }
        Context "When Resource Group does not exist" {
            BeforeAll {
                Mock Get-AzResourceGroup { $null }
                $params = $baseParams.Clone()
                $params.ResourceGroupName = 'non-existent-rg'
            }
            It "Throws an error" {
                { Set-AzIdentityKeyVault @params } | Should -Throw "Resource Group 'non-existent-rg' does not exist."
            }
        }
        Context "When Key Vault does not exist" {
            BeforeAll {
                Mock Get-AzKeyVault { $null }
                $params = $baseParams.Clone()
            }
            It "Creates a new Key Vault" {
                $result = Set-AzIdentityKeyVault @params
                Should -Invoke New-AzKeyVault -Times 1 -ParameterFilter {
                    $Name -eq 'testvault' -and
                    $ResourceGroupName -eq 'test-rg' -and
                    $Location -eq 'eastus'
                }
                $result.VaultName | Should -Be 'testvault'
            }
            It "Should return the created Key Vault" {
                $result = Set-AzIdentityKeyVault @params
                $result | Should -Not -Be $null
                $result.VaultName | Should -Be 'testvault'
            }
            It "Should Respect ShouldProcess" {
                { Set-AzIdentityKeyVault @params -WhatIf }
                Should -Invoke New-AzKeyVault -Times 0
            }
            It "Should Returns $null when skipped by ShouldProcess" {
                $result = Set-AzIdentityKeyVault @params -WhatIf
                $result | Should -Be $null
            }
        }
    }
    Describe "New-ServicePrincipalIdCertificate" {
        BeforeAll {}
        Context "When OpenSSL is not installed at all"  {
            BeforeAll {
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found = $false
                        Path  = $null
                        Version = $null
                    }
                }
            }
            It "Throws an error" {
                { New-ServicePrincipalIdCertificate -CommonName 'MySP' } | 
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
                } -ParameterFilter { $Path -eq '/usr/bin/openssl' }
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found   = $false
                        Path    = $null
                        Version = $null
                    }
                } -ParameterFilter { $Path -in `
                                    '/opt/homebrew/bin/openssl', `
                                    'openssl' }
            }
            It "Throws an error about LibreSSL" {
                { New-ServicePrincipalIdCertificate -CommonName 'MySP' } | 
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
                } -ParameterFilter { $Path -eq '/usr/bin/openssl' }
                Mock Get-OpenSSLInfo {
                    param($Path)
                    @{
                        Found   = $false
                        Path    = $null
                        Version = $null
                    }
                } -ParameterFilter { $Path -in `
                                    '/opt/homebrew/bin/openssl', `
                                    'openssl' }
            }
            It "Throws an error about version" {
                { New-ServicePrincipalIdCertificate -CommonName 'MySP' } | 
                    Should -Throw "OpenSSL >= 3.0.0 required. Found OpenSSL 2.8.3."
            }
        }
        Context "When generating a private key" {
            BeforeAll {
                Mock New-PrivateKey {
                    param($OpenSSLPath, $OutputPath)
                    return '/foo/bar/temp-private.pem'
                }
                Mock Get-OpenSSLInfo { 
                    @{
                        Found   = $true
                        Path    = '/opt/homebrew/bin/openssl'
                        Version = 'OpenSSL 3.3.1' 
                    }
                }
                Mock New-SelfSignedIdentityCertificate {
                    param($OpenSSLPath, $PrivateKeyPath, $OutputPath, $CommonName)
                    return '/foo/bar/temp-cert.crt'
                }

            }
            It "Runs the New-PrivateKey helper with correct parameters" {
                New-ServicePrincipalIdCertificate -CommonName 'MySP'
                Should -Invoke New-PrivateKey -Times 1 -ParameterFilter {
                    $OpenSSLPath -eq '/opt/homebrew/bin/openssl' -and
                    $OutputPath -like '*temp-private.pem'
                }
            }
        }
        Context "When generating a self-signed certificate" {
            BeforeAll {
                Mock New-SelfSignedIdentityCertificate {
                    param($OpenSSLPath, $PrivateKeyPath, $OutputPath, $CommonName, $ValidityDays)
                    return 'temp-cert.crt'
                }
            }
            It "Calls OpenSSL with correct parameters" {
            }
            It "Throws a meaningful error if OpenSSL fails" {
            }
            It "Returns the generated certificate path on success" {
            }
        }
    }
    Describe "Get-OpenSSLInfo" {
        BeforeAll {
            Mock Get-Command { @{ Source = 'openssl' } }
            Mock Invoke-Expression { "OpenSSL 3.3.1" }
        }
        Context "When OpenSSL is found" {
            It "Returns found=true and version text" {
                $r = Get-OpenSSLInfo -Path 'openssl'
                $r.Found | Should -BeTrue
                $r.Version | Should -Match '3\.3\.1'
            }
        }
        Context "When OpenSSL is not found" {
            BeforeEach {
                Mock Get-Command { throw "not found" }
            }
            It "Returns found=false" {
                Mock Get-Command { throw "not found" }
                $r = Get-OpenSSLInfo -Path 'missing'
                $r.Found | Should -BeFalse
            }
        }
    }
    Describe "New-PrivateKey" {
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
                    [pscustomobject]@{ 
                        Path = (Join-Path (Get-Location) 'private.pem')
                    }
                }
                $global:LASTEXITCODE = 0
                
            }
            It "returns the resolved output path" {
                $result = New-PrivateKey @params
                $result | Should -Match 'private\.pem'
            }
            It "calls Invoke-Expression with expected arguments" {
                New-PrivateKey @params
                Assert-MockCalled Invoke-Expression -Times 1 -Exactly -Scope It
            }
        }
        Context "When OpenSSL fails" {
            BeforeEach {
                Mock Invoke-Expression { "error" }
                $global:LASTEXITCODE = 1
            }
            It "throws an error including OpenSSL output" {
                { New-PrivateKey @params } |
                Should -Throw "Failed to generate private key: error"
            }
        }
    }
    Describe "New-SelfSignedIdentityCertificate" {
        BeforeAll {}
        BeforeEach { $global:LASTEXITCODE = 0 }
        Context "When OpenSSL is installed and works" {
            BeforeAll {
                Mock Invoke-Expression { "OK" }
                Mock Test-Path { $true }
                Mock Resolve-Path {
                    [pscustomobject]@{
                        Path = (Join-Path (Get-Location) 'cert.pem')
                    }
                }
            }
            It "Returns resolved output path on success" {
                $result = New-SelfSignedIdentityCertificate -OpenSSLPath 'openssl' -PrivateKeyPath './key.pem' -OutputPath './cert.pem' -CommonName 'test'
                $result | Should -Match 'cert\.pem'
            }
        }
        Context "When OpenSSL fails" {
            BeforeAll {
                Mock Invoke-Expression { "error" }
                $global:LASTEXITCODE = 1
                $params = @{
                    OpenSSLPath     = 'openssl'
                    PrivateKeyPath  = './key.pem'
                    OutputPath      = './cert.pem'
                    CommonName      = 'test'
                }
            }
            It "Throws an error" {
                { New-SelfSignedIdentityCertificate @params } |
                    Should -Throw
            }
        }
    }
}
