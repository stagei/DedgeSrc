@echo off
REM ============================================================================
REM Remove-ReinstallTrigger.bat
REM Removes the reinstall trigger file (cancels pending reinstall)
REM ============================================================================

setlocal

set "TriggerFilePath=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\ReinstallServerMonitor.txt"

echo.
echo ============================================================================
echo Removing Reinstall Trigger for ServerMonitor
echo ============================================================================
echo.
echo Trigger File Path: %TriggerFilePath%
echo.

REM Check if file exists
if not exist "%TriggerFilePath%" (
    echo [INFO] Trigger file does not exist.
    echo [INFO] No pending reinstall to cancel.
    echo.
    goto :end
)

REM Delete the trigger file
echo [INFO] Removing reinstall trigger file...
del /F /Q "%TriggerFilePath%" >nul 2>&1

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Reinstall trigger file removed successfully!
    echo [INFO] Pending reinstall has been cancelled.
) else (
    echo [ERROR] Failed to remove trigger file!
    echo [ERROR] Please check:
    echo [ERROR]   1. Network connectivity to %TriggerFilePath%
    echo [ERROR]   2. File permissions
    echo [ERROR]   3. If the file is locked by another process
    exit /b 1
)

:end
echo.
echo ============================================================================
pause
