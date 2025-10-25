<#
.SYNOPSIS
    Azure Storage reusable functions.
.DESCRIPTION
    Idempotent creation of Azure Stoage account
.EXAMPLE
    Example command showing typical usage:
    .\MyScript.ps1 -Name1 "Value" -Name2 10
.NOTES
    Any additional information, like dependencies or version history.
#>

function New-UniqueStorageAccountName {
    <#
    .SYNOPSIS
        Generates unique name.
    .DESCRIPTION
        Given a prefix, generates a suitable, unique name baseed on the date-time (to the centi-second).
        Throws errors if the prefix contains unsuitable charaters or is too long.
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
        Ensures Azure Storage Account exists.
    .DESCRIPTION
        Checks for existence of a Storage Account in the specified Resource Group, having the same prefix.
        If not found, creates a new Storage Account with a unique name.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]$ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [String]$StorageAccountNamePrefix,
        [Parameter(Mandatory=$true)]
        [String]$Location,
        [String]$Sku = 'Standard_LRS',
        [String]$Kind = 'StorageV2'
    )

    begin {
        # nothing needed here
    }
    
    process {
        $storageAccts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
        $mostRecent = $null
        $storageAccts | ForEach-Object {
            $Name = $_.StorageAccountName
            if ($Name -like "$StorageAccountNamePrefix*") {
                if (-not $mostRecent -or $_.CreationTime -gt $mostRecent.CreationTime) {
                    $mostRecent = $_
                }
            }
        }
        if (-not $mostRecent) {
            Write-Verbose "No existing Storage Account found with prefix '$StorageAccountNamePrefix'."
            Write-Host "No existing Storage Account found with prefix '$StorageAccountNamePrefix'."
            Write-Verbose "Creating new one."
            Write-Host "Creating new one."
            $StorageAccountName = New-UniqueStorageAccountName -Prefix $StorageAccountNamePrefix
            $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                -Name $StorageAccountName -Location $Location -SkuName $Sku -Kind $Kind
        }
        else {
            Write-Verbose "Found existing Storage Account: $($mostRecent.StorageAccountName). Using this."
            Write-Host "Found existing Storage Account: $($mostRecent.StorageAccountName). Using this."
            $storageAccount = $mostRecent
        }
    }

    end {
        $storageAccount
    }
}