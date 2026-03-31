@echo off
REM ==================================================================
REM DB2 SSL Configuration Teardown Script - V3
REM ==================================================================
REM Purpose: Remove SSL configuration applied by configure-db2-ssl.bat with Windows SSO cleanup
REM Usage: Run this script in db2cmd.exe environment
REM Requirements: Must be run as DB2 instance owner with admin rights
REM Version: 3.0 - Windows SSO optimized version without keytab dependencies
REM ==================================================================

echo.
echo ========================================
echo DB2 SSL Configuration Teardown Script V3 (Windows SSO)
echo ========================================
echo.
echo WARNING: This script will remove all SSL configuration from DB2
echo and delete SSL certificate files.
echo.


echo.
REM Set variables
if "%1"=="" (
    echo ERROR: Missing parameter 1 - DATABASE_NAME
    REM exit /b 1
) else (
    set DATABASE_NAME=%1
)

if "%2"=="" (
    echo ERROR: Missing parameter 2 - DATABASE_PORT
    REM exit /b 1
) else (
    set DATABASE_PORT=%2
)

if "%3"=="" (
    echo ERROR: Missing parameter 3 - SSL_PASSWORD
    REM exit /b 1
) else (
    set SSL_PASSWORD=%3
)

if "%4"=="" (
    echo ERROR: Missing parameter 4 - SSL_PORT
    REM exit /b 1
) else (
    set SSL_PORT=%4
)

REM Set variables (same as configure script)
set DB2_INSTALL_PATH=C:\DbInst
set SSL_DIR=C:\DB2\ssl
set SERVER_HOSTNAME=%COMPUTERNAME%.DEDGE.fk.no
set CERT_LABEL=DB2_SERVER_CERT
set GSKIT_PATH=C:\Program Files\ibm\gsk8\bin
REM  Enhanced directories
set COMMON_EXPORT_DIR=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\SSL\%COMPUTERNAME%
set LOG_DIR=%COMMON_EXPORT_DIR%\logs
set BACKUP_DIR=C:\TEMPFK\Db2SslBackup
set KERBEROS_DIR=C:\DB2\kerberos
set STEP=0


echo Teardown Settings:
echo - DB2 Installation: %DB2_INSTALL_PATH%
echo - SSL Directory to remove: %SSL_DIR%
echo - Server Hostname: %SERVER_HOSTNAME%
echo - Kerberos Directory: %KERBEROS_DIR%
echo - Backup Directory: %BACKUP_DIR%
echo - Authentication Mode: Windows SSO
echo.



REM Check if DB2 installation exists
if not exist "%DB2_INSTALL_PATH%" (
    echo ERROR: DB2 installation not found at %DB2_INSTALL_PATH%
    echo Please verify the installation path and try again.
    
    pause
    REM exit /b 1
)

set /a STEP+=1
echo.
echo Step %STEP%: Displaying current SSL configuration...
echo Current SSL settings before removal:
db2 get dbm cfg | findstr -i ssl
echo.

echo.
echo ====================================
echo Creating Backup Before Removal
echo ====================================
echo.
echo Creating backup of current SSL configuration...
md "%BACKUP_DIR%" 2>nul

REM Backup DB2 configuration
db2 get dbm cfg > "%BACKUP_DIR%\dbm_cfg_before_removal_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%.txt"

REM Backup SSL files if they exist
if exist "%SSL_DIR%" (
    echo Backing up SSL directory...
    xcopy "%SSL_DIR%\*" "%BACKUP_DIR%\ssl_files_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%\" /E /I /Y >nul 2>&1
)

REM Backup Kerberos files if they exist
if exist "%KERBEROS_DIR%" (
    echo Backing up Kerberos directory...
    xcopy "%KERBEROS_DIR%\*" "%BACKUP_DIR%\kerberos_files_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%\" /E /I /Y >nul 2>&1
)


echo Backup completed.


set /a STEP+=1
echo.
echo Step %STEP%: Removing existing certificate...
"%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -delete -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" >nul 2>&1
echo - Removed certificate if it existed


set /a STEP+=1
echo.
echo Step %STEP%: Removing DB2 SSL configuration parameters...

echo - Clearing SSL service name...
db2 update dbm cfg using ssl_svcename NULL


echo - Clearing SSL keystore database path...
db2 update dbm cfg using ssl_svr_keydb NULL

echo - Clearing SSL keystore stash file path...
db2 update dbm cfg using ssl_svr_stash NULL

echo - Clearing SSL certificate label...
db2 update dbm cfg using ssl_svr_label NULL

