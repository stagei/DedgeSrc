Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $(Get-ValidServerNameList)
# $(Get-ValidServerNameList | Where-Object { $_ -notlike '*t-no1fkmfut-db*' })