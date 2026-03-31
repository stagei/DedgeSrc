@echo off
REM Synopsis: This script checks which users have authority to grant CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE privileges.
REM It queries SYSCAT.SYSAUTHORITY and SYSCAT.DBAUTH to find users with SYSADM, SECADM, or ACCESSCTRL authorities.

echo Checking which users can grant CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE privileges...
echo.

db2 -tvf "%~dp0Db2CheckGrantAuthority.sql"

echo.
echo Summary:
echo - SYSADM users can always grant these privileges
echo - SECADM/ACCESSCTRL users can grant only if DB2_ALTERNATE_AUTHZ_BEHAVIOUR registry variable is set
echo - Current user authorities are shown in the last result set
echo.
pause 