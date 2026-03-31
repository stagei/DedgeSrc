@echo off
set "Command=%~1"

if "%Command%"=="" (
    "C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Add-Task\Add-Task.ps1"
) else (
    "C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Add-Task\Add-Task.ps1 %Command%"
)

