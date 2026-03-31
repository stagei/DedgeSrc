Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot -DeployModules $false -ComputerNameList @("*prd*")
Deploy-Files -FromFolder $PSScriptRoot -DeployModules $false -ComputerNameList @("*rap*")
