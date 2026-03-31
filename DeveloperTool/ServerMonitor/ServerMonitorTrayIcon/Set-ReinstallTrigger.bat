@echo off
REM ============================================================================
REM Set-ReinstallTrigger.bat
REM Creates the trigger file to automatically reinstall ServerMonitor service
REM ============================================================================
REM 
REM NOTE: This batch file is for MANUAL trigger creation only.
REM       The Build-And-Publish.ps1 script automatically creates the trigger
REM       file with the correct version after a successful build.
REM
REM       If you use this batch file, you MUST specify a version number
REM       that differs from the currently installed version, otherwise
REM       the tray app will skip the reinstall.
REM
REM ============================================================================

setlocal

set "TriggerFilePath=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\ReinstallServerMonitor.txt"

echo.
echo ============================================================================
echo Setting Reinstall Trigger for ServerMonitor
echo ============================================================================
echo.
echo Trigger File Path: %TriggerFilePath%
echo.

REM Check if file already exists
if exist "%TriggerFilePath%" (
    echo [INFO] Trigger file already exists.
    echo [INFO] ServerMonitor Tray will process the reinstall within 3 seconds.
    echo.
    type "%TriggerFilePath%"
    echo.
    goto :end
)

REM Prompt for version
set /p VERSION="Enter target version (e.g., 1.0.1): "

if "%VERSION%"=="" (
    echo [ERROR] Version is required! The tray app compares versions to decide whether to reinstall.
    exit /b 1
)

REM Create the trigger file
echo [INFO] Creating reinstall trigger file with version %VERSION%...
(
    echo # ServerMonitor Reinstall Trigger File
    echo # Created manually via Set-ReinstallTrigger.bat
    echo #
    echo # The tray app will compare this version with the installed version
    echo # and only reinstall if they differ.
    echo.
    echo Version=%VERSION%
    echo BuildDate=%DATE% %TIME%
    echo BuildMachine=%COMPUTERNAME%
    echo BuildUser=%USERNAME%
) > "%TriggerFilePath%"

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Reinstall trigger file created successfully!
    echo [INFO] Version: %VERSION%
    echo [INFO] ServerMonitor Tray will detect this file and start reinstall within 3 seconds.
    echo [INFO] ^(Only if installed version differs from %VERSION%^)
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