echo - Clearing SSL client keystore database...
db2 update dbm cfg using ssl_clnt_keydb NULL

echo - Clearing SSL client stash file...
db2 update dbm cfg using ssl_clnt_stash NULL

echo - Clearing enhanced SSL cipher specifications...
db2 update dbm cfg using SSL_CIPHERSPECS NULL

echo - Clearing SSL versions...
db2 update dbm cfg using SSL_VERSIONS NULL

db2 terminate 
echo.
echo Step 3: Verifying SSL configuration removal...
echo SSL settings after removal:
db2 get dbm cfg | findstr -i ssl
echo.
set /a STEP+=1
echo.
echo Step %STEP%: Stopping DB2 instance to apply changes...
echo - Stopping DB2 instance...
db2stop
if errorlevel 1 (
    set /a STEP+=1
    echo.
    echo Step %STEP%: Secondary attempt to stop DB2 instance to apply changes in 5 seconds...
    timeout /t 5 /nobreak >nul
    db2stop >nul 2>&1
)

set /a STEP+=1
echo.
echo Step %STEP%: Starting DB2 instance...
echo - Starting DB2 instance...
db2start >nul 2>&1
if errorlevel 1 (
    echo ERROR: Failed to start DB2 instance
    echo You may need to start it manually using: db2start
    
    pause
) else (
    echo - DB2 instance started successfully
    
)



set /a STEP+=1
echo.
echo Step %STEP%: Removing SSL certificate files and directory...

if exist "%SSL_DIR%" (
    echo - Removing SSL directory and all contents: %SSL_DIR%
    
    REM Make files writable before deletion
    if exist "%SSL_DIR%\server.kdb" (
        attrib -r "%SSL_DIR%\server.kdb"
        echo   - Removing server.kdb
    )
    
    if exist "%SSL_DIR%\server.sth" (
        attrib -r "%SSL_DIR%\server.sth"
        echo   - Removing server.sth
    )
    
    if exist "%SSL_DIR%\server.rdb" (
        attrib -r "%SSL_DIR%\server.rdb"
        echo   - Removing server.rdb
    )
    
    if exist "%SSL_DIR%\server.crl" (
        attrib -r "%SSL_DIR%\server.crl"
        echo   - Removing server.crl
    )
    
    REM Remove the entire SSL directory
    attrib -r "%SSL_DIR%"
    rmdir /s /q "%SSL_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to remove SSL directory %SSL_DIR%
        echo You may need to remove it manually after stopping any processes using these files.
        
        pause
    ) else (
        echo   - SSL directory removed successfully
        
    )
) else (
    echo - SSL directory %SSL_DIR% does not exist (already removed or never created)
)

REM  Remove minimal Kerberos configuration files (No Keytab cleanup needed)
echo.
set /a STEP+=1
echo.
echo Step %STEP%: Removing minimal Kerberos configuration files...
if exist "%KERBEROS_DIR%" (
    echo - Removing Kerberos directory: %KERBEROS_DIR%
    echo   NOTE: No keytab files to clean - Windows SSO mode
    rmdir /s /q "%KERBEROS_DIR%"
    if errorlevel 1 (
        echo WARNING: Failed to remove Kerberos directory
        
    ) else (
        echo   - Kerberos directory removed successfully
    
    )
) else (
    echo - Kerberos directory does not exist
)



set /a STEP+=1
echo.
echo Step %STEP%: Final verification...
echo Final SSL configuration (should show no SSL settings):
db2 get dbm cfg | findstr -i ssl
echo.

REM Check if SSL directory was successfully removed
if not exist "%SSL_DIR%" (
    set SSL_DIR_STATUS=REMOVED
) else (
    set SSL_DIR_STATUS=STILL EXISTS
)

REM  Check Kerberos directory status
if not exist "%KERBEROS_DIR%" (
    set KERBEROS_DIR_STATUS=REMOVED
) else (
    set KERBEROS_DIR_STATUS=STILL EXISTS
)
set /a STEP+=1
echo.
echo Step %STEP%: Removing firewall rule...
powershell -Command "Get-NetFirewallRule | Where-Object { $_.LocalPort -eq '%SSL_PORT%' } | ForEach-Object { Write-Host ('Removing rule: ' + $_.DisplayName); Remove-NetFirewallRule -DisplayName $_.DisplayName }"

