@{
	Author = 'Roman Kuzmin'
	ModuleVersion = '1.6.1'
	Description = 'SplitPipeline - Parallel Data Processing in PowerShell'
	CompanyName = 'https://github.com/nightroman/SplitPipeline'
	Copyright = 'Copyright (c) 2011-2018 Roman Kuzmin'

	ModuleToProcess = 'SplitPipeline.dll'

	PowerShellVersion = '2.0'
	GUID = '7806b9d6-cb68-4e21-872a-aeec7174a087'

	CmdletsToExport = 'Split-Pipeline'
	FunctionsToExport = @()
	VariablesToExport = @()
	AliasesToExport = @()

	PrivateData = @{
		PSData = @{
			Tags = 'Parallel', 'Pipeline', 'Runspace', 'Invoke', 'Foreach'
			LicenseUri = 'http://www.apache.org/licenses/LICENSE-2.0'
			ProjectUri = 'https://github.com/nightroman/SplitPipeline'
			ReleaseNotes = 'https://github.com/nightroman/SplitPipeline/blob/master/Release-Notes.md'
		}
	}
}
