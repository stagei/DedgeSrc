@echo off
set "Command=%~1"
echo %Command%
"C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Inst-Psh\Inst-Psh.ps1 %Command%"

