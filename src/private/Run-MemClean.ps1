function Run-MemClean {
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
	$PostCleanupMemoryUsed = [System.gc]::GetTotalMemory("forcefullcollection") /1MB
	Write-Verbose "$($LSB2)Post-Cleanup Memory in Use - $($MemoryUsed) MB - Resetting Loop Count"
	Write-Verbose "$($LS)------------------- $($FunctionName): End -------------------"
}