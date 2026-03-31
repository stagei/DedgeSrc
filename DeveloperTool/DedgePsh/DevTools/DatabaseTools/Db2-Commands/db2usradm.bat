@echo off
REM Synopsis Start
REM Revokes DB2 administration privileges, then grants them back to a specified user and exports the results to a CSV file.
REM Synopsis End

set TARGET_USERNAME_INPUT=%1%
if "%TARGET_USERNAME_INPUT%" EQU "" (
    set /p TARGET_USERNAME="Enter username to grant privileges to: eg. FKMUSER:"
) else (
    set TARGET_USERNAME=%TARGET_USERNAME_INPUT%
)
if "%TARGET_USERNAME%" EQU "" (
    echo Error: Username cannot be empty.
    goto :eof
)

if "%TARGET_USERNAME%" EQU "DB2NT" (
    goto :not_allowed
) else if "%TARGET_USERNAME%" EQU "SRV_DB2" (
    goto :not_allowed
) else if "%TARGET_USERNAME%" EQU "SRV_SFKSS07" (
    goto :not_allowed
)

REM Get current date and time in YYYYMMDDHHMMSS format
call "%~dp0Db2Functions.bat" YYYYMMDDHHMMSS

REM Handle current instance
call "%~dp0Db2Functions.bat" db2i
goto :handle_current_instance

REM Handle fed instance
call "%~dp0Db2Functions.bat" db2ifed
goto :handle_current_instance

REM All done...
goto :eof

:handle_current_instance
if not exist C:\TEMPFK mkdir C:\TEMPFK
@REM set REMOTE_PATH=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\%COMPUTERNAME%\%CURRENT_DATABASE%\Db2UsrAdm
@REM if not exist %REMOTE_PATH% mkdir %REMOTE_PATH%

@REM goto :revoke_db2_admin_privileges

goto :grant_db2_admin_privileges

goto :eof

:revoke_db2_admin_privileges
set SQL_SELECT_STATEMENT="SELECT GRANTOR, GRANTORTYPE, GRANTEE, GRANTEETYPE, BINDADDAUTH, CONNECTAUTH, CREATETABAUTH, DBADMAUTH, EXTERNALROUTINEAUTH, IMPLSCHEMAAUTH, LOADAUTH, NOFENCEAUTH, QUIESCECONNECTAUTH, LIBRARYADMAUTH, SECURITYADMAUTH, SQLADMAUTH, WLMADMAUTH, EXPLAINAUTH, DATAACCESSAUTH, ACCESSCTRLAUTH, CREATESECUREAUTH, GRANT_TIME, GRANTREVOKE_TIME FROM SYSCAT.DBAUTH WHERE GRANTEE = '%TARGET_USERNAME%'"
call "%~dp0Db2Functions.bat" db2_select_common Csv %SQL_SELECT_STATEMENT%

set FILENAME=revoke_%TARGET_USERNAME%%YYYYMMDDHHMMSS%.csv
set COMMAND="db2 "EXPORT TO C:\TEMPFK\%FILENAME% OF DEL "
echo %COMMAND%
%COMMAND%
@REM copy C:\TEMPFK\%FILENAME% %REMOTE_PATH%\%FILENAME%

