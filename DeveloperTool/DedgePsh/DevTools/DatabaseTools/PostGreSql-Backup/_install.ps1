Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force
Import-Module ScheduledTask-Handler -Force -ErrorAction Stop

$pgFolders = Find-PgFolders

Register-FkScheduledTask -TaskName "PostGreSql-Backup" `
    -ScriptPath (Join-Path $env:OptPath "DedgePshApps\PostGreSql-Backup\PostGreSql-Backup.ps1") `
    -ScheduleType Daily -AtTime "02:00"