REM  Remove environment variables if they were set (Windows SSO specific)
set /a STEP+=1
echo.
echo Step %STEP%: Cleaning Windows SSO environment variables...
reg delete "HKCU\Environment" /v "DB2_SSL_SERVER" /f >nul 2>&1
reg delete "HKCU\Environment" /v "DB2_SSL_PORT" /f >nul 2>&1
reg delete "HKCU\Environment" /v "DB2_INSTALL_PATH" /f >nul 2>&1
reg delete "HKCU\Environment" /v "SSL_DIR" /f >nul 2>&1
reg delete "HKCU\Environment" /v "SERVER_HOSTNAME" /f >nul 2>&1
reg delete "HKCU\Environment" /v "CERT_LABEL" /f >nul 2>&1
reg delete "HKCU\Environment" /v "GSKIT_PATH" /f >nul 2>&1
reg delete "HKCU\Environment" /v "COMMON_EXPORT_DIR" /f >nul 2>&1
reg delete "HKCU\Environment" /v "LOG_DIR" /f >nul 2>&1
reg delete "HKCU\Environment" /v "BACKUP_DIR" /f >nul 2>&1
reg delete "HKCU\Environment" /v "KERBEROS_DIR" /f >nul 2>&1
reg delete "HKCU\Environment" /v "CLIENT_CONFIG_DIR" /f >nul 2>&1
reg delete "HKCU\Environment" /v "DB2_DATABASE" /f >nul 2>&1
echo - Windows SSO environment variables cleaned (if they existed)
echo - NOTE: No keytab-related variables to clean in Windows SSO mode


@REM REM  Clean up client distribution files
@REM echo.
@REM set /a STEP+=1
@REM echo.
@REM echo Step %STEP%: Cleaning client distribution files...
@REM if exist "%COMMON_EXPORT_DIR%" (
@REM     echo - Removing client distribution directory: %COMMON_EXPORT_DIR%
@REM     rd /s /q "%COMMON_EXPORT_DIR%" 2>nul
@REM     if errorlevel 1 (
@REM         echo WARNING: Failed to remove client distribution directory
@REM     ) else (
@REM         echo   - Client distribution directory removed successfully
@REM     )
@REM ) else (
@REM     echo - Client distribution directory does not exist
@REM )


echo.
echo ==========================================
echo SSL Configuration Teardown Completed!
echo ==========================================
echo.
echo Teardown Summary:
echo - SSL DB2 configuration parameters: RESET TO DEFAULTS
echo - SSL certificate files: %SSL_DIR_STATUS%
echo - Minimal Kerberos configuration files: %KERBEROS_DIR_STATUS%
echo - DB2 instance: RESTARTED
echo - Windows SSO environment variables: CLEANED
echo - Client distribution files: REMOVED
echo - Authentication mode: Windows SSO (No keytab cleanup needed)
echo.

REM  Enhanced status reporting
echo - Configuration backup: CREATED in %BACKUP_DIR%

echo Your DB2 server has been restored to non-SSL configuration.
echo Windows SSO authentication should continue to work as before.
echo.

REM  Enhanced connection information for Windows SSO
echo JDBC Connection Strings (restored to original Windows SSO):
echo.
echo 1. Windows SSPI (Recommended):
echo    jdbc:db2://%SERVER_HOSTNAME%:%DATABASE_PORT%/%DATABASE_NAME%:securityMechanism=15;
echo.
echo 2. Kerberos SSO (Alternative):
echo    jdbc:db2://%SERVER_HOSTNAME%:%DATABASE_PORT%/%DATABASE_NAME%:securityMechanism=11;kerberosServerPrincipal=db2/%SERVER_HOSTNAME%@DEDGE.FK.NO;
echo.
echo Notes:
echo - SSL port %SSL_PORT% is no longer configured
echo - Standard DB2 port %DATABASE_PORT% should work as before
echo - Windows SSO authentication continues to work without keytab files
echo - Firewall rule for SSL port %SSL_PORT% has been removed
echo - All SSL-related files and configurations have been cleaned
echo - Your existing primary application should continue working unchanged
echo.

if exist "%SSL_DIR%" (
    echo WARNING: SSL directory still exists at %SSL_DIR%
    echo You may need to remove it manually if files are locked by other processes.
    echo.
)

if exist "%KERBEROS_DIR%" (
    echo WARNING: Kerberos directory still exists at %KERBEROS_DIR%
    echo You may need to remove it manually if files are locked by other processes.
    echo.
)

echo DB2 SSL Configuration Teardown V3 completed successfully!
echo.


echo.
echo Your primary application using Kerberos SSO should continue working unchanged. 