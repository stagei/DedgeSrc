Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("t-no1fkxtst-db", "p-no1fkxprd-db")