@REM db2 revoke bindadd on database from user %TARGET_USERNAME% >nul
@REM db2 revoke connect on database from user %TARGET_USERNAME% >nul
@REM db2 revoke createtab on database from user %TARGET_USERNAME% >nul
@REM db2 revoke dbadm on database from user %TARGET_USERNAME% >nul
@REM db2 revoke implicit_schema on database from user %TARGET_USERNAME% >nul
@REM db2 revoke load on database from user %TARGET_USERNAME% >nul
@REM db2 revoke quiesce_connect on database from user %TARGET_USERNAME% >nul
@REM db2 revoke secadm on database from user %TARGET_USERNAME% >nul
@REM db2 revoke sqladm on database from user %TARGET_USERNAME% >nul
@REM db2 revoke wlmadm on database from user %TARGET_USERNAME% >nul
@REM db2 revoke explain on database from user %TARGET_USERNAME% >nul
@REM db2 revoke dataaccess on database from user %TARGET_USERNAME% >nul
@REM db2 revoke accessctrl on database from user %TARGET_USERNAME% >nul
@REM db2 revoke create_secure_object on database from user %TARGET_USERNAME% >nul
@REM db2 revoke create_external_routine on database from user %TARGET_USERNAME% >nul
@REM db2 revoke create_not_fenced_routine on database from user %TARGET_USERNAME% >nul
@REM db2 revoke connect on database from user %TARGET_USERNAME% >nul
@REM db2 revoke load on database from user %TARGET_USERNAME% >nul
@REM powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-LocalGroupMember -Group DB2ADMNS -member "DEDGE\%TARGET_USERNAME%" -ErrorAction SilentlyContinue" >nul
goto :eof

:grant_db2_admin_privileges

db2 grant sysadm_group on SYSTEM to 'DB2ADMNS'
db2 grant secadm on SYSTEM to %TARGET_USERNAME%
db2 grant dbadm with accessctrl with dataaccess on SYSTEM to %TARGET_USERNAME%

db2 grant bindadd on database to user %TARGET_USERNAME%
db2 grant connect on database to user %TARGET_USERNAME%
db2 grant createtab on database to user %TARGET_USERNAME%
db2 grant dbadm on database to user %TARGET_USERNAME%
db2 grant implicit_schema on database to user %TARGET_USERNAME%
db2 grant load on database to user %TARGET_USERNAME%
db2 grant quiesce_connect on database to user %TARGET_USERNAME%
db2 grant secadm on database to user %TARGET_USERNAME%
db2 grant sqladm on database to user %TARGET_USERNAME%
db2 grant wlmadm on database to user %TARGET_USERNAME%
db2 grant explain on database to user %TARGET_USERNAME%
db2 grant dataaccess on database to user %TARGET_USERNAME%
db2 grant accessctrl on database to user %TARGET_USERNAME%
db2 grant create_secure_object on database to user %TARGET_USERNAME%
db2 grant create_external_routine on database to user %TARGET_USERNAME%
db2 grant create_not_fenced_routine on database to user %TARGET_USERNAME%
db2 grant connect on database to user %TARGET_USERNAME%
db2 grant load on database to user %TARGET_USERNAME%
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Add-LocalGroupMember -Group DB2ADMNS -member "DEDGE\%TARGET_USERNAME%" -ErrorAction Stop"

set SQL_SELECT_STATEMENT="SELECT GRANTOR, GRANTORTYPE, GRANTEE, GRANTEETYPE, BINDADDAUTH, CONNECTAUTH, CREATETABAUTH, DBADMAUTH, EXTERNALROUTINEAUTH, IMPLSCHEMAAUTH, LOADAUTH, NOFENCEAUTH, QUIESCECONNECTAUTH, LIBRARYADMAUTH, SECURITYADMAUTH, SQLADMAUTH, WLMADMAUTH, EXPLAINAUTH, DATAACCESSAUTH, ACCESSCTRLAUTH, CREATESECUREAUTH, GRANT_TIME, GRANTREVOKE_TIME FROM SYSCAT.DBAUTH WHERE GRANTEE = '%TARGET_USERNAME%'"
call "%~dp0Db2Functions.bat" db2_select_common Csv %SQL_SELECT_STATEMENT%
call "%~dp0Db2Functions.bat" db2_select_common Web %SQL_SELECT_STATEMENT%

goto :eof

:not_allowed
    echo "%TARGET_USERNAME%" is NOT legal to run using this script.
    echo "Please use the db2 command to grant privileges to %TARGET_USERNAME% manually."
    goto :eof

