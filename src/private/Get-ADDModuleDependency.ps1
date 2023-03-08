function Get-ADDModuleDependency {
<#
    .SYNOPSIS
        Determines if there any dependencies

    .DESCRIPTION
        Support function to determine if there are any AD module dependencies. Provides the Module Status as well as a load message to indicate if there 
        is a module present or not, if there is an issue with the module or if it is missing. 

    .PARAMETER Name
        Name of the module of interest
        

    .EXAMPLE
        Example

    .EXAMPLE
        Another example of how to use this cmdlet

    .NOTES
        Help Last Updated: 10/26/2020

        Cmdlet Version: 1.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    param (
        [string]$Name
    )

    #region PrimaryChecks
    if(-not(Get-Module -Name $Name)){

        #region FoundUnloaded-AttemptLoad
        if(Get-Module -ListAvailable | Where-Object {$_.Name -eq $Name}){
            Write-Debug -Message "Module: $($Name) - State: Present, but not loaded"
            $ModStatus = "Present"
            try {
                Write-Debug -Message "Module: $($Name) - Action: Attempting import"
                Import-Module -Name $Name
                $LoadResult = $true
                $LoadMessage = ""
            }
            catch {
                Write-Debug -Message "Module: $($Name) - State: Present, but import failed"
                $LoadResult = $false
                $LoadMessage = "ImportFail"
            }
        } else {
            Write-Debug -Message "Module: $($Name) - State: Missing"
            $ModStatus = "Missing"
            $LoadResult = $false
            $LoadMessage = "Module depenedency not found: $($Name)"
        }
        #endregion FoundUnloaded-AttemptLoad

    } else {
        Write-Debug -Message "Module: $($Name) - State: Already Imported"
        $ModStatus = "Present"
        $LoadResult = $true
        $LoadMessage = "Module already loaded: $($Name)"
    }
    #endregion PrimaryChecks

    #region ModuleSecondaryChecks
    Write-Debug -Message "Module: $($Name) - Action: Execute secondary checks, if any"
    #endregion ModuleSecondaryChecks

    #region ResultObject
    $objOutput = [PSCustomObject]@{
        ModuleStatus = $ModStatus
        ImportResult = $LoadResult
        ImportMessage = $LoadMessage
    }

    Return $objOutput
    #endregion ResultObject

} # End Test-ModuleDependency function
