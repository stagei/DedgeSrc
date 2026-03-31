
@echo off
REM Synopsis: Checks which users have authority to grant CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE privileges.
REM For DB2 LUW 12.1 - uses SYSCAT.DBAUTH since SYSCAT.SYSAUTHORITY doesn't exist in LUW.

echo Checking which users can grant CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE privileges...
echo.

echo === Checking Registry Variable ===
echo Checking DB2_ALTERNATE_AUTHZ_BEHAVIOUR registry variable...
db2set DB2_ALTERNATE_AUTHZ_BEHAVIOUR

echo.
echo === Users with SECADM Authority (Can Grant if Registry Set) ===
db2 "SELECT 'SECADM_HOLDERS' AS AUTHORITY_TYPE, GRANTEE, GRANTOR, GRANTEDTS AS GRANTED_TIME FROM SYSCAT.DBAUTH WHERE SECADMAUTH = 'Y' ORDER BY GRANTEE"

echo.
echo === Users with ACCESSCTRL Authority (Can Grant if Registry Set) ===
db2 "SELECT 'ACCESSCTRL_HOLDERS' AS AUTHORITY_TYPE, GRANTEE, GRANTOR, GRANTEDTS AS GRANTED_TIME FROM SYSCAT.DBAUTH WHERE ACCESSCTRLAUTH = 'Y' ORDER BY GRANTEE"

echo.
echo === Check Current User's Authorities ===
db2 "SELECT USER AS CURRENT_USER, CASE WHEN SECADMAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS HAS_SECADM, CASE WHEN ACCESSCTRLAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS HAS_ACCESSCTRL, CASE WHEN DBADMAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS HAS_DBADM FROM SYSCAT.DBAUTH WHERE GRANTEE = USER"

echo.
echo === Summary ===
echo - In DB2 LUW 12.1, SYSADM authority is typically granted at the instance level
echo - Check your local administrators group or contact your DB2 instance administrator
echo - SECADM/ACCESSCTRL users can grant only if DB2_ALTERNATE_AUTHZ_BEHAVIOUR registry variable is set
echo - If registry variable is NULL, only SYSADM can grant these privileges