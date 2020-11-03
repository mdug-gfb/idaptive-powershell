[CmdletBinding()]
param(
    #Used for interactive auth only. Comment out for OAuth
    [Parameter(Mandatory=$true)]
    [string]$username="",
    [string]$endpoint = "https://pod0.idaptive.app"
)

# Import the Idaptive PowerShell Sample Module (see https://github.com/mdug-gfb/idaptive-powershell)
Import-Module .\module\Idaptive-Powershell.psd1 3>$null 4>$null

# MFA login and get a bearer token as the MFA'd user
#  If you already have a bearer token and endpoint just start using Invoke-IdaptiveREST
try{
    if($null -eq $token)
    {
        Write-Verbose "Creating New Token"
        $token = Invoke-IdaptiveInteractiveLoginToken -Username $username -Endpoint "https://pod0.idaptive.app" -Verbose:$enableVerbose    
    }
    else {
        Write-Verbose "Reusing Token"
    }

    $today = Get-Date
    $startdate = $today.AddDays(-14).ToString("yyyy-MM-dd HH:mm")
    # Define the arguments to the Query API:
    $restArg = @{}
    $restArg.Args = @{}
    $restArg.Args.PageNumber = 1
    $restArg.Args.PageSize = 10000
    $restArg.Args.Limit = 10000
    $restArg.Args.Caching = -1
    $restArg.Script = @"
    SELECT ID AS _ID, Name, LastUsedCentrifyUrl, WebAppType
    FROM Application
    WHERE LastUsedCentrifyUrl >= "$startdate" AND WebAppType = "Saml"
    ORDER BY LastUsedCentrifyUrl DESC
"@
        
    $queryResult = Invoke-IdaptiveREST -Method "/redrock/query" -Endpoint $token.Endpoint -Token $token.BearerToken -ObjectContent $restArg

    # Get licenses used as a percentage of 500
    $centrifyurl=$queryResult.Result.Results.row | Select-Object Name, WebappType, LastUsedCentrifyUrl
    Write-Output $centrifyurl
}
finally
{
    # Always remove the Idaptive.Samples.Powershell and Idaptive-CPS modules, makes development iteration on the module itself easier
    Remove-Module Idaptive-Powershell 4>$null
}