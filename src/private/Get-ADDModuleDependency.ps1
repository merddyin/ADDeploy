function Get-ADDModuleDependency {
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
