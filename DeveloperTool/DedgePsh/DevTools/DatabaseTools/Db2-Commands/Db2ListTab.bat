@echo off
REM Synopsis Start
REM This script lists all tables in the current DB2 database.
REM Synopsis End
call "%~dp0Db2Functions.bat" db2conn

db2 list tables for all

