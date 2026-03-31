@echo off
REM ============================================================================
REM Set-StopFile.bat
REM Creates the stop file to gracefully shutdown ServerMonitor
REM ============================================================================

setlocal

set "StopFilePath=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\StopServerMonitor.txt"

echo.
echo ============================================================================
echo Setting Stop File for ServerMonitor
echo ============================================================================
echo.
echo Stop File Path: %StopFilePath%
echo.

REM Check if file already exists
if exist "%StopFilePath%" (
    echo [INFO] Stop file already exists.
    echo [INFO] ServerMonitor will shutdown gracefully within 10 seconds.
    echo.
    goto :end
)

REM Create the stop file
echo [INFO] Creating stop file...
(
    echo Stop ServerMonitor
    echo This file was created on %DATE% %TIME%
) > "%StopFilePath%"

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Stop file created successfully!
    echo [INFO] ServerMonitor will detect this file and shutdown gracefully within 10 seconds.
) else (
    echo [ERROR] Failed to create stop file!
    echo [ERROR] Please check:
    echo [ERROR]   1. Network connectivity to %StopFilePath%
    echo [ERROR]   2. Write permissions to the directory
    exit /b 1
)

:end
echo.
echo ============================================================================
pause

