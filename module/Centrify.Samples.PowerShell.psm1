<# 
 .Synopsis
  Performs a REST call against the CIS platform.  

 .Description
  Performs a REST call against the CIS platform (JSON POST)

 .Parameter Endpoint
  Required - The target host for the call (i.e. https://cloud.centrify.com)
 
 .Parameter Method
  Required - The method to call (i.e. /security/logout)
  
 .Parameter Token
  Optional - The bearer token retrieved after authenticating, necessary for 
  authenticated calls to succeed.
  
 .Parameter ObjectContent
  Optional - A powershell object which will be provided as the POST arguments
  to the API after passing through ConvertTo-Json.  Overrides JsonContent.
  
 .Parameter JsonContent
  Optional - A string which will be posted as the application/json body for
  the call to the API.

 .Example
   # Get current user details
   Centrify-InvokeREST -Endpoint "https://cloud.centrify.com" -Method "/security/whoami" 
#>
function Centrify-InvokeREST {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string] $endpoint,
        [Parameter(Mandatory=$true)]
        [string] $method,        
        [string] $token = $null,
        $objectContent = $null,
        [string]$jsonContent = $null,       
        $websession = $null,
        [bool]$includeSessionInResult = $false,
        [System.Security.Cryptography.X509Certificates.X509Certificate] $certificate = $null
    )
                             
    $methodEndpoint = $endpoint + $method
    Write-Verbose "Calling $methodEndpoint"
    
    $addHeaders = @{ 
        "X-CENTRIFY-NATIVE-CLIENT" = "1"
    }
    
    if(![string]::IsNullOrEmpty($token))
    {        
        Write-Verbose "Using token: $token"
        $addHeaders.Authorization = "Bearer " + $token
    }
    
    if($objectContent -ne $null)
    {
        $jsonContent = $objectContent | ConvertTo-Json
    }
    
    if(!$jsonContent)
    {
        Write-Verbose "No body provided"
        $jsonContent = "[]"
    }

    if(!$websession)
    {
        Write-Verbose "Creating new session variable"
        if($certificate -eq $null)
        {
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body $jsonContent -SessionVariable websession -Headers $addHeaders
        }
        else 
        {
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body $jsonContent -SessionVariable websession -Headers $addHeaders -Certificate $certificate
        }
    }
    else
    {
        Write-Verbose "Using existing session variable $websession"
        if($certificate -eq $null)
        {
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body $jsonContent -WebSession $websession
        }
        else
        {            
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body $jsonContent -WebSession $websession -Certificate $certificate
        }
        
    }
             
    if($includeSessionInResult)
    {             
        $resultObject = @{}
        $resultObject.RestResult = $response
        $resultObject.WebSession = $websession 
             
        return $resultObject
    }
    else
    {
        return $response
    }                        
}

<# 
 .Synopsis
  Performs a silent login using a certificate, and outputs a bearer token (Field name "BearerToken").

 .Description
  Performs a silent login using client certificate, and retrieves a token suitable for making
  additional API calls as a Bearer token (Authorization header).  Output is an object
  where field "BearerToken" contains the resulting token, or "Error" contains an error
  message from failed authentication. Result object also contains Endpoint for pipeline.

 .Parameter Endpoint
  The endpoint to authenticate against, required - must be tenant's url/pod

 .Example
   # Get a token for API calls to abc123.centrify.com
   Centrify-CertSsoLogin-GetToken -Endpoint "https://abc123.centrify.com" 
#>
function Centrify-CertSsoLogin-GetToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string] $endpoint = "https://cloud.centrify.com",
        [Parameter(Mandatory=$true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate] $certificate = $null        
    )
        
    $subject = $certificate.Subject
    Write-Verbose "Initiating Certificate SSO against $endpoint with $subject"
    $noArg = @{}
                     
    $restResult = Centrify-InvokeREST -Endpoint $endpoint -Method "/negotiatecertsecurity/sso" -Token $null -ObjectContent $startArg -IncludeSessionInResult $true -Certificate $certificate                    
    $startAuthResult = $restResult.RestResult                     
        
    # First, see if we need to repeat our call against a different pod 
    if($startAuthResult.success -eq $false)
    {            
        throw $startAuthResult.Message
    }
            
    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.WebSession.Cookies.GetCookies($endpoint)[".ASPXAUTH"].value
    
    Write-Output $finalResult        
}

