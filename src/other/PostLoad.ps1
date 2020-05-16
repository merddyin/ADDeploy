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

# Supplemental load elements
$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name

#region LoadNon-PluginModules
#TODO: Reorg function - Group all by type and reorder: import data, create ref hashes, create ref variables, process initialization (validate order vs dependencies)
#TODO: Adjust logging - Change all current items to Debug, Create pass/fail var for each section (above), Output mod load summary using section vars with Verbose
#TODO: P1 - add import progress feedback
Write-Debug -Message "Processing GroupPolicy module dependency..."
$GPModuleLoad = Get-ADDModuleDependency -Name GroupPolicy
if(-not($GPModuleLoad.ImportResult)){
    Write-Debug "GroupPolicy module dependency issue found - throwing fatal error which should abort import"
    Throw "Dependent Module Load Error`nModule: GroupPolicy`nStatus: $($ADModuleLoad.ModuleStatus)`nImport Result: $($ADModuleLoad.ImportResult)`nImport Message: $($ADModuleLoad.ImportMessage)"
}
#endregion LoadNon-PluginModules

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
        #TODO: Add code to run initial module setup
        #?: Should initial setup just be a cmdlet, or should it be a plugin?

        #TODO: Review all functions to ensure Rundata values are being effectively used
    }

    New-Variable -Name Initialized -Value $NotFirstRun -Scope Script -Visibility Private

}else{
    Write-Verbose "`t`tImport Rundata: Failed"
    Write-Error "Unable to import Rundata from DB - Quitting load sequence" -ErrorAction Stop
}

Write-Verbose "Initialize: Import core OU data"
$CoreData = Import-ADDModuleData -DataSet OUCore
if($CoreData){
    Write-Verbose "`t`tImport Core data: Success"
    New-Variable -Name CoreOUs -Value $CoreData -Scope Script -Visibility Private
}else{
    Write-Verbose "`t`tImport Core Data: Failed"
    Write-Error "Unable to import Core Data from DB - Quitting load sequence" -ErrorAction Stop
}

