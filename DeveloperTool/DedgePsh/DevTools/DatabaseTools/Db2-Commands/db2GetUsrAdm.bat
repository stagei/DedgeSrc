@echo off
REM Synopsis Start
REM Gets all DB2 administration privileges for a specified user and exports the results to a CSV file.
REM Synopsis End

REM Handle current instance
call "%~dp0Db2Functions.bat" db2GetAllAuthorities

REM All done...
goto :eof

