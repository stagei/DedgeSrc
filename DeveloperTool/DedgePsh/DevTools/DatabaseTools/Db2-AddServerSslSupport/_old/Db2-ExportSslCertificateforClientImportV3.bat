@echo off
REM ==================================================================
REM Extract DB2 SSL Certificate for Client Import - V3
REM ==================================================================
REM Purpose: Extract the self-signed certificate from DB2 server with Windows SSO client automation
REM Usage: Run this script on the DB2 server (t-no1fkmdev-db)
REM Requirements: Must be run where GSKit tools are available
REM Version: 3.0 - Windows SSO optimized version without keytab dependencies
REM ==================================================================

echo.
REM Set variables
if "%1"=="" (
    echo ERROR: Missing parameter 1 - DATABASE_NAME
    exit /b 1
) else (
    set DATABASE_NAME=%1
)

if "%2"=="" (
    echo ERROR: Missing parameter 2 - DATABASE_PORT
    exit /b 1
) else (
    set DATABASE_PORT=%2
)

if "%3"=="" (
    echo ERROR: Missing parameter 3 - SSL_PASSWORD
    exit /b 1
) else (
    set SSL_PASSWORD=%3
)

if "%4"=="" (
    echo ERROR: Missing parameter 4 - SSL_PORT
    exit /b 1
) else (
    set SSL_PORT=%4
)

if "%5"=="" (
    echo ERROR: Missing parameter 5 - SSL_DIR
    exit /b 1
) else (
    set SSL_DIR=%5
)


if "%6"=="" (
    echo ERROR: Missing parameter 6 - CERT_LABEL
    exit /b 1
) else (
    set CERT_LABEL=%6
)


if "%7"=="" (
    echo ERROR: Missing parameter 7 - LOG_DIR
    exit /b 1
) else (
    set LOG_DIR=%7
)


if "%8"=="" (
    echo ERROR: Missing parameter 8 - BACKUP_DIR
    exit /b 1
) else (
    set BACKUP_DIR=%8
)

if "%9"=="" (
    echo ERROR: Missing parameter 9 - GSKIT_PATH
    exit /b 1
) else (
    set GSKIT_PATH=%9
)

if "%10"=="" (
    echo ERROR: Missing parameter 10 - COMMON_EXPORT_DIR
    exit /b 1
) else (
    set COMMON_EXPORT_DIR=%10
)

if "%11"=="" (
    echo ERROR: Missing parameter 11 - CERT_SCRIPTS_DIR
    exit /b 1
) else (
    set CERT_SCRIPTS_DIR=%11
)

if "%12"=="" (   
    echo ERROR: Missing parameter 12 - STEP
    exit /b 1
) else (
    set STEP=%12
)

echo.
echo ========================================
echo DB2 SSL Certificate Extraction Script V3 (Windows SSO)
echo ========================================
echo.

@REM set CERT_LABEL=DB2_SERVER_CERT
@REM set GSKIT_PATH=C:\Program Files\ibm\gsk8\bin
set SERVER_HOSTNAME=%COMPUTERNAME%.DEDGE.fk.no
@REM set COMMON_EXPORT_DIR=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\SSL\%COMPUTERNAME%
@REM set CERT_FILE=%COMMON_EXPORT_DIR%\db2-server-cert.cer
REM Enhanced client distribution structure
@REM set CLIENT_CONFIG_DIR=%COMMON_EXPORT_DIR%\ClientConfig
set CERT_SCRIPTS_DIR=%COMMON_EXPORT_DIR%\CertificateImport
REM Enhanced logging
set LOGFILE=%LOG_DIR%\cert_export_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
echo %DATE% %TIME% - Starting Certificate Export V2 (No Keytab) >> "%LOGFILE%"

REM Create enhanced directory structure
md "%CERT_SCRIPTS_DIR%" 2>nul

REM Clean old files with enhanced cleanup
del "%COMMON_EXPORT_DIR%\db2-server-cert.cer" 2>nul
del "%COMMON_EXPORT_DIR%\db2-client-import-system-java-truststore.bat" 2>nul
del "%COMMON_EXPORT_DIR%\db2-client-import-dbeaver-java-truststore.bat" 2>nul
del "%COMMON_EXPORT_DIR%\db2-client-import-dbeaver-custom-truststore.bat" 2>nul
REM Clean certificate scripts directory
del "%CERT_SCRIPTS_DIR%\*.bat" 2>nul
del "%CERT_SCRIPTS_DIR%\*.cer" 2>nul

