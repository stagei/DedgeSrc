Import-Module SoftwareUtils -Force

Write-Host "`nTesting Install-WindowsApp with and without force" -ForegroundColor Yellow
Install-WindowsApps -AppName "VSCode System-Installer"
Install-WindowsApps -AppName "VSCode System-Installer" -Force

