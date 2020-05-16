function Test-ADDOuStructure {
    <#
        .SYNOPSIS
            Deploys one or more levels of the OU structure to a directory

        .DESCRIPTION
            This cmdlet uses information from the embedded sqlite database to generate one or more levels of an OU structure within the 'Gold' or
            'production' AD forest for an Enhanced Security Administration Model (Red Forest) implemenation. The cmdlet provides the ability to deploy
            the structure at varying levels, and can include the defined object type and sub-type containers for all enabled object types.

        .PARAMETER DeployLevel
            Used to indicate if the entire structure should be deployed, or only the organizational containers. By default, the full structure will always be deployed.

        .PARAMETER OrgSchema
            Optional parameter used to specify the name of one of the built-in schema options, instead of a custom one, for the organizational containers.

        .PARAMETER SetAcls
            Using this switch will cause the default set of Task Delegation Groups to be created, and the associated ACLs assigned to the object type container.
            This switch will be ignored in the event the DeployLevel is set to 'OrgOnly'.

        .PARAMETER Credential
            Allows user to provide alternate credentials to run the process under. When specifying a value for this parameter, you must also specify a domain.

        .PARAMETER Domain
            Allows user to specify an alternate domain to connect to. When specifying a value for this parameter, you must also specify credentials.

        .PARAMETER TargetOU
            When specifying a DeployLevel of 'OrgOnly', this parameter must have a value specifying the name of the OU under which to create the structure. The
            value provided must be in distinguishedName format - i.e. "OU=OUname,DC=MYDOMAIN,DC=NET"

        .EXAMPLE
            PS C:\> <example usage>
            Explanation of what the example does

        .NOTES
            Help Last Updated: 7/25/2019

            Cmdlet Version 0.5 - Alpha

            Copyright (c) Topher Whitfield All rights reserved.

            Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
            source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
            own risk, and the author assumes no liability.

        .LINK
            https://mer-bach.org
    #>
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="Standard",ConfirmImpact='Low')]
        Param(
            [Parameter(ParameterSetName="Standard")]
            [Parameter(ParameterSetName="AltDomain")]
            [ValidateSet("USRegion")]
            [String[]]
            $OrgSchema,

            [Parameter(ParameterSetName="Standard")]
            [Parameter(ParameterSetName="AltDomain")]
            [switch]
            $SetAcl,

            [Parameter(ParameterSetName="Standard")]
            [Parameter(ParameterSetName="AltDomain")]
            [switch]
            $CreateTDG,

            [Parameter(ParameterSetName="Standard")]
            [Parameter(ParameterSetName="AltDomain")]
            [switch]
            $CreateObjTypeOUs=$true,

            [Parameter(Mandatory=$true,ParameterSetName="AltDomain")]
            [System.Management.Automation.PSCredential]
            $Credential,

            [Parameter(Mandatory=$true,ParameterSetName="AltDomain")]
            [String[]]
            $Domain
        )

        Begin {
            $PIParams = @{
                PassThru = $true
                ProtectedFromAccidentalDeletion = $true
            }

            Write-Verbose "ADDOuStructure - CreateObjTypeOUs: $($CreateObjTypeOUs)"
            $ChainParams = @{
                SetAcl = $SetAcl
                CreateTDG = $CreateTDG
                CreateObjTypeOUs = $CreateObjTypeOUs
            }

            #region ProcessDomain
            if($Domain){
                switch ($Domain) {
                    {$_ -like "*.*"} {
                        $DomSuf = $Domain.replace('.',',DC=')
                        $DomDN = "DC=$($DomSuf)"
                    }
                    {$_ -like "DC=*"} {
                        $DomDN = $Domain
                    }
                    {$_ -like $ENV:USERDOMAIN} {
                        $DomSuf = ($ENV:USERDNSDOMAIN).Replace('.',',DC=')
                        $DomDN = "DC=$($DomSuf)"
                    }
                }

                $PIParams.Add("Server", $Domain)
                $PIParams.Add("Credential", $Credential)
            }else{
                $Domain = $ENV:USERDNSDOMAIN
                $DomSuf = ($Domain).Replace('.',',DC=')
                $DomDN = "DC=$($DomSuf)"
            }
            #endregion ProcessDomain

            #region ProcessRootVars
            $PIParams.Add("Path", $DomDN)

            $OUTop = $CoreOUs | Where-Object{$_.OU_type -like "Tier"}

            if($OrgSchema){
                $OUOrg = Import-ADDModuleData -DataSet OUOrg -QueryFilter $OrgSchema
            }else{
                $OUOrg = Import-ADDModuleData -DataSet OUOrg #!: Review for continued relevance against PostLoad
            }

            $MaxLevel = (($OUOrg | Select-Object OU_orglvl -Unique).OU_orglvl | Measure-Object -Maximum).Maximum

            $ChainParams.Add("MaxLevel", $MaxLevel)

            $OUFocusItems = $CoreOUs | Where-Object{$_.OU_type -like "Focus"}
            #endregion ProcessRootVars

            $TopLevelOUs = @()
            $FocusLevelOUs = @()
            $GlobalOUs = @()
        }

        Process {
            #region CreateTopLevelOUs
            Write-Verbose "Creating top level OUs"
            foreach($ouRoot in $OUTop){
                $TopName = $($ouRoot.OU_name)
                Write-Verbose "Current Top-Level OU: $TopName"
                try {
                    $TopOUobj = New-ADOrganizationalUnit -Name $TopName @PIParams
                }
                catch [Microsoft.ActiveDirectory.Management.ADException] {
                    if($($Error[0].Exception.InnerException) -like "The supplied entry already exists."){
                        Write-Information -MessageData "OU - $TopName - already exists...skipping" -Tags "Information" -InformationAction Continue
                    }else{
                        Write-Error "A general failure occurred attempting to create the $($TopName) OU - Process will skip to next item"
                    }
                }
                catch {
                    Write-Error "General failure to create OU $($TopName) - Process will skip to next item"
                    Break
                }

                if($TopOUobj){
                    Write-Verbose "Create succeeded - TopOUobj: $TopOUobj"
                    $TopLevelOUs += $TopOUobj
                }
            } # End OUTop Foreach
            #endregion CreateTopLevelOUs

            #region CreateFocusContainers
            Foreach($TopLevelOU in $TopLevelOUs){
                $PIParams.Path = $TopLevelOU.DistinguishedName
                Write-Verbose "Current PIParams.Path Value: $($PIParams.Path)"

                foreach($ouFocus in $OUFocusItems){
                    $FocusName = $($OUFocus.OU_name)
                    $ChainParams.Focus = $FocusName
                    Write-Verbose "Focus: $FocusName"

                    try {
                        $FocusOUobj = New-ADOrganizationalUnit -Name $FocusName @PIParams
                    }
                    catch [Microsoft.ActiveDirectory.Management.ADException] {
                        if($($Error[0].Exception.InnerException) -like "The supplied entry already exists."){
                            Write-Information -MessageData "OU - $($FocusName) - already exists...skipping" -Tags "Information" -InformationAction Continue
                        }else{
                            Write-Error "A general failure occurred attempting to create the $($FocusName) OU - Process will skip to next item"
                        }
                    }
                    catch {
                        Write-Error "General failure to create OU $($FocusName) - Process will skip to next item"
                        Break
                    }

                    if($FocusOUobj){
                        Write-Verbose "Create succeeded - `nFocusName: $FocusName`nTopOUobj: $TopOUobj"
                        $FocusLevelOUs += $FocusOUobj
                    }
                } # End OUFocusItems Foreach
            } # End TopLevelOUs Foreach
            #endregion CreateFocusContainers

            #region CreateGlobalContainers
            $AdminFocusOUs = $FocusLevelOUs | Where-Object{$_.Name -like $($FocusHash["Admin"])}
            Write-Verbose "ADDOuStructure: AdminFocusOUs Count - $($AdminFocusOUs.count)"
            $ChainParams.Focus = $($FocusHash["Admin"])
            Write-Verbose "ADDOuStructure: ChainParams Focus - $($ChainParams.Focus)"
            foreach($AdminFocusOU in $AdminFocusOUs){
                $PIParams.Path = $AdminFocusOU.DistinguishedName
                Write-Verbose "PIParams.Path Value Updated: $($PIParams.Path)"

                for($i = 1; $i -lt ($MaxLevel + 1); $i++){
                    Write-Verbose "Creating Shared Svcs OU - Level $i"
                    try {
                        $GlobalOUobj = New-ADOrganizationalUnit -Name $OUGlobal @PIParams
                    }
                    catch [Microsoft.ActiveDirectory.Management.ADException] {
                        if($($Error[0].Exception.InnerException) -like "The supplied entry already exists."){
                            Write-Information -MessageData "OU - $($OUGlobal) - already exists...skipping" -Tags "Information" -InformationAction Continue
                        }else{
                            Write-Error "A general failure occurred attempting to create the $($OUGlobal) OU - Process will skip to next item"
                        }
                    }
                    catch {
                        Write-Error "General failure to create OU $($OUGlobal) - Process will skip to next item"
                        Break
                    }

                    $PIParams.Path = $GlobalOUobj.distinguishedName
                    Write-Verbose "PIParams.Path Value Updated: $($PIParams.Path)"

                    $GlobalObj = [PSCustomObject]@{
                        GlobalDN = $GlobalOUobj.distinguishedName
                        Level = $i
                    }
                    $GlobalOUs += $GlobalObj
                }
            }# End AdminFocusOUs Foreach

            $GlobalLoop = $GlobalOUs | Where-Object{$_.Level -eq $MaxLevel}
            Write-Verbose "GlobalLoop: $($GlobalLoop.count)"
            if($CreateObjTypeOUs){
                if($GlobalOUs){

                    foreach($GlobalOU in $GlobalLoop){

                        Write-Verbose "Calling Publish-ADDObjTypeOU: Shared Services"

                        $PIParams.Path = $GlobalOU.GlobalDN
                        Write-Verbose "PIParams.Path Value Updated: $($PIParams.Path)"

                        $ChainParams.Remove("CreateObjTypeOUs")
                        Write-Verbose "ADDOuStructure: ChainParams Focus - $($ChainParams.Focus)"

                        Publish-ADDObjTypeOU @ChainParams -PIParams $PIParams -OUOrg $OUOrg -Verbose:$VerbosePreference
                    }# End GlobalOUs Foreach
                }
            }
            #endregion CreateGlobalContainers

            Foreach($FocusLevelOU in $FocusLevelOUs){
                $FocusName = $FocusLevelOU.Name
                $ChainParams.Focus = $FocusName
                Write-Verbose "Focus: $FocusName"

                $PIParams.Path = $FocusLevelOU.DistinguishedName
                Write-Verbose "PIParams.Path Value Updated: $($PIParams.Path)"

                if($FocusName -like $($FocusHash["Stage"])){
                    Publish-ADDObjTypeOU @ChainParams -PIParams $PIParams -OUOrg $OUOrg -Verbose:$VerbosePreference
                }else{
                    if(!($ChainParams.CreateObjTypeOUs)){
                        $ChainParams.Add("CreateObjTypeOUs", $CreateObjTypeOUs)
                    }
                    New-ADDOrgOuStructure -OUOrg $OUOrg -PIParams $PIParams -ChainParams $ChainParams -Verbose:$VerbosePreference
                }
            }
            #endregion CreateFocusContainers
        }

        End {

        }

    }