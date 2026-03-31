Import-Module Deploy-Handler.psm1 -Force
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("t-no1fkmper-db")
#$(Get-ValidServerNameList)
