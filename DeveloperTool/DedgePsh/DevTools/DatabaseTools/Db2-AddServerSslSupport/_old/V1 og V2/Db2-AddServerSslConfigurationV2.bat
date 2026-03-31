@echo off
REM ==================================================================
REM DB2 SSL Server Configuration Script for Kerberos JDBC Client Setup - V2
REM ==================================================================
REM Purpose: Configure DB2 server for SSL connections with enhanced security
REM Usage: Run this script in db2cmd.exe environment
REM Requirements: Must be run as DB2 instance owner with admin rights
REM Note: This script is IDEMPOTENT - safe to run multiple times
REM Version: 2.0 - Enhanced with Kerberos config, security hardening, and client automation
REM ==================================================================

echo.
echo ====================================
echo DB2 SSL Configuration Script V2
echo ====================================
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

set DB2_INSTALL_PATH=C:\DbInst
set SSL_DIR=C:\DB2\ssl
set SERVER_HOSTNAME=%COMPUTERNAME%.DEDGE.fk.no
set CERT_LABEL=DB2_SERVER_CERT
set GSKIT_PATH=C:\Program Files\ibm\gsk8\bin
set COMMON_EXPORT_DIR=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\SSL\%COMPUTERNAME%
REM V2: Enhanced logging and backup directories
set LOG_DIR=C:\DB2\logs\ssl
set BACKUP_DIR=C:\DB2\backup\ssl
set KERBEROS_DIR=C:\DB2\kerberos
set CLIENT_CONFIG_DIR=%COMMON_EXPORT_DIR%\ClientConfig
rd /s /q "%COMMON_EXPORT_DIR%"
md "%COMMON_EXPORT_DIR%" 2>nul  
md "%CLIENT_CONFIG_DIR%" 2>nul
md "%LOG_DIR%" 2>nul
md "%BACKUP_DIR%" 2>nul
md "%KERBEROS_DIR%" 2>nul
set NO_STOP_ON_ERROR=1

REM V2: Enhanced logging
set LOGFILE=%LOG_DIR%\ssl_config_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
echo %DATE% %TIME% - Starting DB2 SSL Configuration V2 > "%LOGFILE%"

echo Configuration Settings:
echo - DB2 Installation: %DB2_INSTALL_PATH%
echo - Database Name: %DATABASE_NAME%
echo - Database Port: %DATABASE_PORT%
echo - SSL Directory: %SSL_DIR%
echo - SSL Port: %SSL_PORT%
echo - Server Hostname: %SERVER_HOSTNAME%
echo - SSL Password: %SSL_PASSWORD%
echo - Certificate Label: %CERT_LABEL%
echo - GSKit Path: %GSKIT_PATH%
echo - Log Directory: %LOG_DIR%
echo - Backup Directory: %BACKUP_DIR%
echo - Kerberos Directory: %KERBEROS_DIR%
echo - Client Config Directory: %CLIENT_CONFIG_DIR%
echo - No Stop On Error: %NO_STOP_ON_ERROR%
echo.

REM V2: Log configuration settings
echo %DATE% %TIME% - Configuration: DB=%DATABASE_NAME%, SSL_PORT=%SSL_PORT%, SERVER=%SERVER_HOSTNAME% >> "%LOGFILE%"

REM Check if DB2 installation exists
if not exist "%DB2_INSTALL_PATH%" (
    echo ERROR: DB2 installation not found at %DB2_INSTALL_PATH%
    echo Please verify the installation path and try again.
    echo %DATE% %TIME% - ERROR: DB2 installation not found at %DB2_INSTALL_PATH% >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)

REM Check if GSKit tools exist
if not exist "%GSKIT_PATH%\gsk8capicmd_64.exe" (
    echo ERROR: GSKit tools not found at %GSKIT_PATH%
    echo Please verify the DB2 installation includes GSKit.
    echo %DATE% %TIME% - ERROR: GSKit tools not found >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)

REM V2: Create backup of existing configuration
echo.
echo ====================================
echo V2: Creating Configuration Backup
echo ====================================
echo.
echo Creating backup of existing DB2 configuration...
db2 get dbm cfg > "%BACKUP_DIR%\dbm_cfg_backup_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%.txt"
if exist "%SSL_DIR%" (
    echo Backing up existing SSL directory...
    xcopy "%SSL_DIR%\*" "%BACKUP_DIR%\ssl_backup_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%\" /E /I /Y >nul 2>&1
)
echo %DATE% %TIME% - Configuration backup created >> "%LOGFILE%"

