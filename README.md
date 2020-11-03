# Idaptive.Samples.PowerShell

Notes: This package contains code samples for the Idaptive Identity Service Platform API's written in PowerShell. Please use PowerShell version 4 or above. 

The sample is broken into 3 parts:

  1. module/Idaptive.Samples.PowerShell.psm1 - This is a PowerShell module which can be included with Import-Module.  The 
  module provides an MFA implementation for interactive authentication, as well as a wrapper for invoking Idaptive REST api's.
  2. Idaptive.Samples.PowerShell.Example.ps1 - This is an example script, which import's the Idaptive.Samples.PowerShell module
  as well as a library of functions (functions/*) for common REST api endpoints.
  3. functions/*.ps1 - A set of functions broken into individual files exhibit how to invoke specific APIs using the 
  Idaptive.Samples.Powershell module. 
 

Sample Functionality Includes:

    1. Utilizing interactive MFA to authenticate a user and retrieve a session for interacting with the platform
    2. Issuing a certificate for a user
    3. Negotiating a authentication token from a certificate
    4. Issuing queries to the report system
    5. Updating credentials on a UsernamePassword application
    6. Getting assigned apps (User Portal view)
    7. Getting assigned apps by role
    8. Creating a new CUS user
    9. Locking/Unlocking a CUS user
   
For support, please contact devsupport@idaptive.app
