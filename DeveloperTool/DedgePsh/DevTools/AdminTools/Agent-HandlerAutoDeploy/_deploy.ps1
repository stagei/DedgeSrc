Import-Module Deploy-Handler -Force 
Import-Module GlobalFunctions -Force
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList (Get-ValidServerNameList) 

