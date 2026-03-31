Import-Module Deploy-Handler -Force
Import-Module GlobalFunctions -Force
# $devToolsLineCount = Get-CodeLineCount "$env:OptPath\src\DedgePsh\DevTools"
# $modulesLineCount = Get-CodeLineCount "$env:OptPath\src\DedgePsh\_Modules"
# $totalLineCount = $devToolsLineCount + $modulesLineCount
# Write-Host "Total lines of PowerShell code: $totalLineCount" -ForegroundColor Green
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $(Get-ValidServerNameList)
#Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList "*-db" 
