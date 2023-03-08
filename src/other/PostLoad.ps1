# Use this variable for any path-sepecific actions (like loading dlls and such) to ensure it will work in testing and after being built
$MyModulePath = $(
    Function Get-ScriptPath {
        $Invocation = (Get-Variable MyInvocation -Scope 1).Value
        if($Invocation.PSScriptRoot) {
            $Invocation.PSScriptRoot
        }
        Elseif($Invocation.MyCommand.Path) {
            Split-Path $Invocation.MyCommand.Path
        }
        elseif ($Invocation.InvocationName.Length -eq 0) {
            (Get-Location).Path
        }
        else {
            $Invocation.InvocationName.Substring(0,$Invocation.InvocationName.LastIndexOf("\"));
        }
    }

    Get-ScriptPath
)

# Load any plugins found in the plugins directory
if (Test-Path (Join-Path $MyModulePath 'plugins')) {
    Get-ChildItem (Join-Path $MyModulePath 'plugins') -Directory | ForEach-Object {
        if (Test-Path (Join-Path $_.FullName "Load.ps1")) {
            Invoke-Command -NoNewScope -ScriptBlock ([Scriptblock]::create(".{$(Get-Content -Path (Join-Path $_.FullName "Load.ps1") -Raw)}")) -ErrorVariable errmsg 2>$null
        }
    }
}

$ExecutionContext.SessionState.Module.OnRemove = {
    # Action to take if the module is removed
    # Unload any plugins found in the plugins directory
    if (Test-Path (Join-Path $MyModulePath 'plugins')) {
        Get-ChildItem (Join-Path $MyModulePath 'plugins') -Directory | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName "UnLoad.ps1")) {
                Invoke-Command -NoNewScope -ScriptBlock ([Scriptblock]::create(".{$(Get-Content -Path (Join-Path $_.FullName "UnLoad.ps1") -Raw)}")) -ErrorVariable errmsg 2>$null
            }
        }
    }
}

$null = Register-EngineEvent -SourceIdentifier ( [System.Management.Automation.PsEngineEvent]::Exiting ) -Action {
    # Action to take if the whole pssession is killed
    # Unload any plugins found in the plugins directory
    if (Test-Path (Join-Path $MyModulePath 'plugins')) {
        Get-ChildItem (Join-Path $MyModulePath 'plugins') -Directory | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName "UnLoad.ps1")) {
                Invoke-Command -NoNewScope -ScriptBlock [Scriptblock]::create(".{$(Get-Content -Path (Join-Path $_.FullName "UnLoad.ps1") -Raw)}") -ErrorVariable errmsg 2>$null
            }
        }
    }
}

# Use this in your scripts to check if the function is being called from your module or independantly.
$ThisModuleLoaded = $true

#region DataImport:CoreItems
Write-Verbose "Initialize: Import Rundata"
$Rundata = Import-ADDModuleData -DataSet "Rundata"
if($Rundata){
    Write-Verbose "`t`tImport Rundata: Success"
    foreach($RunItem in $Rundata){
        if($RunItem.OB_runvalue){
            $VarValue = $RunItem.OB_runvalue
        }else{
            $VarValue = $RunItem.OB_initvalue
        }

        New-Variable -Name $($RunItem.OB_item) -Value $VarValue -Scope Script -Visibility Private
        New-Variable -Name "$($RunItem.OB_item)_LastRun" -Value $RunItem.OB_legacyvalue -Scope Script -Visibility Private
    }

    if($InitDep -eq 1){
        $NotFirstRun = $true
    }else{
        $NotFirstRun = $false
    }

    New-Variable -Name Initialized -Value $NotFirstRun -Scope Script -Visibility Private

}else{
    Write-Verbose "`t`tImport Rundata: Failed"
    Write-Error "Unable to import Rundata from DB - Quitting load sequence" -ErrorAction Stop
}

Write-Verbose "Initialize: Import core OU data"
# Contains all items from the OU_Core table with an enabled state
$OUCoreData = Import-ADDModuleData -DataSet OUCore
if($OUCoreData){
    Write-Verbose "`t`tImport Core data: Success"
    New-Variable -Name CoreData -Value $OUCoreData -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport Core Data: Failed"
    Write-Error "Unable to import Core Data from DB - Quitting load sequence" -ErrorAction Stop
}

