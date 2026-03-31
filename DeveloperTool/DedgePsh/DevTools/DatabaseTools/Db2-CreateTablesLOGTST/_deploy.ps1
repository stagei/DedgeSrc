Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("*fkxtst-db")  