#region CreatePrimaryReferenceHashes
# Abbreviated Tier Values - Used for GPO and Group Names
## When using defaults, values are; T0, T1, T2
$TierHashTmp = @{}
$CoreOUs | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$TierHashTmp.($_.OU_name) = $_.OU_focus}
New-Variable -Name TierHash -Value $TierHashTmp -Scope Script -Visibility Private
New-Variable -Name TierRegEx -Value $($TierHash.Values -join "|") -Scope Script -Visibility Private
$TierDN = $TierHash.Values | ForEach-Object{"OU=$_"}
New-Variable -Name TierDNRegEx -Value $($TierDN -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tTierHash Values"
Write-Debug "`t`t`t`t$($TierHash | Out-String)"
Write-Verbose ""

# Full Tier Values - Used for OU Names
## When using defaults, values are; Tier-0, Tier-1, Tier-2
$CETierHashTmp=@{}
$CoreOUs | Where-Object{$_.OU_type -like "Tier"} | ForEach-Object{$CETierHashTmp.($_.OU_focus) = $_.OU_name}
New-Variable -Name CETierHash -Value $CETierHashTmp -Scope Script -Visibility Private
New-Variable -Name CETierRegEx -Value $($CETierHash.Values -join "|") -Scope Script -Visibility Private
$CETierDN = $CETierHash.Values | ForEach-Object{"OU=$_"}
New-Variable -Name CETierDNRegEx -Value $($CETierDN -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tCETierHash Values"
Write-Verbose "`t`t`t`t$($CETierHash | Out-String)"
Write-Verbose ""

$FocusHashTmp = @{}
$CoreOUs | Where-Object{$_.OU_type -like "Focus"} | ForEach-Object{$FocusHashTmp.($_.OU_focus) = $_.OU_name}
New-Variable -Name FocusHash -Value $FocusHashTmp -Scope Script -Visibility Private
New-Variable -Name FocusRegEx -Value $($FocusHash.Values -join '|') -Scope Script -Visibility Private
$FocusDN = $FocusHash.Values | ForEach-Object{"OU=$_"}
# Create RegEx for detecting Focus containers
New-Variable -Name FocusDNRegEx -Value $($FocusDN -join "|") -Scope Script -Visibility Private
Write-Verbose "`t`tFocusHash Values"
Write-Verbose "`t`t`t`t$($FocusHash | Out-String -Stream)"
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
    New-Variable -Name attribmap -Value $attribmapTmp -Scope Script -Visibility Private
    Write-Debug "`t`tAttribMap Count: $($attribmap.count)"
}else{
    Write-Verbose "`t`tImport Attribute Data: Failed"
}
#TODO: Create priv function to query AD schema, compare to DB, and execute updates for changes or imports for new (i.e. LAPS since GUID is dynamic)

Write-Verbose "Initialize: Import ExRights Data"
$exrights = Import-ADDModuleData -DataSet AttribMap -QueryFilter controlAccessRight
if($exrights){
    Write-Verbose "`t`tImport ExRights Data: Success"
    $exrightsmapTmp = @{}
    $exrights | ForEach-Object {$exrightsmapTmp[$_.OBJ_Name]=[System.GUID]$_.OBJ_guid}
    New-Variable -Name exrightsmap -Value $exrightsmapTmp -Scope Script -Visibility Private
    Write-Debug "`t`tExRightsMap Count - $($exrightsmap.count)"
}else{
    Write-Verbose "`t`tImport ExRights Data: Failed"
}


#endregion CreatePrimaryReferenceHashes

New-Variable -Name OUGlobal -Value $(($CoreOUs | Where-Object{$_.OU_type -like "Shared"}).OU_name) -Scope Script -Visibility Private
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
    New-Variable -Name MaxLevel -Value $((($OUOrg | Select-Object OU_orglvl -Unique).OU_orglvl | Measure-Object -Maximum).Maximum) -Scope Script -Visibility Private
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
$InheritanceNone = [System.DirectoryServices.ActiveDirectorySecurityInheritance]'None'
$ProtectedAceDef = $EveryoneSID,"DeleteTree, Delete","Deny",$allGuidTmp
$ProtectedAceChildDef = $EveryoneSID,"DeleteChild","Deny",$allGuidTmp
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
        #TODO: Add prompt to determine if module should be reinitialized, update domain value only, or run cross-domain
        #TODO: If run cross-domain option is selected, prompt for credentials
        $DomChoice = Prompt-Options -PromptInfo @("Initialize - Domain Mismatch","The domain this system is joined to does not match the last run. Please specify how to proceed.") -Options "Reset and Re-initialize Module","Cross-Domain Execution","Update and Continue","Quit"

        switch ($DomChoice) {
            0 {
                Write-Verbose "DomChoice: 0 - Reset and Reinitialize Module"
                Write-Host "Option 0 selected - Reset and Re-initialize module" -ForegroundColor Yellow
                $ConfirmResetChoice = Prompt-Options -PromptInfo @("Confirm Reset","Please confirm you wish to reset the module. Warning!! This action cannot be undone!") -Options "Yes - Reset Module","No - Cancel Reset" -default 1
                #TODO: Add code for resetting module preferences
            }
            1 {
                Write-Verbose "DomChoice: 1 - Cross-Domain Execution"
                $LoadDomain = Read-Host -Prompt "Please specify the fully qualified domain name to connect to (e.g. mydomain.com)"
                #TODO: Add code to validate entry, as well as to set DomDN to DistinguishedName
                $LoadCred = Get-Credential -Message "Please specify admin credentials to use when connecting to the target domain ($LoadDomain)"
            }
            2 {
                Write-Verbose "DomChoice: 2 - Update and Continue"
                Export-ADDModuleData -DataSet "SetRunData" -QueryValue "$HostDom","DomName"
            }
            3 {
                Write-Verbose "DomChoice: 3 - Quit"
                Read-Host "Quit was selected - Pressing 'Enter' key will close the shell (Press Ctrl+C to just abort module load)"
                exit
            }
        }

        New-Variable -Name DomFull -Value $HostDom -Scope Script -Visibility Private
        New-Variable -Name DomSuf -Value $HostDomSuf -Scope Script -Visibility Private
        New-Variable -Name DomDN -Value $HostDomDN -Scope Script -Visibility Private

    }else{
        New-Variable -Name DomFull -Value $HostDom -Scope Script -Visibility Private
        New-Variable -Name DomSuf -Value $HostDomSuf -Scope Script -Visibility Private
        New-Variable -Name DomDN -Value $HostDomDN -Scope Script -Visibility Private
    }

    Write-Verbose "`t`tDomFull:`t$DomFull"
    Write-Verbose "`t`tDomSuf:`t$DomSuf"
    Write-Verbose "`t`tDomDN:`t$DomDN"
}else{
    #TODO: Add code for initialization of module first run
}
#TODO: Once code sequence above is complete, update all functions to remove domain and credential parameters
#endregion SetDomainReferences

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


# End Supplemental load elements
# Non-function exported public module members might go here.
#Export-ModuleMember -Variable SomeVariable -Function  *