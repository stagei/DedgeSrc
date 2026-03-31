@echo off
REM Synopsis Start
REM This script get the
REM Synopsis End

set NEW_INSTANCE=%1

if "%NEW_INSTANCE%" NEQ "" (
    set DB2INSTANCE=%NEW_INSTANCE%
)
powershell -Command "Write-Host Current instance is: %DB2INSTANCE% -ForegroundColor Green"
powershell -Command "Write-Host Other instances are: -ForegroundColor Cyan"
db2ilist