<# 
 .Synopsis
  Performs an interactive MFA login, and outpus a bearer token (Field name "BearerToken").

 .Description
  Performs an interactive MFA login, and retrieves a token suitable for making
  additional API calls as a Bearer token (Authorization header).  Output is an object
  where field "BearerToken" contains the resulting token, or "Error" contains an error
  message from failed authentication. Result object also contains Endpoint for pipeline.

 .Parameter Endpoint
  The first month to display.

 .Example
   # MFA login to cloud.centrify.com
   Centrify-InteractiveLogin-GetToken -Endpoint "https://cloud.centrify.com" 
#>
function Centrify-InteractiveLogin-GetToken {
    [CmdletBinding()]
    param(
        [string] $endpoint = "https://cloud.centrify.com",
        [Parameter(Mandatory=$true)]
        [string] $username = ""    
    )
    
    Write-Verbose "Initiating MFA against $endpoint for $username"
    $startArg = @{}
    $startArg.User = $username
    $startArg.Version = "1.0"
                     
    $restResult = Centrify-InvokeREST -Endpoint $endpoint -Method "/security/startauthentication" -Token $null -ObjectContent $startArg -IncludeSessionInResult $true                     
    $startAuthResult = $restResult.RestResult                     
        
    # First, see if we need to repeat our call against a different pod 
    if($startAuthResult.success -eq $true -and $startAuthResult.Result.PodFqdn -ne $null)
    {        
        $endpoint = "https://" + $startAuthResult.Result.PodFqdn
        Write-Verbose "Auth redirected to $endpoint"
        $restResult = Centrify-InvokeREST -Endpoint $endpoint -Method "/security/startauthentication" -Token $null -ObjectContent $startArg -WebSession $restResult.WebSession -IncludeSessionInResult $true        
        $startAuthResult = $restResult.RestResult 
    }
    
    # Get the session id to use in handshaking for MFA
    $authSessionId = $startAuthResult.Result.SessionId
    $tenantId = $startAuthResult.Result.TenantId
    
    # Also get the collection of challenges we need to satisfy
    $challengeCollection = $startAuthResult.Result.Challenges
    
    # We need to satisfy 1 of each challenge collection            
    for($x = 0; $x -lt $challengeCollection.Count; $x++)
    {
        # Present the user with the options available to them
        for($mechIdx = 0; $mechIdx -lt $challengeCollection[$x].Mechanisms.Count; $mechIdx++)
        {            
            $mechDescription = Centrify-Internal-MechToDescription -Mech $challengeCollection[$x].Mechanisms[$mechIdx]
            Write-Host "Mechanism $mechIdx => $mechDescription" 
        }
                                
        [int]$selectedMech = 0                               
        if($challengeCollection[$x].Mechanisms.Count -ne 1)
        {
            $selectedMech = Read-Host "Choose mechanism"            
        }             
                 
        $mechResult = Centrify-Internal-AdvanceForMech -Mech $challengeCollection[$x].Mechanisms[$selectedMech] -Endpoint $endpoint -TenantId $tenantId -SessionId $authSessionId -WebSession $restResult.WebSession                           
    }
            
    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.WebSession.Cookies.GetCookies($endpoint)[".ASPXAUTH"].value
    
    Write-Output $finalResult        
}