echo Configuration:
echo - SSL Directory: %SSL_DIR%
echo - Certificate Label: %CERT_LABEL%
echo - Server Hostname: %SERVER_HOSTNAME%
echo - Output Directory: %COMMON_EXPORT_DIR%
echo - Certificate File: %CERT_FILE%
echo - Client Config Directory: %CLIENT_CONFIG_DIR%
echo - Certificate Scripts Directory: %CERT_SCRIPTS_DIR%
echo - Authentication Mode: Windows SSO (No Keytab)
echo.

REM Check if GSKit tools exist
if not exist "%GSKIT_PATH%\gsk8capicmd_64.exe" (
    echo ERROR: GSKit tools not found at %GSKIT_PATH%
    echo %DATE% %TIME% - ERROR: GSKit tools not found >> "%LOGFILE%"
    pause
    exit /b 1
)

REM Check if SSL keystore exists
if not exist "%SSL_DIR%\server.kdb" (
    echo ERROR: SSL keystore not found at %SSL_DIR%\server.kdb
    echo Make sure configure-db2-ssl.bat has been run successfully.
    echo %DATE% %TIME% - ERROR: SSL keystore not found >> "%LOGFILE%"
    pause
    exit /b 1
)
set /a STEP+=1
echo Step %STEP%: Creating output directory...
if not exist "%COMMON_EXPORT_DIR%" (
    mkdir "%COMMON_EXPORT_DIR%"
    echo - Output directory created: %COMMON_EXPORT_DIR%
) else (
    echo - Output directory already exists: %COMMON_EXPORT_DIR%
)
set /a STEP+=1
echo.
echo Step %STEP%: Listing certificates in keystore...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -list -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%"

set /a STEP+=1
echo.
echo Step %STEP%: Extracting certificate to file...
del "%CERT_FILE%" /f /q 2>nul
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -extract -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" -target "%CERT_FILE%"  
if errorlevel 1 (
    echo ERROR: Failed to extract certificate
    echo %DATE% %TIME% - ERROR: Failed to extract certificate >> "%LOGFILE%"
    pause
    exit /b 1
)

echo - Certificate extracted successfully to: %CERT_FILE%
echo %DATE% %TIME% - Certificate extracted successfully >> "%LOGFILE%"

REM Copy certificate to multiple locations for client convenience
copy "%CERT_FILE%" "%CLIENT_CONFIG_DIR%\" >nul
copy "%CERT_FILE%" "%CERT_SCRIPTS_DIR%\" >nul

set /a STEP+=1
echo.
echo Step %STEP%: Displaying certificate details...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -details -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" 

echo.
echo ========================================
echo Creating Enhanced Client Import Scripts (No Keytab)
echo ========================================
echo.

set /a STEP+=1
echo.
echo Step %STEP%: Creating enhanced system Java truststore import script...
echo @echo off > "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo REM ================================================================== >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo REM Import SSL certificate for %SERVER_HOSTNAME% into system Java truststore - V2 (No Keytab) >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo REM ================================================================== >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo echo Importing DB2 SSL certificate into system Java truststore... >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo echo NOTE: This setup uses Windows SSO - no keytab required >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo REM Check for JAVA_HOME >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo if not defined JAVA_HOME ( >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     echo JAVA_HOME environment variable is not set >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     echo Attempting to find Java installation... >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     for /d %%%%i in ("C:\Program Files\Java\*") do ( >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo         if exist "%%%%i\bin\keytool.exe" ( >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo             set JAVA_HOME=%%%%i >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo             echo Found Java at: %%%%i >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo             goto :found_java >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo         ) >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     ) >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     echo Java installation not found automatically >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     set /p JAVA_HOME="Enter Java home directory: " >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo ) >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo :found_java >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo echo Using Java home: %%JAVA_HOME%% >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo REM Remove existing certificate if present >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo "%%JAVA_HOME%%\bin\keytool.exe" -delete -alias %SERVER_HOSTNAME% -keystore "%%JAVA_HOME%%\lib\security\cacerts" -storepass changeit 2^>nul >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo REM Import new certificate >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo "%%JAVA_HOME%%\bin\keytool.exe" -import -alias %SERVER_HOSTNAME% -file "db2-server-cert.cer" -keystore "%%JAVA_HOME%%\lib\security\cacerts" -storepass changeit -noprompt >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo if errorlevel 1 ( >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     echo ERROR: Failed to import certificate >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     pause >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo ) else ( >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     echo Certificate imported successfully! >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo     echo You can now use Windows SSO with SSL connections. >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"
echo ) >> "%CERT_SCRIPTS_DIR%\import-to-system-java-truststore.bat"

