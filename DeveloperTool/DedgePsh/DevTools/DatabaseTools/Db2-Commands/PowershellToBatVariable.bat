@echo off
echo Getting current time from PowerShell...

REM Method 1: Get time
for /f "delims=" %%i in ('powershell "Get-Date -Format \"HH:mm:ss\""') do set "CURRENT_TIME=%%i"

REM Method 2: Get date
for /f "delims=" %%i in ('powershell "Get-Date -Format \"yyyy-MM-dd\""') do set "CURRENT_DATE=%%i"

echo Current time: %CURRENT_TIME%
echo Current date: %CURRENT_DATE%
echo.
echo Test completed!
pause

