@echo off
set "Command=%~1"

if "%Command%"=="" (
    "C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Get-App\Get-App.ps1"
) else (
    "C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Get-App\Get-App.ps1 --updateAll"
)

