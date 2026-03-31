$scriptPath = Join-Path $env:OptPath "DedgePshApps\Db2-ExportServerConfig"
$command = "DB2CMD.EXE " + $scriptPath + "\Db2-ExportServerConfig.bat 1"
Write-Host $command
Invoke-Expression $command

