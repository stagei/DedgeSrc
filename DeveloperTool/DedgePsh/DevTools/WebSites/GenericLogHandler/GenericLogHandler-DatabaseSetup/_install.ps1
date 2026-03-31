if ($env:COMPUTERNAME.ToLower() -eq "t-no1fkxtst-db" -or $env:COMPUTERNAME.ToLower() -eq "p-no1fkxprd-db") {
    Import-Module ScheduledTask-Handler -Force
    New-ScheduledTask -SourceFolder $PSScriptRoot\DedgeAuth-Backup-Database.ps1 -TaskFolder "Database" -RecreateTask $true -RunFrequency "Daily" -StartHour 3 -RunAsUser $true -RunAtOnce $true
    Get-ProcessedScheduledCommands -Format "Format-Table" -Properties @( "Context", "Command", "Output") -Clear $true
}

