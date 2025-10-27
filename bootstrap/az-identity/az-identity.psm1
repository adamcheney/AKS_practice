<#
.SYNOPSIS
    Azure Identity helper functions (module).
.DESCRIPTION
    Idempotent helpers to manage Azure Active Directory identities and access tokens.
    Intended to be used as a module (Import-Module) by bootstrap scripts and tooling.
    These functions:
    - create keyvault
    - create self-signed X.509 cert in .pfx and .der format
    - create service principal
    - add certificate to ad app registration corresponding to service principal
    - grant key vault certificates officer role to service principal
    - import the pfx to the keyvault
    - create container for terraform backend
    - grant service principal access to container
.EXAMPLE
    # Import the module for production or automated usage
    Import-Module "$PSScriptRoot/az-identity.psm1" -Force
    $token = Get-AzAccessToken -Resource 'https://management.azure.com/'
    
.NOTES
    - Designed for PowerShell Core (cross-platform).
    - Functions use ShouldProcess for operations that change state.
#>
function Set-AzIdentityKeyVault {
    <#
    .SYNOPSIS
        Ensure an Azure Key Vault exists.
    .DESCRIPTION
        Searches the specified resource group for a Key Vault with the given name.
        If not found, creates a new Key Vault in the specified location with the given SKU.
    .PARAMETER ResourceGroupName
        Name of the Azure Resource Group to search/create the Key Vault in.
    .PARAMETER VaultName
        Name of the Key Vault to find or create.
    .PARAMETER Location
        Azure region/location for the Key Vault (used if creating a new one).
    .PARAMETER Sku
        SKU for the Key Vault (used if creating a new one). Defaults to 'Standard'.
    .EXAMPLE
        Set-AzIdentityKeyVault -ResourceGroupName 'my-rg' -VaultName 'my-vault' -Location 'eastus'
    .OUTPUTS
        Microsoft.Azure.Commands.KeyVault.Models.PSKeyVault
    .NOTES
        - Uses ShouldProcess for idempotent behavior.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [String]$VaultName,
        
        [Parameter(Mandatory=$true)]
        [String]$Location,
        
        [String]$Sku = 'Standard'
    )

    begin {
        # Begin by confirming the Resource Group exists and throwing if not
        if ( $null -eq (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) ) {
            throw "Resource Group '$ResourceGroupName' does not exist."
        }
    }
    
    process {
        # Check if the Key Vault already exists
        $keyVaultParams = @{
            Name              = $VaultName
            ResourceGroupName = $ResourceGroupName
        }
        $KeyVault = Get-AzKeyVault @keyVaultParams -ErrorAction SilentlyContinue

        if ($null -eq $KeyVault) {
            if ($PSCmdlet.ShouldProcess("Key Vault '$VaultName' in Resource Group '$ResourceGroupName'", "Create")) {
                # Create the Key Vault since it does not exist
                $keyVaultParams += @{
                    Location = $Location
                    Sku      = $Sku
                }
                $KeyVault = New-AzKeyVault @keyVaultParams
            }
            else
            {
                Write-Verbose "Key Vault '$VaultName' creation skipped by ShouldProcess."
            }
        }
    }

    end {
        $KeyVault
    }
}

function Get-OpenSSLInfo {
    <#
    .SYNOPSIS
        Helper - get OpenSSL installation info.
    .DESCRIPTION
        Checks if OpenSSL is installed at the specified path and retrieves its version.
    .PARAMETER Path
        Path to the OpenSSL executable.
    .EXAMPLE
        Get-OpenSSLInfo -Path 'openssl'
    .OUTPUTS
        Hashtable with keys: Found (bool), Path (string), Version (string)
    .NOTES
        - .
    #>
    param($Path)
    try {
        $cmd = Get-Command $Path -ErrorAction Stop
        $ver = Invoke-Expression "$($cmd.Source) version 2>$null"

        return @{
            Found = $true
            Path = $cmd.Source
            Version = $ver
        }
    }
    catch {
        return @{ Found = $false }
    }
}

