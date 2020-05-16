Import-Module (Join-Path $MyModulePath 'plugins\nlog\NLOG\NLogModule\0.0.2\NLogModule.psd1') -Force -Scope:Global
$FileDate = (Get-Date).ToString("dd-MM-yyyy-hhmmss")
$LoggingTarget = New-NLogFileTarget -FileName (Join-Path $ENV:TEMP "ADDeploy_$FileDate.log") -maxArchiveFiles 40 -ArchiveAboveSize 30720000 -KeepFileOpen
Register-NLog -Target $LoggingTarget -LoggerName "Log-ADDeploy"
New-Variable -Name AVALogPath -Value $($LoggingTarget.FileName.Text | Split-Path -Parent) -Scope Global -Visibility Private