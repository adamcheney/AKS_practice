function ConvertTo-Base64Certificate {
    <#
    .SYNOPSIS
        Helper - convert certificate to base64 string.
    .DESCRIPTION
        Reads a certificate file and converts its contents to a base64-encoded string.
    .PARAMETER CertPath
        Path to the certificate file.
    .EXAMPLE
        ConvertTo-Base64Certificate -CertPath 'certificate.der'
    .OUTPUTS
        Base64-encoded string of the certificate.
    .NOTES
        - .
    #>
    param (
        [String]$CertPath
    )

    $certContent = Get-Content -Path $CertPath -Raw
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($certContent))
}

function ConvertTo-Base64Binary {
    <#
    .SYNOPSIS
        Convert a binary keypair file (PFX/DER) to Base64.
    .DESCRIPTION
        Reads a binary keypair file and converts its contents to a base64-encoded string.
    .PARAMETER PfxPath
        Path to the binary pfx file.
    .EXAMPLE    
        ConvertTo-Base64Binary -Path 'keypair.pfx'
    .OUTPUTS
        Base64-encoded string of the binary file.
    .NOTES
        - . 
        #>
    param(
        [Parameter(Mandatory)]
        [String]$PfxPath
    )

    $bytes = [IO.File]::ReadAllBytes($PfxPath)
    return [Convert]::ToBase64String($bytes)
}
