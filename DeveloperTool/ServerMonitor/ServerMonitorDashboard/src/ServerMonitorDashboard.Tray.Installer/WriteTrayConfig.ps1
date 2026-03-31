# Called by the MSI installer custom action after file installation.
# Writes user-prefs.json with the Dashboard API server entered during setup.
# DASHBOARD_SERVER is passed as a command-line argument by the installer.
param(
    [Parameter(Mandatory)]
    [string]$Server
)
$dir  = Join-Path $env:APPDATA "ServerMonitorDashboard.Tray"
$file = Join-Path $dir "user-prefs.json"
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$json = "{`"DashboardApiServer`":`"$Server`"}"
Set-Content -Path $file -Value $json -Encoding UTF8
