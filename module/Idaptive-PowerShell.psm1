<# 
 .Synopsis
  Performs a REST call against the CIS platform.  

 .Description
  Performs a REST call against the CIS platform (JSON POST)

 .Parameter Endpoint
  Required - The target host for the call (i.e. https://pod0.idaptive.app)
 
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
   Invoke-IdaptiveREST-Endpoint "https://pod0.idaptive.app" -Method "/security/whoami" 
#>
function Invoke-IdaptiveREST {
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
    
    # Force use of tls 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                             
    $methodEndpoint = $endpoint + $method
    Write-Verbose "Calling $methodEndpoint"
    
    $addHeaders = @{ 
        "X-IDAP-NATIVE-CLIENT" = "1"
    }
    
    if(![string]::IsNullOrEmpty($token))
    {        
        Write-Verbose "Using token: $token"
        $addHeaders.Authorization = "Bearer " + $token
    }
    
    if($null -ne $objectContent)
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
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonContent)) -SessionVariable websession -Headers $addHeaders
        }
        else 
        {
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonContent)) -SessionVariable websession -Headers $addHeaders -Certificate $certificate
        }
    }
    else
    {
        Write-Verbose "Using existing session variable $websession"
        if($certificate -eq $null)
        {
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonContent)) -WebSession $websession
        }
        else
        {            
            $response = Invoke-RestMethod -Uri $methodEndpoint -ContentType "application/json" -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonContent)) -WebSession $websession -Certificate $certificate
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
   # Get a token for API calls to abc123.idaptive.app
   Invoke-IdaptiveCertSsoLogin-GetToken -Endpoint "https://abc123.idaptive.app" 
#>
function Invoke-IdaptiveCertSsoLoginToken {
    [CmdletBinding()]
    param(
        [Parameter]
        [string] $endpoint = "https://pod0.idaptive.app",
        [Parameter]
        [System.Security.Cryptography.X509Certificates.X509Certificate] $certificate = $null        
    )
        
    $subject = $certificate.Subject
    Write-Verbose "Initiating Certificate SSO against $endpoint with $subject"
    $noArg = @{}
                     
    $restResult = Invoke-IdaptiveREST -Endpoint $endpoint -Method "/negotiatecertsecurity/sso" -Token $null -ObjectContent $startArg -IncludeSessionInResult $true -Certificate $certificate                    
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
   # MFA login to pod0.idaptive.app
   Invoke-IdaptiveInteractiveLoginToken -Endpoint "https://pod0.idaptive.app" 
#>
function Invoke-IdaptiveInteractiveLoginToken {
    [CmdletBinding()]
    param(
        [string] $endpoint = "https://pod0.idaptive.app",
        [Parameter(Mandatory=$true)]
        [string] $username = ""    
    )
    
    Write-Verbose "Initiating MFA against $endpoint for $username"
    $startArg = @{}
    $startArg.User = $username
    $startArg.Version = "1.0"
                     
    $restResult = Invoke-IdaptiveREST -Endpoint $endpoint -Method "/security/startauthentication" -Token $null -ObjectContent $startArg -IncludeSessionInResult $true                     
    $startAuthResult = $restResult.RestResult                     
        
    # First, see if we need to repeat our call against a different pod 
    if($startAuthResult.success -eq $true -and $null -ne $startAuthResult.Result.PodFqdn)
    {        
        $endpoint = "https://" + $startAuthResult.Result.PodFqdn
        Write-Verbose "Auth redirected to $endpoint"
        $restResult = Invoke-IdaptiveREST -Endpoint $endpoint -Method "/security/startauthentication" -Token $null -ObjectContent $startArg -WebSession $restResult.WebSession -IncludeSessionInResult $true        
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
            $mechDescription = Invoke-IdaptiveInternalMechToDescription -Mech $challengeCollection[$x].Mechanisms[$mechIdx]
            Write-Host "Mechanism $mechIdx => $mechDescription" 
        }
                                
        [int]$selectedMech = 0                               
        if($challengeCollection[$x].Mechanisms.Count -ne 1)
        {
            $selectedMech = Read-Host "Choose mechanism"            
        }             
                 
        $mechResult = Invoke-IdaptiveInternalAdvanceForMech -Mech $challengeCollection[$x].Mechanisms[$selectedMech] -Endpoint $endpoint -TenantId $tenantId -SessionId $authSessionId -WebSession $restResult.WebSession                           
    }
            
    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.WebSession.Cookies.GetCookies($endpoint)[".ASPXAUTH"].value
    
    Write-Output $finalResult        
}

