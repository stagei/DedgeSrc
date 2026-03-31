Import-Module ScheduledTask-Handler -Force

Add-DefaultScheduledTasksServer
if ($env:COMPUTERNAME.ToLower().Contains("-db")) {
    Add-DefaultScheduledTasksServerDatabase
}

