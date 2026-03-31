@echo off
setlocal enabledelayedexpansion

rem Extract first argument (receiver) and remaining arguments (message)
set "RECEIVER=%~1"
set "MESSAGE=%*"

rem Remove the first argument from MESSAGE to get just the message part
rem This handles both quoted and unquoted first arguments
call set "MESSAGE=%%MESSAGE:*%1=%%"
rem Trim leading space
for /f "tokens=* delims= " %%a in ("!MESSAGE!") do set "MESSAGE=%%a"

rem Call PowerShell with properly quoted arguments
rem Using -Command instead of -File allows better argument handling
pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%OptPath%\DedgePshApps\Send-Sms\Send-Sms.ps1' -Receiver '%RECEIVER%' -Message '%MESSAGE%'"

