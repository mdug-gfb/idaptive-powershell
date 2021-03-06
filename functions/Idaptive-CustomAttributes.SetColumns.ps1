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

function SetColumns {
    param(
        [Parameter(Mandatory=$true)]
        $endpoint,
        [Parameter(Mandatory=$true)]
        $bearerToken,
        [Parameter(Mandatory=$true)]
        $column,
        [Parameter(Mandatory=$false)]
        $value,
        [Parameter(Mandatory=$false)]
        $id,
        [Parameter(Mandatory=$false)]
        $table

                  
    )
    
    $restArg = @{}
    $restArg.Columns = @{}
    $restArg.Columns.$column = $value #Column to update and its value
    $restArg.ID = $id #User UUID
    $restArg.Table = $table #Normally set to users
    
    $restResult = Invoke-IdaptiveREST -Method "/ExtData/SetColumns" -Endpoint $endpoint -Token $bearerToken -ObjectContent $restArg -Verbose:$enableVerbose
    if($restResult.success -ne $true)
    {
        throw "Server error: $($restResult.Message)"
    }     
    
    return $restResult.Result
}
