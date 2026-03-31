@echo off
REM Synopsis Start
REM This script exports the structure of all tables in the DB2 database to a SQL file.
REM Synopsis End

set DB2INSTANCE=DB2
db2 -x -v "select tabname from syscat.tables where tabschema = '%SCHEMA_NAME%'" > tables.txt
type tables.txt

echo.
echo Reading tables from tables.txt:
echo.
for /f "delims=" %%i in (tables.txt) do (
    echo %%i
)

