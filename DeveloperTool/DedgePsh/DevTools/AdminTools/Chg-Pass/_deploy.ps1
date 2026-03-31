Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("dedge-server", "p-no1fkxprd-app")


