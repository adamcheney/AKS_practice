<#
.SYNOPSIS
    Common parameters and reusable functions.
.DESCRIPTION
    The bootstrapping scripts can dot-source this file to reuse common configuration variables and functions.
    These functions:
    - define defaults
    - create resource group
    - register resource providers
.EXAMPLE
    Example command showing typical usage:
    .\MyScript.ps1 -Name1 "Value" -Name2 10
.NOTES
    Any additional information, like dependencies or version history.
#>

function Get-InfraConfig {
    <#
    .SYNOPSIS
        Pulls infrastructure configuration from JSON file and (optionally) environment variables.
    .DESCRIPTION
        Loads JSON config, applies environment-variable overrides and emits the final config object.
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
    }

    end {
        # emit final config object (pipeline friendly / idiomatic)
        $infraConfig
    }
}

function Set-AzureContext {
    <#
    .SYNOPSIS
        Ensures Azure context exists.
    .DESCRIPTION
        Checks if there is an existing Azure context; if not, it initiates a login.
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
                if ($PSCmdlet.ShouldProcess("AzAccount", "Remove version $loadedModule.Version")) {
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


# --- Reusable Functions ---
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
        Registers necessary Azure Resource Providers.
    .DESCRIPTION
        Registers required Azure Resource Providers for the deployment.
    .PARAMETER DependencyFile
        Path to the dependencies file listing required resource providers.
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
            $notRegistered = (Get-AzResourceProvider -ListAvailable `
              | Where-Object ProviderNamespace -eq $providerName ).RegistrationState -eq "NotRegistered"
            $temp = (Get-AzResourceProvider -ListAvailable `
              | Where-Object ProviderNamespace -eq $providerName )
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
