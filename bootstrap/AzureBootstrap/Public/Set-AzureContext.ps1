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
        return $currentContext
    }
}
