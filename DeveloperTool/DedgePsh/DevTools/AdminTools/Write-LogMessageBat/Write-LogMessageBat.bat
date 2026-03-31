@echo off
setlocal enabledelayedexpansion

rem =================================================================
rem Write-LogMessageBat.bat - Batch wrapper for PowerShell logging
rem =================================================================
rem This batch file provides a simple interface to call the PowerShell
rem logging script from other batch files.
rem
rem Usage:
rem   Write-LogMessageBat.bat "message" [level] [logfile] [options]
rem
rem Parameters:
rem   %1 - Message (required)
rem   %2 - Level (optional: INFO, WARNING, ERROR, DEBUG, SUCCESS)
rem   %3 - LogFile (optional: path to log file)
rem   %4 - Options (optional: NOTIMESTAMP, NOCONSOLE, or COLOR:colorname)
rem
rem Examples:
rem   Write-LogMessageBat.bat "Starting process"
rem   Write-LogMessageBat.bat "Error occurred" ERROR
rem   Write-LogMessageBat.bat "Process completed" SUCCESS "C:\logs\app.log"
rem   Write-LogMessageBat.bat "Debug info" DEBUG "" NOCONSOLE
rem =================================================================

rem Check if message parameter is provided
if "%~1"=="" (
    echo ERROR: Message parameter is required
    echo Usage: %~nx0 "message" [level] [logfile] [options]
    exit /b 1
)

rem Set default values
set "MESSAGE=%~1"
set "LEVEL=%~2"
set "LOGFILE=%~3"
set "OPTIONS=%~4"

rem Set default level if not provided
if "%LEVEL%"=="" set "LEVEL=INFO"

rem Build PowerShell command
set "PS_SCRIPT=%~dp0Write-LogMessageBat.ps1"
set "PS_CMD=powershell.exe -ExecutionPolicy Bypass -File ""%PS_SCRIPT%"" -Message ""%MESSAGE%"" -Level ""%LEVEL%"""

rem Add log file parameter if provided
if not "%LOGFILE%"=="" (
    set "PS_CMD=!PS_CMD! -LogFile ""%LOGFILE%"""
)

rem Parse options
if not "%OPTIONS%"=="" (
    echo %OPTIONS% | findstr /i "NOTIMESTAMP" >nul
    if !errorlevel! equ 0 (
        set "PS_CMD=!PS_CMD! -NoTimestamp"
    )

    echo %OPTIONS% | findstr /i "NOCONSOLE" >nul
    if !errorlevel! equ 0 (
        set "PS_CMD=!PS_CMD! -NoConsole"
    )

    echo %OPTIONS% | findstr /i "COLOR:" >nul
    if !errorlevel! equ 0 (
        for /f "tokens=2 delims=:" %%a in ("%OPTIONS%") do (
            set "PS_CMD=!PS_CMD! -Color ""%%a"""
        )
    )
)

rem Execute PowerShell command
%PS_CMD%
exit /b %errorlevel%

