function New-AutomationServicePrincipal {
    <#
    .SYNOPSIS
        Create a new Azure AD Service Principal for automation.
    .DESCRIPTION
        Creates a new Azure AD Application and corresponding Service Principal
        with a self-signed certificate for authentication.
    .PARAMETER DisplayName
        Display name for the Service Principal.
    .EXAMPLE
        New-AutomationServicePrincipal -DisplayName 'my-automation-sp'
    .OUTPUTS
        Hashtable with Service Principal details and certificate paths.
    .NOTES
        - Uses New-AzADApplication and New-AzADServicePrincipal; requires appropriate Azure permissions.
        - Idempotent: checks for existence before creating.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$DisplayName,
        [Int]$KeyLength = 2048,
        [DateTime]$CertExpiry = (Get-Date).AddYears(1),
        [String]$TempFilePath = ([IO.Path]::GetTempPath())
    )

    process {
        $certFiles = $null
        $adApplication = $null
        $spParams = @{
            DisplayName = $DisplayName
        }
        $certParams = @{
            CommonName     = $DisplayName
            KeyLength      = $KeyLength
            Expiry         = $CertExpiry
            TempIdFilePath = $TempFilePath
        }
        $certFiles = New-ServicePrincipalIdCredentials @certParams
        $adApplication = Get-AzADApplication -DisplayName $DisplayName -ErrorAction SilentlyContinue
        if ($null -ne $adApplication) {
            Write-Verbose "Service Principal with DisplayName '$DisplayName' already exists. Skipping creation."
        }
        else {
            if ($PSCmdlet.ShouldProcess("AD Application '$DisplayName'", "Create")) {
                # Create the Azure AD Application
                $adApplication = New-AzADApplication -DisplayName $DisplayName
            }
        }

        $sp = Get-AzADServicePrincipal -AppId $adApplication.AppId -ErrorAction SilentlyContinue
        if (-not $sp) {
            $sp = New-AzADServicePrincipal -AppId $adApplication.AppId
        }

        # Add the certificate credential to the AD Application
        $credsParams = @{
            ObjectId  = $adApplication.AppId
            CertValue = ConvertTo-Base64Certificate -CertPath $certFiles.DerPath
        }
        New-AzADAppCredential @credsParams
        return [PSCustomObject]@{
            AppId          = [String]$adApplication.AppId
            PFXFilePath    = $certFiles.PfxPath
        }
    }
}
