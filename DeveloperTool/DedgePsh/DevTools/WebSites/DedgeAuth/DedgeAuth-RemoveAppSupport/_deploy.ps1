Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("t-no1fkxtst-db", "p-no1fkxprd-db","dedge-server", "p-no1fkxprd-app")