function New-ServicePrincipalIdCertificate {
    <#
    .SYNOPSIS
        Create a new self-signed certificate for a service principal.
    .DESCRIPTION
        This function creates a new self-signed certificate for a service principal
        and stores it in the specified certificate store.
    .PARAMETER CommonName
        Common name (CN) for the certificate - the ServicePrincipal name.
    .PARAMETER KeyLength
        Key length for the certificate. Defaults to 2048.
    .PARAMETER Expiry
        Expiration date for the certificate. Defaults to 1 year from now.
    .EXAMPLE
        New-ServicePrincipalIdCertificate -CommonName 'my-sp'
    .OUTPUTS
        Certificate object
    .NOTES
        - .
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (        
        [Parameter(Mandatory)]
        [String]$CommonName,
    
        [String]$KeyLength = 2048,
        
        [String]$Expiry = (Get-Date).AddYears(1),

        [String]$TempIdFilePath = ([IO.Path]::GetTempPath())

    )

    begin {
        # Validate OpenSSL is installed and is version 3.0.0 or higher
        $SSLVendor = $null
        $SSLExecutable = $null
        $version = '0.0.0'
        $compatible = $false
        $found = $false
        $openSSLPaths = if ($IsMacOS) {
            @('/opt/homebrew/bin/openssl', '/usr/local/bin/openssl', '/usr/bin/openssl', 'openssl')
        } elseif ($IsLinux) {
            @('/usr/bin/openssl', 'openssl')
        } elseif ($IsWindows) {
            @('openssl')  # assume it's in PATH or provided
        }
        foreach ($path in $openSSLPaths) {
            $openSSLInfo = Get-OpenSSLInfo -Path $path
            if ($openSSLInfo.Found) {
                $found = $true
                # Check version
                if ($openSSLInfo.Version -match '(\w+SSL)\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)') {
                    $SSLVendor = $matches[1]
                    $version = [String]$matches[2]
                    if (($SSLVendor -eq 'OpenSSL') -and ([Version]$matches[2] -ge [Version]'3.0.0')) {
                        # We have a winner!
                        $SSLExecutable = $path
                        $compatible = $true
                        break
                    }
                }
            }
        }
        if (-not $found) {
            throw "OpenSSL not found in PATH. Install OpenSSL or add it to PATH."
        }
        if (-not $compatible) {
            throw "OpenSSL >= 3.0.0 required. Found $SSLVendor $version."
        }
    }

    process {
        $privateKeyName  = "temp-private.pem"
        $certificateName = "temp-cert.crt"
        $keyParams = @{
            OpenSSLPath = $SSLExecutable
            OutputPath  = Join-Path -Path $TempIdFilePath -ChildPath $privateKeyName
            KeySize     = $KeyLength
        }
        $privateKeyPath = New-PrivateKey @keyParams
        
        $certPath = Join-Path -Path $TempIdFilePath -ChildPath $certificateName
        $certParams = @{
            OpenSSLPath    = $SSLExecutable
            PrivateKeyPath = $privateKeyPath
            OutputPath     = $certPath
            CommonName     = $CommonName
        }
        $certPath = New-SelfSignedIdentityCertificate @certParams
    }

    end {
        $Cert
    }
}

function New-PrivateKey {
    <#
    .SYNOPSIS
        Helper - create a private key with OpenSSL.
    .DESCRIPTION
        Uses OpenSSL to generate a new private key.
    .PARAMETER OpenSSLPath
        Path to the OpenSSL executable.
    .PARAMETER OutputPath
        Path to save the generated private key.
    .PARAMETER KeySize
        Size of the key to generate (default is 2048).
    .EXAMPLE
        New-PrivateKey -OpenSSLPath 'openssl' -OutputPath 'private.pem'
    #>
    param(
        [String]$OpenSSLPath,
        [String]$OutputPath,
        [Int]$KeySize = 2048
    )

    $cmd = @(
        $OpenSSLPath, 'genrsa',
        '-out', ('"{0}"' -f $OutputPath),
        $KeySize
    ) -join ' '
    $result = Invoke-Expression "$cmd 2>&1"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate private key: $result"
    }

    return (Resolve-Path $OutputPath).Path
}

function New-SelfSignedIdentityCertificate {
    <#
    .SYNOPSIS
        Helper - create a self-signed certificate with OpenSSL.
    .DESCRIPTION
        Uses OpenSSL to generate a new self-signed certificate from an existing private key.
    .PARAMETER OpenSSLPath
        Path to the OpenSSL executable.
    .PARAMETER PrivateKeyPath
        Path to the existing private key.
    .PARAMETER OutputPath
        Path to save the generated self-signed certificate.
    .PARAMETER CommonName
        Common Name (CN) for the certificate.
    .PARAMETER ValidityDays
        Number of days the certificate is valid for (default is 365).
    .EXAMPLE
        New-SelfSignedIdentityCertificate -OpenSSLPath 'openssl' -PrivateKeyPath 'private.pem' -OutputPath 'cert.pem' -CommonName 'MyCommonName'
    #>
    param(
        [string]$OpenSSLPath,
        [string]$PrivateKeyPath,
        [string]$OutputPath,
        [string]$CommonName,
        [int]$ValidityDays = 365
    )
    # Check the private key exists
    if (-not (Test-Path -Path $PrivateKeyPath)) {
        throw "Private key file '$PrivateKeyPath' does not exist."
    }
    # OpenSSL command: 
    # openssl req -new -x509 -key private.key -out cert.pem -days 365 -subj "/CN=MyCommonName"
    $cmd = @(
        $OpenSSLPath, 'req', '-new', '-x509',
        '-key', ('"{0}"' -f $PrivateKeyPath),
        '-out', ('"{0}"' -f $OutputPath),
        '-days', $ValidityDays,
        '-subj', ('"/CN={0}"' -f $CommonName)
    ) -join ' '
    $result = Invoke-Expression "$cmd 2>&1"
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate certificate: $result"
    }
    
    return (Resolve-Path $OutputPath).Path
}
