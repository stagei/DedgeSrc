@echo off
REM Synopsis Start
REM This script executes a DB2 SELECT statement and displays the results as a json file.
REM Synopsis End

set "SQL_SELECT_STATEMENT=%*"
call "%~dp0Db2Functions.bat" db2_select_common Json %SQL_SELECT_STATEMENT%

