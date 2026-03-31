
@echo off
rem https://stackoverflow.com/questions/19798777/accessing-batch-functions-in-another-batch-file
call:%~1 %~2 %~3 %~4 %~5 %~6 %~7 %~8 %~9
goto exit

REM :db2SetDatabaseFromInstance - Db2 Set Database From Instance
set CURRENT_APPLICATION=%COMPUTERNAME:~5,3%
set CURRENT_ENVIRONMENT=%COMPUTERNAME:~8,3%

:db2SetDatabaseFromInstance
if "%DB2INSTANCE%"=="DB2" (
    set CURRENT_DATABASE=%COMPUTERNAME:~5,6%
    goto :eof
)
if "%DB2INSTANCE%"=="DB2HST" (
    set CURRENT_DATABASE=%COMPUTERNAME:~5,3%HST
    echo CURRENT_DATABASE: %CURRENT_DATABASE%
    goto :eof
)
if "%DB2INSTANCE%"=="DB2FED" (
    set CURRENT_DATABASE=x%COMPUTERNAME:~5,6%
    goto :eof
)
if "%DB2INSTANCE%"=="DB2HFED" (
    set CURRENT_DATABASE=x%COMPUTERNAME:~5,3%HST
    goto :eof
)
echo Error: Unhandled DB2INSTANCE: %DB2INSTANCE% in function: db2SetDatabaseFromInstance in file: %~dp0Db2Functions.bat
goto :eof

REM :db2conn - Db2 Connect to current database
:db2conn
call :db2SetDatabaseFromInstance
REM Check if computername ends with -db, otherwise prompt for database name
echo %COMPUTERNAME% | findstr /I "\-db" >nul
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo This computer does not appear to be a database server.
    echo Computer name: %COMPUTERNAME%
    echo.
    set /p CURRENT_DATABASE="Please enter the database name to connect to: "
    if "!CURRENT_DATABASE!"=="" (
        echo Error: No database name provided.
        goto :eof
    )
)

@REM echo Connecting to %CURRENT_DATABASE% database
powershell -Command "Write-Host Connecting to $('%CURRENT_DATABASE%').ToUpper() database on instance %DB2INSTANCE%. -ForegroundColor Green"
db2 connect reset >nul 2>&1
db2 connect to %CURRENT_DATABASE%
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host Error: Failed to connect to %CURRENT_DATABASE% database on instance %DB2INSTANCE%. -ForegroundColor Red"
    goto :eof
)

goto :eof

REM :db2i - Db2 Instance Name
:db2i
db2 connect reset >nul 2>&1
set DB2INSTANCE=DB2
set CURRENT_DATABASE=%COMPUTERNAME:~5,6%
goto :db2conn
goto :eof

REM :db2ix - Db2 Instance Name
:db2ix
db2 connect reset >nul 2>&1
set DB2INSTANCE=DB2FED
set CURRENT_DATABASE=x%COMPUTERNAME:~5,6%
goto :db2conn
goto :eof

REM :db2ih - DB2HST Instance Name
:db2ih
db2 connect reset >nul 2>&1
set DB2INSTANCE=DB2HST
set CURRENT_DATABASE=%COMPUTERNAME:~5,6%
goto :db2conn
goto :eof

REM :db2ihx - DB2HFED Instance Name
:db2ihx
db2 connect reset >nul 2>&1
set DB2INSTANCE=DB2HFED
set CURRENT_DATABASE=x%COMPUTERNAME:~5,6%
goto :db2conn
goto :eof

