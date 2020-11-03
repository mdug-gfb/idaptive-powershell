# Copyright 2016 Idaptive Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[CmdletBinding()]
param(
    #Used for interactive auth only. Comment out for OAuth
    [Parameter(Mandatory=$true)]
    [string]$username = "",
    [string]$endpoint = "https://pod0.idaptive.app"
)

$domain="@"+$username.Split("@")[1]
# Get the directory the example script lives in
$exampleRootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import the Idaptive.Samples.Powershell  and Idaptive-CPS modules 
Import-Module $exampleRootDir\module\Idaptive-Powershell.psd1 3>$null 4>$null

# If Verbose is enabled, we'll pass it through
$enableVerbose = ($PSBoundParameters['Verbose'] -eq $true)

# Import sample function definitions
. $exampleRootDir\functions\Idaptive-IssueUserCert.ps1
. $exampleRootDir\functions\Idaptive-Query.ps1
. $exampleRootDir\functions\Idaptive-GetUPData.ps1
. $exampleRootDir\functions\Idaptive-GetRoleApps.ps1
. $exampleRootDir\functions\Idaptive-CreateUser.ps1
. $exampleRootDir\functions\Idaptive-SetUserState.ps1
. $exampleRootDir\functions\Idaptive-HandleAppClick.ps1
. $exampleRootDir\functions\Idaptive-CheckProxyHealth.ps1
. $exampleRootDir\functions\Idaptive-GetNicepLinks.ps1
. $exampleRootDir\functions\Idaptive-GetPolicyBlock.ps1
. $exampleRootDir\functions\Idaptive-SavePolicyBlock3.ps1


