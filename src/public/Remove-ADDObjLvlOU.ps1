function Remove-ADDObjLvlOU {
<#
	.SYNOPSIS
		Used to remove a site, along with all supporting containers, within the directory

	.DESCRIPTION
		This cmdlet will remove the full container structure for a specified site from an existing region and country container. The cmdlet will
		prompt multiple times to verify you actually wish to remove the item.

		Note: This will remove ALL identified containers AND anything in those containers from the directory without prompting!! Use caution!!

	.PARAMETER Region
		Two letter region identifier. Must be one of the previously defined values as follows:

			- AP
			- EU
			- LA
			- NA

	.PARAMETER Country
		Three letter country identifier. Identifier must consist of three Alpha characters, though specific values beyond that are not enforced.

		AAA will be accepted, but AA, AA1, and AAAA will all be rejected as invalid.

	.PARAMETER Site
		Three letter city or site identifier. Identifier must consist of three Alpha characters, though specific values beyond that are not enforced.

		AAA will be accepted, but AA, AA1, and AAAA will all be rejected as invalid.

	.PARAMETER DeleteTaskGroups
		Not yet implemented - do not use

	.INPUTS
		Accepts pipeline input of custom objects that have properties with matching names of 'Region', 'Country', and 'Site'

	.OUTPUTS
		None

	.EXAMPLE
		C:\PS> Remove-ADDSiteOU -Region "NA" -Country "TST" -Site "TST"

		Removes a site called 'TST' from the 'TST' country in the NA region

	.NOTES
        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org

#>
[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,ValueFromPipelineByPropertyName,ValueFromPipeline)]
		[ValidateNotNullorEmpty()][ValidateSet("AP","EU","LA","NA")]
		[string]$Region,
		[Parameter(Mandatory=$true,Position=1,ValueFromPipelineByPropertyName,ValueFromPipeline)]
		[ValidateNotNullorEmpty()][ValidatePattern("\b[a-zA-Z]{3}\b")]
		[string]$Country,
		[Parameter(Mandatory=$true,Position=2,ValueFromPipelineByPropertyName,ValueFromPipeline)]
		[ValidateNotNullorEmpty()][ValidatePattern("\b[a-zA-Z]{3}\b")]
		[string]$Site,
		[Parameter()]
		[switch]$DeleteTaskGroups
	)

	#$qpath = "AD:\$((Get-ADDomain).DistinguishedName)"
	$OUObjs = Get-ChildItem -Path $qpath -Recurse | Where-Object{$_.objectclass -like "organizationalUnit" -and $_.distinguishedname -like "OU=$($Site),OU=$($Country),OU=$($region),*"}

	if($OUObjs){
		Write-Host "Continuing will result in the removal of $($OUObjs.count) OUs and ALL child objects!" -Foregroundcolor Yellow
		$Confirmation = Read-Host -Prompt 'Are sure you wish to continue? [Y]es or [N]o'
		if($Confirmation -like "N"){
			Write-Host "Quitting"
			Break
		}else{
			foreach($OUObj in $OUObjs){
				$rDN = $OUObj.DistinguishedName
				$rPath = "AD:\$($rDN)"
				$ChildObjOUs = Get-ChildItem -Path $rPath -Recurse
				foreach($ChildObjOU in $ChildObjOUs){
					# Set-ADObject $rDN -ProtectedFromAccidentalDeletion $false
				}
				Write-Verbose "Removing $($rDN)"
				#Remove-ADObject -Identity $rDN -Recursive -Confirm:$false

				Write-Verbose "Removing Server GPOs if found"
				if($rDN -like "*,OU=SRV,*"){
					$Country = ($rDN.Split(",") -replace "OU=")[1]
					$Region = ($rDN.Split(",") -replace "OU=")[2]
					$Focus = ($rDN.Split(",") -replace "OU=")[3]
					$Tier = (($rDN.Split(",") -replace "OU=")[4]).split("-")[1]

					$gponame = "T$($Tier)_$($Focus)_$($Region)_$($Country)_$($Site)_Server"
					Write-Verbose "GPO Name: $($gponame)"
					Get-GPO $gponame | Remove-GPO

				}
			}
		}
	}
}
