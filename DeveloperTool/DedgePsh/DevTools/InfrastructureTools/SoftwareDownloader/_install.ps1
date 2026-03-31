if ($env:COMPUTERNAME.ToLower() -eq "p-no1avd-vdi024") {
    Import-Module ScheduledTask-Handler -Force
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 9 -RunAsUser $true -RunAtOnce $true
    #Get-ProcessedScheduledCommands -Format "Format-Table" -Properties @( "Context", "Command", "Output") -Clear $true
}

