Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot 
Write-Host "Deploying RestoreCbl.cmd to $env:OptPath\QuickRun\"
Copy-Item -Path $($PsScriptRoot + "\RestoreCbl.cmd") -Destination "$env:OptPath\QuickRun" -Force

Copy-Item -Path $(Join-Path $PSScriptRoot "RestoreProdVersionToDev.ps1") -Destination "K:\fkavd\PSH" -Force
Copy-Item -Path $(Join-Path $PSScriptRoot "RestoreCbl.cmd") -Destination "K:\fkavd\NT" -Force
