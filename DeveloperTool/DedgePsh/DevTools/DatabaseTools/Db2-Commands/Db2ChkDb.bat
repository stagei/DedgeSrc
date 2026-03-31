@echo off
REM Synopsis Start
REM This script get the
REM Synopsis End
@REM call "%~dp0Db2Functions.bat"

set CHECKSTRING=%1

set CURRENT_INSTANCE=%DB2INSTANCE%

if "%CURRENT_INSTANCE%"=="DB2HST" (
    set DB2INSTANCE=DB2HST
) else (
    set DB2INSTANCE=DB2
)

echo Checking dbm cfg for %CURRENT_INSTANCE%...
call "%~dp0Db2Functions.bat" db2chkdb %CHECKSTRING%

if "%CURRENT_INSTANCE%"=="DB2HST" (
    set DB2INSTANCE=DB2HFED
) else (
    set DB2INSTANCE=DB2FED
)

echo Checking dbm cfg for %CURRENT_INSTANCE%...
call "%~dp0Db2Functions.bat" db2chkdb %CHECKSTRING%

echo Resetting DB2INSTANCE to %CURRENT_INSTANCE%...
set DB2INSTANCE=%CURRENT_INSTANCE%

goto :eof