set /a STEP+=1
echo.
echo Step %STEP%: Creating enhanced DBeaver JRE truststore import script...
echo @echo off > "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo REM ================================================================== >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo REM Import SSL certificate for %SERVER_HOSTNAME% into DBeaver JRE truststore - V2 (No Keytab) >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo REM ================================================================== >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo echo Importing DB2 SSL certificate into DBeaver JRE truststore... >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo echo NOTE: This setup uses Windows SSO - no keytab required >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo REM Check for DBeaver installation >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo set DBEAVER_PATHS="C:\Program Files\DBeaver" "C:\Users\%%USERNAME%%\AppData\Local\DBeaver" >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo for %%%%p in (%%DBEAVER_PATHS%%) do ( >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo     if exist "%%%%~p\jre\bin\keytool.exe" ( >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo         set DBEAVER_JRE=%%%%~p\jre >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo         echo Found DBeaver JRE at: %%%%~p\jre >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo         goto :found_dbeaver >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo     ) >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo ) >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo echo ERROR: DBeaver JRE not found in standard locations >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo exit /b 1 >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo :found_dbeaver >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo REM Remove existing certificate >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo "%%DBEAVER_JRE%%\bin\keytool.exe" -delete -alias %SERVER_HOSTNAME% -keystore "%%DBEAVER_JRE%%\lib\security\cacerts" -storepass changeit 2^>nul >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo REM Import new certificate >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo "%%DBEAVER_JRE%%\bin\keytool.exe" -import -alias %SERVER_HOSTNAME% -file "db2-server-cert.cer" -keystore "%%DBEAVER_JRE%%\lib\security\cacerts" -storepass changeit -noprompt >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo if errorlevel 1 ( >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo     echo ERROR: Failed to import certificate to DBeaver JRE >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo ) else ( >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo     echo Certificate imported successfully to DBeaver JRE! >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo     echo You can now use Windows SSO with SSL connections in DBeaver. >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"
echo ) >> "%CERT_SCRIPTS_DIR%\import-to-dbeaver-jre-truststore.bat"

set /a STEP+=1
echo.
echo Step %STEP%: Creating enhanced custom truststore creation script...
echo @echo off > "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo REM ================================================================== >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo REM Create custom truststore for %SERVER_HOSTNAME% - V2 (No Keytab) >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo REM ================================================================== >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo echo Creating custom truststore for DB2 SSL connections... >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo echo NOTE: This setup uses Windows SSO - no keytab required >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo REM Create truststore directory >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo set TRUSTSTORE_DIR=C:\ProgramData\DB2SSL >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo if not exist "%%TRUSTSTORE_DIR%%" mkdir "%%TRUSTSTORE_DIR%%" >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo REM Find Java installation >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo if not defined JAVA_HOME ( >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     for /d %%%%i in ("C:\Program Files\Java\*") do ( >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo         if exist "%%%%i\bin\keytool.exe" ( >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo             set JAVA_HOME=%%%%i >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo             goto :java_found >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo         ) >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     ) >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     REM Try DBeaver JRE as fallback >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     if exist "C:\Program Files\DBeaver\jre\bin\keytool.exe" ( >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo         set JAVA_HOME=C:\Program Files\DBeaver\jre >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo         goto :java_found >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     ) >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     echo ERROR: Java installation not found >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     exit /b 1 >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo ) >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo :java_found >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo echo Using Java: %%JAVA_HOME%% >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo echo Creating truststore: %%TRUSTSTORE_DIR%%\db2-truststore.jks >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo. >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo REM Create custom truststore >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo "%%JAVA_HOME%%\bin\keytool.exe" -import -alias %SERVER_HOSTNAME% -file "db2-server-cert.cer" -keystore "%%TRUSTSTORE_DIR%%\db2-truststore.jks" -storepass %SSL_PASSWORD% -noprompt >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo if errorlevel 1 ( >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     echo ERROR: Failed to create custom truststore >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo ) else ( >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     echo Custom truststore created successfully! >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     echo Location: %%TRUSTSTORE_DIR%%\db2-truststore.jks >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     echo Password: %SSL_PASSWORD% >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo     echo Use with Windows SSO for SSL connections. >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"
echo ) >> "%CERT_SCRIPTS_DIR%\create-custom-truststore.bat"

