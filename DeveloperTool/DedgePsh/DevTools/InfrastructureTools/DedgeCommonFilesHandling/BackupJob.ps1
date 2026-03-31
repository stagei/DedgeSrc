Import-Module GlobalFunctions -Force
$fromFolderPath = Get-ConfigFilesPath

$toFolderPath = Get-ApplicationDataPath

$date = Get-Date -Format "yyyyMMdd-HHmm"
$toFolderPath = Join-Path $toFolderPath $date
New-Item -Path $toFolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Copy-Item -Path $fromFolderPath\* -Destination $toFolderPath -Force -Recurse

Get-ChildItem -Path $toFolderPath | Select-Object -Property Directory, Name, LastWriteTime | Format-Table -AutoSize

$toFolderPath = Join-Path $PSScriptRoot "Backup"
New-Item -Path $toFolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Copy-Item -Path $fromFolderPath\* -Destination $toFolderPath -Force -Recurse

Write-LogMessage -Message "Backuped config files to $toFolderPath"
# lIST FILES IN BACKUP FOLDER

