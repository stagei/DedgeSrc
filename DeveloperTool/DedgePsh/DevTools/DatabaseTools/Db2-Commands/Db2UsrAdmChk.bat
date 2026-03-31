@echo off
REM Synopsis Start
REM This script queries and exports DB2 database authorization information for a specific user.
REM It retrieves all database-level privileges and authorities granted to the target username
REM from the SYSCAT.DBAUTH system catalog view and outputs the results via the common DB2 function.
REM Synopsis End

set TARGET_USERNAME_INPUT=%1%
if "%TARGET_USERNAME_INPUT%" EQU "" (
    set /p TARGET_USERNAME="Enter username to check privileges for (e.g. FKMUSER): "
) else (
    set TARGET_USERNAME=%TARGET_USERNAME_INPUT%
)
if "%TARGET_USERNAME%" EQU "" (
    echo Error: Username cannot be empty.
    pause
    goto :eof
)

echo.
echo ===================================================================
echo DB2 Database Authorities Report for: %TARGET_USERNAME%
echo ===================================================================
echo.

REM Execute the query directly with proper formatting
echo Querying database authorities for user: %TARGET_USERNAME%
echo.

call "%~dp0Db2Functions.bat" db2UsrAdmChk

