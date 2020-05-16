function Export-ADDModuleData {
    <#
        .SYNOPSIS
            Exports data to the embedded Sqlite data source from a module function

        .DESCRIPTION
            This cmdlet initiates a connection to the ADDeploySettings.sqlite data source. After establishing the connection, the function
            executes one or more predefined queries to populate data into the Sqlite database for later future uses of the module.

            Note: Updates the embeded DB copy stored with the loaded module instance only - Updated DB will need to be redistributed to all
            module users, ideally via update of the module distribution package stored in a central location

        .PARAMETER DataSet
            Used to specify the name of a previously defined data set to be populated or updated

        .PARAMETER DataQuery
            Used to specify a custom query for pushing data into the database

        .EXAMPLE
            Placeholder text

        .NOTES
            Module developed by Topher Whitfield for deploying and maintaining a 'Red Forest' environment and all use and distribution rights remain in force.
            Help Last Updated: 7/22/2019

        .LINK
            https://mer-bach.com

    #>
[CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="StandardQuery")]
        [string]$DataSet,

        [Parameter(Position=1,ParameterSetName="StandardQuery")]
        [string[]]$QueryValue,

        [Parameter(Mandatory=$true,Position=0,ParameterSetName="CustomQuery")]
        [string]$DataQuery
        )

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "`n`n"
		Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""

        if(Test-Path $MyModulePath){
            $DBSrcPath = Join-Path -Path $MyModulePath -ChildPath '\src\other'
        }else{
            $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
            $DBSrcPath = Join-Path -Path $scriptDir -ChildPath '\src\other'
        }

        $DBPath = Join-Path -Path $DBSrcPath -ChildPath 'ADDeploySettings.sqlite'
        Write-Verbose "`t`t`t`t`t`t`t`tOpening connection to embeded sqlite db"
        if(Test-Path $DBPath){
            $conn = New-SQLiteConnection -DataSource $DBPath
        }else{
            Write-Error -Category ResourceUnavailable -CategoryActivity DBConnect -TargetObject $DBPath -Message "File not found" -ErrorAction Stop
        }

        Write-Debug "`t`t`t`t`t`t`t`tDataSet: `t$DataSet"
        if($QueryFilter){
            Write-Debug "`t`t`t`t`t`t`t`tQueryFilter:`t$QueryFilter"
        }else{
            Write-Debug "`t`t`t`t`t`t`t`tQueryFilter:`tNot Present"
        }
    }

    Process {
        Write-Debug "`t`t`t`t`t`t`t`tSet query text based on specified inputs"
        if($($PSCmdlet.ParameterSetName) -like "StandardQuery"){
            $QType = "DataSet"
            switch ($DataSet) {
                "SetRunData" {
                    $Query = "UPDATE AP_Rundata SET OB_runvalue = '$($QueryValue[0])' WHERE OB_item = '$($QueryValue[1])'"
                }

                "AddOrgEntry" {

                }

                "UpdateOrgEntry" {

                }
            }
        }else{
            $QType = "CustomQuery"
            $Query = $DataQuery
        }
    }

    End {
        Write-Verbose "`t`t`t`t`t`t`t`tData Set:`t$DataSet"
        Write-Verbose "`t`t`t`t`t`t`t`tQuery String:`t$Query"

        try
        {
            $Output = Invoke-SqliteQuery -Connection $conn -Query $Query
            if($Output){
                Write-Verbose "`t`t`t`t`t`t`t`tQuery Result:`tData Updated"
            }else{
                Write-Verbose "`t`t`t`t`t`t`t`tQuery Result:`tNo Data Updated"
            }
        }
        catch
        {
            Write-Error "`t`t`t`t`t`t`t`tQuery Result:`tFailed" -ErrorAction Continue
            Write-Debug "`t`t`t`t`t`t`t`tExecuted Query:`t$Query"
            Write-Debug "`t`t`t`t`t`t`t`tQuery Type: $QType"
        }

        Write-Verbose "`t`t`t`t`t`t`t`tClosing connection to embeded sqlite db"
        $conn.Close()
        Write-Verbose "`n"
        Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): End -------------------"
        Write-Verbose "`n`n"

        if($Output){
            Return $Output
        }
    }

}