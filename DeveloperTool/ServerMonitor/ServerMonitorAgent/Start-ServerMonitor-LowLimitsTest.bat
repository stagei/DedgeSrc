@echo off
REM ============================================================
REM Start ServerMonitor with LowLimitsTest Configuration
REM ============================================================
REM This uses appsettings.json (base) + appsettings.LowLimitsTest.json
REM DevMode is enabled - skips CommonAppsettingsFile sync
REM ============================================================

REM Change to script directory to ensure relative paths work
cd /d "%~dp0"

REM Call PowerShell script with LowLimitsTest profile
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Start-ServerMonitor.ps1" -AppSettingsFile "LowLimitsTest"

REM If PowerShell script exits with error, pause to show message
if errorlevel 1 (
    pauseimage.pngimage.png
)

