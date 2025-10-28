#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for AzureIdentity module helpers.
.DESCRIPTION
    Unit tests for 
    . External Az and filesystem operations
    are mocked to ensure deterministic, side-effect free tests.
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/AzureIdentity/AzureIdentity.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file identity.psm1 from the same folder.
    - Tests clear relevant AZURE_* environment variables to avoid leakage between runs.
#>
$modulePath = Join-Path $PSScriptRoot 'AzureIdentity.psm1'
Import-Module $modulePath -Force

InModuleScope AzureIdentity {
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
            It "Should throw an error" {
                { Set-AzIdentityKeyVault @params } | Should -Throw "Resource Group 'non-existent-rg' does not exist."
            }
        }
        Context "When Key Vault does not exist" {
            BeforeAll {
                Mock Get-AzKeyVault { $null }
                $params = $baseParams.Clone()
            }
            It "Should create a new Key Vault" {
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
            It "Should respect ShouldProcess" {
                { Set-AzIdentityKeyVault @params -WhatIf }
                Should -Invoke New-AzKeyVault -Times 0
            }
            It "Should return $null when skipped by ShouldProcess" {
                $result = Set-AzIdentityKeyVault @params -WhatIf
                $result | Should -Be $null
            }
        }
    }
    Describe "New-ServicePrincipalIdCredentials" {
        BeforeAll {
            $credsParams = @{
                CommonName     = 'MySP'
                KeyLength      = 2048
                Expiry         = (Get-Date).AddYears(1)
                TempIdFilePath = '/foo/bar'
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
                }
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
            It "Should throw an error about version" {
                { New-ServicePrincipalIdCredentials @credsParams } | 
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
                Mock Export-IdentityCertificateFiles {
                    @{
                        DerPath = '/foo/bar/temp-cert.cer'
                        PfxPath = '/foo/bar/temp-cert.pfx'
                    }
                }
            }
            It "Should run the New-PrivateKey helper with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke New-PrivateKey -Times 1 -ParameterFilter {
                    $OpenSSLPath -eq '/opt/homebrew/bin/openssl' -and
                    $OutputPath -like '*temp-private.pem'
                }
            }
        }
        Context "When generating a self-signed certificate" {
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
                Mock Export-IdentityCertificateFiles {
                    @{
                        DerPath = '/foo/bar/temp-cert.cer'
                        PfxPath = '/foo/bar/temp-cert.pfx'
                    }
                }
            }
            It "Should run the New-SelfSignedIdentityCertificate helper with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke New-SelfSignedIdentityCertificate -Times 1 -ParameterFilter {
                    $OpenSSLPath     -eq '/opt/homebrew/bin/openssl' -and
                    $PrivateKeyPath  -eq '/foo/bar/temp-private.pem' -and
                    $OutputPath      -eq '/foo/bar/temp-cert.crt' -and
                    $CommonName      -eq 'MySP'
                }
            }
        }
        Context "When exporting certificate files" {
            BeforeEach {
                Mock Get-OpenSSLInfo { 
                    @{ 
                        Found=$true
                        Path='openssl'
                        Version='OpenSSL 3.3.1'
                    }
                }
                Mock New-PrivateKey { '/foo/bar/temp-private.pem' }
                Mock New-SelfSignedIdentityCertificate { '/foo/bar/temp-cert.crt' }
                Mock Export-IdentityCertificateFiles {
                    @{
                        DerPath = '/foo/bar/temp-cert.cer'
                        PfxPath = '/foo/bar/temp-cert.pfx'
                    }
                }
            }
            It "Should call Export-IdentityCertificateFiles with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke Export-IdentityCertificateFiles -Times 1 -ParameterFilter {
                    $CertPath -eq '/foo/bar/temp-cert.crt' -and
                    $KeyPath -eq '/foo/bar/temp-private.pem'
                }
            }
            It "Should return expected certificate file paths" {
                $result = New-ServicePrincipalIdCredentials @credsParams
                $result.DerPath | Should -Be '/foo/bar/temp-cert.cer'
                $result.PfxPath | Should -Be '/foo/bar/temp-cert.pfx'
            }
        }
    }
    Describe "Get-OpenSSLInfo" {
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
            It "Should return resolved output path on success" {
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
            It "Should throw an error" {
                { New-SelfSignedIdentityCertificate @params } |
                    Should -Throw
            }
        }
    }
    Describe "Export-IdentityCertificateFiles" {
        BeforeAll {
            $exportParams = @{
                OpenSSLPath = 'openssl'
                CertPath    = '/foo/bar/cert.crt'
                KeyPath     = '/foo/bar/key.pem'
            }
        }
        Context "When OpenSSL exports successfully" {
            BeforeAll {
                Mock Invoke-Expression { "OK" }
                Mock Test-Path { $true }
                Mock Resolve-Path {
                    param($Path)
                    [pscustomobject]@{
                        Path = $Path
                    }
                }
                $global:LASTEXITCODE = 0
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
        Context "When OpenSSL fails" {
            BeforeEach {
                Mock Invoke-Expression { "error" }
                $global:LASTEXITCODE = 1
            }
            It "Should throw with the OpenSSL output" {
                { Export-IdentityCertificateFiles @exportParams } |
                Should -Throw "Failed to export certificate files: error"
            }
        }
    }
    Describe "New-AutomationServicePrincipal" {
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
            Mock New-AzADAppCredential { $null }
            Mock New-AzADServicePrincipal { $null }
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
                    [pscustomobject]@{
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
                    [pscustomobject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = $DisplayName
                        Id          = 'new-app-object-id'
                    }
                }
            }
            It "Should create a new set of credentials" {
                New-AutomationServicePrincipal @identityParams
                Should -Invoke New-ServicePrincipalIdCredentials -Times 1 -ParameterFilter {
                    $CommonName -eq 'test-app' }
                
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
                    [pscustomobject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = 'test-app'
                        Id          = 'app-object-id'
                    }
                }
                Mock Get-AzADServicePrincipal { $null }
                Mock New-AzADServicePrincipal {
                    param($AppId)
                    [pscustomobject]@{
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
                    [pscustomobject]@{
                        AppId       = '00000000-0000-0000-0000-000000000001'
                        DisplayName = 'test-app'
                        Id          = 'app-object-id'
                    }
                }
                Mock Get-AzADServicePrincipal {
                    [pscustomobject]@{
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
    }
    # TODO: Implement tests for Get-AutomationServicePrincipalCredentialStatus
    # Describe "Get-AutomationServicePrincipalCredentialStatus" {
    #     BeforeAll {
    #         $params = @{
    #             DisplayName = 'test-app'
    #         }
    #     }
    #     Context "When the AD Application does not exist" {
    #         BeforeAll {
    #             Mock Get-AzADApplication { $null }
    #         }
    #         It "Should return throw an error" {
    #             { Get-AutomationServicePrincipalCredentialStatus @params } |
    #             Should -Throw "Service Principal with DisplayName 'test-app' does not exist."
    #         }
    #     }
    #     Context "When the AD Application exists and there is a valid credential" {
    #         BeforeAll {
    #             Mock Get-AzADApplication {
    #                 param($DisplayName)
    #                 [pscustomobject]@{
    #                     AppId       = '00000000-0000-0000-0000-000000000001'
    #                     DisplayName = $DisplayName
    #                     Id          = 'app-object-id'
    #                     KeyCredentials = @(
    #                         [pscustomobject]@{
    #                             StartDateTime = (Get-Date).AddDays(-1)
    #                             EndDateTime   = (Get-Date).AddDays(300)
    #                             CustomKeyIdentifier = 'base64-thumb'
    #                             Type = 'AsymmetricX509Cert'
    #                         }
    #                     )
    #                 }
    #             }
    #         }
    #         It "Should return object with IsValidCredential = $true" {
    #             $result = Get-AutomationServicePrincipalCredentialStatus @params
    #             $result | Should -BeTrue
    #         }
    #         It "Should return object with remaining days > 0" {
    #             $result = Get-AutomationServicePrincipalCredentialStatus @params
    #             $result.RemainingDays | Should -BeGreaterThan 0
    #         }
    #     }
    #     Context "When the AD Application exists but no valid credentials" {}
    # }
}
