function New-ADDADObject {
    [CmdletBinding()]
    Param (
        [string]$ObjName,
        [string]$ObjDescription,
        [string]$ObjParentDN,
        [string]$ObjType="organizationalUnit"
    )

    $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
    Write-Verbose ""
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t`tExecuting create AD Object..."
    Write-Verbose "`t`t`t`t`t`t`t`tName:`t$ObjName"
    Write-Verbose "`t`t`t`t`t`t`t`tDescription:`t$ObjDescription"
    Write-Verbose "`t`t`t`t`t`t`t`tParentDN:`t$ObjParentDN"
    Write-Verbose "`t`t`t`t`t`t`t`tObject Type:`t$ObjType"

    #TODO: Add path mismatch validation checking for calls from some cmdlets - need to make sure we don't create things in the wrong places

    if($ObjType -like "organizationalUnit"){
        $O = "OU"
    }else {
        $O = "CN"
    }

    if($ObjParentDN -like "LDAP://*"){
        $ParentPath = $ObjParentDN
        $ObjParentDN = ($ObjParentDN -split "//")[1]
    }else {
        $ParentPath = "LDAP://$ObjParentDN"
    }
    $ChildPath = "LDAP://$O=$ObjName,$ObjParentDN"

    Write-Verbose "`t`t`t`tParentPath:`t$ParentPath"
    Write-Verbose "`t`t`t`tChildPath:`t$ChildPath"

    if($([adsi]::Exists($ChildPath))){
        $OrgObj = New-Object System.DirectoryServices.DirectoryEntry($ChildPath)
        $ObjState = "Existing"
    }else{
        if($([adsi]::Exists($ParentPath))){
            $ParentDE = New-Object System.DirectoryServices.DirectoryEntry($ParentPath)
            try{
                $OrgObj = $ParentDE.psbase.Children.Add("$O=$ObjName","$ObjType")
                $ObjState = "New"
            }
            catch {
                Write-Verbose "Create failed"
                $ObjState = "Create Failed"
            }

            if($OrgObj){
                switch ($ObjType) {
                    {$_ -like "organizationalUnit"} {
                        $OrgObj.psbase.CommitChanges()

                        if($OUDescription){
                            $OrgObj.psbase.Properties["displayName"].Value = $ObjDescription
                        }

                        $OrgObj.psbase.ObjectSecurity.AddAccessRule($ProtectedAce)
                        $OrgObj.psbase.ObjectSecurity.AddAccessRule($ProtectedChildAce)
                        $OrgObj.psbase.CommitChanges()
                    }

                    {$_ -like "group"} {
                        $OrgObj.Properties["name"].Value = $ObjName
                        $OrgObj.Properties["sAMAccountName"].Value = $ObjName
                        $OrgObj.Properties["groupType"].Value = "-2147483646"
                        $OrgObj.CommitChanges()
                    }
                    Default {}
                }

            }

        }else {
            Write-Verbose "Parent not found"
            $ObjState = "No Parent"
        }
    }

    if($OrgObj){
        $OrgObjOut = [PSCustomObject]@{
            State = $ObjState
            DEObj = $OrgObj
        }

        return $OrgObjOut
    }
}
