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

    process {
        return $Prefix + (Get-Date -Format MMddHHmmssff)
    }
}
