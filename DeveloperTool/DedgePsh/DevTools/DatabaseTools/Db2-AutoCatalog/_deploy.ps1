Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $($(Get-ValidServerNameList | Where-Object { $_ -notlike "*-db" }))