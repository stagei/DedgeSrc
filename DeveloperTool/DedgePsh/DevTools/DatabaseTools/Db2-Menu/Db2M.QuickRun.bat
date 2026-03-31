@echo off
set "Param1=%~1"
set VSCODE_PATH="C:\Users\%username%\AppData\Local\Programs\Microsoft VS Code\Code.exe"
"C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Db2-Menu\Db2-Menu.ps1"