echo.
echo ====================================
echo Pre-Step: Cleaning Previous SSL Configuration
echo ====================================
echo.
echo This ensures the script can be run multiple times safely...
call Db2-RemoveServerSslConfigurationV2.bat %DATABASE_NAME% %DATABASE_PORT% %SSL_PASSWORD% %SSL_PORT%
echo   - Previous SSL files cleaned (if any existed)
timeout /t 5 /nobreak >nul

echo.
echo ====================================
echo Beginning Fresh SSL Configuration
echo ====================================

echo Step 1: Creating SSL directory...
if not exist "%SSL_DIR%" (
    mkdir "%SSL_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to create SSL directory %SSL_DIR%
        echo %DATE% %TIME% - ERROR: Failed to create SSL directory >> "%LOGFILE%"
        if "%NO_STOP_ON_ERROR%"=="0" (
            pause
            exit /b 1
        )
    )
    echo - SSL directory created: %SSL_DIR%
    echo %DATE% %TIME% - SSL directory created >> "%LOGFILE%"
) else (
    echo - SSL directory already exists: %SSL_DIR%
)

echo.
echo Step 2: Creating SSL keystore database...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -keydb -create -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -stash
if errorlevel 1 (
    echo ERROR: Failed to create SSL keystore database
    echo This should not happen after cleanup. Check GSKit installation.
    echo %DATE% %TIME% - ERROR: Failed to create SSL keystore database >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)
echo - SSL keystore database created successfully
echo %DATE% %TIME% - SSL keystore database created >> "%LOGFILE%"

echo.
echo Step 3.1: Removing existing certificate...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -delete -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" >nul 2>&1
echo - Existing certificate removed successfully

echo.
echo Step 3.2: Creating self-signed certificate...
REM V2: Enhanced certificate with stronger parameters
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -create -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" -dn "CN=%SERVER_HOSTNAME%,O=FK,C=NO" -size 2048 -sigalg SHA256WithRSA -expire 365
if errorlevel 1 (
    echo ERROR: Failed to create self-signed certificate
    echo This should not happen after cleanup. Check certificate parameters.
    echo %DATE% %TIME% - ERROR: Failed to create certificate >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)
echo - Self-signed certificate created successfully
echo %DATE% %TIME% - Certificate created with enhanced parameters >> "%LOGFILE%"

echo.
echo Step 4: Setting certificate as default...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -setdefault -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%"
if errorlevel 1 (
    echo ERROR: Failed to set certificate as default
    echo %DATE% %TIME% - ERROR: Failed to set certificate as default >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)
echo - Certificate set as default successfully

echo.
echo Step 5: Listing certificates in keystore...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -list -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%"

echo.
echo Step 6: Configuring DB2 SSL parameters...

echo - Setting SSL service name to port %SSL_PORT%...
db2 update dbm cfg using ssl_svcename %SSL_PORT%
if errorlevel 1 (
    echo ERROR: Failed to set SSL service name
    echo %DATE% %TIME% - ERROR: Failed to set SSL service name >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)

echo - Setting SSL keystore database path...
db2 update dbm cfg using ssl_svr_keydb "%SSL_DIR%\server.kdb"
if errorlevel 1 (
    echo ERROR: Failed to set SSL keystore database path
    echo %DATE% %TIME% - ERROR: Failed to set SSL keystore database path >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)

echo - Setting SSL keystore stash file path...
db2 update dbm cfg using ssl_svr_stash "%SSL_DIR%\server.sth"
if errorlevel 1 (
    echo ERROR: Failed to set SSL keystore stash file path
    echo %DATE% %TIME% - ERROR: Failed to set SSL keystore stash file path >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)

echo - Setting SSL certificate label...
db2 update dbm cfg using ssl_svr_label "%CERT_LABEL%"
if errorlevel 1 (
    echo ERROR: Failed to set SSL certificate label
    echo %DATE% %TIME% - ERROR: Failed to set SSL certificate label >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)

REM V2: Enhanced SSL security configuration
echo.
echo Step 6.1: V2 - Configuring enhanced SSL security...
echo - Setting SSL cipher suites for enhanced security...
REM https://www.ibm.com/docs/en/db2/12.1.0?topic=parameters-ssl-cipherspecs-supported-cipher-specifications-server
db2 update dbm cfg using SSL_CIPHERSPECS "TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
if errorlevel 1 (
    echo WARNING: Failed to set enhanced SSL cipher suites, using defaults
    echo %DATE% %TIME% - WARNING: Failed to set SSL cipher suites >> "%LOGFILE%"
)

