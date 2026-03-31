@echo off
REM Synopsis Start
REM This script changes the current directory to the database restore directory.
REM It checks for common database restore paths (E:, F:, G: drives) and falls back to %OptPath% if none are found.
REM Synopsis End

REM Check for database restore directories in order of preference
if exist "g:\DbRestore" (
    set CHANGE_TO_DIRECTORY=g:\DbRestore
) else if exist "f:\DbRestore" (
    set CHANGE_TO_DIRECTORY=f:\DbRestore
) else if exist "e:\DbRestore" (
    set CHANGE_TO_DIRECTORY=e:\DbRestore
) else (
    set CHANGE_TO_DIRECTORY=%OptPath%\DedgePshApps
)

call "%~dp0Db2Functions.bat" cdAnyDrive "%CHANGE_TO_DIRECTORY%"
goto :eof

