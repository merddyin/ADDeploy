function Deploy-GPOPlaceHolder {
<#
    .SYNOPSIS
        Short description

    .DESCRIPTION
        Long description

    .PARAMETER exampleparam
        Description of parameter and required elements

    .EXAMPLE
        Example of how to use this cmdlet

    .EXAMPLE
        Another example of how to use this cmdlet

    .INPUTS
        Inputs to this cmdlet (if any)

    .OUTPUTS
        Output from this cmdlet (if any)

    .NOTES
        Help Last Updated: 08/20/2019

        Cmdlet Version: 0.1
        Cmdlet Status: (Alpha/Beta/Release-Functional/Release-FeatureComplete)

        Copyright (c) Topher Whitfield. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Topher Whitfield assumes no liability.

    .LINK
        https://mer-bach.com
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Alias("DistinguishedName","OrgDN")]
        $SourceDN,

        [Parameter()]
        [PSCustomObject]
        $OUOrg,

        [Parameter()]
        [int]
        $MaxLevel,

        [PSCustomObject]
        $PIParams
    )

    begin {
        Write-Verbose "------------------- Starting Deploy-GPOPlaceHolder -------------------"
        Write-Verbose "`t`t......... Execute: Begin Section ........."
        #TODO: Finish cutover to public function and add WhatIf processing support
        $GPOFocuses = @("User","Computer")
        $GuidRe = '(?<={)(.*?)(?=})'

        if($PIParams){
            Write-Verbose "`t`tDeploy-GPOPlaceHolder: PIParams detected"
            if($PIParams.PassThru){
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: Evaluate PIParams `n`t`t`t`tPassThru Detected - Removing"
                $PIParams.Remove("PassThru")
            }
            if($PIParams.Path){
                `t`t"Deploy-GPOPlaceHolder: Evaluate PIParams `n`t`t`t`tPath Detected - Removing"
                $PIParams.Remove("Path")
            }
        }else{
            Write-Verbose "`t`tDeploy-GPOPlaceHolder: PIParams not detected - Creating"
            $PIParams = @{
                ProtectedFromAccidentalDeletion = $true
            }
        }

        if(!($OUOrg)){
            Write-Verbose "`t`tDeploy-GPOPlaceHolder: OUOrg not detected - Retrieving data"
            $DBRPath = $(Join-Path $MyModulePath 'other')
            $DBPath = $(Join-Path $DBRPath 'ADDeploySettings.sqlite')
            Write-Verbose "`t`tDeploy-GPOPlaceHolder: DBPath - $DBPath"
            $conn = New-SQLiteConnection -DataSource $DBPath
            $OUOrg = Invoke-SqliteQuery -SQLiteConnection $conn -Query "Select * FROM Cust_OU_Organization"

            if($OUOrg){
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: Successfully retrieved custom org - $($OUOrg.Count)"
                $MaxLevel = (($OUOrg | Select-Object OU_orglvl -Unique).OU_orglvl | Measure-Object -Maximum).Maximum
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: MaxLevel - $($MaxLevel)"
            }else{
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: No custom org data - Prompting for schema"
                $OrgSchema = Read-Host -Prompt "No custom org data. Please specify an OrgSchema to proceed."

                if($OrgSchema){
                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: Retrieving built-in OUOrg data `n`t`t`t`tOrgSchema - $($OrgSchema)"
                    $OUOrg = Invoke-SqliteQuery -SQLiteConnection $conn -Query "Select * FROM OU_Organization WHERE OU_schema = '$OrgSchema'"
                    if(!($OUOrg)){
                        throw "No OrgData - Cannot proceed"
                    }else{
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: Successfully retrieved built-in org - $($OUOrg.Count)"
                    }
                }else{
                    throw "No OrgData - Cannot proceed"
                }
            }
        }

        if(!($CoreOUs)){
            Write-Verbose "`t`tDeploy-GPOPlaceHolder: CoreOUs not detected - Retrieving data"
            if(!($DBPath)){
                $DBPath = $(Resolve-Path -Path "..\other\ADDeploySettings.sqlite")
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: DBPath - $DBPath"
            }

            if(!($conn)){
                $conn = New-SQLiteConnection -DataSource $DBPath
            }

            $CoreOUs = Invoke-SqliteQuery -SQLiteConnection $conn -Query "Select OU_name,OU_type,OU_focus FROM OU_core WHERE OU_enabled = 1"

            if($CoreOUs){
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: CoreOUs Count - $($CoreOUs.Count)"

                if(!($TierHash)){
                    $TierHash = @{}
                    $CoreOUs | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$TierHash.($_.OU_name) = $_.OU_focus}
                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: TierHash Count - $($TierHash.Count)"
                }

                if(!($FocusHash)){
                    $FocusHash = @{}
                    $CoreOUs | Where-Object{$_.OU_type -like "Focus"} | ForEach-Object{$FocusHash.($_.OU_focus) = $_.OU_name}
                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: FocusHash Count - $($FocusHash.Count)"
                }

            }
        }
    }

    process {
        Write-Verbose ""
        Write-Verbose ""
        Write-Verbose "`t`t......... Process Section ........."
        foreach($input in $SourceDN){
            Write-Verbose "`t`tDeploy-GPOPlaceHolder: Processing SourceDN `n`t`t`t`tCurrent Item - $Input"
            if($input -match '^(?:(?<cn>CN=(?<name>[^,]*)),)?(?:(?<path>(?:(?:CN|OU)=[^,]+,?)+),)?(?<domain>(?:DC=[^,]+,?)+)$'){
                $PathPieces = $input.Split(",") -replace "OU=" | Where-Object{$_ -notmatch "DC=*"}
            }

            if($PathPieces){
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: Evaluate Path Components - $($PathPieces.Count)"
                $OrgElements = @()

                switch ($($PathPieces.Count)) {

                    {$_ -eq 1} {
						Write-Verbose "`t`tDeploy-GPOPlaceHolder: Input Contains 1 Component - Identify TierID"
						$TierID = $TierHash[$($PathPieces)]

                        if($TierID){
                            Write-Verbose "`t`t`t`t`t`tTierID - $TierID"
                        }else{
                            throw "TierID - Not Found"
                        }
                    }

                    {$_ -eq 2} {
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: Input Contains 2 Components - Identify TierID"
                        $TierID = $TierHash[$($PathPieces[$PathPieces.count - 1])]
                        if($TierID){
                            Write-Verbose "`t`t`t`t`t`tTierID - $TierID"
                        }else{
                            throw "TierID - Not Found"
                        }

						Write-Verbose "`t`tDeploy-GPOPlaceHolder: Input Contains 2 Components - Identify TierID and FocusID"
                        if($($PathPieces[$PathPieces.count - 2]) -match ($($CoreOUs | Where-Object{$_.OU_type -like "Focus"}).OU_name -join "|")){
                            $FocusID = ($PathPieces[$PathPieces.count - 2])
                        }
                        if($FocusID){
                            Write-Verbose "`t`t`t`t`t`tFocusID - $FocusID"
                        }
                    }

					{$_ -eq 3} {
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: Input Contains 3 Components - Identify TierID, FocusID, OrgL1"
                        $TierID = $TierHash[$($PathPieces[$PathPieces.count - 1])]
                        if($TierID){
                            Write-Verbose "`t`t`t`t`t`tTierID - $TierID"
                        }else{
                            throw "TierID - Not Found"
                        }

                        if($($PathPieces[$PathPieces.count - 2]) -match ($($CoreOUs | Where-Object{$_.OU_type -like "Focus"}).OU_name -join "|")){
                            $FocusID = ($PathPieces[$PathPieces.count - 2])
                            Write-Verbose "`t`t`t`t`t`tFocusID - $FocusID"
                        }
                        if($FocusID){
                            Write-Verbose "`t`t`t`t`t`tFocusID - $FocusID"
                        }

						$OrgL1 = $PathPieces[$PathPieces.count - 3]
						if($OrgL1){
							Write-Verbose "`t`t`t`t`t`tOrgL1 - $OrgL1"
							$OrgElements += $OrgL1
						}
					}

					{$_ -eq 4} {
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: Input Contains 4 Components - Identify TierID, FocusID, OrgL1, OrgL2"
                        $TierID = $TierHash[$($PathPieces[$PathPieces.count - 1])]
                        if($TierID){
                            Write-Verbose "`t`t`t`t`t`tTierID - $TierID"
                        }else{
                            throw "TierID - Not Found"
                        }

                        if($($PathPieces[$PathPieces.count - 2]) -match ($($CoreOUs | Where-Object{$_.OU_type -like "Focus"}).OU_name -join "|")){
                            $FocusID = ($PathPieces[$PathPieces.count - 2])
                            Write-Verbose "`t`t`t`t`t`tFocusID - $FocusID"
                        }
                        if($FocusID){
                            Write-Verbose "`t`t`t`t`t`tFocusID - $FocusID"
                        }

						$OrgL1 = $PathPieces[$PathPieces.count - 3]
						if($OrgL1){
							Write-Verbose "`t`t`t`t`t`tOrgL1 - $OrgL1"
							$OrgElements += $OrgL1
						}

						$OrgL2 = $PathPieces[$PathPieces.count - 4]
						if($OrgL2){
							Write-Verbose "`t`t`t`t`t`tOrgL2 - $OrgL2"
							$OrgElements += $OrgL2
						}
					}

					{$_ -ge 5} {
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: Input Contains 5 or more Components - Identify TierID, FocusID, OrgL1, OrgL2, OrgL3"
                        $TierID = $TierHash[$($PathPieces[$PathPieces.count - 1])]
                        if($TierID){
                            Write-Verbose "`t`t`t`t`t`tTierID - $TierID"
                        }else{
                            throw "TierID - Not Found"
                        }

                        if($($PathPieces[$PathPieces.count - 2]) -match ($($CoreOUs | Where-Object{$_.OU_type -like "Focus"}).OU_name -join "|")){
                            $FocusID = ($PathPieces[$PathPieces.count - 2])
                        }
                        if($FocusID){
                            Write-Verbose "`t`t`t`t`t`tFocusID - $FocusID"
                        }

						$OrgL1 = $PathPieces[$PathPieces.count - 3]
						if($OrgL1){
							Write-Verbose "`t`t`t`t`t`tOrgL1 - $OrgL1"
							$OrgElements += $OrgL1
						}

						$OrgL2 = $PathPieces[$PathPieces.count - 4]
						if($OrgL2){
							Write-Verbose "`t`t`t`t`t`tOrgL2 - $OrgL2"
							$OrgElements += $OrgL2
						}

						$OrgL3 = $PathPieces[$PathPieces.count - 5]
						if($OrgL3){
							Write-Verbose "`t`t`t`t`t`tOrgL3 - $OrgL3"
							$OrgElements += $OrgL3
						}
					}

                }

                if(!($FocusID)){
                    $FocusID = "GBL"
                    Write-Verbose "`t`t`t`t`t`tFocusID Defaulted - $FocusID"
                }

                $GPPrefix = "$($TierID)_$($FocusID)"
                Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPPrefix - $GPPrefix"

                if($OrgElements){
					if($OrgElements.count -gt 1){
						$GPMid = $OrgElements -join "_"
						Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPMid - $GPMid"
					}else{
						$GPMid = $OrgElements
					}
                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPMid - OrgElements Join Failure"
                }

                foreach($GPOFocus in $GPOFocuses){
                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: Process GPOFocuses `n`t`t`t`tCurrent Item - $GPOFocus"

                    if($GPMid){
                        $GPFullName = Join-String $GPPrefix,$GPMid,$GPOFocus -Separator "_"
                    }else{
                        $GPFullName = Join-String $GPPrefix,$GPOFocus -Separator "_"
                    }

                    if($GPFullName){
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPFullName - $GPFullName"
                        try {
                            Write-Verbose "`t`tDeploy-GPOPlaceHolder: Check for GPO"
                            $GPOObj = Get-GPO -Name $GPFullName -ErrorAction SilentlyContinue
                        }
                        catch {
                            Write-Verbose "`t`tDeploy-GPOPlaceHolder: Check for GPO - Retrieve Failed"
                        }

                        if($GPOObj){
                            Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO Found ($($GPOObj.DisplayName)) - Checking Links"
                            $Links = (Get-ADOrganizationalUnit $input).LinkedGroupPolicyObjects
                            $LinkedGPOs = @()
                            foreach($Link in $Links){
                                $LinkedGPOs += ([Regex]::Match($($Link),$GuidRe)).Value
                            }

                            if($($GPOObj.Id).Guid -in $LinkedGPOs){
                                Write-Verbose "`t`tDeploy-GPOPlaceHolder: Checking Links ($($GPOObj.DisplayName)) - Already Linked to OU ($($input))"
                            }else{
                                Write-Verbose "`t`tDeploy-GPOPlaceHolder: Attempt GPO Link ($($GPOObj.DisplayName)) - Attempting to Link to OU ($($input))"
                                try {
                                    $GPOLink = $GPOObj | New-GPLink -Target $input
                                }
                                catch {
                                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: Attempt GPO Link ($($GPOObject.DisplayName)) `n`t`t`t`tLink to OU ($($input)) - Experienced Exception"
                                }
                            }
                        }else{
                            Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO Not Found ($($GPFullName)) - Attempting Creation"
                            try {
                                $GPOObj = New-GPO -Name $GPFullName -Comment "Created by ADDeploy Module deployment sequence"
                            }
                            catch {
                                Write-Error "`t`tDeploy-GPOPlaceHolder: GPO Not Found ($($GPFullName)) - Experienced Exception"
                            }

                            if($GPOObj){
                                try {
                                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO Created ($($GPOObj.DisplayName)) - Attempting Link"
                                    $GPOLink = $GPOObj | New-GPLink -Target $SourceDN
                                }
                                catch {
                                    Write-Error "`t`tDeploy-GPOPlaceHolder: GPO Attempt Link ($($GPOObj.DisplayName)) - Experienced Exception"
                                }

                                if($GPOLink){
                                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO Linked ($($GPOObj.DisplayName)) - Link to Target ($($input))"
                                }else{
                                    Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO Link Not Present ($($GPOObj.DisplayName)) - Link to Target ($($input))"
                                }
                            }else{
                                Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO Creation ($($GPFullName)) - GPO Object ReCheck"
								try {
									Write-Verbose "`t`tDeploy-GPOPlaceHolder: Check for GPO"
									$GPOObj = Get-GPO -Name $GPFullName
								}
								catch {
									Write-Verbose "`t`tDeploy-GPOPlaceHolder: Check for GPO - Retrieve Failed"
								}

								if($GPOObj){
									Write-Verbose "`t`tDeploy-GPOPlaceHolder: Attempt GPO Link ($($GPOObj.DisplayName)) - Attempting to Link to OU ($($input))"
									try {
										$GPOLink = $GPOObj | New-GPLink -Target $input
									}
									catch {
										Write-Verbose "`t`tDeploy-GPOPlaceHolder: Attempt GPO Link ($($GPOObject.DisplayName)) `n`t`t`t`tLink to OU ($($input)) - Experienced Exception"
									}
								}else{
									Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPO ReCheck ($($GPFullName)) - GPO Not Created"
								}
                            }
                        }
                    }else{
                        Write-Verbose "`t`tDeploy-GPOPlaceHolder: GPFullName - Name could not be derived"
                    }
                }
            }
        }
    }

    end {
    }
}