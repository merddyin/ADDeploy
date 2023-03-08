function New-ADDADObject {
<#
    .SYNOPSIS
        Helper function to create OU and Group objects

    .DESCRIPTION
        Helper function to create OU and Group objects

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
        Help Last Updated: 5/6/2022

        Cmdlet Version: 1.2.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding(DefaultParameterSetName="Group")]
    Param (
        [Parameter(ParameterSetName="Group")]
        [Parameter(ParameterSetName="OrgUnit")]
        [string]$ObjName,

        [Parameter(ParameterSetName="Group")]
        [int]$ObjTier,

        [Parameter(ParameterSetName="Group")]
        [string]$ObjFocus,

        [Parameter(ParameterSetName="Group")]
        [string]$ObjScope,

        [Parameter(ParameterSetName="Group")]
        [string]$ObjRefType,

        [Parameter(ParameterSetName="Group")]
        [Parameter(ParameterSetName="OrgUnit")]
        [string]$ObjDescription="Created for ZTAD using ADDeploy",

        [Parameter(ParameterSetName="Group")]
        [string]$ObjOwner,

        [Parameter(ParameterSetName="Group")]
        [Parameter(ParameterSetName="OrgUnit")]
        [string]$ObjType = "group",

        [Parameter(ParameterSetName="Group")]
        [Parameter(ParameterSetName="OrgUnit")]
        [string]$ObjParentDN,

        [Parameter(ParameterSetName="OrgUnit")]
        [string]$ObjFriendlyName
    )

    $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
    Write-Verbose ""
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t`tExecuting create AD Object..."

    $AttribVals = @{}
    foreach($item in $($CoreData | Where-Object{$_.OU_type -like 'Attribute'})){
        $AttribVals[$item.OU_focus]="$($item.OU_name)"
    }

    $Tattrib = $AttribVals["Tier"]
    $Fattrib = $AttribVals["Focus"]
    $Sattrib = $AttribVals["Scope"]
    $Oattrib = $AttribVals["ObjRef"]

    if($ObjType -like "organizationalUnit"){
        $O = "OU"
    }else {
        $O = "CN"
    }
    
    Write-Verbose "`t`t`t`t`t`t`t`tO Value:`t$O"
    Write-Verbose "`t`t`t`t`t`t`t`tObjType Value:`t$ObjType"

    if($null -eq $ObjOwner){
        $ObjDom = [adsi]"LDAP://$DomDN"
        $DomSid = New-Object System.Security.Principal.SecurityIdentifier($ObjDom.objectSid[0],0)
        $rAdm = [adsi]"LDAP://<SID=$($DomSid.Value)-500>"
        $ObjOwner = $rAdm.distinguishedName
    }

    $ParentExists = $false
    if($null -eq $ObjParentDN){
        $ObjParentDN = $domdn
    }
    
    if($ObjParentDN -like "LDAP://*"){
        $ParentPath = $ObjParentDN
        $ObjParentDN = ($ObjParentDN -split "//")[1]
    }else {
        $ParentPath = "LDAP://$ObjParentDN"
    }

    Write-Debug "ParentPath: $ParentPath"
        
    $ParentExists = $([adsi]::Exists($ParentPath))

    $OjbChildDN = "$O=$ObjName,$ObjParentDN"
    $ChildPath = "LDAP://$OjbChildDN"

    Write-Verbose "`t`t`t`tParentPath:`t$ParentPath"
    Write-Verbose "`t`t`t`tChildPath:`t$ChildPath"

    if($([adsi]::Exists($ChildPath))){
        Write-Verbose "Child object already exists in target location; Binding and returning"
        $OrgObj = New-Object System.DirectoryServices.DirectoryEntry($ChildPath)
        $ObjState = "Existing"
    }else{
        Write-Verbose "Child object was not found in target location; Binding to parent"
        if($ParentExists){
            $ParentDE = New-Object System.DirectoryServices.DirectoryEntry($ParentPath)

            switch ($O) {
                {$_ -like "OU"} {
                    Write-Verbose "Attempting to create OU object..."

                    try{
                        $OrgObj = $ParentDE.psbase.Children.Add("$O=$ObjName","$ObjType")
                        $ObjState = "New"
                    }
                    catch {
                        Write-Verbose "Create failed"
                        $ObjState = "Create Failed"
                    }

                    $OrgObj.psbase.CommitChanges()
                    Write-Verbose "Create succeeded; Updating secondary properties..."

                    if($ObjFriendlyName){
                        $OrgObj.psbase.Properties["displayName"].Value = $ObjFriendlyName
                    }

                    $OrgObj.psbase.Properties["description"].Value = $ObjDescription

                    Write-Verbose "Adding delete protection..."
                    $OrgObj.psbase.ObjectSecurity.AddAccessRule($ProtectedAce)
                    $OrgObj.psbase.ObjectSecurity.AddAccessRule($ProtectedChildAce)
                    $OrgObj.psbase.CommitChanges()

                    if ($ObjName -like "Computers" -or $ParentPath -like "OU=$($FocusHash["Server"]),*") {
                        if($LAPSDeployed){
                            Write-Verbose "LAPS was detected: Adding associated LAPS Self ACLs to computer focused OU: $ObjName"
                            foreach($ace in $LAPSSelfAces){
                                $OrgObj.psbase.ObjectSecurity.AddAccessRule($ace)
                            }

                            $OrgObj.psbase.CommitChanges()
                        }
                    }
                }

                {$_ -like "CN"} {
                    Write-Verbose "Performing secondary check for group in wrong location..."
                    Write-Verbose "DomFull: $DomFull"
                    try {
                        $GrpExists = [ADSI]::Exists("WinNT://$DomFull/$ObjName,Group")
                    }
                    catch {
                        
                    }
                    if($GrpExists){
                        Write-Verbose "Group Object ($ObjName) found on secondary check; getting current location..."
                        $Current = (([adsisearcher]"name=$ObjName").FindOne()).path
                        if($Current){
                            $Group = New-Object System.DirectoryServices.DirectoryEntry($Current)
                            if($Group.Parent -notlike $ParentPath){
                                Write-Verbose "Location mismatch confirmed; Attempting move..."
                                Write-Verbose "Current: $Current`nTarget: $ParentPath"

                                try{
                                    ($Group.psbase).MoveTo([adsi]$ParentPath)
                                    Write-Verbose "Moved successfully"
                                    $OrgObj = New-Object System.DirectoryServices.DirectoryEntry($ChildPath)
                                    $ObjState = "Existing"
                                }
                                catch {
                                    Write-Verbose "Move failed"
                                    $ObjState = "Move Failed"
                                }
                            }else{
                                Write-Verbose "Current and Target paths match; Binding and returning..."
                                $OrgObj = New-Object System.DirectoryServices.DirectoryEntry($ChildPath)
                                $ObjState = "Existing"
                            }

                            Write-Verbose "Validating properties..."
                            if($($OrgObj.Properties["owner"]) -ne $ObjOwner){
                                $OrgObj.Properties["owner"].Value = $ObjOwner
                            }

                            if($($OrgObj.Properties["$Tattrib"]) -ne $ObjTier){
                                $OrgObj.Properties["$Tattrib"].Value = $ObjTier
                            }

                            if($($OrgObj.Properties["$Fattrib"]) -ne $ObjFocus){
                                $OrgObj.Properties["$Fattrib"].Value = $ObjFocus
                            }

                            if($($OrgObj.Properties["$Sattrib"]) -ne $ObjScope){
                                $OrgObj.Properties["$Sattrib"].Value = $ObjScope
                            }

                            if($($OrgObj.Properties["$Oattrib"]) -ne $ObjRefType){
                                $OrgObj.Properties["$Oattrib"].Value = $ObjRefType
                            }

                        }else{
                            Write-Verbose "Failed to bind to group for move"
                            $ObjState = "Move Failed"
                        }
                    }else{
                        # Group does not exist and must be created
                        Write-Verbose "Secondary check cleared; Attempting create..."
                        try{
                            $OrgObj = $ParentDE.psbase.Children.Add("$O=$ObjName","$ObjType")
                            $ObjState = "New"
                        }
                        catch {
                            Write-Verbose "Create failed"
                            $ObjState = "Create Failed"
                        }

                        Write-Verbose "No errors on create; Attempting to set primary properties..."
                        try{
                            $OrgObj.Properties["name"].Value = $ObjName
                            $OrgObj.Properties["sAMAccountName"].Value = $ObjName
                            $OrgObj.Properties["description"].Value = $ObjDescription
                            $OrgObj.Properties["groupType"].Value = "-2147483646"
                            $OrgObj.CommitChanges()
                        }
                        catch{
                            Write-Verbose "Received errors while setting primary properties - retrying"
                            try {
                                Start-Sleep -Seconds 1
                                $OrgObj.Properties["name"].Value = $ObjName
                                $OrgObj.Properties["sAMAccountName"].Value = $ObjName
                                $OrgObj.Properties["description"].Value = $ObjDescription
                                $OrgObj.Properties["groupType"].Value = "-2147483646"
                                $OrgObj.CommitChanges()
    
                            }
                            catch {
                                Write-Error "$($FunctionName): `tSecond attempt failed:$($ObjName)" -ErrorAction Continue
                            }
                        }

                        if($OrgObj){
                            Write-Verbose "$($FunctionName): `tAttempting to set secondary properties"
                            $OrgObj.Properties["owner"].Value = $ObjOwner
                            $OrgObj.Properties["$Tattrib"].Value = $ObjTier
                            $OrgObj.Properties["$Fattrib"].Value = $ObjFocus
                            $OrgObj.Properties["$Sattrib"].Value = $ObjScope
                            $OrgObj.Properties["$Oattrib"].Value = $ObjRefType
                            $OrgObj.CommitChanges()
    
                        }

                    }
                }
                Default {
                    Write-Verbose "No OrgObj processed..."

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
        Write-Verbose ""
	    Write-Verbose "`t`t`t`t`t`tObject created/moved"
	    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): End -------------------"
	    Write-Verbose ""
	    Write-Verbose ""

        return $OrgObjOut
    }else{
        Write-Verbose ""
	    Write-Verbose "`t`t`t`t`t`tNo return object - nothing created"
	    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): End -------------------"
	    Write-Verbose ""
	    Write-Verbose ""
    }
}
