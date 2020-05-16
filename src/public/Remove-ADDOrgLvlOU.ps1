function New-ADDOrgLvlOU {
<#
    .SYNOPSIS
        Short description

    .DESCRIPTION
        Long description

    .PARAMETER CreateLevel
        Used to indicate if the entire structure should be deployed, or only up to a specific point. Acceptable values for this parameter are as follows:

            ORG - Deploys only the Organizatinal (all) OU level
            OBJ - Deploys all OU levels, but does not deploy Task Delegation Groups or ACLs
            TDG - Deploys all OU levels and Task Delegation Groups, but does not configure related ACLs
            ALL - Deploys all elements of the structure except placeholder Group Policy Objects (Default)

        If this parameter is not specified, or a value is not provided, the ALL option will be used by default. This parameter only applies when this cmdlet
        is directly invoked. If this cmdlet is invoked via Publish-ADDESAEStructure instead, each element is individually executed for operational efficiency.

    .PARAMETER StartOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path, instead of underneath a Focus OU. You should
        provide the value as a string in distinguishedName format (ex. "OU=OUname,DC=MYDOMAIN,DC=NET"), though a simple name can also be specified provided the
        target is located in the root of the domain.

        SPECIAL NOTE: Using this option in a non-standard location (A Focus OU) may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups
        with the appropriate names as this option is still experimental.

    .PARAMETER TargetOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path, instead of underneath a Focus OU. This value
        must be the output from the Get-ADOrganizationalUnit cmdlet that is part of the Microsoft ActiveDirectory module.

        SPECIAL NOTE: Using this option in a non-standard location (A Focus OU) may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups
        with the appropriate names as this option is still experimental.

    .PARAMETER ChainRun
        This switch causes objects required for the next stage of execution to be returned to the pipeline for additional scrutinty or action. This switch is
        only intended to be called by internal cmdlets, such as when this cmdlet is invoked by the Publish-ADDESAEStructure cmdlet, or another upstream cmdlet,
        during chained execution.

        .PARAMETER PipelineCount
        This parameter allows the number of objects being passed to this cmdlet via the pipeline to be specified. This value is used when presenting the progress
        indicator during execution. If this value is not provided, the progress window will display the current activity, but cannot indicate the completion
        percent as PowerShell is unable to determine how many objects are pending.

    .PARAMETER TargetOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path. This value must be a DirectoryEntry type object
        using the ADSI type accelerator. Typically this value is only specified internally by the Publish-ADDESAEStructure cmdlet, or another upstream cmdlet,
        during chained execution.

        SPECIAL NOTE: Using this option in a non-standard location (A Focus OU) may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups
        with the appropriate names as this option is still experimental.

    .EXAMPLE
        #TODO: Add at least two examples
        Example of how to use this cmdlet

    .EXAMPLE
        Another example of how to use this cmdlet

    .INPUTS
        Microsoft.ActiveDirectory.Management.ADOrganizationalUnit
            If the ActiveDirectory module is available, the Get-ADOrganizationalUnit cmdlet can be used to obtain pipeline values for TargetOU, or
            a single OU object can be specified as the value as a named parameter

        System.String
            A simple string can be passed via the pipeline, or as a named parameter, to provide a starting point similar to TargetOU. This value should
            be in DistinguishedName format, though it can also be a simple name provided the target OU is located in the root of the domain

        System.DirectoryServices.DirectoryEntry
            A single DirectoryEntry object, or an array of such objects, can be either passed via the pipeline, or provided as a single value with a named
            parameter

        System.Integer
            A single integer

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry

    .NOTES
        Help Last Updated: 10/22/2019

        Cmdlet Version: 0.9.0 - Beta

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Low')]
    param (
        [Parameter(ParameterSetName="ManualRun")]
        [ValidateSet("ORG","OBJ","TDG","ALL")]
        [string]$CreateLevel,

        [Parameter(ParameterSetName="ManualRun",Mandatory=$true,Position=0)]
        [string[]]$StartOU,

        [Parameter(ParameterSetName="ManualRun",Mandatory=$true,Position=1,ValueFromPipelineByPropertyName=$true)]
        [string]$Level1,

        [Parameter(ParameterSetName="ManualRun",Mandatory=$false,Position=2,ValueFromPipelineByPropertyName=$true)]
        [string]$Level1Display,

        [Parameter(ParameterSetName="ChainRun")]
        [int]$PipelineCount,

        [Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.DirectoryServices.DirectoryEntry]$TargetDE,

        [Parameter(DontShow,ParameterSetName="ChainRun")]
        [Switch]$MTRun
    )

    begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "$($LP)------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        Write-Verbose "$($LPB1)Run Type:`t$($pscmdlet.ParameterSetName)"
        Write-Verbose "$($LPB1)Setting supplemental run values..."

        #TODO: Update WhatIf processing support to match New-ADDTopLvlOU cmdlet

        if($pscmdlet.ParameterSetName -like "ManualRun"){
            $ChainRun = $false

            switch ($CreateLevel) {
                "TDG" {$CreateVal = 3}
                "OBJ" {$CreateVal = 2}
                "ORG" {$CreateVal = 1}
                Default {$CreateVal = 4}
            }

            Write-Verbose "$($LPB2)CreateVal:`t$CreateVal"
        }else {
            $ChainRun = $true
        }

        if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
            Write-Verbose "Pipeline:`tDetected"
            $Pipe = $true

			if($MTRun){
                $ProgParams = @{
                    Id = 25
                    ParentId = 20
                }
			}else {
                $ProgParams = @{
                    Id = 15
                    ParentId = 10
                }
            }

			if($PipelineCount -gt 0){
				$TotalItems = $PipelineCount
            }

            Write-Progress @ProgParams -Activity "Creating Org OUs" -CurrentOperation "Initializing..."

		}

        $FinalOrgOUObjs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        $WFFinalOrgOUObjs = New-Object System.Collections.Generic.List[psobject]

        $TotalOrgItems = $OUOrg.Count
        $ProcessedCount = 0
        $OrgProcessedCount = 0
        $FailedCount = 0
        $ExistingCount = 0
        $NewCount = 0
        $GCloopCount = 1
        $loopCount = 1
        $subloopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $subloopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()

        Write-Verbose ""
    }

    process {
		Write-Verbose ""
		Write-Verbose "$($LPP1)****************** Start of loop ($loopCount) ******************"
		Write-Verbose ""
        $loopTimer.Start()







        $ProcessedCount ++
        $loopCount ++
        $GCloopCount ++
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

    end {
        $TotalOrgProcessed = $Org1ItemsProcessed + $Org2ItemsProcessed + $Org3ItemsProcessed
        Write-Verbose ""
        Write-Verbose ""
        Write-Verbose "Wrapping Up"
        Write-Verbose "`t`tSource Paths Procesed:`t$ProcessedCount"
        Write-Verbose "`t`tOrg OUs Processed:`t$TotalOrgProcessed"
        Write-Verbose "`t`tNew Org OUs Created:`t$NewCount"
        Write-Verbose "`t`tPre-Existing Org OUs:`t$ExistingCount"
        Write-Verbose "`t`tFailed Org OUs:`t$FailedCount"
        Write-Verbose ""
        Write-Verbose ""

        if($Pipe){
            Write-Progress -Id 25 -Activity "Deploying" -CurrentOperation "Finished" -Completed -ParentId 20
            Write-Progress -Id 20 -Activity "Creating OUs" -CurrentOperation "Finished" -Completed -ParentId 10
        }

        if($CreateVal -gt 1) {
            Write-Verbose "$($LPB1)Manual Run and CreateVal greater than 1 - Passing results to New-ADDOrgLvlOU"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            $FinalOrgOUObjs | New-ADDObjLvlOU -PipelineCount $($FinalFocusLevelOUs.Count)
        }else {
            Write-Verbose "$($LPB1)Chain Run or CreateVal of 1 - Returning results to caller"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            return $FinalOrgOUObjs
        }
    }
}