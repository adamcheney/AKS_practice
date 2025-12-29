function Set-InfraState {
    <#
    .SYNOPSIS
        Records the bootstrap state to a JSON file.
    .DESCRIPTION
        Writes the provided hashtable content to a JSON file at the specified path,
        adding a DateTime field with the current timestamp.
        Creates the file if it does not exist.
        Merges with existing content if the file already exists.
        Idempotent operation.
    .PARAMETER FilePath
        Path to the state JSON file (default: 'infrastate.json' in the script folder).
    .PARAMETER State
        Hashtable representing the state to record.
    .EXAMPLE
        $state = @{
            "deployedResources" = @("resource1", "resource2")
            "configVersion" = "1.0.0"
        }
        Set-InfraState -State $state
    .NOTES
        Intended for use by bootstrap scripts to track infrastructure state.
        Opinionated about filename: infrastate.json in the bootstrap folder.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Hashtable]$State,
        [String]$Path = (Get-DefaultStatePath)
    )
    
    process {
        $existingContent = @{}
        if (-not (Test-Path -Path $Path)) {
            try {
                New-Item -Path $Path -ItemType File -Force | Out-Null
            }
            catch {
                throw "Failed to create state file: $Path. $_"
            }
        } else {
            Write-Host "State file exists at $Path."
            $existingContent = Get-InfraState -Path $Path
        }
        if ($null -ne $State) {}
            
        return $Path
    }
}
        