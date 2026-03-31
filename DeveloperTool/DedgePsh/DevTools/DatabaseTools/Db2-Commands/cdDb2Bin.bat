@echo off
REM Synopsis Start
REM Changes the current directory to the DB2 binary directory.
REM It checks for common DB2 installation paths and falls back to %OptPath% if none are found.
REM Synopsis End

REM Check for DB2 binary directories in order of preference
if exist "C:\DbInst\Bin" (
    set CHANGE_TO_DIRECTORY=C:\DbInst\Bin
) else if exist "C:\Program Files\IBM\SQLLIB\BIN" (
    set CHANGE_TO_DIRECTORY=C:\Program Files\IBM\SQLLIB\BIN
) else if exist "C:\Program Files (x86)\IBM\SQLLIB\BIN" (
    set CHANGE_TO_DIRECTORY=C:\Program Files (x86)\IBM\SQLLIB\BIN
) else (
    set CHANGE_TO_DIRECTORY=%OptPath%
)

call "%~dp0Db2Functions.bat" cdAnyDrive "%CHANGE_TO_DIRECTORY%"
goto :eof

