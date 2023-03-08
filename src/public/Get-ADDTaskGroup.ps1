function Get-ADDTaskGroup {
    <#
    .SYNOPSIS
        Helper function to quickly retrieve model Task Delegation Groups for use in reporting, or for piping to other module cmdlets

    .DESCRIPTION
        Function is capable of retrieving Task Delegation Groups for any level of the structure. All values returned by the cmdlet are
        returned as DirectoryEntry objects. Either a class type, or an OU distinguishedName path must be provided.

    .PARAMETER OUPath
        Specify the fully qualified distinguished name of a ZTAD OU for which to retrieve associated Task Delegation Groups. Cannot be
        used with other parameters.

    .PARAMETER Class
        Retrieves all Task Delegation Groups for a specific AD class. Cannot be used with the OUPath parameter.

    .PARAMETER Tier
        Can be used with the Class parameter to filter the objects returned to only a specific AD Risk Tier. Cannot be used with the 
        OUPath parameter.

    .PARAMETER Focus
        Can be used with the Class and Tier parameters to filter the objects returned to only a specific Focus type. Cannot be used 
        with the OUPath parameter. Accepts the following values:

        - Admin
        - Standard
        - Server

    .PARAMETER SL
        Can be used with the Class, Tier, and Focus parameters to filter the objects returned to only a specifc Scope. Cannot be used
        with the OUPath parameter.

    .EXAMPLE
        PS C:\> Get-ADDTaskGroup -OUPath 'OU=User,OU=GBL,OU=ADM,OU=Tier-1,DC=Domain,DC=com' | Grant-ADDTDGRights

        The above command retrieves all Task Delegation Groups for admin accounts in Tier 1 and passes the results to the Grant-ADDTDGRights
        cmdlet, which will apply, or reapply, the associated ACLs for each group.

    .EXAMPLE
        PS C:\> Get-ADDTaskGroup -Class Users -Tier 1 -Focus Admin -SL GBL | Grant-ADDTDGRights

        The above command performs the same actions as the prior example.

    .EXAMPLE
        PS C:\> Get-ADDTaskGroup -Class Users -Tier 1 -Focus Admin | Export-CSV C:\Temp\TDGOutput.csv -NoTypeInformation

        The above command retrieves all User focused Task Delegation Groups for the Admin focus in Tier 1, then sends the results to a CSV file
        without including the object type information.

        Note: Since the objects returned are DirectoryEntry objects, additional adjustment is recommended before outputting to a file

    .INPUTS
		System.String
		System.DirectoryServices.DirectoryEntry

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry

    .NOTES
        Help Last Updated: 5/18/2022

        Cmdlet Version: 1.1.1
		Cmdlet Status: Release

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
    [CmdletBinding(DefaultParameterSetName="PathType")]
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [Parameter(ParameterSetName="PathType",Position=0,ValueFromPipeline=$true,Mandatory=$true)]
        [ValidatePattern('^(?:(?<ou>OU=(?<name>[^,]*)),)?(?:(?<path>(?:(?:OU)=[^,]+,?)+),)?(?<domain>(?:DC=[^,]+,?)+)$')]
        [String[]]
        $OUPath,

        [Parameter(ParameterSetName="ObjRef",Position=0,Mandatory=$true)]
        [String]
        $ReferenceID,

        [Parameter(ParameterSetName="ObjRef")]
        [Parameter(ParameterSetName="Task")]
        [ValidateRange(0,2)]
        [Int]
        $Tier,

        [Parameter(ParameterSetName="ObjRef")]
        [Parameter(ParameterSetName="Task")]
        [String]
        $SL,

        [Parameter(ParameterSetName="Task",Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$true)]
        [SupportsWildCards()]
        [String]
        $TaskName
    )

    Begin {
        if ($script:ThisModuleLoaded -eq $true) {
            Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        }
        #TODO: Add callerpref to other functions

        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""

        $Tattrib = $AttributeHash["Tier"]
        $Fattrib = $AttributeHash["Focus"]
        $Sattrib = $AttributeHash["Scope"]
        $Oattrib = $AttributeHash["ObjRef"]

        $SearchHash = @{}

        $Output = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry] 

        $ProcessedCount = 0
        $FailedCount = 0
        $GCloopCount = 1
        $loopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()

        Write-Verbose ""
    }

    Process {
		Write-Verbose ""
		Write-Verbose "`t`t****************** Start of loop ($loopCount) ******************"
		Write-Verbose ""
		$loopTimer.Start()

		# Enforced .NET garbage collection to ensure memory utilization does not balloon
		if($GCloopCount -eq 30){
			Invoke-MemClean
			$GCloopCount = 0
		}

        Write-Verbose "$($FunctionName):`t ParameterSetName Switch:`t $($pscmdlet.ParameterSetName)"

        switch ($pscmdlet.ParameterSetName) {
            "PathType" {
                $TDGNamePrefix = $null

                $TDGElements = ConvertTo-Elements -SourceValue $OUPath

                if ($TDGElements.TierID) {
                    $TDGNamePrefix = "$($TDGElements.TierID)_"
                }else {
                    break
                }
                
                if ($TDGElements.FocusID) {
                    $TDGNamePrefix = $TDGNamePrefix + "$($TDGElements.FocusID)"
                }else {
                    $TDGNamePrefix = $TDGNamePrefix + '*'
                }

                if ($TDGElements.OrgL1) {
                    $TDGNamePrefix = $TDGNamePrefix + "_$($TDGElements.OrgL1)"
                }else {
                    $TDGNamePrefix = $TDGNamePrefix + '*'
                }

                if($TDGElements.ObjectTypeRefID){
                    $TDGNamePrefix = $TDGNamePrefix + "-$($TDGElements.ObjectTypeRefID)"                   
                }

                if ($null -ne $TDGNamePrefix) {
                    $Groups = Find-ADDADObject -ADClass Group -ADAttribute sAMAccountName -SearchString "$($TDGNamePrefix)*"
                }else {
                    break
                }
            }

            "ObjRef" {
                $SearchHash.Add("$Oattrib","TDG")
                $SearchHash.Add("sAMAccountName","*$($ReferenceID)*")

                if($Tier){
                    $SearchHash.Add("$Tattrib","$Tier")
                }

                if($SL){
                    $SearchHash.Add("$Sattrib","$SL")
                }

                Write-Verbose "$($FunctionName):`t SearchHash Values:`t $SearchHash"
                $Groups = Find-ADDADObject -ADClass Group -Collection $SearchHash

            }

            Default {
                $SearchHash.Add("$Oattrib","TDG")
                $SearchHash.Add("sAMAccountName","*$TaskName")

                if($Tier){
                    $SearchHash.Add("$Tattrib","$Tier")
                }

                if($SL){
                    $SearchHash.Add("$Sattrib","$SL")
                }

                $Groups = Find-ADDADObject -ADClass Group -Collection $SearchHash
                
            }
        }

        if($null -ne $Groups -and $($Groups.GetType()) -notlike "*int"){
            foreach($grp in $Groups){
                if($($grp.GetType()) -notlike "*int"){
                    Write-Verbose "$($FunctionName):`t Grp Search Result:`t $grp"
                    Write-Verbose "$($FunctionName):`t Grp Search Result Type:`t $($grp.GetType())"
                    $Output.Add($grp)
                }
            }
        }else{
            Write-Host "No Results"
        }

        $GCloopCount ++
		$loopCount ++
		$loopTimer.Stop()
		$loopTime = $loopTimer.Elapsed.TotalSeconds
		$loopTimes += $loopTime
		Write-Verbose "`t`tLoop $($ProcessedCount) Time (sec):`t$loopTime"

		if($loopTimes.Count -gt 2){
			$loopAverage = [math]::Round(($loopTimes | Measure-Object -Average).Average, 3)
			$loopTotalTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 3)
			Write-Verbose "`t`tAverage Loop Time (sec):`t$loopAverage"
			Write-Verbose "`t`tTotal Elapsed Time (sec):`t$loopTotalTime"
		}
		$loopTimer.Reset()
		Write-Verbose ""
		Write-Verbose "`t`t****************** End of loop ($loopCount) ******************"
		Write-Verbose ""
    }

    End {
		Write-Verbose ""
		Write-Verbose ""
		Write-Verbose "Wrapping Up"
		Write-Verbose "`t`tTDGs procesed:`t$ProcessedCount"
		Write-Verbose "`t`tTDGs failed:`t$FailedCount"
		$FinalLoopTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 0)
		$FinalAvgLoopTime = [math]::Round(($loopTimes | Measure-Object -Average).Average, 0)
		Write-Verbose "`t`tTotal time (sec):`t$FinalLoopTime"
		Write-Verbose "`t`tAvg Loop Time (sec):`t$FinalAvgLoopTime"
		Write-Verbose ""

        Write-Output $Output

        Write-Verbose "------------------- $($FunctionName): End -------------------"
		Write-Verbose ""
    }
}