
Import-Module Deploy-Handler -Force
Import-Module GlobalFunctions -Force
Import-Module ScheduledTask-Handler -Force

$taskname = "agent"
$taskfolder = "DevTools"
# Remove the task
Remove-ScheduledTask -TaskName $taskname -TaskFolder $taskfolder

