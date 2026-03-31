@echo off
REM Synopsis Start
REM Set DB2INSTANCE=DB2HFED and connect to the federated database, if exists.
REM Synopsis End
call "%~dp0Db2Functions.bat" db2ihx

