@echo off
REM Synopsis: Simple check to see who can grant CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE privileges.
REM Shows current user's authorities and lists users with SECADM/ACCESSCTRL.

echo.
echo =================================================
echo   Who Can Grant External Routine Privileges?
echo =================================================
echo.

echo === Current User ===
db2 "SELECT USER AS CURRENT_USER FROM SYSIBM.SYSDUMMY1"

echo.
echo === Your Current Authorities ===
db2 "SELECT GRANTEE, CASE WHEN SECURITYADMAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS SECADM, CASE WHEN ACCESSCTRLAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS ACCESSCTRL, CASE WHEN DBADMAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS DBADM FROM SYSCAT.DBAUTH WHERE GRANTEE = USER"

echo.
echo === Users with SECURITYADMAUTH Authority ===
db2 "SELECT GRANTEE, GRANTOR, GRANT_TIME FROM SYSCAT.DBAUTH WHERE SECURITYADMAUTH = 'Y' ORDER BY GRANTEE"

echo.
echo === Users with ACCESSCTRLAUTH Authority ===
db2 "SELECT GRANTEE, GRANTOR, GRANT_TIME FROM SYSCAT.DBAUTH WHERE ACCESSCTRLAUTH = 'Y' ORDER BY GRANTEE"

echo.
echo === Users with EXTERNALROUTINEAUTH ===
db2 "SELECT GRANTEE, GRANTOR, GRANT_TIME FROM SYSCAT.DBAUTH WHERE EXTERNALROUTINEAUTH = 'Y' ORDER BY GRANTEE"

echo.
echo === Users with NOFENCEAUTH ===
db2 "SELECT GRANTEE, GRANTOR, GRANT_TIME FROM SYSCAT.DBAUTH WHERE NOFENCEAUTH = 'Y' ORDER BY GRANTEE"

echo.
echo === Registry Variable Status ===
echo Checking DB2_ALTERNATE_AUTHZ_BEHAVIOUR...
db2set DB2_ALTERNATE_AUTHZ_BEHAVIOUR

echo.
echo =================================================
echo   SUMMARY
echo =================================================
echo - If DB2_ALTERNATE_AUTHZ_BEHAVIOUR contains EXTERNAL_ROUTINE_DBAUTH:
echo   SECURITYADMAUTH or ACCESSCTRLAUTH users can grant CREATE_EXTERNAL_ROUTINE
echo.
echo - If DB2_ALTERNATE_AUTHZ_BEHAVIOUR contains NOT_FENCED_ROUTINE_DBAUTH:
echo   SECURITYADMAUTH or ACCESSCTRLAUTH users can grant CREATE_NOT_FENCED_ROUTINE
echo.
echo - If registry variable is not set:
echo   Only SYSADM (instance administrators) can grant these privileges
echo.
echo - Contact your DB2 instance administrator if you need these privileges
echo =================================================
echo.

