function Get-InfraState {
    param (
        [string]$Path = (Get-DefaultStatePath)
    )
    Write-Host "Get-InfraState called with path: $Path"
}