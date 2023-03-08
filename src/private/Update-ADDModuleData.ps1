function Update-ADDModuleData {
<#
    .SYNOPSIS
        Brief description of cmdlet

    .DESCRIPTION
        Detailed description of cmdlet

    .PARAMETER ParameterName
        Parameter description

    .EXAMPLE
        PS C:\> <example usage>
        Explanation of what the example does

    .NOTES
        Help Last Updated: 10/15/2020

        Cmdlet Version 1.0 - Release

        Copyright (c) Deloitte All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE file. This source code is provided 'AS IS',
        with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your own risk, and the author 
        assumes no liability.

    .LINK
        https://deloitte.com
#>
    
        [CmdletBinding()]
        param(
            [Parameter()]
            [ValidateSet("CoreOU","AD","OUData","ALL")]
            [string]$DataSet
        )
    
        if ($script:ThisModuleLoaded -eq $true) {
            Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        }

        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "$($LP)`t`t------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        #region CODE AREA

        switch ($DataSet) {
            "CoreOU" { 
                Write-Verbose "Initialize: Import core OU data"
                $Script:CoreOUs = Import-ADDModuleData -DataSet OUCore

                $TierHashTmp = @{}
                $CoreData | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$TierHashTmp.($_.OU_name) = $_.OU_focus}
                $Script:TierHash = $TierHashTmp
                $Script:TierRegEx = $($TierHash.Values -join "|")
                $TierDN = $TierHash.Values | ForEach-Object{"OU=$_"}
                $Script:TierDNRegEx = $($TierDN -join "|")

                $CETierHashTmp=@{}
                $CoreData | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$CETierHashTmp.($_.OU_focus) = $_.OU_name}
                $Script:CETierHash = $CETierHashTmp
                $Script:CETierRegEx = $($CETierHash.Values -join "|")
                $CETierDN = $CETierHash.Values | ForEach-Object{"OU=$_"}
                $Script:CETierDNRegEx = $($CETierDN -join "|")

                $FocusHashTmp = @{}
                $CoreData | Where-Object{$_.OU_type -like "Focus"} | ForEach-Object{$FocusHashTmp.($_.OU_focus) = $_.OU_name}
                $Script:FocusHash = $FocusHashTmp
                $Script:FocusRegEx = $($FocusHash.Values -join '|')
                $FocusDN = $FocusHash.Values | ForEach-Object{"OU=$_"}
                $Script:FocusDNRegEx = $($FocusDN -join "|")
            }

            "AD" {

            }

            "OUData" {
                $OrgData = Import-ADDModuleData -DataSet OUOrg
                $Script:OUOrg = $OrgData
            }

            Default {}
        }


        #endregion CODE AREA

}