try
{
    # MFA login and get a bearer token as the provided user, uses interactive Read-Host/Write-Host to perform MFA
    #  If you already have a bearer token and endpoint, no need to do this, just start using Invoke-IdaptiveREST
    if($null -eq $token)
    {
        $token = Invoke-IdaptiveInteractiveLoginToken -Username $username -Endpoint $endpoint -Verbose:$enableVerbose    
    }

    #Authorization using OAuth2 Auth Code Flow.
    #$token = Invoke-IdaptiveOAuthCodeFlow -Endpoint $endpoint -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope" -Verbose:$enableVerbose    

    #Authorization using OAuth2 Implicit Flow. 
    #$token = Invoke-IdaptiveOAuthImplicit -Endpoint $endpoint -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Scope "scope" -Verbose:$enableVerbose    

    #Authorization using OAuth2 Client Credentials Flow. If interactive or MFA is desired, use OnDemandChallenge APIs https://developer.idaptive.com/reference#post_security-ondemandchallenge
    #$token = Invoke-IdaptiveOAuthClientCredentials  -Endpoint $endpoint -Appid "applicationId" -Clientid "mduggan@goldfinchbio.com" -Clientsecret "clientSec" -Scope "scope" -Verbose:$enableVerbose    

    #Authorization using OAuth2 Resopurce Owner Flow. If interactive or MFA is desired, use OnDemandChallenge APIs https://developer.idaptive.com/reference#post_security-ondemandchallenge
    #$token = Idaptive-OAuthResourceOwner -Endpoint $endpoint -Appid "applicationId" -Clientid "client@domain" -Clientsecret "clientSec" -Username "user@domain" -Password "password" -Scope "scope" -Verbose:$enableVerbose

    # Issue a certificate for the logged in user. This only needs to be called once.
    #$userCert = IssueUserCert -Endpoint $token.Endpoint -BearerToken $token.BearerToken

    #Write user cert to file. This only needs to be called once. File location can be customized as needed.
    #$certificateFile = $username + "_certificate.p12"
    #$certbytes = [Convert]::FromBase64String($userCert)
    #[io.file]::WriteAllBytes("C:\\" + $certificateFile,$certBytes)

    #Get a certificate from file for use instead of MFA login. This can be called after IssueUserCert has been completed and the certificate has been written to file.
    #$certificate = new-object System.Security.Cryptography.X509Certificates.X509Certificate2("C:\\$certificateFile")

    #Negotiate an ASPXAUTH token from a certificate stored on file. This replaces the need for Idaptive-InteractiveLogin-GetToken. This can be called after IssueUserCert has been completed and the certificate has been written to file.
    #$token = Idaptive-CertSsoLogin-GetToken -Certificate $certificate -Endpoint $endpoint -Verbose:$enableVerbose
            
    # Get information about the user who owns this token via /security/whoami     
    $userInfo = Invoke-IdaptiveREST -Endpoint $token.Endpoint -Method "/security/whoami" -Token $token.BearerToken -Verbose:$enableVerbose     
    Write-Host "Current user: " $userInfo.Result.User
    
    # Run a query for top user logins from last 30 days
    $query = "select NormalizedUser as User, Count(*) as count from Event where EventType = 'Cloud.Core.Login' and WhenOccurred >= DateFunc('now', '-30') group by User order by count desc"
    $queryResult = Query -Endpoint $token.Endpoint -BearerToken $token.BearerToken -Query $query            
    Write-Host "Query resulted in " $queryResult.FullCount " results, first row is: " $queryResult.Results[0].Row    
        
    # Get user's assigned applications
    $myApplications = GetUPData -Endpoint $token.Endpoint -BearerToken $token.BearerToken
    foreach($app in $myApplications)
    {
        Write-Host "Assigned to me => Name: " $app.DisplayName " Key: " $app.AppKey " Icon: " $app.Icon
    } 
    
    # Get apps assigned to sysadmin role
    #$sysadminApps = GetRoleApps -Endpoint $token.Endpoint -BearerToken $token.BearerToken -Role "sysadmin"
    foreach($app in $sysadminApps)
    {
        Write-Host "Assigned to sysadmin role members => Key: " $app.Row.ID
    }    
    
    # Create a new Idaptive Cloud Directory user
    $newUserUUID = CreateUser -Endpoint $token.Endpoint -BearerToken $token.BearerToken -Username "apitest+$domain" -Password "newP@3651awdF@!%^"
    Write-Host "Create user result: " $newUserUUID
                   
    # Lock a Idaptive Cloud Directory user
    SetUserState -Endpoint $token.Endpoint -BearerToken $token.BearerToken -UserUuid $newUserUUID -NewState "Locked"

    # Unlock a Idaptive Cloud Directory user            
    SetUserState -Endpoint $token.Endpoint -BearerToken $token.BearerToken -UserUuid $newUserUUID -NewState "None"
        
    # Update the credentials for my UP app...
    #UpdateApplicationDE -Endpoint $token.Endpoint -BearerToken $token.BearerToken -AppKey "someAppKeyFromGetUPData" -Username "newUsername" -Password "newPassword"  
    
    # Simulate an App Click and return SAML Response...
    $appClickResult = HandleAppClick -Endpoint $token.Endpoint -BearerToken $token.BearerToken -AppKey "use-app-key"   
    # Parse out SAML Response
    $appClickResult -match "value=(?<content>.*)/>" 
    #Clean SAML Response
    $SAMLResponse = $matches['content'].Replace('"', "")
    #Print SAML Response
    Write-Host $SAMLResponse
    
    # Check Cloud Connector Health
    #Get a list of connectors registered to a tenant using a Redrock Query and then loop through the connector list and write results to file.
    $connectorUuidList = Query -Endpoint $token.Endpoint -BearerToken $token.BearerToken -Query "select MachineName, ID from proxy"     
    foreach($row in $connectorUuidList.Results)
    {
        Write-Host "Checking health of Cloud Connector on" $row.Row.MachineName
        $connectorHealth = CheckProxyHealth -Endpoint $token.Endpoint -BearerToken $token.BearerToken -ProxyUuid $row.Row.ID
        $connectorHealth.Connectors| ConvertTo-Json | Out-File -Append ("C:\temp\" + $row.Row.MachineName + ".json")        
    }

    #Get/Save Policy
    $getPolicyLinksResult = GetNicepLinks -Endpoint $token.Endpoint -BearerToken $token.BearerToken
    $policy=$getPolicyLinksResult.Results[0].Row.ID
    $getPolicyBlockResult = GetPolicyBlock -Endpoint $token.Endpoint -BearerToken $token.BearerToken -Name $policy
    #$savePolicyBlock = SavePolicyBlock -Endpoint $token.Endpoint -BearerToken $token.BearerToken -PolicyJsonBlock $getPolicyBlockResult.Settings

    # We're done, and don't want to use this token for anything else, so invalidate it by logging out
    #$logoutResult = Invoke-IdaptiveREST -Endpoint $token.Endpoint -Method "/security/logout" -Token $token.BearerToken -Verbose:$enableVerbose           
}
finally
{
    # Always remove the Idaptive.Samples.Powershell and Idaptive-CPS modules, makes development iteration on the module itself easier
    Remove-Module Idaptive-Powershell 4>$null
}