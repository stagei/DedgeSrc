Import-Module GlobalFunctions -Force
Import-Module ScheduledTask-Handler -Force
Import-Module SoftwareUtils -Force
# Setup logging
Write-LogMessage "Starting Refresh-WorkstationSettings script" -Level INFO
Start-OurPshApp -AppName "Upd-Apps"
Save-ScheduledTaskFiles
Write-LogMessage "Refresh-WorkstationSettings script completed successfully" -Level INFO

