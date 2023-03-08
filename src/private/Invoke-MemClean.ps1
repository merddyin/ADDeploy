function Invoke-MemClean {
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
        Help Last Updated: 10/24/2020

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
	param()
    $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
    Write-Verbose "$($LS)------------------- $($FunctionName): Start -------------------"
    Write-Verbose ""

	Write-Verbose "$($LSB1)Initiating forced garbage collection (memory cleanup)"
	$MemoryUsed = [System.gc]::GetTotalMemory("forcefullcollection") /1MB
	Write-Verbose "$($LSB2)Current Memory in Use (Loop 20) - $($MemoryUsed) - Initiating cleanup"
	[System.GC]::Collect()
	[System.gc]::GetTotalMemory("forcefullcollection") | Out-Null
	[System.GC]::Collect()
	[System.gc]::GetTotalMemory("forcefullcollection") /1MB | Out-Null
	Write-Verbose "$($LSB2)Post-Cleanup Memory in Use - $($MemoryUsed) MB - Resetting Loop Count"
	Write-Verbose "$($LS)------------------- $($FunctionName): End -------------------"
}