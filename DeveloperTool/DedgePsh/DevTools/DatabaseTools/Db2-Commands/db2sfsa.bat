@echo off
REM Synopsis Start
REM Synopsis End
@REM call "%~dp0Db2Functions.bat"

echo WARNING: This script will stop and restart the DB2 Current Database Instance: %DB2INSTANCE%.
if "%CURRENT_ENVIRONMENT%"=="PRD" (
    echo.
    set /p confirm="Are you sure you want to continue? (Y/N): "
    if /i "%confirm%" NEQ "Y" (
        echo Operation cancelled by user.
        exit /b 1
    )
    echo Proceeding with CURRENT_DATABASE operations...
    echo.
)
call "%~dp0Db2Functions.bat" restart_and_activate_db2

goto :eof

