@echo off
REM Synopsis Start
REM Grants all users in the local group DB2USERS to be able to connect, select, insert, delete and update data in the tables in local database
REM Synopsis End

echo Granting permissions to DB2USERS group members...

REM Check if DB2 is available
db2 version >nul 2>&1
if errorlevel 1 (
    echo Error: DB2 command not found. Please ensure DB2 is installed and in PATH.
    pause
    exit /b 1
)

REM Get the current database name
for /f "tokens=*" %%i in ('db2 "get database directory" ^| findstr "Database name"') do set DBNAME=%%i
set DBNAME=%DBNAME:Database name =%

if "%DBNAME%"=="" (
    echo Error: Could not determine database name. Please ensure you are connected to a database.
    pause
    exit /b 1
)

echo Using database: %DBNAME%

REM Connect to the database
db2 connect to %DBNAME%
if errorlevel 1 (
    echo Error: Failed to connect to database %DBNAME%
    pause
    exit /b 1
)

REM Check if DB2USERS group exists
net localgroup DB2USERS >nul 2>&1
if errorlevel 1 (
    echo Error: Local group DB2USERS does not exist. Please create the group first.
    pause
    exit /b 1
)

echo Found DB2USERS group. Processing members...

REM Get all users in the DB2USERS group
for /f "tokens=*" %%u in ('net localgroup DB2USERS ^| findstr /v "The command completed successfully" ^| findstr /v "Members" ^| findstr /v "---" ^| findstr /v "^$"') do (
    echo Processing user: %%u

    REM Grant CONNECT privilege
    db2 "GRANT CONNECT ON DATABASE TO USER %%u"
    if errorlevel 1 echo Warning: Failed to grant CONNECT to %%u

    REM Grant SELECT, INSERT, DELETE, UPDATE on all tables in all schemas
    db2 "GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES TO USER %%u"
    if errorlevel 1 echo Warning: Failed to grant table permissions to %%u

    REM Grant SELECT, INSERT, DELETE, UPDATE on all views in all schemas
    db2 "GRANT SELECT, INSERT, DELETE, UPDATE ON ALL VIEWS TO USER %%u"
    if errorlevel 1 echo Warning: Failed to grant view permissions to %%u

    REM Grant USAGE on all schemas
    db2 "GRANT USAGE ON ALL SCHEMAS TO USER %%u"
    if errorlevel 1 echo Warning: Failed to grant schema usage to %%u

    REM Grant EXECUTE on all procedures
    db2 "GRANT EXECUTE ON ALL PROCEDURES TO USER %%u"
    if errorlevel 1 echo Warning: Failed to grant procedure execute to %%u

    echo Completed permissions for user: %%u
)

echo Permissions granted successfully to all users in DB2USERS group.
pause

