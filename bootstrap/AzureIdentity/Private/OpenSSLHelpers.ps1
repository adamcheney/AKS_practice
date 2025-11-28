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
        [String]$OpenSSLPath,
        [String]$PrivateKeyPath,
        [String]$OutputPath,
        [String]$CommonName,
        [Int]$ValidityDays = 365
    )
    # Check the private key exists
    if (-not (Test-Path -Path $PrivateKeyPath)) {
        throw "Private key file '$PrivateKeyPath' does not exist."
    }
    # OpenSSL command: 
    # openssl req -new -x509 -key pkey.key -out cert.pem -days 365 -subj "/CN=MyCommonName"
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

function Export-IdentityCertificateFiles {
    <#
    .SYNOPSIS
        Helper - export key bundle and encoded cert files using OpenSSL.
    .DESCRIPTION
        Uses OpenSSL to generate .pfx and .der files from existing key and cert.
    .PARAMETER OpenSSLPath
        Path to the OpenSSL executable.
    .PARAMETER CertPath
        Path to the existing certificate.
    .PARAMETER KeyPath
        Path to the existing private key.
    .EXAMPLE
        Export-IdentityCertificateFiles -OpenSSLPath 'openssl' -CertPath 'cert.crt' -KeyPath 'private.pem'
    #>
    param(
        [String]$OpenSSLPath,
        [String]$CertPath,
        [String]$KeyPath,
        [String]$OutputDirectory = (Split-Path -Path $CertPath -Parent),
        [String]$DerFileName = 'certificate.der',
        [String]$PfxFileName = 'certificate.pfx'
    )

    $derPath = Join-Path $OutputDirectory $DerFileName
    $pfxPath = Join-Path $OutputDirectory $PfxFileName

    $cmdDer = @(
        $OpenSSLPath, 'x509',
        '-in', ('"{0}"' -f $CertPath),
        '-outform', 'der',
        '-out', ('"{0}"' -f $derPath)
    ) -join ' '
    $resultDer = Invoke-Expression "$cmdDer 2>&1"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to export .der file: $resultDer"
    }
    
    $cmdPfx = @(
        $OpenSSLPath, 'pkcs12', '-export',
        '-out', ('"{0}"' -f $pfxPath),
        '-inkey', ('"{0}"' -f $KeyPath),
        '-in', ('"{0}"' -f $CertPath),
        '-passout', 'pass:'
    ) -join ' '
    $result = Invoke-Expression "$cmdPfx 2>&1"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to export .pfx file: $result"
    }

    return @{
        DerPath = (Resolve-Path $derPath).Path
        PfxPath = (Resolve-Path $pfxPath).Path
    }
}
