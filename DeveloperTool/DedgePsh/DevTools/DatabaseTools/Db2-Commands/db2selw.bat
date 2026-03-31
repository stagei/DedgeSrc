@echo off
REM Synopsis Start
REM This script executes a DB2 SELECT statement and displays the results in a web browser.
REM Synopsis End

set "SQL_SELECT_STATEMENT=%*"
call "%~dp0Db2Functions.bat" db2_select_common Web %SQL_SELECT_STATEMENT%

