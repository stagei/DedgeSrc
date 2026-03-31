Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("t-no1fkmmig-db")

