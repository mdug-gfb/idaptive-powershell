# Import the Idaptive PowerShell Sample Module (see https://github.com/idaptive/idaptive-samples-powershell)
Import-Module .\module\Idaptive.Samples.Powershell.psm1 3>$null 4>$null

# MFA login and get a bearer token as the MFA'd user
#  If you already have a bearer token and endpoint just start using Idaptive-InvokeREST
$token = Idaptive-InteractiveLogin-GetToken -Username "your@username" \
            -Endpoint "https://corp.my.idaptive.app" -Verbose:$enableVerbose    
 
# Define the arguments to the Query API:
$restArg = @{}
$restArg.Args = @{}
$restArg.Args.PageNumber = 1
$restArg.Args.PageSize = 10000
$restArg.Args.Limit = 10000
$restArg.Args.Caching = -1
$restArg.Script = @"
select ApplicationName, count(*) as Count from (select distinct ApplicationName, NormalizedUser from event
     where EventType = 'Cloud.Saas.Application.AppLaunch' and ApplicationName = 'Salesforce' 
	  and WhenOccurred > datefunc('now', -7)) group by ApplicationName
"@
    
$queryResult = Idaptive-InvokeREST -Method "/redrock/query" -Endpoint $token.Endpoint -Token $token.BearerToken -ObjectContent $restArg

# Get licenses used as a percentage of 500
$licensePercentage = 100.0 * ($queryResult.Results[0].Row.Count / 500.0) 
Write-Output "Used $licensePercentage% of our 500 last week"

if($queryResult.Results[0].Row.Count -lt 90) {
    Write-Output "Sending alert, as we have less than 90% utilization of our licenses this week!"
}




