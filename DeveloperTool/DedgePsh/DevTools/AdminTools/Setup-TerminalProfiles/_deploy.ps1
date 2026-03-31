Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot 
#-ComputerNameList @("p-no1avd-vdi0*")