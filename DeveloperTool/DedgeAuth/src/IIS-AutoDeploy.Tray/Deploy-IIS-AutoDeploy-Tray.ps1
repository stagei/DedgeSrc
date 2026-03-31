<#
.SYNOPSIS
    Configures the IIS Auto-Deploy Tray to run at user logon via Scheduled Task.

.DESCRIPTION
    Creates a Scheduled Task that runs the launcher script at user logon.
    The tray is installed via DedgeAuth template AdditionalWinApps (Install-OurWinApp).
    This script only configures the Scheduled Task.

.EXAMPLE
    .\Deploy-IIS-AutoDeploy-Tray.ps1
#>

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force

$taskName = "IIS-AutoDeploy-Tray"
$trayExePath = "$env:OptPath\DedgeWinApps\IIS-AutoDeploy-Tray\IIS-AutoDeploy.Tray.exe"
$launcherPath = Join-Path (Split-Path $trayExePath) "IIS-AutoDeploy-Tray-Launcher.ps1"

if (-not (Test-Path $trayExePath)) {
    Write-LogMessage "Tray executable not found at $trayExePath. Deploy DedgeAuth first (includes IIS-AutoDeploy-Tray via AdditionalWinApps)." -Level ERROR
    exit 1
}

if (-not (Test-Path $launcherPath)) {
    Write-LogMessage "Launcher not found at $launcherPath" -Level ERROR
    exit 1
}

Write-LogMessage "Configuring Scheduled Task for $taskName..." -Level INFO

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $taskAction = "pwsh.exe -NoProfile -WindowStyle Hidden -File `"$launcherPath`""
    $schtasksArgs = @(
        '/Create'
        '/TN', $taskName
        '/TR', $taskAction
        '/SC', 'ONLOGON'
        '/RL', 'HIGHEST'
        '/IT'
        '/DELAY', '0000:10'
        '/F'
    )
    $result = & schtasks.exe @schtasksArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-LogMessage "Scheduled Task created (runs at logon)" -Level INFO
    }
    else {
        Write-LogMessage "schtasks.exe returned: $result" -Level WARN
    }

    Write-LogMessage "Starting tray via scheduled task..." -Level INFO
    $runResult = & schtasks.exe /Run /TN $taskName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-LogMessage "Tray started" -Level INFO
    }
    else {
        Write-LogMessage "Task run failed (no interactive session?): $runResult" -Level WARN
    }
}
catch {
    Write-LogMessage "Failed to create Scheduled Task: $($_.Exception.Message)" -Level ERROR
    exit 1
}

Write-LogMessage "Deploy-IIS-AutoDeploy-Tray completed" -Level INFO
