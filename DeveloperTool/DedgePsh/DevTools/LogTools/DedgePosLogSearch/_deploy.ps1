Import-Module Deploy-Handler -Force
Deploy-Files -FromFolder $PSScriptRoot 
Write-Host "Deploying Spal.cmd to $env:OptPath\QuickRun"
Copy-Item -Path $($PsScriptRoot + "\Spal.QuickRun.cmd") -Destination "$env:OptPath\QuickRun\Spal.cmd" -Force

# try {
#     Copy-Item -Path $(Join-Path $PSScriptRoot "DedgePosLogSearch.ps1") -Destination "K:\fkavd\PSH" -Force
# }
# catch {
#     Write-Host "Error deploying DedgePosLogSearch.ps1: $_" -ForegroundColor Red
# }

# try {
#     Copy-Item -Path $(Join-Path $PSScriptRoot "Spal.cmd") -Destination "K:\fkavd\NT" -Force
# }
# catch {
#     Write-Host "Error deploying Spal.cmd: $_" -ForegroundColor Red
# }
