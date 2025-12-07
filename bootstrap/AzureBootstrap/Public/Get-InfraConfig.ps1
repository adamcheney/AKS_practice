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
    param(
        [String]$ConfigPath = $null
    )

    process {
        if (-not $ConfigPath) {
            $moduleRoot = Split-Path -Parent (Get-Module -Name $ExecutionContext.SessionState.Module.Name).ModuleBase
            $ConfigPath = Join-Path -Path $moduleRoot -ChildPath 'infra-config.json'
        }
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
        function Use-EnvOrDefault([String]$envVar, $default) {
            $val = ($envVar ?? '') -as [String]
            if ($val.Trim()) { return $envVar } else { return $default }
        }
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

        return $infraConfig
    }
}
