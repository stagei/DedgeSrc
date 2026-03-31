Import-Module ScheduledTask-Handler -Force

if ($env:COMPUTERNAME.ToLower().Trim() -eq "dedge-server") {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 1 -RunAsUser $true -RunAtOnce $true
    # Get-ProcessedScheduledCommands -Format "Format-Table" -Properties @( "Context", "Command", "Output") -Clear $true
}