function Centrify-Internal-AdvanceForMech {
    param(
        $mech,
        $endpoint,
        $tenantId,
        $sessionId,
        $websession
    )
    
    $advanceArgs = @{}
    $advanceArgs.TenantId = $tenantId
    $advanceArgs.SessionId = $sessionId
    $advanceArgs.MechanismId = $mech.MechanismId
    $advanceArgs.PersistentLogin = $false
    
    $prompt = Centrify-Internal-MechToPrompt -Mech $mech
    
    # Password, or other 'secret' string
    if($mech.AnswerType -eq "Text" -or $mech.AnswerType -eq "StartTextOob")    
    {    
        if($mech.AnswerType -eq "StartTextOob")
        {
            $advanceArgs.Action = "StartOOB"
            $advanceResult = (Centrify-InvokeREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -ObjectContent $advanceArgs -WebSession $websession -IncludeSessionInResult $true).RestResult            
        }
            
        $responseSecure = Read-Host $prompt -assecurestring
        $responseBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($responseSecure)
        $responsePlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($responseBstr)
            
        $advanceArgs.Answer = "PASSWORDGOESHERE"
        $advanceArgs.Action = "Answer"

        # Powershell's ConvertTo-Json likes to escape things, generally this is okay - but passwords shouldn't be touched
        #  so instead we serialize to Json, then substitute the actual password.
        $advanceArgsJson = $advanceArgs | ConvertTo-Json
        $advanceArgsJson = $advanceArgsJson.Replace("PASSWORDGOESHERE", $responsePlain)                        
                        
        $advanceResult = (Centrify-InvokeREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -JsonContent $advanceArgsJson -WebSession $websession -IncludeSessionInResult $true).RestResult
        if($advanceResult.success -ne $true -or 
            ($advanceResult.Result.Summary -ne "StartNextChallenge" -and $advanceResult.Result.Summary -ne "LoginSuccess" -and $advanceResult.Result.Summary -ne "NewPackage")
        )
        {            
            throw $advanceResult.Message
        }     
            
        return $advanceResult   
        break
    }
    # Out of band code or link which must be invoked remotely, we poll server
    elseif($mech.AnswerType -eq "StartOob")
    {
            # We ping advance once to get the OOB mech going, then poll for success or abject fail
            $advanceArgs.Action = "StartOOB"
            $advanceResult = (Centrify-InvokeREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -ObjectContent $advanceArgs -WebSession $websession -IncludeSessionInResult $true).RestResult
            
            Write-Host $prompt
            $advanceArgs.Action = "Poll"
            do
            {
                Write-Host -NoNewline "."
                $advanceResult = (Centrify-InvokeREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -ObjectContent $advanceArgs -WebSession $websession -IncludeSessionInResult $true).RestResult
                Start-Sleep -s 1                    
            } while($advanceResult.success -eq $true -and $advanceResult.Result.Summary -eq "OobPending")
            
            Write-Host ""   # new line
            
            # Polling done, did we succeed in our challenge?
            if($advanceResult.success -ne $true -or 
                ($advanceResult.Result.Summary -ne "StartNextChallenge" -and $advanceResult.Result.Summary -ne "LoginSuccess")
            )
            {            
                throw $advanceResult.Message
            } 
            return $advanceResult
            break
    }        
}

# Internal function, maps mechanism to description for selection
function Centrify-Internal-MechToDescription {
    param(
        $mech
    )
    
    if($mech.PromptSelectMech -ne $null)
    {
        return $mech.PromptSelectMech
    }
        
    $mechName = $mech.Name
    switch($mechName)
    {
        "UP" {
            return "Password"
        }                    
        "SMS" {
            return "SMS to number ending in " + $mech.PartialDeviceAddress
        }
        "EMAIL" {
            return "Email to address ending with " + $mech.PartialAddress
        }
        "PF" {
            return "Phone call to number ending with " + $mech.PartialPhoneNumber
        }
        "OATH" {
            return "OATH compatible client"
        }
        "SQ" {
            return "Security Question"
        }
        default {
            return $mechName
        }
    }
}

