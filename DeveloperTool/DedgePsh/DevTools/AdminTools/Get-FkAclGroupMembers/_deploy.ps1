Import-Module Deploy-Handler.psm1 -Force
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("*fkxtst-app")

#$(Get-ValidServerNameList)