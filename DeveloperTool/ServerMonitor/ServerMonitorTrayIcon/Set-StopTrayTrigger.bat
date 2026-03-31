@echo off
REM ============================================================================
REM Set-StopTrayTrigger.bat
REM Creates the trigger file to close the ServerMonitor Tray application
REM ============================================================================

setlocal

set "TriggerFilePath=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\StopServerMonitorTray.txt"

echo.
echo ============================================================================
echo Setting Stop Trigger for ServerMonitor Tray
echo ============================================================================
echo.
echo Trigger File Path: %TriggerFilePath%
echo.

REM Check if file already exists
if exist "%TriggerFilePath%" (
    echo [INFO] Trigger file already exists.
    echo [INFO] ServerMonitor Tray will close within 3 seconds.
    echo.
    goto :end
)

REM Create the trigger file
echo [INFO] Creating stop tray trigger file...
(
    echo Stop ServerMonitor Tray
    echo This file was created on %DATE% %TIME%
    echo.
    echo When ServerMonitor Tray detects this file, it will:
    echo   1. Delete this trigger file
    echo   2. Show a brief notification
    echo   3. Close the tray application
) > "%TriggerFilePath%"

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Stop tray trigger file created successfully!
    echo [INFO] ServerMonitor Tray will detect this file and close within 3 seconds.
) else (
    echo [ERROR] Failed to create trigger file!
    echo [ERROR] Please check:
    echo [ERROR]   1. Network connectivity to %TriggerFilePath%
    echo [ERROR]   2. Write permissions to the directory
    exit /b 1
)

:end
echo.
echo ============================================================================
pause
