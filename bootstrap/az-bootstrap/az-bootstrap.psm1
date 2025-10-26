<#
.SYNOPSIS
    Common bootstrap helpers and shared configuration.
.DESCRIPTION
    Reusable functions for repository bootstrapping:
      - Load infra config
      - Ensure Azure context / login
      - Create Resource Group (idempotent)
      - Register required Azure resource providers
    Designed to be dot-sourced by bootstrap scripts in this repository.
.EXAMPLE
    Set up as a module - Load-Module .\bootstrap\az-bootstrap\az-bootstrap.psm1
    Then call functions, e.g.:
    $cfg = Get-InfraConfig -ConfigPath "$PSScriptRoot\infra-config.json"
.NOTES
    - Intended for PowerShell Core on macOS / Linux / Windows.
    - Keep functions small and testable; use ShouldProcess where changes occur.
#>
function Get-InfraConfig {
    <#
    .SYNOPSIS
        Load infrastructure configuration and apply environment overrides.
    .DESCRIPTION
        Reads a JSON configuration file and applies optional environment-variable overrides
        for common settings (for example AZURE_RG_NAME, AZURE_LOCATION). Returns the final
        configuration object for use by other bootstrap steps.
    .PARAMETER ConfigPath
        Path to the infra JSON configuration file. Defaults to '../infra-config.json' relative to this module.
    .EXAMPLE
        $cfg = Get-InfraConfig -ConfigPath "$PSScriptRoot\..\infra-config.json"
    .OUTPUTS
        PSCustomObject - the parsed and possibly modified configuration object.
    .NOTES
        - Throws if the file is missing or contains invalid JSON.
        - Function is pipeline-friendly and safe to call multiple times.
    #>
    [CmdletBinding()]
    param (
        [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'infra-config.json')
    )

    begin {
        # validate + parse once
        if (-not (Test-Path -Path $ConfigPath)) {
            throw "Config file not found at '$ConfigPath'."
        }
        try {
            $content = Get-Content -Raw -Path $ConfigPath
            $infraConfig = $content | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Invalid JSON in config file '$ConfigPath'. Error: $($_.Exception.Message)"
        }
        # Helper function to choose env var or default
        function Use-EnvOrDefault([string]$envVar, $default) {
            $val = ($envVar ?? '') -as [string]
            if ($val.Trim()) { return $envVar } else { return $default }
        }
    }

    process {
        # apply environment overrides (idempotent, safe if called multiple times)
        $infraConfig.resourceGroup.name = `
            Use-EnvOrDefault $env:AZURE_RG_NAME `
            $infraConfig.resourceGroup.name
        $infraConfig.resourceGroup.location = `
            Use-EnvOrDefault $env:AZURE_LOCATION `
            $infraConfig.resourceGroup.location
        $infraConfig.storageAccount.namePrefix = `
            Use-EnvOrDefault $env:AZURE_STORAGE_PREFIX `
            $infraConfig.storageAccount.namePrefix
    }

    end {
        # emit final config object (pipeline friendly / idiomatic)
        $infraConfig
    }
}

function Set-AzureContext {
    <#
    .SYNOPSIS
        Ensure an authenticated Azure context is available.
    .DESCRIPTION
        Verifies an existing Az context is present; if not, prompts an interactive login
        (Connect-AzAccount). This function uses SupportsShouldProcess for any action that
        changes session state.
    .EXAMPLE
        $ctx = Set-AzureContext
    .OUTPUTS
        Microsoft.Azure.Commands.Common.Authentication.Abstractions.IAuthenticationResult (Azure context object)
    .NOTES
        - Intended for interactive bootstrap runs. For non-interactive automation, ensure service principal auth is configured.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    begin {
        Write-Verbose "Checking Azure context..."
        $currentContext = $null
    }

    process {
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        if (-not ($currentContext)) {
            Write-Verbose "No Azure context found. Initiating login..." 
            try {
                if ($PSCmdlet.ShouldProcess("AzAccount", "Interactive Login")) {
                    $currentContext = Connect-AzAccount -ErrorAction Stop
                    Write-Verbose "Logged in to Azure successfully." 
                }            
            }
            catch {
                Write-Error "Azure login failed. Error: $($_.Exception.Message)"
                throw # Re-throw to stop the script
            }
        }
        else {
            Write-Verbose "Azure context exists - already logged in." 
        }
    }

    end { $currentContext }
}

function Set-AzResourceGroup {
    <#
    .SYNOPSIS
        Creates the foundational Azure Resource Group.
    .DESCRIPTION
        Ensures the specified Resource Group exists at the specified location.
        This function is idempotent.
    .PARAMETER ResourceGroupName
        The name of the Resource Group to create or verify.
    .PARAMETER Location
        The Azure location/region where the Resource Group should reside (e.g., 'uksouth').
    .EXAMPLE
        Set-AzResourceGroup -ResourceGroupName "my-rg" -Location "uksouth"
    .NOTES
        - Designed to be idempotent; skips creation if named Resource Group already exists.
        - Uses New-AzResourceGroup; requires appropriate Azure permissions.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [String]$Location
    )

    begin {
        Write-Verbose "Attempting to create or verify Resource Group: $ResourceGroupName in $Location"
        $resourceGroup = $null
    }

    process {
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not ($resourceGroup)) {
            if ($PSCmdlet.ShouldProcess("Resource Group '$ResourceGroupName'", "Create")) {
                Write-Verbose "Creating Resource Group '$ResourceGroupName'..."
                try {
                    $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -ErrorAction Stop
                    Write-Verbose "Resource Group '$ResourceGroupName' created successfully." 
                }
                catch {
                    Write-Error "Failed to create Resource Group '$ResourceGroupName'. Error: $($_.Exception.Message)"
                    throw
                }
            }
        }
        else {
            Write-Verbose "Resource Group '$ResourceGroupName' already exists. Verified." 
        }
    }

    end { $resourceGroup }
}

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

    begin {
        Write-Verbose "Loading required Azure Resource Providers from '$DependencyFile'..."
        $requiredProviders = @()
    }

    process {
        if (-not (Test-Path -Path $DependencyFile)) {
            throw "Dependency file '$DependencyFile' not found."
        }
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
              .  Where-Object ProviderNamespace -eq $providerName ).RegistrationState -eq "NotRegistered"
            $temp = (Get-AzResourceProvider -ListAvailable |
              .  Where-Object ProviderNamespace -eq $providerName )
            if ($notRegistered) {
                Write-Verbose "Registering Resource Provider: '$providerName'..."
                Register-AzResourceProvider -ProviderNamespace $providerName -ErrorAction Stop
            }
            else {
                Write-Verbose "Resource Provider '$providerName' is already registered."
            }
        }
    }

    end {
        Write-Verbose "All required Azure Resource Providers have been registered."
    }
}