# Internal function, maps mechanism to prompt once selected
function Centrify-Internal-MechToPrompt {
    param(
        $mech        
    )
    
    if($mech.PromptMechChosen -ne $null)
    {
        return $mech.PromptMechChosen
    }
    
    $mechName = $mech.Name
    switch ($mechName)
    {
        "UP" {
            return "Password: "
        }
        "SMS" {
            return "Enter the code sent via SMS to number ending in " + $mech.PartialDeviceAddress
        }
        "EMAIL" {                    
            return "Please click or open the link sent to the email to address ending with " + $mech.PartialAddress
        }
        "PF" {
            return "Calling number ending with " + $mech.PartialPhoneNumber + " please follow the spoken prompt"
        }
        "OATH" {
            return "Enter your current OATH code"
        }
        "SQ" {
            return "Enter the response to your secret question"
        }
        default {
            return $mechName
        }
    }
}

<# 
 .Synopsis
  Performs Authorization to an OAuth server in Application Services using Client Credentials Flow.

 .Description
  Performs Authorization to an OAuth server in Application Services using Client Credentials Flow. Returns 
  Access Bearer Token.

 .Parameter Endpoint
  The endpoint to authenticate against, required - must be tenant's url/pod

 .Example
   # Get an OAuth2 token for API calls to abc123.centrify.com
   Centrify-OAuth-ClientCredentials -Endpoint "https://abc123.centrify.com" -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope"
#>
function Centrify-OAuth-ClientCredentials
{
    [CmdletBinding()]
    param(
        [string] $endpoint = "https://cloud.centrify.com",
        [Parameter(Mandatory=$true)]
        [string] $appid, 
        [Parameter(Mandatory=$true)]
        [string] $clientid,
        [Parameter(Mandatory=$true)]
        [string] $clientsecret,
        [Parameter(Mandatory=$true)]
        [string] $scope
        )

    $verbosePreference = "Continue"
    $api = "$endpoint/oauth2/token/$appid"
    $bod = @{}
    $bod.grant_type = "client_credentials"
    $bod.scope = $scope
    $basic = Centrify-InternalMakeClientAuth $clientid $clientsecret
    $restResult = Invoke-RestMethod -Method Post -Uri $api -Headers $basic -Body $bod

    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.access_token

    Write-Output $finalResult  
}

function Centrify-OAuthResourceOwner
{
    [CmdletBinding()]
    param(
        [string] $endpoint = "https://cloud.centrify.com",
        [Parameter(Mandatory=$true)]
        [string] $appid, 
        [Parameter(Mandatory=$true)]
        [string] $clientid,
        [string] $clientsecret,
        [string] $username,
        [Parameter(Mandatory=$true)]
        [string] $password,
        [Parameter(Mandatory=$true)]
        [string] $scope
        )

    $verbosePreference = "Continue"
    $api = "$endpoint/oauth2/token/$appid"
    $bod = @{}
    $bod.grant_type = "password"
    $bod.username = $username
    $bod.password = $password
    $bod.scope = $scope

    if($clientsecret)
    {
        $basic = Centrify-InternalMakeClientAuth $clientid $clientsecret
    }
    else
    {
        $basic = @{}
        $bod.client_id = $clientid
    }

    $restResult = Invoke-RestMethod -Method Post -Uri $api -Headers $basic -Body $bod

    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.access_token

    Write-Output $finalResult  
}


#Internal function. Returns base64 encoded auth token for basic Authorizatioin header.
function Centrify-InternalMakeClientAuth($id,$secret)
{
    # http basic authorization header for token request
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($id):$($secret)"))
    $basic = @{ "Authorization" = "Basic $b64"}
    return $basic
}

Export-ModuleMember -function Centrify-InvokeREST
Export-ModuleMember -function Centrify-InteractiveLogin-GetToken
Export-ModuleMember -function Centrify-CertSsoLogin-GetToken
Export-ModuleMember -function Centrify-OAuth-ClientCredentials
Export-ModuleMember -function Centrify-OAuthResourceOwner