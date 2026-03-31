# Grant-LogonRightsToCurrentUser.ps1
# Author: Geir Helge Starholm, www.dEdge.no
# Description: Grants batch and service logon rights to the current user

Import-Module -Name Infrastructure -Force

Write-Host "Granting logon rights to: $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Cyan

# Grant batch logon rights to the user (required for Task Scheduler)
Write-Host "Granting 'Log on as batch job' right..." -ForegroundColor Yellow
Grant-BatchLogonRight

# Grant service logon rights to the user (required for Windows Services)
Write-Host "Granting 'Log on as a service' right..." -ForegroundColor Yellow
Grant-ServiceLogonRight

Write-Host "Successfully granted logon rights to current user" -ForegroundColor Green
Write-Host "Note: You may need to log out and back in for changes to take effect" -ForegroundColor Yellow