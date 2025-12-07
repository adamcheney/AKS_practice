function New-ServicePrincipalIdCredentials {
    <#
    .SYNOPSIS
        Create a new self-signed certificate for a service principal.
    .DESCRIPTION
        This function creates a new self-signed certificate for a service principal
        and stores it in the specified certificate store.
    .PARAMETER KeyDetails
        PSCustomObject containing:
            CommonName - Common name (CN) for the certificate - the ServicePrincipal name - required;
            KeyLength - Key length for the certificate, defaults to 2048 if not present;
            Expiry - Expiration date for the certificate, details to 1 year from now if not present.
    .PARAMETER CommonName
        Common name (CN) for the certificate - the ServicePrincipal name.
    .PARAMETER KeyLength
        Key length for the certificate. Defaults to 2048.
    .PARAMETER Expiry
        Expiration date for the certificate. Defaults to 1 year from now.
    .EXAMPLE
        New-ServicePrincipalIdCredentials -CommonName 'my-sp'
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
        [DateTime]$Expiry = (Get-Date).AddYears(1),
        [String]$TempIdFilePath = ([IO.Path]::GetTempPath())
    )

    begin {
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
        $privateKeyName  = $CommonName + ".temp-pkey.pem"
        $certificateName = $CommonName + ".temp-cert.crt"
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
            ValidityDays   = (New-TimeSpan -Start (Get-Date) -End $Expiry).Days
        }
        $certPath = New-SelfSignedIdentityCertificate @certParams

        $exportParams = @{
            OpenSSLPath = $SSLExecutable
            CertPath    = $certPath
            KeyPath     = $privateKeyPath
            CommonName  = $CommonName
        }
        $finalCertFiles = Export-IdentityCertificateFiles @exportParams
        
        return [PSCustomObject]@{
            CommonName = $CommonName
            DerPath    = $finalCertFiles.DerPath
            PfxPath    = $finalCertFiles.PfxPath
        }
    }
}
