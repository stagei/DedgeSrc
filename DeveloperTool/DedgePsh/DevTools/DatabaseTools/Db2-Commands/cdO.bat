@echo off
REM Synopsis Start
REM This script changes the current directory to the OptPath.
REM Synopsis End

set CHANGE_TO_DIRECTORY=%OptPath%
call "%~dp0Db2Functions.bat" cdAnyDrive "%CHANGE_TO_DIRECTORY%"
goto :eof

