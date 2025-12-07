function Set-AzBootstrapResourceGroup {
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
        Set-AzBootstrapResourceGroup -ResourceGroupName "my-rg" -Location "uksouth"
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
        return $resourceGroup
    }
}
