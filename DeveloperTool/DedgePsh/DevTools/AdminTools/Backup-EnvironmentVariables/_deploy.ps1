Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot -DeployModules $false -ComputerNameList @("*")