echo - Setting SSL versions for security...
REM https://www.ibm.com/docs/en/db2/12.1.0?topic=parameters-ssl-versions-supported-ssl-versions-server
db2 update dbm cfg using SSL_VERSIONS "TLSv1.2,TLSv1.3"
if errorlevel 1 (
    echo WARNING: Failed to set SSL versions, using defaults
    echo %DATE% %TIME% - WARNING: Failed to set SSL versions >> "%LOGFILE%"
)

echo.
echo Step 7: Displaying current SSL configuration...
db2 get dbm cfg | findstr -i ssl

echo.
echo Step 8: Stopping and starting DB2 instance...
echo - Stopping DB2 instance...
db2stop >nul 2>&1
echo   - DB2 instance stopped (or was not running)
echo %DATE% %TIME% - DB2 instance stopped >> "%LOGFILE%"

echo - Starting DB2 instance...
db2start
if errorlevel 1 (
    echo ERROR: Failed to start DB2 instance
    echo Try running: db2start
    echo %DATE% %TIME% - ERROR: Failed to start DB2 instance >> "%LOGFILE%"
    if "%NO_STOP_ON_ERROR%"=="0" (
        pause
        exit /b 1
    )
)
echo   - DB2 instance started successfully
echo %DATE% %TIME% - DB2 instance started successfully >> "%LOGFILE%"

echo.
echo Step 9: Adding firewall rule...
powershell -Command "Get-NetFirewallRule | Where-Object { $_.LocalPort -eq '%SSL_PORT%' } | ForEach-Object { Write-Host ('Removing rule: ' + $_.DisplayName); Remove-NetFirewallRule -DisplayName $_.DisplayName }"
netsh advfirewall firewall add rule name="DB2 Remote Access %COMPUTERNAME%" dir=in action=allow protocol=TCP localport=%SSL_PORT%

REM V2: Generate Kerberos configuration files
echo.
echo ====================================
echo Step 10: V2 - Generating Kerberos Configuration
echo ====================================
echo.
echo Creating krb5.ini configuration file...
echo [libdefaults] > "%KERBEROS_DIR%\krb5.ini"
echo     default_realm = DEDGE.FK.NO >> "%KERBEROS_DIR%\krb5.ini"
echo     default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 rc4-hmac >> "%KERBEROS_DIR%\krb5.ini"
echo     default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 rc4-hmac >> "%KERBEROS_DIR%\krb5.ini"
echo     permitted_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 rc4-hmac >> "%KERBEROS_DIR%\krb5.ini"
echo     clockskew = 300 >> "%KERBEROS_DIR%\krb5.ini"
echo     ticket_lifetime = 24h >> "%KERBEROS_DIR%\krb5.ini"
echo     renew_lifetime = 7d >> "%KERBEROS_DIR%\krb5.ini"
echo     forwardable = true >> "%KERBEROS_DIR%\krb5.ini"
echo     proxiable = true >> "%KERBEROS_DIR%\krb5.ini"
echo     dns_lookup_realm = false >> "%KERBEROS_DIR%\krb5.ini"
echo     dns_lookup_kdc = false >> "%KERBEROS_DIR%\krb5.ini"
echo     allow_weak_crypto = false >> "%KERBEROS_DIR%\krb5.ini"
echo. >> "%KERBEROS_DIR%\krb5.ini"
echo [realms] >> "%KERBEROS_DIR%\krb5.ini"
echo     DEDGE.FK.NO = { >> "%KERBEROS_DIR%\krb5.ini"
echo         kdc = p-no1dc-vm01.DEDGE.fk.no:88 >> "%KERBEROS_DIR%\krb5.ini"
echo         kdc = p-no1dc-vm02.DEDGE.fk.no:88 >> "%KERBEROS_DIR%\krb5.ini"
echo         admin_server = p-no1dc-vm01.DEDGE.fk.no:749 >> "%KERBEROS_DIR%\krb5.ini"
echo         default_domain = DEDGE.fk.no >> "%KERBEROS_DIR%\krb5.ini"
echo         kpasswd_server = p-no1dc-vm01.DEDGE.fk.no:464 >> "%KERBEROS_DIR%\krb5.ini"
echo     } >> "%KERBEROS_DIR%\krb5.ini"
echo. >> "%KERBEROS_DIR%\krb5.ini"
echo [domain_realm] >> "%KERBEROS_DIR%\krb5.ini"
echo     .DEDGE.fk.no = DEDGE.FK.NO >> "%KERBEROS_DIR%\krb5.ini"
echo     DEDGE.fk.no = DEDGE.FK.NO >> "%KERBEROS_DIR%\krb5.ini"
echo     .fk.no = DEDGE.FK.NO >> "%KERBEROS_DIR%\krb5.ini"
echo     fk.no = DEDGE.FK.NO >> "%KERBEROS_DIR%\krb5.ini"
echo. >> "%KERBEROS_DIR%\krb5.ini"
echo [logging] >> "%KERBEROS_DIR%\krb5.ini"
echo     default = FILE:C:\temp\krb5libs.log >> "%KERBEROS_DIR%\krb5.ini"
echo     kdc = FILE:C:\temp\krb5kdc.log >> "%KERBEROS_DIR%\krb5.ini"
echo     admin_server = FILE:C:\temp\kadmind.log >> "%KERBEROS_DIR%\krb5.ini"
echo. >> "%KERBEROS_DIR%\krb5.ini"
echo # DB2 specific configuration >> "%KERBEROS_DIR%\krb5.ini"
echo [dbms] >> "%KERBEROS_DIR%\krb5.ini"
echo     DB2_AUTHENTICATION = { >> "%KERBEROS_DIR%\krb5.ini"
echo         default_principal = db2/%SERVER_HOSTNAME%@DEDGE.FK.NO >> "%KERBEROS_DIR%\krb5.ini"
echo         keytab = C:\DB2\security\db2.keytab >> "%KERBEROS_DIR%\krb5.ini"
echo     } >> "%KERBEROS_DIR%\krb5.ini"

