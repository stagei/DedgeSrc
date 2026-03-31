-- DB2 LUW 12.1 Authority Check for External Routine Privileges
-- This script checks who can grant CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE

-- Current user
SELECT 'Current User:' AS INFO, USER AS USERNAME FROM SYSIBM.SYSDUMMY1;

-- Current user's authorities
SELECT 'Your Authorities:' AS INFO, 
       GRANTEE,
       CASE WHEN SECURITYADMAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS SECURITYADM,
       CASE WHEN ACCESSCTRLAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS ACCESSCTRL,
       CASE WHEN DBADMAUTH = 'Y' THEN 'YES' ELSE 'NO' END AS DBADM
FROM SYSCAT.DBAUTH 
WHERE GRANTEE = USER;

-- Users with SECURITYADMAUTH authority (can grant external routine privileges if registry variable is set)
SELECT 'Users with SECURITYADMAUTH:' AS INFO,
       GRANTEE, 
       GRANTOR, 
       GRANT_TIME
FROM SYSCAT.DBAUTH 
WHERE SECURITYADMAUTH = 'Y'
ORDER BY GRANTEE;

-- Users with ACCESSCTRLAUTH authority (can grant external routine privileges if registry variable is set)
SELECT 'Users with ACCESSCTRLAUTH:' AS INFO,
       GRANTEE, 
       GRANTOR, 
       GRANT_TIME
FROM SYSCAT.DBAUTH 
WHERE ACCESSCTRLAUTH = 'Y'
ORDER BY GRANTEE;

-- Users who already have EXTERNALROUTINEAUTH
SELECT 'Users with EXTERNALROUTINEAUTH:' AS INFO,
       GRANTEE, 
       GRANTOR, 
       GRANT_TIME
FROM SYSCAT.DBAUTH 
WHERE EXTERNALROUTINEAUTH = 'Y'
ORDER BY GRANTEE;

-- Users who already have NOFENCEAUTH
SELECT 'Users with NOFENCEAUTH:' AS INFO,
       GRANTEE, 
       GRANTOR, 
       GRANT_TIME
FROM SYSCAT.DBAUTH 
WHERE NOFENCEAUTH = 'Y'
ORDER BY GRANTEE; 