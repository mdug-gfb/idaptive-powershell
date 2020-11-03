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
if($null -eq $token)
{
    Write-Verbose "Creating New Token"
    $token = Invoke-IdaptiveInteractiveLoginToken -Username $usename -Endpoint "https://pod0.idaptive.app" -Verbose:$enableVerbose    
}
else {
    Write-Verbose "Reusing Token"
}

$application="Prendio"
 
# Define the arguments to the Query API:
$restArg = @{}
$restArg.Args = @{}
$restArg.Args.PageNumber = 1
$restArg.Args.PageSize = 10000
$restArg.Args.Limit = 10000
$restArg.Args.Caching = -1
$restArg.Script = @"
select ApplicationName, count(*) as Count from (select distinct ApplicationName, NormalizedUser from event
     where EventType = 'Cloud.Saas.Application.AppLaunch' and ApplicationName = '$application'
	  and WhenOccurred > datefunc('now', -7)) group by ApplicationName
"@
    
$queryResult = Invoke-IdaptiveREST -Method "/redrock/query" -Endpoint $token.Endpoint -Token $token.BearerToken -ObjectContent $restArg

# Get licenses used as a percentage of 500
$launchCount = $queryResult.Result.Results[0].Row.Count

Write-Output "$application was launched $launchCount times in the last 7 days "