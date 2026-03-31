@echo off
REM Synopsis Start
REM This script changes the current directory to the database backup directory.
REM It checks for common database backup paths (E:, F:, G: drives) and falls back to %OptPath% if none are found.
REM Synopsis End

REM Check for database backup directories in order of preference
if exist "g:\DbBackup" (
    set CHANGE_TO_DIRECTORY=g:\DbBackup
) else if exist "f:\DbBackup" (
    set CHANGE_TO_DIRECTORY=f:\DbBackup
) else if exist "e:\DbBackup" (
    set CHANGE_TO_DIRECTORY=e:\DbBackup
) else (
    set CHANGE_TO_DIRECTORY=%OptPath%\DedgePshApps
)

call "%~dp0Db2Functions.bat" cdAnyDrive "%CHANGE_TO_DIRECTORY%"
goto :eof