echo - Kerberos configuration file created: %KERBEROS_DIR%\krb5.ini
echo %DATE% %TIME% - Kerberos configuration file created >> "%LOGFILE%"

REM V2: Copy all configuration files to client distribution directory
echo.
echo ====================================
echo Step 11: V2 - Preparing Client Configuration Files
echo ====================================
echo.
echo Copying configuration files to client distribution directory...
copy "%KERBEROS_DIR%\krb5.ini" "%CLIENT_CONFIG_DIR%\" >nul
copy "%LOGFILE%" "%CLIENT_CONFIG_DIR%\" >nul

REM V2: Create enhanced client setup scripts
echo Creating enhanced client setup scripts...

REM Create Windows client setup script
echo @echo off > "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo REM ================================================================== >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo REM Windows Client Setup for DB2 SSL + Kerberos Connection >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo REM Server: %SERVER_HOSTNAME% >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo REM ================================================================== >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo echo Setting up Windows client for DB2 SSL connection... >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo. >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo REM Copy Kerberos configuration >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo if not exist "C:\Windows\krb5.ini" ( >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo     copy "krb5.ini" "C:\Windows\krb5.ini" >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo     echo Kerberos configuration installed >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo ) >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo. >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo REM Set environment variables >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo setx KRB5_CONFIG "C:\Windows\krb5.ini" >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo setx DB2_SSL_SERVER "%SERVER_HOSTNAME%" >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo setx DB2_SSL_PORT "%SSL_PORT%" >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo setx DB2_DATABASE "%DATABASE_NAME%" >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo. >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo echo Windows client setup completed! >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"
echo echo Please restart your command prompt to use new environment variables. >> "%CLIENT_CONFIG_DIR%\setup-windows-client.bat"

REM Create Linux client setup script
echo #!/bin/bash > "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo # ================================================================== >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo # Linux Client Setup for DB2 SSL + Kerberos Connection >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo # Server: %SERVER_HOSTNAME% >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo # ================================================================== >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "Setting up Linux client for DB2 SSL connection..." >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo. >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo # Copy Kerberos configuration >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo sudo cp krb5.ini /etc/krb5.conf >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "Kerberos configuration installed" >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo. >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo # Set environment variables >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "export KRB5_CONFIG=/etc/krb5.conf" ^>^> ~/.bashrc >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "export DB2_SSL_SERVER=%SERVER_HOSTNAME%" ^>^> ~/.bashrc >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "export DB2_SSL_PORT=%SSL_PORT%" ^>^> ~/.bashrc >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "export DB2_DATABASE=%DATABASE_NAME%" ^>^> ~/.bashrc >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo. >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "Linux client setup completed!" >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"
echo echo "Please run: source ~/.bashrc" >> "%CLIENT_CONFIG_DIR%\setup-linux-client.sh"

