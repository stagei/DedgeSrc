# Verify we are running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator. Please run PowerShell as Administrator and try again."
    exit 1
}

# Verify we are on Windows Server 2025
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$productType = $osInfo.ProductType
$buildNumber = [System.Environment]::OSVersion.Version.Build

# ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
if ($productType -eq 1) {
    Write-Error "This script is designed for Windows Server. Current OS is a workstation edition."
    exit 1
}

# Windows Server 2025 build number is 26100 or higher
if ($buildNumber -lt 26100) {
    Write-Warning "This script is designed for Windows Server 2025 (build 26100+). Current build: $buildNumber"
    Write-Warning "Continuing anyway, but some features may not work as expected."
}

Write-Host "Administrator privileges confirmed" -ForegroundColor Green
Write-Host "Running on Windows Server (Build: $buildNumber)" -ForegroundColor Green

Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature

