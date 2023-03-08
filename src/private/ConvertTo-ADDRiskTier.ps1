function ConvertTo-ADDRiskTier {
<#
    .SYNOPSIS
        Converts a numerical value from a TierAssoc data value into AD Risk Tier identifiers

    .DESCRIPTION
        Support function to convert TierAssoc integer values from the DB into one or more AD Risk Tier identifiers. Used
        by other cmdlets to determine which tier or tiers a given item should be associated with. Can also be used to simply
        test whether the integer value would be part of a specific tier, returning a boolean value instead of the resulting Tier.

    .PARAMETER intValue
        Source value to be converted

    .PARAMETER ReturnFull
        Switch that indicates the full name for the Tier should be returned instead of the short name

    .PARAMETER testValue
        Providing this value along with the integer will return a value of true or false.

    .EXAMPLE
        PS C:\> $result = ConvertTo-ADDRiskTier -intValue 4

        PS C:\> $result
        T0
        T1

        The above takes a value of 4, and returns an array with the shortname tier indicators for Tiers 0 and 1

    .EXAMPLE
        PS C:\> $result = ConvertTo-ADDRiskTier -intValue 2 -ReturnFull

        PS C:\> $result
        Tier-1

        The above takes a value of 2 and, because of the use of the ReturnFull switch, returns a value of 'Tier-1'

    .EXAMPLE
        PS C:\> ConvertTo-ADDRiskTier -intValue 2 -testValue "Tier-1"
        True

        The above command tests whether the supplied integer, which comes from the DB, would be part of Tier-1, 
        which produces a value of 2.

    .NOTES
        Help Last Updated: 11/16/2021

        Cmdlet Version: 1.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding(DefaultParameterSetName="Convert")]
    param (
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="Convert")]
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="Test")]
        [int]$intValue,
        [Parameter(ParameterSetName="Convert")]
        [switch]$ReturnFull,
        [Parameter(Mandatory=$true,Position=1,ParameterSetName="Test")]
        [ValidateSet("T0","T1","T2","Tier-0","Tier-1","Tier-2")]
        [string]$testValue
    )

    $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
    Write-Verbose ""
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t`t`tintValue - $intValue"
    Write-Verbose "`t`t`t`t`t`t`t`tReturnFull - $ReturnFull"
    Write-Verbose "`t`t`t`t`t`t`t`ttestValue - $testValue"
    
    $return = @()

    if($null -ne $ReturnFull -or $($testValue.Length) -gt 2){
        switch ($intValue) {
            { $intValue -in @(0,1,4,6) } {$return += ("Tier-0")}
            { $intValue -in @(0,2,4,5) } {$return += ("Tier-1")}
            { $intValue -in @(0,3,5,6) } {$return += ("Tier-2")}
        }
    }else {
        switch ($intValue) {
            { $intValue -in @(0,1,4,6) } {$return += ("T0")}
            { $intValue -in @(0,2,4,5) } {$return += ("T1")}
            { $intValue -in @(0,3,5,6) } {$return += ("T2")}
        }
    }

    if($testValue){
        if($testValue -in $return){
            $return = $true
        }else{
            $return = $false
        }
    }else{
        $return
    }

    Write-Verbose "$($FunctionName): `t$return"
    Write-Output $return
}