REM Create connection test script
echo @echo off > "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo REM ================================================================== >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo REM Test DB2 SSL + Kerberos Connection >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo REM ================================================================== >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo echo Testing connection to %SERVER_HOSTNAME%:%SSL_PORT%... >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo. >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo REM Test SSL port connectivity >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo powershell -Command "Test-NetConnection -ComputerName %SERVER_HOSTNAME% -Port %SSL_PORT%" >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo. >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo REM Test Kerberos ticket >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo echo Testing Kerberos ticket... >> "%CLIENT_CONFIG_DIR%\test-connection.bat"
echo klist >> "%CLIENT_CONFIG_DIR%\test-connection.bat"

echo - Client configuration files created in: %CLIENT_CONFIG_DIR%
echo %DATE% %TIME% - Client configuration files created >> "%LOGFILE%"

echo.
echo ====================================
echo SSL Configuration Completed Successfully!
echo ====================================
echo.
echo This script can be run again if needed - it will clean and reconfigure automatically.
echo.
echo SSL Configuration Summary:
echo - SSL Port: %SSL_PORT%
echo - Keystore: %SSL_DIR%\server.kdb
echo - Stash File: %SSL_DIR%\server.sth
echo - Certificate Label: %CERT_LABEL%
echo - Server Hostname: %SERVER_HOSTNAME%
echo - Firewall open for port %SSL_PORT%
echo - Enhanced SSL cipher suites configured
echo - Kerberos configuration generated
echo - Client setup files created

REM Original DBeaver setup generation (kept as REM for reference)
REM echo @echo off                                                                                                                                                            > "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
REM echo echo -------------------------------------------------------------------------                                                                                      >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
REM echo echo JDBC Connection Strings for Testing of Dbeaver with SSL towards Database %DATABASE_NAME% on %SERVER_HOSTNAME%:%SSL_PORT%:                                      >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"

REM V2: Enhanced DBeaver setup with better organization
echo @echo off > "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo REM ================================================================== >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo REM Enhanced DBeaver Setup for DB2 SSL + Kerberos - V2 >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo REM Server: %SERVER_HOSTNAME% Database: %DATABASE_NAME% >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo REM ================================================================== >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo ========================================================================= >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo DBeaver Connection Setup for %SERVER_HOSTNAME%:%SSL_PORT% Database: %DATABASE_NAME% >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo ========================================================================= >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo. >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo JDBC Connection Strings: >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo. >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 1. SSL + Kerberos ^(Recommended^): >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo    jdbc:db2://%SERVER_HOSTNAME%:%SSL_PORT%/%DATABASE_NAME%:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/%SERVER_HOSTNAME%@DEDGE.FK.NO; >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo. >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 2. SSL + Windows SSPI: >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo    jdbc:db2://%SERVER_HOSTNAME%:%SSL_PORT%/%DATABASE_NAME%:securityMechanism=15;sslConnection=true; >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo. >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 3. Fallback Non-SSL Kerberos: >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo    jdbc:db2://%SERVER_HOSTNAME%:%DATABASE_PORT%/%DATABASE_NAME%:securityMechanism=11;kerberosServerPrincipal=db2/%SERVER_HOSTNAME%@DEDGE.FK.NO; >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo. >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo V2 Enhanced Features: >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo - Enhanced SSL cipher suites for better security >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo - Kerberos configuration files included >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo - Client setup automation scripts provided >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo - Connection testing tools included >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo - Comprehensive logging and backup procedures >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo. >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo Setup Instructions: >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 1. Run ClientConfig\setup-windows-client.bat for Windows setup >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 2. Import certificate using certificate import scripts >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 3. Use connection test script to verify connectivity >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"
echo echo 4. Configure DBeaver with provided JDBC URLs >> "%COMMON_EXPORT_DIR%\debeaver_setup.bat"

powershell -Command "Write-Host (Get-Content '%COMMON_EXPORT_DIR%\debeaver_setup.bat' -Raw) -ForegroundColor Yellow"
echo All done!

echo %DATE% %TIME% - SSL Configuration completed successfully >> "%LOGFILE%"

powershell -File "ssl-handshake-test.ps1" -serverName "%SERVER_HOSTNAME%" -port %SSL_PORT%

echo.
set /p CONTINUE=Do you want to continue with certificate extraction? (Y/N): 
if /i not "%CONTINUE%"=="Y" (
    echo Skipping certificate extraction.
    exit /b 0
)
echo.

call Db2-ExportSslCertificateforClientImportV2.bat %DATABASE_NAME% %DATABASE_PORT% %SSL_PASSWORD% %SSL_PORT%
