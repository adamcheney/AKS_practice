function Get-DefaultStatePath {
    <#
    .SYNOPSIS
        Returns the default path for the bootstrap state file.
    .DESCRIPTION
        Constructs and returns the default file path for storing bootstrap state information.
    .EXAMPLE
        $defaultPath = Get-DefaultStatePath
    #>

    $moduleRoot = Split-Path -Parent (Get-Module -Name $ExecutionContext.SessionState.Module.Name).ModuleBase
    $defaultPath = Join-Path -Path $moduleRoot -ChildPath 'infrastate.json'
    return $defaultPath
}
