function Find-ADDADObject {
<#
    .SYNOPSIS
        Helper function to quickly retrieve model OUs for use elsewhere

    .DESCRIPTION
        Function is capable of retrieving OUs at any level of the structure. When specifying the OULevel, all available OUs for
        the specified level are returned as DirectoryEntry objects. By default, all OUs are retrieved.

    .PARAMETER OULevel
        Tells the function which level of the ESAE OU structure to retrieve

    .EXAMPLE
        PS C:\> Get-ADDOrgUnits -OULevel CLASS | New-ADDTaskGroup

        The above command retrieves all AD class OUs (Users, Groups, Workstations, etc), and passes it to the New-ADDTaskGroup cmdlet to initiate
        creation of the associated Task Delegation Groups for each OU. The New-ADTaskGroup cmdlet will return DirectoryEntry objects to the pipeline.

   .NOTES
        Help Last Updated: 5/18/2022

        Cmdlet Version: 1.2
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding()]
    [OutputType('System.Collections.Generic.List')]
    Param(
        [Parameter()]
        [String]$ADClass,

        [Parameter(ParameterSetName="Single")]
        [String]$ADAttribute,

        [Parameter(ParameterSetName="Single")]
        [SupportsWildCards()]
        [String[]]$SearchString,

        [Parameter()]
        [string]$SearchRoot,

        [Parameter(ParameterSetName="Group")]
        [System.Collections.Hashtable]
        $Collection
    )

    $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
    Write-Verbose "$($LP)`t`t------------------- $($FunctionName): Start -------------------"
    Write-Verbose ""

    $Results = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]

    $searcher = New-Object System.DirectoryServices.DirectorySearcher
    if($SearchRoot){
        $searcher.SearchRoot = $SearchRoot
    }else{
        $searcher.SearchRoot = "LDAP://$DomDN"
    }
    $searcher.PageSize = 200
    $searcher.SizeLimit = 20000

    foreach($prop in $($AttributeHash.Values)){
        Write-Verbose "$($FunctionName):`t Adding Property to return:`t $prop"
        $searcher.PropertiesToLoad.Add($prop)
    }

    Write-Verbose "$($FunctionName):`t ParameterSetName Value:`t $($pscmdlet.ParameterSetName)"

    switch ($($pscmdlet.ParameterSetName)) {
        "Single" {
            if($($SearchString.Count) -gt 1){
                $Filter = "(&(objectClass=$ADClass)(|"
                foreach($str in $SearchString){
                    $Filter = "$Filter($ADAttribute=$str)"
                }
                $Filter = "$Filter))"
            }else{
                $Filter = "(&(objectClass=$ADClass)($ADAttribute=$SearchString))"
            }    
        }

        Default {
            $Filter = "(&(objectClass=$ADClass)"

            foreach($key in $Collection.Keys){
                $Filter = "$Filter({0}={1})" -f $key, $Collection[$key]
            }

            $Filter = "$Filter)"
            Write-Verbose "$($FunctionName)"
        }
    }

    Write-Verbose "$($FunctionName):`t Search Filter:`t $Filter"
    $searcher.Filter = $Filter

    try {
        $Findings = $searcher.FindAll()
    }
    catch {

    }

    if($Findings){
        foreach($Finding in $Findings){
            Write-Verbose "$($FunctionName):`t Raw Finding Value:`t $Finding"
            $de = New-Object System.DirectoryServices.DirectoryEntry("$($Finding.Path)")
    
            if($de){
                $Results.Add($de)
            }
        }
    
    }

    Write-Output $Results
}