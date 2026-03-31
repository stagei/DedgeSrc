@echo off
REM Synopsis Start
REM This script exports the structure of a DB2 table to a SQL file.
REM Synopsis End
set TARGET_TABLE=%1
echo TARGET_TABLE is set to: %TARGET_TABLE%
if "%TARGET_TABLE%"=="" (
  set /p "TARGET_TABLE2=Enter table name to export: "
  echo TARGET_TABLE2 is set to: %TARGET_TABLE2%
  if "%TARGET_TABLE2%"=="" (
      echo Error: Table name cannot be empty.
      goto :eof
  )
  set TARGET_TABLE=%TARGET_TABLE2%
)

echo Target table is set to: %TARGET_TABLE%
echo.
set DB2INSTANCE=DB2
set CURRENT_DATABASE=%COMPUTERNAME:~5,6%
echo CURRENT_DATABASE is set to: %CURRENT_DATABASE%
db2look -d %CURRENT_DATABASE% -e -t %TARGET_TABLE% -x

for /f "tokens=1,2 delims=." %%a in ("%TARGET_TABLE%") do (
    set SCHEMA_NAME=%%a
    set TABLE_NAME=%%b
)
echo SCHEMA_NAME is set to: %SCHEMA_NAME%
echo TABLE_NAME is set to: %TABLE_NAME%

db2 -x -v -f $tempSqlFile > $tempResultFile

db2 -x -v "select tabname from syscat.tables where tabschema = '%SCHEMA_NAME%'" > tables.txt
type tables.txt

echo.
echo Reading tables from tables.txt:
echo.
for /f "delims=" %%i in (tables.txt) do (
    echo %%i
)

