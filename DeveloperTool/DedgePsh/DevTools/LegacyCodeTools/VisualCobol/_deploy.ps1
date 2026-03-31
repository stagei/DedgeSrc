Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder (Join-Path $PSScriptRoot 'ServerScripts') -ComputerNameList @("t-no1fkmvct-app")