#region CreatePrimaryReferenceHashes
# Abbreviated Tier Values - Used for GPO and Group Names
## When using defaults, values are; T0, T1, T2
$TierHashTmp = @{}
$CoreData | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$TierHashTmp.($_.OU_name) = $_.OU_focus}
New-Variable -Name TierHash -Value $TierHashTmp -Scope Script -Visibility Private
New-Variable -Name TierRegEx -Value $($TierHash.Values -join "|") -Scope Script -Visibility Private
$TierDN = $TierHash.Values | ForEach-Object{"CN=$_"}
New-Variable -Name TierDNRegEx -Value $($TierDN -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tTierHash Values"
Write-Debug "`t`t`t`t$($TierHash | Out-String)"
Write-Verbose ""

# Full Tier Values - Used for OU Names
## When using defaults, values are; Tier-0, Tier-1, Tier-2
$CETierHashTmp=@{}
$CoreData | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$CETierHashTmp.($_.OU_focus) = $_.OU_name}
New-Variable -Name CETierHash -Value $CETierHashTmp -Scope Script -Visibility Private
New-Variable -Name CETierRegEx -Value $($CETierHash.Values -join "|") -Scope Script -Visibility Private
$CETierDN = $CETierHash.Values | ForEach-Object{"OU=$_"}
New-Variable -Name CETierDNRegEx -Value $($CETierDN -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tCETierHash Values"
Write-Verbose "`t`t`t`t$($CETierHash | Out-String)"
Write-Verbose ""

$FocusHashTmp = @{}
$CoreData | Where-Object{$_.OU_type -like "Focus"} | ForEach-Object{$FocusHashTmp.($_.OU_focus) = $_.OU_name}
New-Variable -Name FocusHash -Value $FocusHashTmp -Scope Script -Visibility Private
New-Variable -Name FocusRegEx -Value $($FocusHash.Values -join '|') -Scope Script -Visibility Private
$FocusDN = $FocusHash.Values | ForEach-Object{"OU=$_"}
# Create RegEx for detecting Focus containers
New-Variable -Name FocusDNRegEx -Value $($FocusDN -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tFocusHash Values"
Write-Verbose "`t`t`t`t$($FocusHash | Out-String -Stream)"
Write-Verbose ""

$CEFocusHashTmp = @{}
$CoreData | Where-Object{$_.OU_type -like "Focus"} | ForEach-Object{$CEFocusHashTmp.($_.$OU_name) = $_.OU_focus}
New-Variable -Name CEFocusHash -Value $CEFocusHashTmp -Scope Script -Visibility Private
New-Variable -Name CEFocusHashRegEx -Value $($CEFocusHash.Values -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tCEFocusHash Values"
Write-Verbose "`t`t`t`t$($CEFocusHash | Out-String -Stream)"
Write-Verbose ""


$AttributeHashTmp = @{}
$CoreData | Where-Object{$_.OU_type -like "Attribute"} | ForEach-Object{$AttributeHashTmp.($_.OU_focus) = $_.OU_name}
New-Variable -Name AttributeHash -Value $AttributeHashTmp -Scope Script -Visibility Private
Write-Verbose "`t`tAttribute Values"
Write-Verbose "`t`t`t`t$($AttributeHash | Out-String -Stream)"
Write-Verbose ""

Write-Verbose "Initialize: Import Rights Data"
$RightsData = Import-ADDModuleData -DataSet RightsInfo
if($RightsData){
    Write-Verbose "`t`tImport Rights Data: Success"
    $RightsHashTmp = @{}
    $RightsData | ForEach-Object{$RightsHashTmp.($_.OBJ_indicator) = $_.OBJ_value}
    New-Variable -Name RightsHash -Value $RightsHashTmp -Scope Script -Visibility Private
    Write-Debug "`t`tRightsHash Values:"
    Write-Debug "`t`t`t`t$($RightsHash | Out-String -Stream)"
}else{
    Write-Verbose "`t`tImport Rights Data: Failed"
}
Write-Verbose ""

$rootDSE = [adsi]"LDAP://RootDSE"
$schemaNamingContext = $rootDSE.schemaNamingContext
$configNamingContext = $rootDSE.configurationNamingContext

Write-Verbose "Initialize: Import ClassMap Data"
$ClassData = Import-ADDModuleData -DataSet ClassMap
if($ClassData){
    Write-Verbose "`t`tImport ClassMap Data: Success"
    $classmaptmp = @{}
    $ClassData | ForEach-Object {$classmaptmp[$_.OBJ_Name]=[System.GUID]$_.OBJ_guid}
    New-Variable -Name classmap -Value $classmaptmp -Scope Script -Visibility Private
    Write-Debug "`t`tClassMap Count: $($classmap.count)"
}else{
    Write-Verbose "`t`tImport ClassMap Data: Failed"
}
Write-Verbose ""

Write-Verbose "Initialize: Import Attribute Data"
$attribdata = Import-ADDModuleData -DataSet AttribMap -QueryFilter attributeSchema
if($attribdata){
    Write-Verbose "`t`tImport Attribute Data: Success"
    $attribmapTmp = @{}
    $attribdata | ForEach-Object {$attribmapTmp[$_.OBJ_Name]=[System.GUID]$_.OBJ_guid}

    $mcsAdmPwdPath = "LDAP://CN=ms-Mcs-AdmPwd,$schemaNamingContext"
    $mcsAdmPwdExpirePath = "LDAP://CN=ms-Mcs-AdmPwdExpirationTime,$schemaNamingContext"
    if($([adsi]::Exists($mcsAdmPwdPath))){
        New-Variable -Name LAPSDeployed -Value $true -Scope Script -Visibility Private

        $mcsAdmPwdItem = [adsi]$mcsAdmPwdPath
        $mcsAdmPwdGuid = ([guid]$($mcsAdmPwdItem.schemaIDGUID)).Guid
        $attribmapTmp[$($mcsAdmPwdItem.lDAPDisplayName)]=[System.Guid]$mcsAdmPwdGuid

        $mcsAdmPwdExpireItem = [adsi]$mcsAdmPwdExpirePath
        $mcsAdmPwdExpireGuid = ([guid]$($mcsAdmPwdExpireItem.schemaIDGUID)).Guid
        $attribmapTmp[$($mcsAdmPwdExpireItem.lDAPDisplayName)]=[System.Guid]$mcsAdmPwdExpireGuid

        $Self = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-10")
        New-Variable -Name SelfSID -Value $Self -Scope Script -Visibility Private

        $mcsAdmPwdExpireSelfAclDef = New-Object -TypeName System.DirectoryServices.ActiveDirectoryAccessRule($SelfSID,"ReadProperty, WriteProperty","Allow",$([System.DirectoryServices.ActiveDirectorySecurityInheritance]'Descendents'),$($classmap["computer"]))
        $mcsAdmPwdPassSelfAclDef = New-Object -TypeName System.DirectoryServices.ActiveDirectoryAccessRule($SelfSID,"WriteProperty","Allow",$([System.DirectoryServices.ActiveDirectorySecurityInheritance]'Descendents'),$($classmap["computer"]))

        New-Variable -Name LAPSSelfAces -Value (New-Object System.Collections.Generic.List[System.DirectoryServices.ActiveDirectoryAccessRule])
        $LAPSSelfAces.Add($mcsAdmPwdExpireSelfAclDef)
        $LAPSSelfAces.Add($mcsAdmPwdPassSelfAclDef)
    }else{
        New-Variable -Name LAPSDeployed -Value $false -Scope Script -Visibility Private
    }

    New-Variable -Name attribmap -Value $attribmapTmp -Scope Script -Visibility Private
    Write-Debug "`t`tAttribMap Count: $($attribmap.count)"
}else{
    Write-Verbose "`t`tImport Attribute Data: Failed"
}

Write-Verbose "Initialize: Import ExRights Data"
$exrights = Import-ADDModuleData -DataSet AttribMap -QueryFilter controlAccessRight
if($exrights){
    Write-Verbose "`t`tImport ExRights Data: Success"
    $exrightsmapTmp = @{}
    $exrights | ForEach-Object {
        $exRightsPath = "LDAP://CN=$($_.OBJ_Name),CN=Extended-Rights,$configNamingContext"
        $exRightsItem = [adsi]$exRightsPath
        $exRightsGuid = ([guid]$($exRightsItem.rightsGuid)).Guid
        $exrightsmapTmp[$_.OBJ_Name]=$exRightsGuid
    }
    New-Variable -Name exrightsmap -Value $exrightsmapTmp -Scope Script -Visibility Private
    Write-Debug "`t`tExRightsMap Count - $($exrightsmap.count)"
}else{
    Write-Verbose "`t`tImport ExRights Data: Failed"
}

Write-Verbose ""

#endregion CreatePrimaryReferenceHashes

New-Variable -Name OUGlobal -Value $(($CoreData | Where-Object{$_.OU_type -like "Shared"}).OU_name) -Scope Script -Visibility Private
Write-Verbose "`t`tOUGlobal - $OUGlobal"
Write-Verbose ""

#region ImportOrgData
Write-Verbose "Initialize: Import Org data"
if($OrgPref -notlike "Custom"){
    Write-Verbose "`t`tOrg Type: Builtin - $OrgPref"
    $OrgData = Import-ADDModuleData -DataSet OUOrg -QueryFilter $OrgPref
}else{
    $OrgData = Import-ADDModuleData -DataSet OUOrg
    Write-Verbose "`t`tOrg Type: Custom"
}
Write-Verbose ""

if($OrgData){
    New-Variable -Name OrgImported -Value $true -Scope Script -Visibility Private
    New-Variable -Name MaxLvlSet -Value $true -Scope Script -Visibility Private

    New-Variable -Name OUOrg -Value $OrgData -Scope Script -Visibility Private
    New-Variable -Name MaxLevel -Value 1 -Scope Script -Visibility Private
}else{
    New-Variable -Name OrgImported -Value $false -Scope Script -Visibility Private
    New-Variable -Name MaxLvlSet -Value $false -Scope Script -Visibility Private
}

Write-Verbose "`t`tOrg Data Imported:`t$OrgImported"
Write-Verbose "`t`tOrg MaxLevel Set:`t$MaxLvlSet"
Write-Verbose ""
#endregion ImportOrgData

#region ImportMiscData
Write-Verbose "Initialize: Import Object Data"
$ObjectInfo = Import-ADDModuleData -DataSet AllObjInfo
if($ObjectInfo){
    Write-Verbose "`t`tImport Object Data: Success"
    New-Variable -Name ObjInfo -Value $ObjectInfo -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport Object Data: Failed"
}
Write-Verbose ""

Write-Verbose "Initialize: Import AclPropGroup Data"
$AclPropGroupData = Import-ADDModuleData -DataSet AclPGData
if($AclPropGroupData){
    Write-Verbose "`t`tImport PropGroup Data: Success"
    New-Variable -Name PropGroups -Value $AclPropGroupData -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport PropGroup Data: Failed"
}

Write-Verbose "Initialize: Import PropGroups Data"
$PropGroupsData = Import-ADDModuleData -DataSet AllPGData
if($PropGroupsData){
    Write-Verbose "`t`tImport PropGroups Data: Success"
    New-Variable -Name AllPropGroups -Value $PropGroupsData -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport PropGroups Data: Failed"
}

Write-Verbose "Initialize: Import PropGroupMap Data"
$PropGroupMapData = Import-ADDModuleData -DataSet AllPGMapData
if($PropGroupMapData){
    Write-Verbose "`t`tImport PropGroup Data: Success"
    New-Variable -Name PropGroupMap -Value $PropGroupMapData -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport PropGroupMap Data: Failed"
}
#endregion ImportMiscData


#region SetDestinationPathReferences
Write-Verbose "Initialize: Import DestID Data"
$DestIDInfo = Import-ADDModuleData -DataSet "PropGroupDestIDs"
if($DestIDInfo){
    Write-Verbose "`t`tImport DestID Data: Success"
    New-Variable -Name DestIDs -Value $(($DestIDInfo).OBJ_destination -join ", ") -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport DestID Data: Failed"
}

Write-Verbose "Initialize: Import DestHash Data"
$DPathData = Import-ADDModuleData -DataSet PGPathValues -QueryFilter $DestIDs
if($DPathData){
    Write-Verbose "`t`tImport DPath Data: Success"
    New-Variable -Name DPaths -Value $DPathData -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport DPath Data: Failed"
}

Write-Verbose "Initialize: Create Destination Hash"
$DestHashTmp = @{}
foreach($DPath in $DPaths){
    if($DPath.OBJ_SubTypeOU){
        $SubPath = "OU=$($DPath.OBJ_SubTypeOU),OU=$($DPath.OBJ_TypeOU)"
    }else{
        $SubPath = "OU=$($DPath.OBJ_TypeOU)"
    }
    $DestHashTmp.($DPath.OBJ_id) = $SubPath
}

if($DestHashTmp){
    Write-Verbose "`t`tCreate Destination Hash: Success"
    New-Variable -Name DestHash -Value $DestHashTmp -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tCreate Destination Hash: Failed"
}
#endregion SetDestinationPathReferences


#region SetDomainReferences
$allGuidTmp = New-Object GUID 00000000-0000-0000-0000-000000000000
New-Variable -Name allGuid -Value $allGuidTmp -Scope Script -Visibility Private

$EveryoneSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0")
$ProtectedAceDef = $EveryoneSID,"DeleteTree, Delete","Deny"
$ProtectedAceChildDef = $EveryoneSID,"DeleteChild","Deny"
New-Variable -Name ProtectedAce -Value $(New-Object System.DirectoryServices.ActiveDirectoryAccessRule($ProtectedAceDef)) -Scope Script -Visibility Private
New-Variable -Name ProtectedChildAce -Value $(New-Object System.DirectoryServices.ActiveDirectoryAccessRule($ProtectedAceChildDef)) -Scope Script -Visibility Private

New-Variable -Name OUdnRegEx -Value '^(?:(?<cn>CN=(?<name>[^,]*)),)?(?:(?<path>(?:(?:CN|OU)=[^,]+,?)+),)?(?<domain>(?:DC=[^,]+,?)+)$' -Scope Script -Visibility Private
New-Variable -Name DomDNRegEx -Value '(DC.+?)$' -Scope Script -Visibility Private

Write-Verbose "Initialize: Determine domain values"
$HostDom = $ENV:USERDNSDOMAIN
$HostDomSuf = $HostDom.Replace('.',',DC=')
$HostDomDN = "DC=$($HostDomSuf)"
if($Initialized){
    if($DomName -notlike $HostDom){
        $DomChoice = Show-PromptOptions -PromptInfo @("Initialize - Domain Mismatch","The domain this system is joined to does not match the last run. Please specify how to proceed.") -Options "Update and Continue","Quit"

        switch ($DomChoice) {
            0 {
                Write-Verbose "DomChoice: 1 - Update and Continue"
                Export-ADDModuleData -DataSet "SetRunData" -QueryValue "$HostDom","DomName"
            }
            1 {
                Write-Verbose "DomChoice: 2 - Quit"
                Read-Host "Quit was selected - Pressing 'Enter' key will close the shell (Press Ctrl+C to just abort module load)"
                exit
            }
        }
    }
}
New-Variable -Name DomFull -Value $HostDom -Scope Script -Visibility Private
New-Variable -Name DomSuf -Value $HostDomSuf -Scope Script -Visibility Private
New-Variable -Name DomDN -Value $HostDomDN -Scope Script -Visibility Private

#endregion SetDomainReferences

#region CheckDBScopeOUs
$AllScopeDNs = @(Get-ADDOrgUnit -Level SL).where({($_.distinguishedname -notlike "OU=Provision,*") -and ($_.distinguishedname -notlike "OU=Deprovision,*")}) | select-object distinguishedname

$PathElements = @()

foreach($Scope in $AllScopeDNs){ 
	$PItems = (($Scope).split(",") -replace "OU=")
	$FocusShort = $PItems[1]
	
	switch ($PItems[2]){
		{$_ -like "*-0"} {$TInc = 1}
		{$_ -like "*-1"} {$TInc = 2}
		{$_ -like "*-2"} {$TInc = 3}
	}

	$Obj = [PSCustomObject]@{
		Name = $PItems[0]
		Focus = $CEFocusHash["$FocusShort"]
		Tier = $TInc
	}
	
	$PathElements += $Obj
}

foreach($PE in $PathElements){
	$prop = "OU_$($PE.Focus)"
	if(-not($OUOrg | Where-Object{$_.OU_name -like $PE.Name -and $_.$prop -eq 1})){
		$Query = "AddOrgEntry$($PE.FocusOU)"
		
		Export-ADDModuleData -DataSet $Query -QueryValue $($PE.name),$null,$($PE.Tier)
	}
}

#endregion CheckDBScopeOUs

#endregion DataImport:CoreItems

#region LogDataIndentLevels
## Primary Functions - Chained Run
### Base Level
New-Variable -Name LP -Value $("`t") -Scope Script -Visibility Private
### Begin/End Sections
New-Variable -Name LPB1 -Value $($LP * 2) -Scope Script -Visibility Private
New-Variable -Name LPB2 -Value $($LP * 3) -Scope Script -Visibility Private
### Process Section
New-Variable -Name LPP1 -Value $($LPB2) -Scope Script -Visibility Private
New-Variable -Name LPP2 -Value $($LP * 4) -Scope Script -Visibility Private
New-Variable -Name LPP3 -Value $($LP * 5) -Scope Script -Visibility Private
New-Variable -Name LPP4 -Value $($LP * 6) -Scope Script -Visibility Private

## Secondary Functions - Chained Run
### Base Level
New-Variable -Name LS -Value $($LPB2) -Scope Script -Visibility Private
### Begin/End Sections
New-Variable -Name LSB1 -Value $("$LS`t") -Scope Script -Visibility Private
New-Variable -Name LSB2 -Value $("$LS`t`t") -Scope Script -Visibility Private
### Process Section
New-Variable -Name LSP1 -Value $($LSB2) -Scope Script -Visibility Private
New-Variable -Name LSP2 -Value $("$LSB2`t") -Scope Script -Visibility Private
New-Variable -Name LSP3 -Value $("$LSB2`t`t") -Scope Script -Visibility Private
New-Variable -Name LSP4 -Value $("$LSB2`t`t`t") -Scope Script -Visibility Private


#endregion LogDataIndentLevels

#region ArgumentCompleters

### TDG suffix name argument completer
$ZTDGNameSB = {
	param($commandName,$parameterName,$stringMatch)
	$AllPropGroups | Where-Object{$_.OBJ_name -like "$stringMatch*"} | Sort-Object -Property OBJ_name | Select-Object -ExpandProperty OBJ_name
}

Register-ArgumentCompleter -CommandName Get-ADDTaskGroup -ParameterName TaskName -ScriptBlock $ZTDGNameSB

$ZRefTypeSB = {
	param($commandName,$parameterName,$stringMatch)
    $ObjInfo | Where-Object{$_.OBJ_refid -like "$stringMatch*" -and $_.OBJ_ItemType -like "Primary"} | Sort-Object -Property OBJ_refid | Select-Object -ExpandProperty OBJ_refid
}

Register-ArgumentCompleter -CommandName Get-ADDTaskGroup -ParameterName ReferenceID -ScriptBlock $ZRefTypeSB

$ZFocusNamesSB = {
	param($commandName,$parameterName,$stringMatch)
	$FocusHash.Values | Where-Object {$_ -like "$stringMatch*" -and $_ -notlike "STG"}
}

Register-ArgumentCompleter -CommandName New-ADDOrgUnit -ParameterName Focus -ScriptBlock $ZFocusNamesSB

# End Supplemental load elements
# Non-function exported public module members might go here.
#Export-ModuleMember -Variable SomeVariable -Function  *