@echo off
REM Synopsis Start
REM This script describes the structure of a DB2 table by running the 'describe table' command.
REM It accepts a table name as a command line parameter, or prompts the user to enter one if not provided.
REM Synopsis End
set TARGET_TABNAME_INPUT=%1
if "%TARGET_TABNAME_INPUT%"=="" (
    set /p TARGET_TABNAME="Enter table name to describe: eg. SYSCAT.DBAUTH "
) else (
    set TARGET_TABNAME=%TARGET_TABNAME_INPUT%
)
if "%TARGET_TABNAME%"=="" (
    echo Error: Table name cannot be empty.
    goto :eof
)

db2 describe table %TARGET_TABNAME%

