@echo off
REM ============================================================================
REM Remove-StopFile.bat
REM Removes the stop file to allow ServerMonitor to run normally
REM ============================================================================

setlocal

set "StopFilePath=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\StopServerMonitor.txt"

echo.
echo ============================================================================
echo Removing Stop File for ServerMonitor
echo ============================================================================
echo.
echo Stop File Path: %StopFilePath%
echo.

REM Check if file exists
if not exist "%StopFilePath%" (
    echo [INFO] Stop file does not exist.
    echo [INFO] ServerMonitor can run normally.
    echo.
    goto :end
)

REM Delete the stop file
echo [INFO] Removing stop file...
del /F /Q "%StopFilePath%" >nul 2>&1

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Stop file removed successfully!
    echo [INFO] ServerMonitor can now start/continue running normally.
) else (
    echo [ERROR] Failed to remove stop file!
    echo [ERROR] Please check:
    echo [ERROR]   1. Network connectivity to %StopFilePath%
    echo [ERROR]   2. File permissions
    echo [ERROR]   3. If the file is locked by another process
    exit /b 1
)

:end
echo.
echo ============================================================================
pause

