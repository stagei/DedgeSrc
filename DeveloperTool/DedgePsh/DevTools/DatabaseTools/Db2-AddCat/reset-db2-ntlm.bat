@echo off
echo ===== DB2 Client Reset to NTLM Authentication =====
echo.

db2 update cli cfg for section COMMON using CLI_GSSPLUGIN_NAME_1=''
db2 update cli cfg for section COMMON using CLI_GSSPLUGIN_LIST=''
db2 update cli cfg for section COMMON using CLNT_KRB_PLUGIN=''

db2 update cli cfg for section COMMON using tracecomm=0
db2 update cli cfg for section COMMON using traceflush=0
db2 update cli cfg for section COMMON using trace=0
db2 update cli cfg for section COMMON using tracepathtname=''
echo Checking current authentication settings...
db2 get dbm cfg | findstr "AUTHENTICATION"
db2 get dbm cfg | findstr "SRVCON"
db2 get dbm cfg | findstr "TRUST"
db2 get dbm cfg | findstr "AUTHENTICATION"
db2 get dbm cfg | findstr "TRUST_ALLCLNTS"
db2 get dbm cfg | findstr "TRUST_CLNTAUTH"

dbset -all

echo Resetting DB2 registry variables...
db2set DB2_EXTSECURITY=
echo DB2_EXTSECURITY has been removed

echo Setting communication protocol to TCPIP...
db2set DB2COMM=TCPIP
echo DB2COMM set to TCPIP

echo Setting authentication to SERVER_ENCRYPT (standard for NTLM)...
db2 update cli cfg for section COMMON using AUTHENTICATION SERVER_ENCRYPT
echo Authentication set to SERVER_ENCRYPT

notepad.exe C:\ProgramData\IBM\DB2\DB2COPY1\cfg\db2cli.ini
notepad.exe C:\ProgramData\IBM\DB2\DB2COPY1\db2cli.ini

echo.
echo === Manual steps required ===
echo Please edit the DB2 CLI configuration file to remove Kerberos settings:
echo 1. Make a backup of C:\ProgramData\IBM\DB2\DB2COPY1\cfg\db2cli.ini
echo 2. Open the file in a text editor (run as administrator)
echo 3. Look for the [COMMON] section
echo 4. Remove or comment out these lines:
echo    - CLI_GSSPLUGIN_NAME_1=IBMkrb5
echo    - CLI_GSSPLUGIN_LIST=IBMkrb5
echo    - CLNT_KRB_PLUGIN=IBMkrb5
echo    - tracecomm=1
echo    - traceflush=1
echo    - trace=1
echo    - tracepathtname=C:\temp\db2trace.log
echo 5. Save the file
echo.

echo === Verification ===
echo Current DB2 registry settings:
db2set -all
echo.
echo Current CLI configuration for COMMON section:
db2 get cli cfg for section COMMON
echo.

echo === Next Steps ===
echo After making the manual edits, you may need to:
echo 1. Restart DB2 services
echo 2. Recatalog your databases for NTLM authentication
echo.

pause

