Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if ($env:USERNAME -eq "FKGEISTA") {
    New-ScheduledTask -SourceFolder $(Join-Path $env:OptPath "DedgePshApps\DedgeCommonFilesHandling" "BackupJob.ps1") -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 12 -RunAsUser $false -RunAtOnce $true

    Get-ProcessedScheduledCommands -RemovePasswordFromOutput $false
}