function Invoke-IdaptiveInternalAdvanceForMech {
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
    
    $prompt = Invoke-IdaptiveInternalMechToPrompt -Mech $mech
    
    # Password, or other 'secret' string
    if($mech.AnswerType -eq "Text" -or $mech.AnswerType -eq "StartTextOob")    
    {    
        if($mech.AnswerType -eq "StartTextOob")
        {
            $advanceArgs.Action = "StartOOB"
            $advanceResult = (Invoke-IdaptiveREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -ObjectContent $advanceArgs -WebSession $websession -IncludeSessionInResult $true).RestResult            
        }
            
        $responseSecure = Read-Host $prompt -assecurestring
        $responseBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($responseSecure)
        $responsePlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($responseBstr)
            
        $advanceArgs.Answer = $responsePlain
        $advanceArgs.Action = "Answer"
        $advanceArgsJson = $advanceArgs | ConvertTo-Json                      
                        
        $advanceResult = (Invoke-IdaptiveREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -JsonContent $advanceArgsJson -WebSession $websession -IncludeSessionInResult $true).RestResult
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
            $advanceResult = (-Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -ObjectContent $advanceArgs -WebSession $websession -IncludeSessionInResult $true).RestResult
            
            Write-Host $prompt
            $advanceArgs.Action = "Poll"
            do
            {
                Write-Host -NoNewline "."
                $advanceResult = (Invoke-IdaptiveREST -Endpoint $endpoint -Method "/security/advanceauthentication" -Token $null -ObjectContent $advanceArgs -WebSession $websession -IncludeSessionInResult $true).RestResult
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
function Invoke-IdaptiveInternalMechToDescription {
    param(
        $mech
    )
    
    if($null -ne $mech.PromptSelectMech)
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
function Invoke-IdaptiveInternalMechToPrompt {
    param(
        $mech        
    )
    
    if($null -ne $mech.PromptMechChosen)
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
            return "Click the link in the email " + $mech.PartialAddress + " or manually input the code"
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
  Performs Authorization to an OAuth server in Application Services using Auth Code Flow.

 .Description
  Performs Authorization to an OAuth server in Application Services using Auth Code Flow. Returns 
  Access Bearer Token.

 .Parameter Endpoint
  The endpoint to authenticate against, required - must be tenant's url/pod

 .Example
   # Get an OAuth2 token for API calls to abc123.idaptive.app
   Invoke-IdaptiveOAuthCodeFlow -Endpoint "https://abc123.idaptive.app" -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope"
#>
function Invoke-IdaptiveOAuthCodeFlow()
{

    [CmdletBinding()]
        param(
        [string] $endpoint = "https://pod0.idaptive.app",
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

	$config = @{}
	$config.authUri = "$endpoint/oauth2/authorize/$appid"
	$config.tokUri = "$endpoint/oauth2/token/$appid"
	$config.redirect = "$endpoint/sysinfo/dummy"	
	$config.clientID = $clientid
	$config.clientSecret =  $clientsecret
	$config.scope = $scope

	$restResult = Invoke-IdaptiveInternalOAuthCodeFlow $config

    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.access_token

    Write-Output $finalResult  

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
   # Get an OAuth2 token for API calls to abc123.idaptive.app
   Invoke-IdaptiveOAuthImplicit -Endpoint "https://abc123.idaptive.app" -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope"
#>
function Invoke-IdaptiveOAuthImplicit()
{

   [CmdletBinding()]
   param(
        [string] $endpoint = "https://pod0.idaptive.app",
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
	$config = @{}
	$config.authUri = "$hostURL/oauth2/authorize/$appid"
	$config.tokUri = "$hostURL/oauth2/token/$appid"
	$config.redirect = "$hostURL/sysinfo/dummy"
	$config.clientID = $clientid
	$config.clientSecret =  $clientsecret
	$config.scope = $scope

	$restResult = Invoke-IdaptiveInternalImplicitFlow $config

    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.access_token

    Write-Output $finalResult  
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
   # Get an OAuth2 token for API calls to abc123.idaptive.app
   Invoke-IdaptiveOAuthClientCredentials -Endpoint "https://abc123.idaptive.app" -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope"
#>
function Invoke-IdaptiveOAuthClientCredentials
{
    [CmdletBinding()]
    param(
        [string] $endpoint = "https://pod0.idaptive.app",
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
    $basic = Invoke-IdaptiveInternalBasicAuth $clientid $clientsecret
    $restResult = Invoke-RestMethod -Method Post -Uri $api -Headers $basic -Body $bod

    $finalResult = @{}
    $finalResult.Endpoint = $endpoint    
    $finalResult.BearerToken = $restResult.access_token

    Write-Output $finalResult  
}

<# 
 .Synopsis
  Performs Authorization to an OAuth server in Application Services using Resource Owner Flow.

 .Description
  Performs Authorization to an OAuth server in Application Services using Resource Owner Flow. Returns 
  Access Bearer Token.

 .Parameter Endpoint
  The endpoint to authenticate against, required - must be tenant's url/pod

 .Example
   # Get an OAuth2 token for API calls to abc123.idaptive.app
   Invoke-IdaptiveOAuthResourceOwner-Endpoint "https://abc123.idaptive.app" -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope"
#>
function Invoke-IdaptiveOAuthResourceOwner
{
    [CmdletBinding()]
    param(
        [string] $endpoint = "https://pod0.idaptive.app",
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
        $basic = Invoke-IdaptiveInternalBasicAuth $clientid $clientsecret
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

#Internal function for Auth Code Flow. Returns OAuth2 Access JWT Token
function Invoke-IdaptiveInternalOAuthCodeFlow($ocfg)

{

	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Web



	# build web UI
	$form = New-Object Windows.Forms.Form
	$form.Width = 640
	$form.Height = 480
	$web = New-Object Windows.Forms.WebBrowser
	$web.Size = $form.ClientSize
	$web.Anchor = "Left,Top,Right,Bottom"
	$form.Controls.Add($web)

	$Global:redirect_uri = $null

	# a handler for page change events in the browser
	$web.add_Navigated(
	{
		Write-Verbose "Navigated $($_.Url)"

		# detect when browser is about to fetch redirect_uri
		$uri = [uri] $ocfg.redirect

		if($_.Url.LocalPath -eq $uri.LocalPath) 
        {
			# collect authorization response in a global
			$Global:redirect_uri = $_.Url
			$form.DialogResult = "OK"
			$form.Close()
		}

	})

	write-verbose "host is $($ocfg.authUri)"
	write-verbose "client id is $($ocfg.clientID)"

	# navigate to authorize endpoint
	$web.Navigate("$($ocfg.authUri)?debug=true&scope=$($ocfg.scope)&response_type=code&redirect_uri=$($ocfg.redirect)&client_id=$($ocfg.clientID)&client_secret=$($ocfg.clientSecret)")

	# show browser window, waits for window to close
	if($form.ShowDialog() -ne "OK") 
    {
        Write-Verbose "WebBrowser: Canceled"
		return @{}
	}

	if(-not $Global:redirect_uri) 
    {
        Write-Verbose "WebBrowser: redirect_uri is null"
		return @{}
	}

	# decode query string of authorization code response
	$response = [Web.HttpUtility]::ParseQueryString($Global:redirect_uri.Query)

	if(-not $response.Get("code")) 
    {
		Write-Verbose "WebBrowser: authorization code is null"
		return @{}
	}

	$tokenrequest = @{ "grant_type" = "authorization_code"; "redirect_uri" = $ocfg.redirect; "code" = $response.Get("code") }

    Write-Verbose $tokenrequest.code


	if($ocfg.clientSecret)

	{
		# http basic authorization header for token request
		$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($ocfg.clientID):$($ocfg.clientSecret)"))
		$basic = @{ "Authorization" = "Basic $b64"}
	}
	else
	{
		$basic =@{}
		$tokenRequest.client_id = $ocfg.clientID
	}

	# send token request
	Write-Verbose "token-request: $([pscustomobject]$tokenrequest)"
    Write-Verbose $ocfg.tokUri

	try
	{
		$token = Invoke-RestMethod -Method Post -Uri $ocfg.tokUri -Headers $basic -Body $tokenrequest
	}
	catch [System.Net.WebException]
	{
		$e = $_.Exception
		Write-host "Exception caught: $e"
	}

	Write-Verbose "token-response: $($token)"

	return $token
}

#Internal function for Implicit Flow. Returns OAuth2 Access JWT Token
function Invoke-IdaptiveInternalImplicitFlow($ocfg)
{

	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Web

	# build web UI

	$form = New-Object Windows.Forms.Form
	$form.Width = 640
	$form.Height = 480
	$web = New-Object Windows.Forms.WebBrowser
	$web.Size = $form.ClientSize
	$web.Anchor = "Left,Top,Right,Bottom"
	$form.Controls.Add($web)   

	$Global:redirect_uri = $null

	# a handler for page change events in the browser
	$web.add_Navigated(
	{
		Write-Verbose "Navigated $($_.Url)"

		# detect when browser is about to fetch redirect_uri
		$uri = [uri] $ocfg.redirect

		if($_.Url.LocalPath -eq $uri.LocalPath) 
        {

			# collect authorization response in a global
			$Global:redirect_uri = $_.Url
			$form.DialogResult = "OK"
			$form.Close()
		}

	})

	write-verbose "host is $($ocfg.authUri)"
	write-verbose "client id is $($ocfg.clientID)"

	# navigate to authorize endpoint
	$web.Navigate("$($ocfg.authUri)?debug=true&scope=$($ocfg.scope)&response_type=code&redirect_uri=$($ocfg.redirect)&client_id=$($ocfg.clientID)&client_secret=$($ocfg.clientSecret)")

	# show browser window, waits for window to close
	if($form.ShowDialog() -ne "OK") 
    {
		Write-Verbose "WebBrowser: Canceled"
		return @{}
	}

	if(-not $Global:redirect_uri) 
    {
		Write-Verbose "WebBrowser: redirect_uri is null"
		return @{}
	}

	# decode query string of authorization code response
	$response = [Web.HttpUtility]::ParseQueryString($Global:redirect_uri.Query)

	if(-not $response.Get("code")) 
    {
		Write-Verbose "WebBrowser: authorization code is null"
		return @{}
	}

	$tokenrequest = @{ "grant_type" = "implicit"; "redirect_uri" = $ocfg.redirect; "code" = $response.Get("code") }

	if($ocfg.clientSecret)
	{

		# http basic authorization header for token request
		$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($ocfg.clientID):$($ocfg.clientSecret)"))
		$basic = @{ "Authorization" = "Basic $b64"}
	}

	else
	{

		$basic =@{}
		$tokenRequest.client_id = $ocfg.clientID
	}

	# send token request
	Write-Verbose "token-request: $([pscustomobject]$tokenrequest)"
	$token = Invoke-RestMethod -Method Post -Uri $ocfg.tokUri -Headers $basic -Body $tokenrequest
	Write-Verbose "token-response: $($token)"
	return $token

}

#Internal function. Returns base64 encoded auth token for basic Authorizatioin header.
function Invoke-IdaptiveInternalBasicAuth ($id,$secret)
{
    # http basic authorization header for token request
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($id):$($secret)"))
    $basic = @{ "Authorization" = "Basic $b64"}
    return $basic
}

Export-ModuleMember -function Invoke-IdaptiveREST
Export-ModuleMember -function Invoke-IdaptiveInteractiveLoginToken
Export-ModuleMember -function Invoke-IdaptiveCertSsoLoginToken
Export-ModuleMember -function Invoke-IdaptiveOAuthCodeFlow
Export-ModuleMember -function Invoke-IdaptiveOAuthImplicit
Export-ModuleMember -function Invoke-IdaptiveOAuth-ClientCredentials
Export-ModuleMember -function Invoke-IdaptiveOAuthResourceOwner
