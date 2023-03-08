function Publish-ADDDBMemData {
    [CmdletBinding(DefaultParameterSetName="Hash")]
    param (
        [Parameter(ParameterSetName="Variable",Mandatory=$true)]
        [ValidateSet("DomName","TierRegex","TierDNRegEx","CETierRegEx","CETierDNRegEx","FocusRegEx","FocusDNRegEx",
        "OUGlobal","MaxLvlSet","ProtectedAce","ProtectedChildAce","OUdnRegEx","DomDNRegEx","DomFull","DomSuf","DomDN","availModuleClasses")]
        [string]$VarName,
        [Parameter(ParameterSetName="Hash",Mandatory=$true)]
        [ValidateSet("CoreData","TierHash","CETierHash","FocusHash","CEFocushHash","AttributeHash","RightsHash","ClassMap","AttribMap","ExRightsMap",
        "OUOrg","ObjInfo","PropGroups","AllPropGroups","PropGroupMap","DestHash")]
        [string]$HashName,
        [Parameter(ParameterSetName="Hash")]
        [string]$HashKey,
        [Parameter(ParameterSetName="Enum")]
        [ValidateSet("TierSet","FocusSet","EnvType","RoleStatus","RoleType","ScopeType","ModClass")]
        [string]$EnumName,
        [Parameter(ParameterSetName="List")]
        [switch]$ListAvailable,
        [Parameter(ParameterSetName="List")]
        [ValidateSet("SingleValue","ArrayLookup","HashLookup","Enum")]
        [string]$ExType
    )

    Function Get-ZTEnumValue {
        Param([string]$ename)

        $enumValues = @{}

        $evals = [enum]::GetValues([type]$ename)

        foreach($e in $evals){
            $enumValues.Add($_, $_.value__)
        }

        $enumValues
    }

    switch ($PScmdlet.ParameterSetName) {
        "List" {
            $DP = Join-Path -Path $MyModulePath -ChildPath '\srv\other\DBData.json'
            $DPData = Get-Content $DP | ConvertFrom-Json

            if($ExType){
                $DPData | Where-Object{$_.Type -like "$ExType"}
            }else{
                $DPData | Format-Table Name,Type,Description -AutoSize
            }
        }

        "Hash" {
            $Hash = (Get-Variable "$HashName").Value

            if($HashKey){
                $Hash["$HashKey"]
            }else{
                Write-Output $Hash
            }
        }

        "Variable" {
            $var = (Get-Variable "$VarName").Value
            Write-Output $var
        }

        "Enum" {
            Get-ZTEnumValue -ename $EnumName
        }
    }

}