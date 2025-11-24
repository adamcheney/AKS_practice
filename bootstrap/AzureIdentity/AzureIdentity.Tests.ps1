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
    BeforeAll {
        # Define all Azure cmdlets used across all tests
        function Get-AzResourceGroup {}
        function Get-AzKeyVault {
            param($VaultName, $ResourceGroupName)
        }
        function New-AzKeyVault {
            param($Name, $ResourceGroupName, $Location, $Sku = 'Standard')
        }
        function Get-AzADUser {
            param($UserPrincipalName)
        }
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
        function Set-AzKeyVaultSecret {
            param($VaultName, $Name, $SecretValue)
        }
        function New-AzRoleAssignment {
            param($ObjectId, $RoleDefinitionName, $Scope)
        }
    }

    Describe "Set-AzIdentityKeyVault" -Tag 'Unit' {
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
                $result = Set-AzIdentityKeyVault @params -Confirm:$false
                Should -Invoke New-AzKeyVault -Times 1 -ParameterFilter {
                    $Name -eq 'testvault' -and
                    $ResourceGroupName -eq 'test-rg' -and
                    $Location -eq 'eastus' -and
                    $Sku -eq 'Standard'
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

    Describe "New-ServicePrincipalIdCredentials" -Tag 'Unit' {
        BeforeAll {
            Mock Get-OpenSSLInfo {
                param($Path)
                Write-Host " Describe-level Mock Get-OpenSSLInfo called with Path='$Path'"
                if ($Path -eq 'openssl') {
                    return @{
                        Found = $true
                        Path = 'openssl'
                        Version = 'OpenSSL 3.6.0 1 Oct 2025'
                    }
                } else {
                    return @{
                        Found = $false
                        Path = $null
                        Version = $null
                    }
                }
            }
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
                    Write-Host "  Context-level Mock Get-OpenSSLInfo called with path='$Path' - Found = true"
                    @{
                        Found   = $true
                        Path    = $Path
                        Version = 'LibreSSL 3.3.6'
                    }
                } -ParameterFilter { $Path -eq 'openssl' }
                Mock Get-OpenSSLInfo {
                    param($Path)
                    Write-Host "  Context-level Mock Get-OpenSSLInfo called with path='$Path' - Found = false"
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
            It "Should run the New-PrivateKey helper with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke New-PrivateKey -Times 1 -ParameterFilter {
                    $OpenSSLPath -eq 'openssl' -and
                    $OutputPath -like '*temp-pkey.pem'
                }
            }
        }
        Context "When generating a self-signed certificate" {
            BeforeAll {
                Mock New-PrivateKey {
                    param($OpenSSLPath, $OutputPath)
                    return '/foo/bar/MySP.temp-pkey.pem'
                }
                Mock Get-OpenSSLInfo { 
                    @{
                        Found   = $true
                        Path    = '/opt/homebrew/bin/openssl'
                        Version = 'OpenSSL 3.3.1' 
                    }
                }
                Mock New-SelfSignedIdentityCertificate {
                    param($OpenSSLPath, $PrivateKeyPath, $OutputPath, $CommonName, $ValidityDays)
                    return '/foo/bar/MySP.temp-cert.crt'
                }
                Mock Export-IdentityCertificateFiles {
                    @{
                        DerPath = '/foo/bar/MySP.temp-cert.der'
                        PfxPath = '/foo/bar/MySP.temp-cert.pfx'
                    }
                }
            }
            It "Should run the New-SelfSignedIdentityCertificate helper with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke New-SelfSignedIdentityCertificate -Times 1 -ParameterFilter {   
                    $OpenSSLPath     -eq '/opt/homebrew/bin/openssl' -and
                    $PrivateKeyPath  -eq '/foo/bar/MySP.temp-pkey.pem' -and
                    $OutputPath      -eq '/foo/bar/MySP.temp-cert.crt' -and
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
                Mock New-PrivateKey { '/foo/bar/MySP.temp-private.pem' }
                Mock New-SelfSignedIdentityCertificate { '/foo/bar/MySP.temp-cert.crt' }
                Mock Export-IdentityCertificateFiles {
                    @{
                        DerPath = '/foo/bar/MySP.temp-cert.cer'
                        PfxPath = '/foo/bar/MySP.temp-cert.pfx'
                    }
                }
            }
            It "Should call Export-IdentityCertificateFiles with correct parameters" {
                New-ServicePrincipalIdCredentials @credsParams
                Should -Invoke Export-IdentityCertificateFiles -Times 1 -ParameterFilter {
                    $CertPath -eq '/foo/bar/MySP.temp-cert.crt' -and
                    $KeyPath -eq '/foo/bar/MySP.temp-private.pem'
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
                Mock Get-Command { throw "not found" }
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
        BeforeAll {}
        BeforeEach { $global:LASTEXITCODE = 0 }
        Context "When OpenSSL is installed and works" {
            BeforeAll {
                Mock Invoke-Expression { "OK" }
                Mock Test-Path { $true }
                Mock Resolve-Path {
                    [PSCustomObject]@{
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

    Describe "Export-IdentityCertificateFiles" -Tag 'Unit' {
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
                    [PSCustomObject]@{
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

        # Context "When it all works" {
        #     BeforeAll {
        #         Mock Get-AzADServicePrincipal { $null }
        #         Mock Get-AzADApplication { $null }
        #         Mock New-AzADApplication {
        #             param($DisplayName)
        #             Write-Host " Mock: Creating new AD Application '$DisplayName'"
        #             [PSCustomObject]@{
        #                 AppId       = '00000000-0000-0000-0000-000000000001'
        #                 DisplayName = $DisplayName
        #                 Id          = 'new-app-object-id'
        #             }
        #         }
        #         Mock New-AzADServicePrincipal {
        #             param($AppId)
        #             [PSCustomObject]@{
        #                 AppId       = $AppId
        #                 DisplayName = 'test-app'
        #                 Id          = 'sp-object-id'
        #             }
        #         }
        #     }
        #     It "Should return an object with AppId and PFXFilePath" {
        #         $result = New-AutomationServicePrincipal @identityParams
        #         $result.AppId | Should -Be '00000000-0000-0000-0000-000000000001'
        #         $result.PFXFilePath | Should -Be '/foo/bar/cert.pfx'
        #     }
        # }
    }

    Describe "Import-AzKeyVaultPfx" -Tag 'Unit' {
        BeforeAll {
            $keyParams = @{
                VaultName   = 'testvault'
                PfxPath = '/foo/bar/cert.pfx'
                SecretName  = 'cheneyaw-aks-iac'
            }
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

    Describe "Set-AccessToKeyVault" -Tag 'Unit' {
        BeforeAll {
            $baseParams = @{
                VaultName          = 'testvault'
                SignInName         = 'testdude'
                SubscriptionId     = '00000000-0000-0000-0000-000000000001'
                ResourceGroupName  = 'test-rg'
            }
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
        }
        Context "When setting access to Key Vault" {
            BeforeAll {
                $roleParams = $baseParams.Clone()
            }
            It "Should call New-AzRoleAssignment with correct parameters" {
                Set-AccessToKeyVault @roleParams
                Should -Invoke New-AzRoleAssignment -Times 1 -ParameterFilter {
                    $RoleDefinitionName -eq 'Key Vault Certificates Officer' -and
                    $Scope -eq "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-rg/providers/Microsoft.KeyVault/vaults/testvault"
                }
            }
        }
        Context "When ShouldProcess is used to skip action" {
            BeforeAll {
                $roleParams = $baseParams.Clone()
            }
            It "Should not call New-AzRoleAssignment" {
                { Set-AccessToKeyVault @roleParams -WhatIf }
                Should -Invoke New-AzRoleAssignment -Times 0
            }
        }
        Context "When New-AzRoleAssignment succeeds" {
            BeforeAll {
                $roleParams = $baseParams.Clone()
            }
            It "Should return a role assignment object" {
                $result = Set-AccessToKeyVault @roleParams
                $result | Should -BeOfType [PSCustomObject]
            }
        }
        Context "When New-AzRoleAssignment fails" {
            BeforeAll {
                Mock New-AzRoleAssignment { throw "Role assignment error" }
                $roleParams = $baseParams.Clone()
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
                $roleParams = $baseParams.Clone()
            }
            It "Should call Get-AzKeyVault" {
                try {
                    Set-AccessToKeyVault @roleParams -ErrorAction SilentlyContinue
                } catch {
                    # Expected
                }
                Should -Invoke Get-AzKeyVault -Times 1 -ParameterFilter {
                    Write-Host " ParameterFilter: $VaultName, $ResourceGroupName"
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
                $roleParams = $baseParams.Clone()
                $roleParams.Remove('ServicePrincipalId')
                $roleParams.SignInName = 'testdude@example.com'
            }
            It "Should check a user" {
                Set-AccessToKeyVault @roleParams
                Should -Invoke Get-AzADUser -Times 1 -ParameterFilter {
                    $UserPrincipalName -eq 'testdude@example.com'
                }
            }
            It "Should not check for a Service Principal" {
                Set-AccessToKeyVault @roleParams
                Should -Invoke Get-AzADServicePrincipal -Times 0
            }
            It "Should throw an error if the user is not found" {
                Mock Get-AzADUser { $null }
                { Set-AccessToKeyVault @roleParams } |
                Should -Throw "Azure AD User with SignInName 'testdude@example.com' not found and ServicePrincipalID not supplied."
            }
        }
        Context "When the ServicePrincipalId parameter is set" {
            BeforeAll {
                Mock Get-AzADUser { $null }
                $roleParams = $baseParams.Clone()
                $roleParams.Remove('SignInName')
                $roleParams.ServicePrincipalId = '00000000-0000-0000-0000-000000000001'
            }
            It "Should check for a Service Principal" {
                Set-AccessToKeyVault @roleParams
                Should -Invoke Get-AzADServicePrincipal -Times 1 -ParameterFilter {
                    $ObjectId -eq '00000000-0000-0000-0000-000000000001'
                }
            }
            It "Should not check for a User" {
                Set-AccessToKeyVault @roleParams
                Should -Invoke Get-AzADUser -Times 0
            }
            It "Should throw an error if the Service Principal is not found" {
                Mock Get-AzADServicePrincipal { $null }
                { Set-AccessToKeyVault @roleParams } |
                Should -Throw "Azure AD Service Principal with ObjectId '00000000-0000-0000-0000-000000000001' not found and no SignInName supplied."
            }
        }
    }

}
