Import-Module Deploy-Handler -Force -ErrorAction Stop
Import-Module GlobalFunctions -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("*-db")  