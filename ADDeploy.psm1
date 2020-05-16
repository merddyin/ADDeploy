# Current script path
[string]$ModulePath = Split-Path (get-variable myinvocation -scope script).value.Mycommand.Definition -Parent

# Module Pre-Load code
. (Join-Path $ModulePath 'src\other\PreLoad.ps1') @ProfilePathArg

# Private and other methods and variables
Get-ChildItem (Join-Path $ModulePath 'src\private') -Recurse -Filter "*.ps1" -File | Sort-Object Name | ForEach-Object {
    Write-Verbose "Dot sourcing private script file: $($_.Name)"
    . $_.FullName
}

# Load and export public methods
$FunctionFiles = Get-ChildItem (Join-Path $ModulePath 'src\public') -Recurse -Filter "*.ps1" -File
ForEach($FunctionFile in $FunctionFiles) {
    $Path = $FunctionFile.FullName
    Write-Verbose "Dot sourcing public script file: $($FunctionFile.Name)"
    . $Path

    # Find all the functions defined no deeper than the first level deep and export it.
    $Content = Get-Content -Path $Path -Raw
    if($Content){
        $ASTdata = [System.Management.Automation.Language.Parser]::ParseInput(($Content), [ref]$null, [ref]$null)
        Export-ModuleMember ($ASTdata.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false)).Name
    }else{
        Write-Verbose "FileName: $($FunctionFile.Name)`tIssue: No data, skipping export"
    }
}

#TODO: Add new cmdlet to allow replace/rename of Org containers or structure - should include steps for: create new structure, move objects, delete legacy, and update DB
#TODO: Add support for centrally located DB - should include deployment of new DB, update of connection profile, and migration of content if firstrun previously executed
# Module Post-Load code
. (Join-Path $ModulePath 'src\other\PostLoad.ps1')
