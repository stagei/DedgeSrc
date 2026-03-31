Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList "dedge-server"
