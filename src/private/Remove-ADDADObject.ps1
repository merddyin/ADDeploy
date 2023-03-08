function Remove-ADDADObject {
<#
    .SYNOPSIS
        Helper function to remove OU and Group objects

    .DESCRIPTION
        Helper function to remove OU and Group objects

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
        Help Last Updated: 6/1/2022

        Cmdlet Version: 1.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^(OU=|CN=)(?=.*[A-Za-z]{2,4})')]
        [string]$ObjName,
        [string]$ObjType = "group",
        [Parameter(Mandatory=$true)]
        [ValidateScript({$_ -match $OUdnRegEx})]
        [string]$ObjParentDN
    )

    $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
    Write-Verbose ""
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t`t $($FunctionName): Executing remove AD Object..."

    Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): ObjType Value:`t$ObjType"

    if($ObjType -like "organizationalUnit"){
        $O = "OU=$($ObjName)"
        $Odn = "$O,$ObjParentDN"
        $ChildPath = "LDAP://$Odn"

        Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Object DN Value:`t$Odn"

        $Parent = New-Object System.DirectoryServices.DirectoryEntry($ObjParentDN)
        $Child = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Odn")

        if($([adsi]::Exists($ChildPath))){
            Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Child located ($($Child.DistinguishedName)): `tEnsuring OU is empty..."
            $OrgObj = $Child.DistinguishedName

            if("" -eq $Child.psbase.Children){
                Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): OU empty ($($Child.DistinguishedName)): `tRemoving protected ACEs..."
                $AceRemoved = $false
    
                try {
                    $RMPAce = $Child.psbase.ObjectSecurity.RemoveAccessRule($ProtectedAce)
                    $RMCAce = $Child.psbase.ObjectSecurity.RemoveAccessRule($ProtectedChildAce)
    
                    if($RMPAce -and $RMCAce){
                        $Child.psbase.CommitChanges()
                        $AceRemoved = $true
                    }else{
                        Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Remove ACE failed ($($Child.DistinguishedName))"
                        $ObjState = "Remove ACE Failed"
                    }
                }
                catch {
                    Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Remove ACE error ($($Child.DistinguishedName))"
                    $ObjState = "Remove ACE Error"
                }
                
                if($AceRemoved){
                    Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Protection Removed ($($Child.DistinguishedName)): `t Attempting delete..."
                    try {
                        $Parent.psbase.Children.Remove($Child)
                        $ObjState = "Removed"
                    }
                    catch [System.Management.Automation.MethodInvocationException] {
                        Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): OU not empty ($($Child.DistinguishedName))"
                        $ObjState = "Not Empty"
                    }
                    catch {
                        for($i = 1; $i -gt 0; $i--){
                            Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Delete Error ($($Child.DistinguishedName)): `t Retrying delete in $i seconds..."
                            Start-Sleep -Seconds 1
                        }

                        try {
                            $Parent.psbase.Children.Remove($Child)
                            $ObjState = "Removed"
                        }
                        catch {
                            Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Delete Error ($($Child.DistinguishedName)): `t Retry Failed"
                            $ObjState = "Delete Retry Error"
                        }
                    }
                }
    
            }

        }else{
            Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Delete Error ($($ChildPath)): `t Path not found"
            $ObjState = "Not Found"
        } #End IfElse - ChildPath Exists

        #EndIfElse - OrganizationalUnit
    }else {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $Context = [PrincipalContext]::new([ContextType]::Domain,$DomFull)

        Write-Verbose "$Context"

        try {
            $TargetGroup = [GroupPrincipal]::FindByIdentity($Context, $ObjName)
        }
        catch {
            Write-Verbose "`t`t`t`t`t`t`t`t $($FunctionName): Find failed"
            $ObjState = "Find Failed"
        }

        if($TargetGroup){
            Write-Verbose "`t`t`t`t`t`t`t $($FunctionName): Group located ($ObjName)- Attempting delete"
            $OrgObj = $TargetGroup.DistinguishedName

            try {
                $TargetGroup.Delete()
                $ObjState = "Removed" 
            }
            catch {
                Write-Verbose "`t`t`t`t`t`t`t $($FunctionName): Delete failed ($ObjName)"
                $ObjState = "Find Failed"
            }
        }
    } #EndIfElse - Group
    
    if($OrgObj){
        $OrgObjOut = [PSCustomObject]@{
            State = $ObjState
            DEObj = $OrgObj
        }
    }else{
        $OrgObjOut = [PSCustomObject]@{
            State = $ObjState
            DEObj = $OrgName
        }
    } #EndIfElse - OrgObj Exists

    return $OrgObjOut

    Write-Verbose ""
    Write-Verbose "`t`t`t`t`t`t $($FunctionName): Remove Complete `t -Result: $ObjState"
    Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): End -------------------"
    Write-Verbose ""
    Write-Verbose ""
}
    