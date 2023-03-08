function Remove-ADDOrgUnit {
<#
    .SYNOPSIS
        Deploys the ZTAD OU structure, or adds a new entry to the structure

    .DESCRIPTION
        This cmdlet will deploy the entirety of the registered ZTAZ OU structure within a new environment. 
        Alternatively, this cmdlet can accept values that will be used to create new branches within a 
        previously deployed structure.

    .PARAMETER TargetGroup
        Specify one or more groups by distinguished name to process TDGs for

    .PARAMETER PipelineCount
        Used to specity the number of objects being passed in the pipeline, if knownn, to use in showing progress

    .PARAMETER TargetDE
        Accepts one or more DirectoryEntry objects to process TDGs for

    .PARAMETER MTRun
        Only used when calling this cmdlet from the Publish-ADDZTADStructure -MultiThread command - modifies the behavior of progress

    .EXAMPLE
        PS C:\> Get-ADDOrgUnits -OULevel CLASS | New-ADDTaskGroup

        The above command retrieves all AD class OUs (Users, Groups, Workstations, etc), and passes it to the New-ADDTaskGroup cmdlet to initiate
        creation of the associated Task Delegation Groups for each OU. The New-ADTaskGroup cmdlet will return DirectoryEntry objects to the pipeline.

    .INPUTS
        System.String
        System.DirectoryServices.DirectoryEntry

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry

    .NOTES
        Help Last Updated: 5/16/2022

        Cmdlet Version: 1.1
        Cmdlet Status: Release

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>

    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ManualRun",ConfirmImpact='High')]
    param (
        [Parameter(ParameterSetName="ManualRun")]
        [ValidateRange(0,2)]
        [int]$Tier,

        [Parameter(ParameterSetName="ManualRun")]
        [ValidateScript({$_ -match $FocusRegEx})]
        [string]$Focus,

        [Parameter(ParameterSetName="ManualRun",ValueFromPipeline=$true,Mandatory=$true)]
        [string[]]$ScopeNode,

        [Parameter(ParameterSetName="ManualRun")]
        [Parameter(ParameterSetName="ManualRunB")]
        [switch]$KeepTDGs,

        [Parameter(ParameterSetName="ManualRunB",Mandatory=$true,ValueFromPipeline=$true)]
        [System.DirectoryServices.DirectoryEntry]$TargetDE,

        [Parameter(ParameterSetName="ManualRun")]
        [Parameter(ParameterSetName="ManualRunB")]
        [Parameter()]
        [switch]$Force
    )

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        if($Force){
            $ConfirmPreference = 'None'
        }

        $RemovedObjects = New-Object System.Collections.Generic.List[PSCustomObject]
        $FailedObjects = New-Object System.Collections.Generic.List[PSCustomObject]

        if($Tier){
            $T = "T$Tier"
            $TierList = @($CETierHash[$T])

            switch ($Tier) {
                0 { $TierAssoc = 1 }
                1 { $TierAssoc = 2 }
                2 { $TierAssoc = 3 }
            }

        }else{
            $TierList = @($($CETierHash.GetEnumerator()).Value)

            $TierAssoc = 0
        }

        if($Focus){
            $FocusList = @($Focus)
        }else{
            $FocusList = @($($FocusHash.GetEnumerator() | Where-Object{$_.name -notlike 'Stage'}).value)
        }

        $ProcessedCount = 0
        $FailedCount = 0
        $GCloopCount = 1
        $loopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()

        Write-Verbose ""
    } #End Begin block

    Process {
        Write-Verbose ""
        Write-Verbose "`t`t****************** $($FunctionName): Start of loop ($loopCount) ******************"
        Write-Verbose ""
        $loopTimer.Start()

        # Enforced .NET garbage collection to ensure memory utilization does not balloon 
        if($GCloopCount -eq 30){
            Invoke-MemClean
            $GCloopCount = 0
        }

        Write-Verbose "`t`t $($FunctionName): `t ParameterSetName:`t $($pscmdlet.ParameterSetName)"

        switch ($pscmdlet.ParameterSetName){
            "ManualRun" {
                foreach($Tier in $TierList){
                    Write-Verbose "`t`t $($FunctionName):`t Tier Provided:`t $($Tier)"
                    $ParentPath = "OU=Tier-$($Tier),$DomDN"

                    foreach($Focus in $FocusList){
                        if($ScopeNode -like $OUGlobal -and $Focus -like $($FocusHash["Admin"])){
                            Write-Error -Message "Global OU in Admin focus must be manually removed - skipping"
                        }else{
                            $DBColumn = "OU_$((($FocusHash.GetEnumerator() | Where-Object {$_.value -like $Focus}).key).ToLower())"
                            Write-Verbose "`t`t $($FunctionName):`t  Focus Provided:`t $($Focus) - Updating ParentPath"
                            $ParentPath = "OU=$($Focus),$ParentPath"
                            $ChildPath = "OU=$($ScopeNode),$ParentPath"
    
                            $ChildDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$ChildPath")
                            $ChildClassOUs = $ChildDE.psbase.Children
    
                            if($ChildClassOUs.count -gt 0){
                                $RemovedChildren = @()
    
                                foreach($ChildClass in $ChildClassOUs){
                                    $ChildClassName = $ChildClass.Name
                                    if($Force -or $pscmdlet.ShouldProcess("$ChildClassName","Remove class OUs for $ScopeNode")){
                                        $RemoveChildObj = Remove-ADDADObject -ObjName $ChildName -ObjType OrganizationalUnit -ObjParentDN $ChildPath
                                    }
    
                                    if($RemoveChildObj){
                                        switch ($RemoveChildObj.State) {
                                            "Removed" {
                                                $RemovedChildren += $RemoveChildObj
                                                $ProcessedCount ++
                                            }
    
                                            Default {
                                                Write-Error -Message "$($FunctionName): An error occurred attempting to delete the Class OU $ChildClassName object ($ChildPath)" -RecommendedAction "Correct Issue: $($RemoveObj.State)"
                                                $FailedObjects.Add($RemoveObj)
                                                $FailedCount ++        
                                            }
                                        }
                                    }
                                }
                            }
    
                            if($ChildClassOUs.count -eq $RemovedChildren.count){
                                if($Force -or $pscmdlet.ShouldProcess("$ScopeNode",'Remove Scope OU')){
                                    $RemoveObj = Remove-ADDADObject -ObjName $ScopeNode -ObjType OrganizationalUnit -ObjParentDN $ParentPath
                                }
    
                                if($RemoveObj){
                                    switch ($RemoveObj.State){
                                        "Removed" {
                                            $RemovedObjects.Add($RemoveObj)
                                            $ProcessedCount ++

                                            Write-Verbose "`t`t $($FunctionName):`t Updating Database"
                                            Export-ADDModuleData -DataSet "RemoveOrgEntry" -QueryValue $ScopeNode,$DBColumn,$TierAssoc

                                            Write-Verbose "`t`t $($FunctionName):`t Updating Variable"
                                            $OrgData = Import-ADDModuleData -DataSet OUOrg
                                            Set-Variable -Name OUOrg -Value $OrgData -Scope Script -Visibility Private
                                        }
    
                                        Default {
                                            Write-Error -Message "$($FunctionName): An error occurred attempting to delete the object ($ChildPath)" -RecommendedAction "Correct Issue: $($RemoveObj.State)"
                                            $FailedObjects.Add($RemoveObj)
                                            $FailedCount ++
                                        }
                                    }
                                }
                            }else{
                                Write-Error -Message "Failed to remove one or more child OUs from $ChildPath - Cannot remove $ScopeNode"
                            }
                        } #End IfElse - Global/Admin check
                    } #End Foreach - Focus
                } #End Foreach - Tier
            } #End SwitchOption - ManualRun

            "ManualRunB" {
                $PathParts = $(($TargetDE.DistinguishedName) -split ',')

                switch ($PathParts.count) {
                    {$_ -lt 5} {
                        Write-Warning -Message "The specified path value does not include a Scope layer OU and will not be actioned $($TargetDE.DistinguishedName)"
                    }

                    {$_ -eq 6} {
                        $ParentPath = "$(($TargetDE.DistinguishedName -split (',',3))[2])"
                        $ChildPath = "$(($TargetDE.DistinguishedName -split (',',2))[1])"
                    }

                    {$_ -eq 5} {
                        $ParentPath = "$(($TargetDE.DistinguishedName -split (',',2))[1])"
                        $ChildPath = "$($TargetDE.DistinguishedName)"
                    }

                    Default {
                        Write-Error -Message "Unable to determine correct path elements from value $($TargetDE.DistinguishedName)"
                    }
                }

                if($ChildPath){
                    $PIElements = ConvertTo-Elements -SourceValue $ChildPath

                    $ScopeNode = $PIElements.OrgL1
                    $Focus = $PIElements.Focus
                    $Tier = $PIElements.Tier

                    switch ($Tier) {
                        "T0" { $TierAssoc = 1 }
                        "T1" { $TierAssoc = 2 }
                        "T2" { $TierAssoc = 3 }
                    }
        
                    $DBColumn = "OU_$((($FocusHash.GetEnumerator() | Where-Object {$_.value -like $Focus}).key).ToLower())"

                    if($ScopeNode -like $OUGlobal -and $Focus -like $($FocusHash["Admin"])){
                        Write-Error -Message "Global OU in Admin focus must be manually removed - skipping"
                    }else{
                        $ChildDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$ChildPath")
                        $ChildClassOUs = $ChildDE.psbase.Children

                        if($ChildClassOUs.count -gt 0){
                            $RemovedChildren = @()

                            foreach($ChildClass in $ChildClassOUs){
                                $ChildClassName = $ChildClass.Name
                                if($Force -or $pscmdlet.ShouldProcess("$ChildClassName","Remove class OUs for $ScopeNode - Keep TDGs")){
                                    $RemoveChildObj = Remove-ADDADObject -ObjName $ChildName -ObjType OrganizationalUnit -ObjParentDN $ChildPath
                                }

                                if($RemoveChildObj){
                                    switch ($RemoveChildObj.State) {
                                        "Removed" {
                                            $RemovedChildren += $RemoveChildObj
                                            $ProcessedCount ++
                                        }

                                        Default {
                                            Write-Error -Message "$($FunctionName): An error occurred attempting to delete the Class OU $ChildClassName object ($ChildPath)" -RecommendedAction "Correct Issue: $($RemoveObj.State)"
                                            $FailedObjects.Add($RemoveObj)
                                            $FailedCount ++        
                                        }
                                    }
                                }
                            }
                        }

                        if($ChildClassOUs.count -eq $RemovedChildren.count){
                            if($Force -or $pscmdlet.ShouldProcess("$ScopeNode",'Remove Scope OU')){
                                $RemoveObj = Remove-ADDADObject -ObjName $ScopeNode -ObjType OrganizationalUnit -ObjParentDN $ParentPath
                            }

                            if($RemoveObj){
                                switch ($RemoveObj.State){
                                    "Removed" {
                                        $RemovedObjects.Add($RemoveObj)
                                        $ProcessedCount ++

                                        Write-Verbose "`t`t $($FunctionName):`t Updating Database"
                                        Export-ADDModuleData -DataSet "RemoveOrgEntry" -QueryValue $ScopeNode,$DBColumn,$TierAssoc

                                        Write-Verbose "`t`t $($FunctionName):`t Updating Variable"
                                        $OrgData = Import-ADDModuleData -DataSet OUOrg
                                        Set-Variable -Name OUOrg -Value $OrgData -Scope Script -Visibility Private
                                    }

                                    Default {
                                        Write-Error -Message "$($FunctionName): An error occurred attempting to delete the object ($ChildPath)" -RecommendedAction "Correct Issue: $($RemoveObj.State)"
                                        $FailedObjects.Add($RemoveObj)
                                        $FailedCount ++
                                    }
                                }
                            }
                        }else{
                            Write-Error -Message "Failed to remove one or more child OUs from $ChildPath - Cannot remove $ScopeNode"
                        }
                    }
                }
            }
        }

        if(-not($KeepTDGs)){
            Write-Verbose "`t`t $($FunctionName):`t Initiating TDG Cleanup"

            foreach($path in $RemovedObjects){
                $TDGDe = Get-ADDTaskGroup -OUPath $path.DEObj

                if($TDGDe){
                    foreach($TDG in $TDGDe){
                        $ParentPath = $(($TDG.DistinguishedName -split (',',2))[1])
                        $TDGName = $TDG.Name

                        if($Force -or $pscmdlet.ShouldProcess("$TDGName","Remove TDGs")){
                            $RemoveObj = Remove-ADDADObject -ObjName $TDGName -ObjType Group -ObjParentDN $ParentPath
                        }

                        if($RemoveObj){
                            switch ($RemoveObj.State){
                                "Removed" {
                                    $RemovedObjects.Add($RemoveObj)
                                    $ProcessedCount ++
                                }

                                Default {
                                    Write-Error -Message "$($FunctionName): An error occurred attempting to delete the object ($($TDG.DistinguishedName))" -RecommendedAction "Correct Issue: $($RemoveObj.State)"
                                    $FailedObjects.Add($RemoveObj)
                                    $FailedCount ++
                                }
                            }
                        }
                    }
                }
            }
        }

        $GCloopCount ++
        $loopCount ++
        $loopTimer.Stop()
        $loopTime = $loopTimer.Elapsed.TotalSeconds
        $loopTimes += $loopTime
        Write-Verbose "`t`t $($FunctionName): `tLoop $($ProcessedCount) Time (sec):`t$loopTime"

        if($loopTimes.Count -gt 2){
            $loopAverage = [math]::Round(($loopTimes | Measure-Object -Average).Average, 3)
            $loopTotalTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 3)
            Write-Verbose "`t`t $($FunctionName): `tAverage Loop Time (sec):`t$loopAverage"
            Write-Verbose "`t`t $($FunctionName): `tTotal Elapsed Time (sec):`t$loopTotalTime"
        }
        $loopTimer.Reset()
        Write-Verbose ""
        Write-Verbose "`t`t****************** $($FunctionName): End of loop ($loopCount) ******************"
        Write-Verbose ""
    } #End Process block

    End {
        Write-Verbose ""
        Write-Verbose ""
        Write-Verbose "$($FunctionName): Wrapping Up"
        Write-Verbose "`t`tTDGs procesed:`t$ProcessedCount"
        Write-Verbose "`t`tTDGs failed:`t$FailedCount"
        $FinalLoopTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 0)
        $FinalAvgLoopTime = [math]::Round(($loopTimes | Measure-Object -Average).Average, 0)
        Write-Verbose "`t`tTotal time (sec):`t$FinalLoopTime"
        Write-Verbose "`t`tAvg Loop Time (sec):`t$FinalAvgLoopTime"
        Write-Verbose ""

        Write-Verbose "------------------- $($FunctionName): End -------------------"
        Write-Verbose ""
    } #End End block
}