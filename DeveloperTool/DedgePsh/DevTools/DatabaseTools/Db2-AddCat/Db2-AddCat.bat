@echo off
set "Param1=%~1"
set "Param2=%~2"
set "Param3=%~3"
"C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -Command "& %OptPath%\DedgePshApps\Db2-AddCat\Db2-AddCat.ps1 '%Param1%' '%Param2%' '%Param3%'"

