@echo off
setlocal

echo ===================================================
echo Running Write-LogMessageBat Test Suite
echo ===================================================

set "SCRIPT_DIR=%~dp0"
set "TEST_LOG=%TEMP%\Write-LogMessageBat-Tests.log"

echo Script Directory: %SCRIPT_DIR%
echo Test Log File: %TEST_LOG%
echo.

rem Clean up any existing test log
if exist "%TEST_LOG%" del "%TEST_LOG%"

echo ===================================================
echo 1. Running Simple Batch Tests
echo ===================================================
call "%SCRIPT_DIR%test.bat"

echo.
echo ===================================================
echo 2. Running Comprehensive PowerShell Tests
echo ===================================================
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Test-WriteLogMessageBat.ps1" -TestLogFile "%TEST_LOG%"

set "PS_EXIT_CODE=%ERRORLEVEL%"

echo.
echo ===================================================
echo Test Suite Results
echo ===================================================
if %PS_EXIT_CODE% equ 0 (
    echo Status: ALL TESTS PASSED
    echo Exit Code: %PS_EXIT_CODE%
) else (
    echo Status: SOME TESTS FAILED
    echo Exit Code: %PS_EXIT_CODE%
)

echo.
echo Test log files:
if exist "%TEST_LOG%" (
    echo - %TEST_LOG% (exists)
) else (
    echo - %TEST_LOG% (not found)
)

if exist "%TEMP%\test-log.txt" (
    echo - %TEMP%\test-log.txt (exists)
) else (
    echo - %TEMP%\test-log.txt (not found)
)

echo.
echo ===================================================
echo Press any key to exit...
pause >nul

exit /b %PS_EXIT_CODE%

