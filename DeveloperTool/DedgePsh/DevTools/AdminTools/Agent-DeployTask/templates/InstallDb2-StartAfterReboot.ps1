Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force

Install-OurPshApp -AppName "Db2-StartAfterReboot"
Write-LogMessage "Db2-StartAfterReboot installed" -Level INFO
Send-Sms -Receiver "+4797188358" -Message "$($env:COMPUTERNAME) - Db2-StartAfterReboot installed and Agent Worked"

