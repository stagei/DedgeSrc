# IIS Auto-Deploy Tray Launcher
# Runs the tray app and restarts it after 5 seconds if it exits (crash or user Exit).
# Used by the Scheduled Task for auto-restart on failure.

$exe = "$env:OptPath\DedgeWinApps\IIS-AutoDeploy-Tray\IIS-AutoDeploy.Tray.exe"

if (-not (Test-Path $exe)) {
    Write-Error "Tray executable not found: $exe"
    exit 1
}

while ($true) {
    & $exe
    Start-Sleep -Seconds 5
}
