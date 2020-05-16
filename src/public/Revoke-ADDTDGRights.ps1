function Revoke-ADDTDGRights {
<#
	.SYNOPSIS
		Removes the ACLs for a specific group from a specific target OU.

	.DESCRIPTION
		This cmdlet removes all ACLs related to a specific group from the targeted OU. Multiple OUs and/or groups can be provided via the pipeline.
		To automatically remove all group permissions for a particular task type in a batch, you can use Push-MeOrgPerms instead.

	.PARAMETER TargetOU
		Specifies an OU, in DistinguishedName format, from which to determine the required task group ACLs to remove. Sample OU should specify
		down to the same level that is being targeted (site level for Site/All, or Region level for Region only)

	.PARAMETER ADGroup
		Specifies the name of the AD group for which to remove assigned ACLs.

	.INPUTS
		Accepts pipeline input that has a 'DistinguishedName' attribute, such as from the ActiveDirectory filesystem provider, or a custom object.

	.OUTPUTS
		None

	.EXAMPLE
		C:\PS> Remove-ADDOrgAcl -TargetOU "OU=TST,OU=TST,OU=NA,OU=STD,OU=Tier-0,DC=test,DC=local" -ADGroup "T0_STD_NA_TST_TST_L_Move_User_Objects_OUs"

		Remove all ACLs for the TST site related to moving User objects.

	.NOTES
        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
	[CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Medium')]
	Param (
		[Parameter(ParameterSetName="ManualRunA",Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]
		$TargetGroup,

		[Parameter(ParameterSetName="ManualRunB",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]$StartOU,

		[Parameter(ParameterSetName="ManualRun")]
		[Parameter(ParameterSetName="ChainRun")]
		[int]$PipelineCount,

		[Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[System.DirectoryServices.DirectoryEntry]$TargetDE,

		[Parameter(DontShow,ParameterSetName="ChainRun")]
		[Switch]$MTRun
	)

	Begin {
		$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""

		if($pscmdlet.ParameterSetName -like "ManualRun"){
            $ChainRun = $false
        }else {
            $ChainRun = $true
        }


		if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
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

			Write-Progress @ProgParams -Activity "Setting ACLs" -CurrentOperation "Initializing..."

		}

        $ProcessedCount = 0
        $FailedCount = 0
        $ExistingCount = 0
        $NewCount = 0
		$TotalAcesCount = 0
		$FailedAcesCount = 0
        $GCloopCount = 1
        $loopCount = 1
        $subloopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $subloopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()

        Write-Verbose ""
	}

	Process {
		if($pipe){
			Write-Progress -Id 30 -Activity "OU ACL Provisioning" -CurrentOperation "Updating ACLs" -Status "Processing item $i"
			$I++
		}
		Write-Verbose "Setting target OU"
		if($TargetOU -notlike "AD:\*"){
			$OrgUnit = "AD:\" + $TargetOU
		}else{
			$OrgUnit = $TargetOU
		}

		if(!(Test-Path $OrgUnit)){
			Write-Error "Could not find the specified path: $($OrgUnit)"
			Break
		}

		Write-Verbose "Target OU set to $($OrgUnit)"
		Write-Verbose "Process group name to build ACL object and assigning permissions"
		if($ADGroup -notlike "$($NetBiosName)\*"){
			$gID = "$($NetBiosName)\$($ADGroup)"
		}else{
			$gID = $ADGroup
		}

<# 		if(!(Get-ADGroup $gID)){
			Write-Error "Could not find the specified group: $($gID)"
			Break
		}

 #>
 		Write-Verbose "Group name set to - $($gID)"
		Write-Verbose "Getting current ACL from target OU"
		$ACL = Get-Acl $OrgUnit
		Write-Verbose "ACL retrieved with the following Access List - `n$(($ACL).Access)"
		Write-Verbose "Starting ACL rewrite to remove specified Group"
		Foreach($ACE in $ACL.Access){
			if($ACE.IdentityReference -eq $gID){
				$ACL.RemoveAccessRule($ACE)
			}
		}
        $ACL | Set-Acl -Path $OrgUnit
	}

	End {
		Write-Verbose "ACL updates complete"
		if($pipe){
			Write-Progress -Id 30 -Activity "OU ACL Provisioning" -CurrentOperation "Finished" -Completed
			Write-Host "Updates complete. Processed $i items."
		}
	}
}
