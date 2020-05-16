function Remove-ADDTaskGroup {
<#
	.SYNOPSIS
		Command uses the specified OU path to auto-remove all task groups for a given object type.

	.DESCRIPTION
		This cmdlet takes a specified OU, in distinguishedName format, to identify all task delegation groups for that tier,
		region, country, and site. The cmdlet then removes all of these groups, if found, from the ADM focus container structure. If specified,
		the cmdlet will also automatically remove the related ACLs for	each delegation group prior to deleting the group.

	.PARAMETER RemoveLevel
		Specifies which levels of groups should be Removed using one of the below values:

			- Site: Removes only the site level groups - useful for site specific task groups, particularly those with custom suffix
			- Region: Removes only the region level groups - useful for region specific task groups, particularly those with custom suffix
			- All: Removes both Site and Region groups - default value if this parameter is not specified

	.PARAMETER RemovePerms
		Specifying this switch will initiate a push removal of the ACLs to the associated containers (Experimental).

		Note: Only groups with one of the standard suffixes should include this switch to avoid errors.

	.PARAMETER TargetOU
		Specifies an OU, in DistinguishedName format, from which to determine the required task groups to remove. Sample OU should specify
		down to the same level that is being removed (site level for Site/All, or Region level for Region only)

	.PARAMETER OUFocus
		Used to specify the OU focus for targeting. For standard suffixes, this should be either ADM, SRV, STD, STG, or you can specify
		ALL to removed all four. Custom values are also accepted. All values are case insensitive.

	.PARAMETER CustomSuffix
		Optional parameter to specify a specific standard task group, or a custom suffix to remove task groups for.

	.PARAMETER Push
		Should not be used directly. This parameter is called when executed using the Push-ADDTaskGroup cmdlet.

	.EXAMPLE
		C:\PS> Remove-ADDTaskGroup -RemoveLevel Site -TargetOU "OU=TST,OU=TST,OU=NA,DC=test,DC=local"

		This command removes all site level task groups for Tier 0 for the TST site, in the TST country, in the NA region for the test.local domain.
		The above does not remove any Region level task groups.

	.EXAMPLE
		C:\PS> Remove-ADDTaskGroup -RemoveLevel All -TargetOU "OU=TST,OU=TST,OU=NA,DC=test,DC=local"

		This command removes all site and region level task groups for Tier 0 for the TST site, in the TST country, in the NA region for the
		test.local domain. The above cmdlet removes all region AND site level task groups, but does not remove the associated ACLs, which should
		be removed first.

	.NOTES
        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
[CmdletBinding(SupportsShouldProcess=$true)]
	Param(
		[Parameter()]
		[ValidateSet("Site","Region","All")]
		[string]$RemoveLevel="All",
		[Parameter()]
		[switch]$RemovePerms,
		[Parameter(Mandatory=$true)]
		[string]$TargetOU,
		[Parameter()]
		[ValidatePattern("\A[A-Z]{3}\Z")]
		[string]$OUFocus="All",
		[Parameter()]
		[string]$CustomSuffix,
		[Parameter()]
		[switch]$Push
	)
	Write-Verbose "---------Remove-ADDtaskGroup Begin----------"
	Write-Verbose "Original Cmdline arguments - "
	Write-Verbose "TargetOU: $($TargetOU)"
	Write-Verbose "Level: $($RemoveLevel)"
	Write-Verbose "RemovePerms: $($RemovePerms)"
	Write-Verbose "OUFocus: $($OUFocus)"
	Write-Verbose "GroupFocus: $($GroupFocus)"
	Write-Verbose "CustomSuffix: $($CustomSuffix)"
	Write-Verbose "Push: $($Push)"

	if($Push){
		$elvl = 0
	}

	if($OUFocus -like "All"){
		Write-Verbose "OUFocus of All detected - setting to standard focus types"
		$FocusTypes = @("ADM","SRV","STD","STG")
	}else{
		Write-Verbose "Custom or single focus detected"
		$FocusTypes = $OUFocus
	}
	Write-Verbose "Modified FocusTypes: $($FocusTypes)"

	if($TargetOU -like "*,OU=Provision,*"){
		$Site = ($TargetOU.Split(",") -replace "OU=")[0]
		$Country = ($TargetOU.Split(",") -replace "OU=")[1]
		$Region = ($TargetOU.Split(",") -replace "OU=")[2]
		$Tier = (($TargetOU.Split(",") -replace "OU=")[5]).split("-")[1]
	}else{
		$Site = ($TargetOU.Split(",") -replace "OU=")[0]
		$Country = ($TargetOU.Split(",") -replace "OU=")[1]
		$Region = ($TargetOU.Split(",") -replace "OU=")[2]
		$Tier = (($TargetOU.Split(",") -replace "OU=")[4]).split("-")[1]
	}

	Foreach($FocusType in $FocusTypes){
		if(!($CustomSuffix)){
			switch ($FocusType){
				"SRV" {
					$Suffixes = $ServerSuffixes
				}
				"ADM" {
					$Suffixes = $GroupSuffixes + $UserSuffixes + $WorkstationSuffixes
				}
				"STD" {
					$Suffixes = $GroupSuffixes + $UserSuffixes + $WorkstationSuffixes
				}
				"STG" {
					$Suffixes = $GroupSuffixes + $UserSuffixes + $WorkstationSuffixes
				}
			}
		}else{
			$Suffixes = $CustomSuffix
		}

		Foreach($Suffix in $Suffixes){
			switch ($RemoveLevel) {
				"Site" {
					Write-Verbose "Switch processed as Site"
					Write-Verbose "Removing site group"
					foreach($FocusType in $FocusTypes){
						Write-Verbose "Site FocusType: $($FocusType)"
						$gname = "T$($Tier)_$($FocusType)_$($Region)_$($Country)_$($Site)_L_$($Suffix)"
						Write-Verbose "Site Group Name: $($gname)"
						if($RemovePerms){
							Write-Verbose "RemovePerms detected - Calling Remove-ADDOrgAcl"
							#$asCheck = Remove-ADDOrgAcl -TargetOU $TargetOU -ADGroup $gname
							if(!($asCheck)){
								Write-Error "Failed to remove ACLs for Group: $($gname) from OU: $($TargetOU)"
							}else{
								Write-Verbose "Site permissions removal returned clean"
							}
						}

						Write-Verbose "Attempt to delete site group from AD"
						Try {
							#Remove-ADGroup -Name $gname
						}
						Catch {
							if($Push){
								$elvl + 1
							}else{
								Write-Error "Failed to remove AD Group: $($gname) from the directory"
							}
						}
					}
				}
				"Region" {
					Write-Verbose "Switch processed as Region"
					Write-Verbose "Removing region group"
					foreach($FocusType in $FocusTypes){
						$gname = "T$($Tier)_$($FocusType)_$($Region)_L_$($Suffix)"
						Write-Verbose "Region Group Name: $($gname)"
						if($RemovePerms){
							Write-Verbose "RemovePerms detected - Calling Remove-ADDOrgAcl"
							$arCheck = Remove-ADDOrgAcl -TargetOU $TargetOU -ADGroup $gname
							if(!($arCheck)){
								Write-Error "Failed to remove ACLs for Group: $($gname) from OU: $($TargetOU)"
							}else{
								Write-Verbose "Region permissions removal returned clean"
							}
						}

						Write-Verbose "Attempt to delete region group from AD"
						Try {
							#Remove-ADGroup -Name $gname
						}
						Catch {
							if($Push){
								$elvl + 1
							}else{
								Write-Error "Failed to remove AD Group: $($gname) from the directory"
							}
						}
					}
				}
				"All" {
					Write-Verbose "Switch processed as All"
					Write-Verbose "Removing site group"
					foreach($FocusType in $FocusTypes){
						Write-Verbose "Site FocusType: $($FocusType)"
						$gname = "T$($Tier)_$($FocusType)_$($Region)_$($Country)_$($Site)_L_$($Suffix)"
						Write-Verbose "Site Group Name: $($gname)"
						if($RemovePerms){
							Write-Verbose "RemovePerms detected - Calling Remove-ADDOrgAcl"
							#$asCheck = Remove-ADDOrgAcl -TargetOU $TargetOU -ADGroup $gname
							if(!($asCheck)){
								Write-Error "Failed to remove ACLs for Group: $($gname) from OU: $($TargetOU)"
							}else{
								Write-Verbose "Site permissions removal returned clean"
							}
						}

						Write-Verbose "Attempt to delete site group from AD"
						Try {
							#Remove-ADGroup -Name $gname
						}
						Catch {
							if($Push){
								$elvl + 1
							}else{
								Write-Error "Failed to remove AD Group: $($gname) from the directory"
							}
						}
					}

					Write-Verbose "Removing region group"
					foreach($FocusType in $FocusTypes){
						$gname = "T$($Tier)_$($FocusType)_$($Region)_L_$($Suffix)"
						Write-Verbose "Region Group Name: $($gname)"
						if($RemovePerms){
							Write-Verbose "RemovePerms detected - Calling Remove-ADDOrgAcl"
							#$arCheck = Remove-ADDOrgAcl -TargetOU $TargetOU -ADGroup $gname
							if(!($arCheck)){
								Write-Error "Failed to remove ACLs for Group: $($gname) from OU: $($TargetOU)"
							}else{
								Write-Verbose "Region permissions removal returned clean"
							}
						}

						Write-Verbose "Attempt to delete region group from AD"
						Try {
							#Remove-ADGroup -Name $gname
						}
						Catch {
							if($Push){
								$elvl + 1
							}else{
								Write-Error "Failed to remove AD Group: $($gname) from the directory"
							}
						}
					}
				}
			}
		}
	}

	Write-Verbose "---------Remove-ADDtaskGroup End----------"

	if($Push){
		if($elvl -gt 0){
			$eResult = $true
		}else{
			$eResult = $false
		}
		Return $eResult
	}
}
