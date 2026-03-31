Import-Module ScheduledTask-Handler -Force

if (Test-IsDb2Server) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -Executable "Db2-FederationHandlerStandardInstanceDb2Refresh.ps1" -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 06 -StartMinute 00 -RunAsUser $true 

    if ($env:COMPUTERNAME.ToLower().Contains("fkmprd-db")) {
        New-ScheduledTask -SourceFolder $PSScriptRoot -Executable "Db2-FederationHandlerHistoryFkmprdFkmHstRefresh.ps1" -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 05 -StartMinute 30 -RunAsUser $true 
    }
}
