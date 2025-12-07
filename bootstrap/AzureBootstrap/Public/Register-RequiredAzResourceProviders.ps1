function Register-RequiredAzResourceProviders {
    <#
    .SYNOPSIS
        Register required Azure resource providers.
    .DESCRIPTION
        Reads a dependencies PSD1 to obtain RequiredProviders and registers each provider
        if it is not already registered. Throws if the dependency file is missing or malformed.
    .PARAMETER DependencyFile
        Path to the PSD1 file containing a RequiredProviders array. Defaults to 'dependencies.psd1' next to this module.
    .EXAMPLE
        Register-RequiredAzResourceProviders -DependencyFile "$PSScriptRoot\dependencies.psd1"
    .NOTES
        - Designed to be idempotent; skips providers already registered.
        - Uses Register-AzResourceProvider; requires appropriate Azure permissions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$false)]
        [String]$DependencyFile = (Join-Path -Path $PSScriptRoot -ChildPath 'dependencies.psd1')
    )

    process {
        if (-not (Test-Path -Path $DependencyFile)) {
            throw "Dependency file '$DependencyFile' not found."
        }
        Write-Verbose "Loading required Azure Resource Providers from '$DependencyFile'..."
        $requiredProviders = @()
        try {
            $Providers = (Import-PowerShellDataFile -Path $DependencyFile).RequiredProviders
        }
        catch {
            Throw "Failed to import dependency file '$DependencyFile'. Error: $($_.Exception.Message)"
        }
        if (-not $Providers){
            # The list of required providers should not be empty - throw an error
            throw "No RequiredProviders found in '$DependencyFile'. Nothing to register."
        }
        foreach ($providerName in $Providers) {
            $notRegistered = (Get-AzResourceProvider -ListAvailable |
              . Where-Object ProviderNamespace -eq $providerName ).RegistrationState -eq "NotRegistered"
            if ($notRegistered) {
                Write-Verbose "Registering Resource Provider: '$providerName'..."
                Register-AzResourceProvider -ProviderNamespace $providerName -ErrorAction Stop
            }
            else {
                Write-Verbose "Resource Provider '$providerName' is already registered."
            }
        }
        Write-Verbose "All required Azure Resource Providers have been registered."
    }
}
