#This example is currently broken.

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
    [Parameter(Mandatory=$true)]
    [string]$username,
    [string]$endpoint = "https://pod0.idaptive.app"
)

# Get the directory the example script lives in
$exampleRootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import the Idaptive.Samples.Powershell module
Import-Module $exampleRootDir\module\Idaptive-Powershell.psd1 3>$null 4>$null

# If Verbose is enabled, we'll pass it through
$enableVerbose = ($PSBoundParameters['Verbose'] -eq $true)

# Import sample function definitions
. $exampleRootDir\functions\Idaptive-IssueUserCert.ps1
. $exampleRootDir\functions\Idaptive-Query.ps1


try
{
    # MFA login and get a bearer token as the provided user, uses interactive Read-Host/Write-Host to perform MFA
    #  If you already have a bearer token and endpoint, no need to do this, just start using Invoke-IdaptiveREST
    if($null -eq $token)
    {
      $token = Invoke-IdaptiveInteractiveLoginToken -Username $username -Endpoint $endpoint -Verbose:$enableVerbose
    }

    # Issue a certificate for the logged in user. This only needs to be called once.
    #$userCert = IssueUserCert -Endpoint $token.Endpoint -BearerToken $token.BearerToken

    #Write user cert to file. This only needs to be called once. File location can be customized as needed.
    #$certificateFile = $username + "_certificate.p12"
    #$certbytes = [Convert]::FromBase64String($userCert)
    #[io.file]::WriteAllBytes("C:\\" + $certificateFile,$certBytes)

    #Get a certificate from file for use instead of MFA login. This can be called after IssueUserCert has been completed and the certificate has been written to file.
    #$certificate = new-object System.Security.Cryptography.X509Certificates.X509Certificate2("C:\\$certificateFile")

    #Negotiate an ASPXAUTH token from a certificate stored on file. This replaces the need for Idaptive-InteractiveLogin-GetToken. This can be called after IssueUserCert has been completed and the certificate has been written to file.
    #$token = Invoke-IdaptiveCertSsoLoginToken -Certificate $certificate -Endpoint $endpoint -Verbose:$enableVerbose

    # Get information about the user who owns this token via /security/whoami
    $userInfo = Invoke-IdaptiveREST -Endpoint $token.Endpoint -Method "/security/whoami" -Token $token.BearerToken -Verbose:$enableVerbose
    Write-Host "Current user: " $userInfo.Result.User

      #Enter the hostname of the system and the name of the set below
      $computer = "mduggan-mbp"
      $systemset = "OS X"
      #Note that the HostName is case-sensitive and both the HostName and SetName must exist in CPS prior to executing this script

      $systemkey = ""
      $servertable = "Server"

      #get the system ID
      $query = "select ID from Device where Name = '$computer'"
      $systemquery = Query -Endpoint $token.Endpoint -BearerToken $token.BearerToken -Query $query
      $systemkey = $systemquery.Results[0].Row.ID
      if ($systemkey.Length -gt 0)
      {
        #get system set ID
        $setid = GetSetID -Endpoint $token.Endpoint -BearerToken $token.BearerToken -ObjectType "Device" -name $systemset

        if ($setid -ne 0)
        {
            Write-Host "Adding system $computer to $systemset set..."
            UpdateMembersCollection -Endpoint $token.Endpoint -BearerToken $token.BearerToken -ID $setid -key $systemkey -table $servertable
        }else{
            Write-Host "Set $systemset not found...aborted member add. Please check that this set exists already in your Idaptive instance and that you have permissions to edit the set."
        }

      }else{
        Write-Host "$computer not found...aborted member add. Please check the import CSV file and ensure that the HostName for this object is correct in case-sensitivity and spelling."
      }

    # We're done, and don't want to use this token for anything else, so invalidate it by logging out
    #$logoutResult = Invoke-IdaptiveREST -Endpoint $token.Endpoint -Method "/security/logout" -Token $token.BearerToken -Verbose:$enableVerbose
}
finally
{
    # Always remove the Idaptive-Powershell module, makes development iteration on the module itself easier
    Remove-Module Idaptive-Powershell 4>$null
}
