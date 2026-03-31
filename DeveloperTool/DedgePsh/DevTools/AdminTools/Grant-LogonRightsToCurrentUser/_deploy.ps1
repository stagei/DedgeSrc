Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $(Get-ValidServerNameList)