set /a STEP+=1
echo.
echo Step %STEP%: Creating comprehensive Windows SSO setup guide...
echo REM ================================================================== > "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo DB2 SSL Client Setup Guide - Windows SSO (No Keytab) - %SERVER_HOSTNAME% >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo Generated: %DATE% %TIME% >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo ================================================================== >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo WINDOWS SSO QUICK START: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo 1. Run ClientConfig\Distribute-KRB5-Ini-File-To-Client-Windir.bat >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo 2. Run CertificateImport\import-to-dbeaver-jre-truststore.bat >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo 3. Use RECOMMENDED JDBC URL from debeaver_sso_setup.bat >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo 4. Leave username/password EMPTY in DBeaver - uses Windows login >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo RECOMMENDED JDBC CONNECTION STRING: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo jdbc:db2://%SERVER_HOSTNAME%:%SSL_PORT%/%DATABASE_NAME%:securityMechanism=15;sslConnection=true; >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo ALTERNATIVE JDBC CONNECTION STRING: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo jdbc:db2://%SERVER_HOSTNAME%:%SSL_PORT%/%DATABASE_NAME%:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/%SERVER_HOSTNAME%@DEDGE.FK.NO; >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo SECURITY MECHANISM EXPLANATION: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - securityMechanism=15: Windows SSPI (simplest, no krb5.ini needed) >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - securityMechanism=11: Kerberos (may need krb5.ini for some clients) >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo CERTIFICATE IMPORT OPTIONS: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - import-to-system-java-truststore.bat: For system-wide Java applications >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - import-to-dbeaver-jre-truststore.bat: For DBeaver Community Edition >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - create-custom-truststore.bat: For custom applications >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo FILES INCLUDED: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - db2-server-cert.cer: Server SSL certificate >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - ClientConfig\krb5.ini: Minimal Kerberos configuration (optional) >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - ClientConfig\Distribute-KRB5-Ini-File-To-Client-Windir.bat: Windows SSO client setup >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - ClientConfig\Test-Ssl-Connection-From-Client.bat: SSO connection testing >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - CertificateImport\*.bat: Certificate import scripts >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - debeaver_sso_setup.bat: DBeaver connection strings >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo. >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo IMPORTANT NOTES: >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - NO KEYTAB FILES REQUIRED - uses Windows integrated authentication >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - Your Windows domain login credentials are used automatically >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - Works with existing Kerberos infrastructure without additional setup >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - SSL certificate import is required for SSL connections >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"
echo - Test connection first with ClientConfig\Test-Ssl-Connection-From-Client.bat >> "%COMMON_EXPORT_DIR%\CLIENT_SSO_SETUP_GUIDE.txt"

echo.
echo ========================================
echo Certificate Extraction Completed!
echo ========================================
echo.
echo Certificate file location: %CERT_FILE%
echo Client configuration directory: %CLIENT_CONFIG_DIR%
echo Certificate import scripts: %CERT_SCRIPTS_DIR%
echo.
echo V2 Enhanced Features (No Keytab):
echo - Windows SSO integration - no keytab files required
echo - Multiple certificate import options with auto-detection
echo - Simplified client setup for Windows integrated authentication
echo - Connection testing tools for SSO validation
echo - Detailed Windows SSO setup documentation
echo.

echo Next steps for Windows SSO clients:
echo 1. Navigate to: %COMMON_EXPORT_DIR%
echo 2. Read CLIENT_SSO_SETUP_GUIDE.txt for Windows SSO instructions
echo 3. Run ClientConfig\Distribute-KRB5-Ini-File-To-Client-Windir.bat
echo 4. Import certificate using scripts from CertificateImport\ directory
echo 5. Test SSO connection using ClientConfig\Test-Ssl-Connection-From-Client.bat
echo 6. Configure DBeaver with RECOMMENDED JDBC URL (securityMechanism=15)
echo.

echo %DATE% %TIME% - Certificate export and Windows SSO client setup completed >> "%LOGFILE%"

explorer "%COMMON_EXPORT_DIR%" 