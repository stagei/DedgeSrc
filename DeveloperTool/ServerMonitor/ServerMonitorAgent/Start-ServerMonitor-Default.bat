@echo off
REM ============================================================
REM Start ServerMonitor with Default/Production Configuration
REM ============================================================
REM This uses appsettings.json (base) + appsettings.Production.json
REM ============================================================

REM Change to script directory to ensure relative paths work
cd /d "%~dp0"

REM Call PowerShell script with Production profile (default)
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Start-ServerMonitor.ps1" -AppSettingsFile "Production"

REM If PowerShell script exits with error, pause to show message
if errorlevel 1 (
    pause
)

