@echo off
REM Edit Server Health Monitor Check Tool Configuration
REM Opens appsettings.json in default editor

set CONFIG_FILE=%~dp0src\ServerMonitor\ServerMonitorAgent\appsettings.json

if not exist "%CONFIG_FILE%" (
    echo ERROR: Configuration file not found: %CONFIG_FILE%
    pause
    exit /b 1
)

echo Opening configuration file...
echo %CONFIG_FILE%
echo.
echo After editing, the changes will be hot-reloaded automatically (no restart needed).
echo.

start "" "%CONFIG_FILE%"