REM :db2GetAllAuthorities - Db2 Get All Authorities
:db2GetAllAuthorities
db2 list active databases > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Not connected to any DB2 database. connecting to default database
    call :db2i
)
db2 SELECT GRANTORTYPE, GRANTEE, GRANTEETYPE, MAX(BINDADDAUTH) AS BINDADDAUTH, MAX(CONNECTAUTH) AS CONNECTAUTH, MAX(CREATETABAUTH) AS CREATETABAUTH, MAX(DBADMAUTH) AS DBADMAUTH, MAX(EXTERNALROUTINEAUTH) AS EXTERNALROUTINEAUTH, MAX(IMPLSCHEMAAUTH) AS IMPLSCHEMAAUTH, MAX(LOADAUTH) AS LOADAUTH, MAX(NOFENCEAUTH) AS NOFENCEAUTH, MAX(QUIESCECONNECTAUTH) AS QUIESCECONNECTAUTH, MAX(SECURITYADMAUTH) AS SECURITYADMAUTH, MAX(SQLADMAUTH) AS SQLADMAUTH, MAX(WLMADMAUTH) AS WLMADMAUTH, MAX(EXPLAINAUTH) AS EXPLAINAUTH, MAX(DATAACCESSAUTH) AS DATAACCESSAUTH, MAX(ACCESSCTRLAUTH) AS ACCESSCTRLAUTH, MAX(CREATESECUREAUTH) AS CREATESECUREAUTH, MAX(GRANT_TIME) AS GRANT_TIME, MAX(GRANTREVOKE_TIME) AS GRANTREVOKE_TIME FROM SYSCAT.DBAUTH GROUP BY GRANTORTYPE, GRANTEE, GRANTEETYPE ORDER BY GRANTORTYPE, GRANTEETYPE
echo.
echo ===================================================================
echo Query completed for user: %TARGET_USERNAME%
echo ===================================================================
echo.
echo Legend:
echo Y = Authority granted
echo N = Authority not granted
echo.
echo Note: LIBRARYADMAUTH exists for z/OS compatibility but cannot be
echo       granted in DB2 LUW - it will always show 'N'
echo ===================================================================
goto :eof

REM :YYYYMMDDHHMMSS - Get current date and time in YYYYMMDDHHMMSS format
:YYYYMMDDHHMMSS
SET YYYYMMDDHHMMSS=""
SET YYYY=%date:~-4,4%
SET MM=%date:~-7,2%
SET DD=%date:~-10,2%
SET HH=%time:~0,2%
if "%HH:~0,1%"==" " set HH=0%HH:~1,1%
SET MIN=%time:~3,2%
SET SS=%time:~6,2%
SET YYYYMMDDHHMMSS=%YYYY%%MM%%DD%%HH%%MIN%%SS%
goto :eof

REM :restart_and_activate_db2 - Restart and activate db2
:restart_and_activate_db2
db2 connect reset >nul 2>&1
db2stop force
db2start
db2 activate database %CURRENT_DATABASE%
goto :eof

REM :stop_force_db2 - Stop db2 forcefully
:stop_force_db2
db2stop force
goto :eof

REM :start_db2 - Start db2
:start_db2
db2start
goto :eof

REM :activate_db2 - Activate db2
:activate_db2
db2 activate database %CURRENT_DATABASE%
goto :eof

REM :db2_select_common - Db2 Select with common output
:db2_select_common
setlocal EnableDelayedExpansion
if %USERNAME%==FKGEISTA (
    set PSH_PATH="%OptPath%\src\DedgePsh\DevTools\DatabaseTools\Db2-Commands\Db2-SelectHelper.ps1"
) else (
    set PSH_PATH="%OptPath%\DedgePshApps\Db2-Commands\Db2-SelectHelper.ps1"
)
pwsh.exe -ExecutionPolicy Bypass -File %PSH_PATH% -OutputMethod %1 -CombinedString "%SQL_SELECT_STATEMENT%"
goto :eof

REM :db2UsrAdmChk - Db2 User Administration Check
:db2UsrAdmChk
db2 list active databases > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Not connected to any DB2 database. connecting to default database
    call :db2i
)
db2sel SELECT GRANTORTYPE, GRANTEE, GRANTEETYPE, MAX(BINDADDAUTH) AS BINDADDAUTH, MAX(CONNECTAUTH) AS CONNECTAUTH, MAX(CREATETABAUTH) AS CREATETABAUTH, MAX(DBADMAUTH) AS DBADMAUTH, MAX(EXTERNALROUTINEAUTH) AS EXTERNALROUTINEAUTH, MAX(IMPLSCHEMAAUTH) AS IMPLSCHEMAAUTH, MAX(LOADAUTH) AS LOADAUTH, MAX(NOFENCEAUTH) AS NOFENCEAUTH, MAX(QUIESCECONNECTAUTH) AS QUIESCECONNECTAUTH, MAX(SECURITYADMAUTH) AS SECURITYADMAUTH, MAX(SQLADMAUTH) AS SQLADMAUTH, MAX(WLMADMAUTH) AS WLMADMAUTH, MAX(EXPLAINAUTH) AS EXPLAINAUTH, MAX(DATAACCESSAUTH) AS DATAACCESSAUTH, MAX(ACCESSCTRLAUTH) AS ACCESSCTRLAUTH, MAX(CREATESECUREAUTH) AS CREATESECUREAUTH, MAX(GRANT_TIME) AS GRANT_TIME, MAX(GRANTREVOKE_TIME) AS GRANTREVOKE_TIME FROM SYSCAT.DBAUTH WHERE GRANTEE = '%TARGET_USERNAME%' GROUP BY GRANTORTYPE, GRANTEE, GRANTEETYPE ORDER BY GRANTORTYPE, GRANTEETYPE
echo.
echo ===================================================================
echo Query completed for user: %TARGET_USERNAME%
echo ===================================================================
echo.
echo Legend:
echo Y = Authority granted
echo N = Authority not granted
echo.
echo Note: LIBRARYADMAUTH exists for z/OS compatibility but cannot be
echo       granted in DB2 LUW - it will always show 'N'
echo ===================================================================
goto :eof

