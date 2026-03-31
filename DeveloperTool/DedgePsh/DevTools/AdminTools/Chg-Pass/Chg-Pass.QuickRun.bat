@echo off
set "Param1=%~1"
"C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Chg-Pass\Chg-Pass.ps1 %Param1%"

