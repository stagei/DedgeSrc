Import-Module Infrastructure -Force
# Update FK admin user credentials for service and scheduled tasks
Update-FkAdmUser

Write-Host "All done" -ForegroundColor Green