REM :db2UsrAdmChkFed - Db2 User Administration Check for federated database
:db2UsrAdmChkFed
call :db2i

db2 list active databases > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Not connected to any DB2 database. connecting to default database
    call :db2ix
)
db2sel SELECT GRANTORTYPE, GRANTEE, GRANTEETYPE, MAX(BINDADDAUTH) AS BINDADDAUTH, MAX(CONNECTAUTH) AS CONNECTAUTH, MAX(CREATETABAUTH) AS CREATETABAUTH, MAX(DBADMAUTH) AS DBADMAUTH, MAX(EXTERNALROUTINEAUTH) AS EXTERNALROUTINEAUTH, MAX(IMPLSCHEMAAUTH) AS IMPLSCHEMAAUTH, MAX(LOADAUTH) AS LOADAUTH, MAX(NOFENCEAUTH) AS NOFENCEAUTH, MAX(QUIESCECONNECTAUTH) AS QUIESCECONNECTAUTH, MAX(SECURITYADMAUTH) AS SECURITYADMAUTH, MAX(SQLADMAUTH) AS SQLADMAUTH, MAX(WLMADMAUTH) AS WLMADMAUTH, MAX(EXPLAINAUTH) AS EXPLAINAUTH, MAX(DATAACCESSAUTH) AS DATAACCESSAUTH, MAX(ACCESSCTRLAUTH) AS ACCESSCTRLAUTH, MAX(CREATESECUREAUTH) AS CREATESECUREAUTH, MAX(GRANT_TIME) AS GRANT_TIME, MAX(GRANTREVOKE_TIME) AS GRANTREVOKE_TIME FROM SYSCAT.DBAUTH WHERE GRANTEE = '%TARGET_USERNAME%' GROUP BY GRANTORTYPE, GRANTEE, GRANTEETYPE ORDER BY GRANTORTYPE, GRANTEETYPE
echo.
echo ===================================================================
echo Query completed for user: %TARGET_USERNAME%
echo ===================================================================
echo.
echo Legend:
echo Y = Authority granted
echo N = Authority not granted
echo.
echo Note: LIBRARYADMAUTH exists for z/OS compatibility but cannot be
echo       granted in DB2 LUW - it will always show 'N'
echo ===================================================================
goto :eof

REM :db2chkdb - Db2 Check Database Configuration
:db2chkdb
call :db2SetDatabaseFromInstance
if "%CHECKSTRING%"=="" (
    echo Checking dbm cfg...
    db2 get dbm cfg
    db2 get db for %CURRENT_DATABASE%
) else (
    echo Checking dbm cfg for %CHECKSTRING%...
    db2 get dbm cfg | findstr /I "%CHECKSTRING%"
    echo Checking db cfg in %CURRENT_DATABASE% for %CHECKSTRING%...
    db2 get db for %CURRENT_DATABASE% | findstr /I "%CHECKSTRING%"
)

goto :eof

REM :Change to any directory on any drive either from pwsh or bat
:cdAnyDrive
REM Check if %CHANGE_TO_DIRECTORY% is defined
if "%CHANGE_TO_DIRECTORY%"=="" (
    echo ERROR: OptPath environment variable is not defined
    echo Please set OptPath before running this script
    goto :end
)

REM Check if %CHANGE_TO_DIRECTORY% exists
if not exist "%CHANGE_TO_DIRECTORY%" (
    echo ERROR: OptPath directory does not exist: %CHANGE_TO_DIRECTORY%
    goto :end
)

REM Change to the OptPath directory
set CURRENT_DRIVE=%CHANGE_TO_DIRECTORY:~0,2%
%CURRENT_DRIVE%
cd /d "%CHANGE_TO_DIRECTORY%"
echo Changed directory to: %CURRENT_DRIVE% and to folder: %CHANGE_TO_DIRECTORY%

:exit
exit /b

