Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("p-no1fkmprd-db", "p-no1inlprd-db", "p-no1fkmrap-db") 

