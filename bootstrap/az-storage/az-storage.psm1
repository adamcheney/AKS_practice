<#
.SYNOPSIS
    Azure Storage helper functions (module).
.DESCRIPTION
    Idempotent helpers to generate unique storage account names and ensure a backend storage account exists.
    Intended to be used as a module (Import-Module) by bootstrap scripts and tooling.
    Dot-sourcing is supported for quick interactive debugging but module import is preferred.
.EXAMPLE
    # Import the module for production or automated usage
    Import-Module "$PSScriptRoot/az-storage.psm1" -Force
    $saName = New-UniqueStorageAccountName -Prefix 'testacct'
.NOTES
    - Designed for PowerShell Core (cross-platform).
    - Functions use ShouldProcess for operations that change state.
#>
function New-UniqueStorageAccountName {
    <#
    .SYNOPSIS
        Generate a unique storage account name.
    .DESCRIPTION
        Given a lowercase alphabetic prefix (3-12 characters), generates a unique name
        by appending a timestamp (to centisecond precision). Validates prefix length
        and pattern and throws on invalid input.
    .PARAMETER Prefix
        Lowercase alphabetic prefix (3..12 characters).
    .EXAMPLE
        New-UniqueStorageAccountName -Prefix 'testacct'
    .OUTPUTS
        System.String
    .NOTES
        This implements basic prefix validation. Callers should ensure the final name
        complies with all Azure Storage naming constraints.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateLength(3, 12)]
        [ValidatePattern('^[a-z]+$')]
        [String]$Prefix
    )

    begin {
        # nothing needed here
    }
    
    process {
        $storageAccountName = $Prefix + (Get-Date -Format MMddHHmmssff)
    }

    end {
        $storageAccountName
    }
}

function Set-BackendStorageAccount {
    <#
    .SYNOPSIS
        Ensure a backend Azure Storage Account exists.
    .DESCRIPTION
        Searches the specified resource group for storage accounts with the given prefix.
        If none exists (or creation is required), creates a new storage account with a
        unique name. Creation is guarded by SupportsShouldProcess.
    .PARAMETER ResourceGroupName
        The name of the Azure resource group to inspect.
    .PARAMETER StorageAccountNamePrefix
        Prefix to match existing storage accounts and to use when generating a new name.
    .PARAMETER Location
        Azure region in which to create a new storage account if required.
    .PARAMETER SkuName
        Storage account SKU (default 'Standard_LRS').
    .EXAMPLE
        $p = @{ ResourceGroupName='test-rg'; StorageAccountNamePrefix='testacct'; Location='eastus' }
        Set-BackendStorageAccount @p
    .OUTPUTS
        PSCustomObject representing the selected or newly created storage account.
    .NOTES
        - Function is idempotent: it prefers the most recent matching existing account.
        - Uses Get-AzStorageAccount and New-AzStorageAccount; callers/tests may mock these.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [String]$StorageAccountNamePrefix,
        [Parameter(Mandatory=$true)]
        [String]$Location,
        [Parameter(Mandatory=$false)]
        [String]$SkuName = 'Standard_LRS'
    )

    begin {
        # nothing needed here
    }
    
    process {
        $storageAccts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
        $mostRecent = $null
        $storageAccts | ForEach-Object {
            $name = $_.StorageAccountName
            if ($name -like "$StorageAccountNamePrefix*") {
                if (-not $mostRecent -or $_.CreationTime -gt $mostRecent.CreationTime) {
                    $mostRecent = $_
                }
            }
        }
        if (-not $mostRecent) {
            Write-Verbose "No existing Storage Account found with prefix '$StorageAccountNamePrefix'."
            $StorageAccountName = New-UniqueStorageAccountName -Prefix $StorageAccountNamePrefix
            $storageAccountParams = @{
                ResourceGroupName = $ResourceGroupName
                Name              = $StorageAccountName
                Location          = $Location
                SkuName           = $SkuName
            }
            if ($PSCmdlet.ShouldProcess("Storage Account '$StorageAccountName' in Resource Group '$ResourceGroupName'")) {
                Write-Verbose "Creating Storage Account: $StorageAccountName"
                $storageAccount = New-AzStorageAccount @storageAccountParams
            }
        }
        else {
            Write-Verbose "Found existing Storage Account: $($mostRecent.StorageAccountName). Using this."
            $storageAccount = $mostRecent
        }
    }

    end {
        $storageAccount
    }
}