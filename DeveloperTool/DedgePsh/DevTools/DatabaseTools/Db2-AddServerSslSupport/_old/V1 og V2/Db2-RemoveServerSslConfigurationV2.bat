@echo off
REM ==================================================================
REM DB2 SSL Configuration Teardown Script - V2
REM ==================================================================
REM Purpose: Remove SSL configuration applied by configure-db2-ssl.bat with enhanced cleanup
REM Usage: Run this script in db2cmd.exe environment
REM Requirements: Must be run as DB2 instance owner with admin rights
REM Version: 2.0 - Enhanced with comprehensive cleanup and logging
REM ==================================================================

echo.
echo ========================================
echo DB2 SSL Configuration Teardown Script V2
echo ========================================
echo.
echo WARNING: This script will remove all SSL configuration from DB2
echo and delete SSL certificate files.
echo.

REM V2: Enhanced confirmation with backup option
set /p CONFIRM=Do you want to continue with SSL removal? (Y/N): 
if /i not "%CONFIRM%"=="Y" (
    echo Operation cancelled by user.
    pause
    exit /b 0
)

echo.
set /p BACKUP_CONFIRM=Do you want to create a backup before removal? (Y/N): 
if /i "%BACKUP_CONFIRM%"=="Y" (
    set CREATE_BACKUP=1
) else (
    set CREATE_BACKUP=0
)

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

REM Set variables (same as configure script)
set DB2_INSTALL_PATH=C:\DbInst
set SSL_DIR=C:\DB2\ssl
set SERVER_HOSTNAME=%COMPUTERNAME%.DEDGE.fk.no
set CERT_LABEL=DB2_SERVER_CERT
set GSKIT_PATH=C:\Program Files\ibm\gsk8\bin
REM V2: Enhanced directories
set LOG_DIR=C:\DB2\logs\ssl
set BACKUP_DIR=C:\DB2\backup\ssl
set KERBEROS_DIR=C:\DB2\kerberos
set COMMON_EXPORT_DIR=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\SSL\%COMPUTERNAME%

REM V2: Enhanced logging
set LOGFILE=%LOG_DIR%\ssl_removal_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
md "%LOG_DIR%" 2>nul
echo %DATE% %TIME% - Starting SSL Configuration Removal V2 > "%LOGFILE%"

echo Teardown Settings:
echo - DB2 Installation: %DB2_INSTALL_PATH%
echo - SSL Directory to remove: %SSL_DIR%
echo - Server Hostname: %SERVER_HOSTNAME%
echo - Kerberos Directory: %KERBEROS_DIR%
echo - Backup Directory: %BACKUP_DIR%
echo - Log File: %LOGFILE%
echo.

echo %DATE% %TIME% - Teardown initiated for %SERVER_HOSTNAME% >> "%LOGFILE%"

REM Check if DB2 installation exists
if not exist "%DB2_INSTALL_PATH%" (
    echo ERROR: DB2 installation not found at %DB2_INSTALL_PATH%
    echo Please verify the installation path and try again.
    echo %DATE% %TIME% - ERROR: DB2 installation not found >> "%LOGFILE%"
    pause
    exit /b 1
)

REM V2: Create backup if requested
if "%CREATE_BACKUP%"=="1" (
    echo.
    echo ====================================
    echo V2: Creating Backup Before Removal
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
    
    echo %DATE% %TIME% - Backup created in %BACKUP_DIR% >> "%LOGFILE%"
    echo Backup completed.
)

echo.
echo Step 1: Displaying current SSL configuration...
echo Current SSL settings before removal:
db2 get dbm cfg | findstr -i ssl
echo.

REM V2: Enhanced certificate removal with better error handling
echo Step 1.1: Removing existing certificate...
if exist "%GSKIT_PATH%\gsk8capicmd_64.exe" (
    if exist "%SSL_DIR%\server.kdb" (
        "%GSKIT_PATH%\gsk8capicmd_64.exe" -cert -delete -db "%SSL_DIR%\server.kdb" -pw "%SSL_PASSWORD%" -label "%CERT_LABEL%" >nul 2>&1
        echo - Certificate removed from keystore (if it existed)
        echo %DATE% %TIME% - Certificate removed from keystore >> "%LOGFILE%"
    ) else (
        echo - SSL keystore not found, skipping certificate removal
    )
) else (
    echo - GSKit tools not found, skipping certificate removal
)

echo.
echo Step 2: Removing DB2 SSL configuration parameters...

echo - Clearing SSL service name...
db2 update dbm cfg using ssl_svcename ""
if errorlevel 1 (
    db2 update dbm cfg using ssl_svcename NULL
    if errorlevel 1 (
        echo ERROR: Failed to clear SSL service name
        echo %DATE% %TIME% - ERROR: Failed to clear SSL service name >> "%LOGFILE%"
        exit /b 1
    )
)

echo - Clearing SSL keystore database path...
db2 update dbm cfg using ssl_svr_keydb ""
if errorlevel 1 (
    db2 update dbm cfg using ssl_svr_keydb NULL
    if errorlevel 1 (
        echo ERROR: Failed to clear SSL keystore database path
        echo %DATE% %TIME% - ERROR: Failed to clear SSL keystore database path >> "%LOGFILE%"
        exit /b 1
    )
)

echo - Clearing SSL keystore stash file path...
db2 update dbm cfg using ssl_svr_stash ""
if errorlevel 1 (
    db2 update dbm cfg using ssl_svr_stash NULL
    if errorlevel 1 (
        echo ERROR: Failed to clear SSL keystore stash file path
        echo %DATE% %TIME% - ERROR: Failed to clear SSL keystore stash file path >> "%LOGFILE%"
        exit /b 1
    )
)

echo - Clearing SSL certificate label...
db2 update dbm cfg using ssl_svr_label ""
if errorlevel 1 (
    db2 update dbm cfg using ssl_svr_label NULL
    if errorlevel 1 (
        echo ERROR: Failed to clear SSL certificate label
        echo %DATE% %TIME% - ERROR: Failed to clear SSL certificate label >> "%LOGFILE%"
        exit /b 1
    )
)

echo - Clearing SSL client keystore database...
db2 update dbm cfg using ssl_clnt_keydb ""
if errorlevel 1 (
    db2 update dbm cfg using ssl_clnt_keydb NULL
    if errorlevel 1 (
        echo ERROR: Failed to clear SSL client keystore database
        echo %DATE% %TIME% - ERROR: Failed to clear SSL client keystore database >> "%LOGFILE%"
        exit /b 1
    )
)

echo - Clearing SSL client stash file...
db2 update dbm cfg using ssl_clnt_stash ""
if errorlevel 1 (
    db2 update dbm cfg using ssl_clnt_stash NULL
    if errorlevel 1 (
        echo ERROR: Failed to clear SSL client stash file
        echo %DATE% %TIME% - ERROR: Failed to clear SSL client stash file >> "%LOGFILE%"
        exit /b 1
    )
)

REM V2: Clear enhanced SSL settings if they exist
echo - Clearing enhanced SSL cipher specifications...
db2 update dbm cfg using SSL_CIPHERSPECS ""
if errorlevel 1 (
    db2 update dbm cfg using SSL_CIPHERSPECS NULL >nul 2>&1
)

echo - Clearing SSL versions...
db2 update dbm cfg using SSL_VERSIONS ""
if errorlevel 1 (
    db2 update dbm cfg using SSL_VERSIONS NULL >nul 2>&1
)

echo.
echo Step 3: Verifying SSL configuration removal...
echo SSL settings after removal:
db2 get dbm cfg | findstr -i ssl
echo.

echo Step 4: Stopping DB2 instance to apply changes...
echo - Stopping DB2 instance...
db2stop
if errorlevel 1 (
    echo WARNING: Error stopping DB2 instance (may not be running)
    echo %DATE% %TIME% - WARNING: Error stopping DB2 instance >> "%LOGFILE%"
)

echo.
echo Step 5: Removing SSL certificate files and directory...

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
    rmdir /s /q "%SSL_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to remove SSL directory %SSL_DIR%
        echo You may need to remove it manually after stopping any processes using these files.
        echo %DATE% %TIME% - ERROR: Failed to remove SSL directory >> "%LOGFILE%"
        pause
    ) else (
        echo   - SSL directory removed successfully
        echo %DATE% %TIME% - SSL directory removed successfully >> "%LOGFILE%"
    )
) else (
    echo - SSL directory %SSL_DIR% does not exist (already removed or never created)
)

REM V2: Remove Kerberos configuration files
echo.
echo Step 5.1: V2 - Removing Kerberos configuration files...
if exist "%KERBEROS_DIR%" (
    echo - Removing Kerberos directory: %KERBEROS_DIR%
    rmdir /s /q "%KERBEROS_DIR%"
    if errorlevel 1 (
        echo WARNING: Failed to remove Kerberos directory
        echo %DATE% %TIME% - WARNING: Failed to remove Kerberos directory >> "%LOGFILE%"
    ) else (
        echo   - Kerberos directory removed successfully
        echo %DATE% %TIME% - Kerberos directory removed successfully >> "%LOGFILE%"
    )
) else (
    echo - Kerberos directory does not exist
)

REM V2: Clean up client distribution files
echo.
echo Step 5.2: V2 - Cleaning client distribution files...
if exist "%COMMON_EXPORT_DIR%" (
    echo - Removing client distribution directory: %COMMON_EXPORT_DIR%
    rd /s /q "%COMMON_EXPORT_DIR%" 2>nul
    if errorlevel 1 (
        echo WARNING: Failed to remove client distribution directory
        echo %DATE% %TIME% - WARNING: Failed to remove client distribution directory >> "%LOGFILE%"
    ) else (
        echo   - Client distribution directory removed successfully
        echo %DATE% %TIME% - Client distribution directory removed successfully >> "%LOGFILE%"
    )
) else (
    echo - Client distribution directory does not exist
)

echo.
echo Step 6: Starting DB2 instance...
echo - Starting DB2 instance...
db2start
if errorlevel 1 (
    echo ERROR: Failed to start DB2 instance
    echo You may need to start it manually using: db2start
    echo %DATE% %TIME% - ERROR: Failed to start DB2 instance >> "%LOGFILE%"
    pause
) else (
    echo - DB2 instance started successfully
    echo %DATE% %TIME% - DB2 instance started successfully >> "%LOGFILE%"
)

echo.
echo Step 7: Final verification...
echo Final SSL configuration (should show no SSL settings):
db2 get dbm cfg | findstr -i ssl
echo.

REM Check if SSL directory was successfully removed
if not exist "%SSL_DIR%" (
    set SSL_DIR_STATUS=REMOVED
) else (
    set SSL_DIR_STATUS=STILL EXISTS
)

REM V2: Check Kerberos directory status
if not exist "%KERBEROS_DIR%" (
    set KERBEROS_DIR_STATUS=REMOVED
) else (
    set KERBEROS_DIR_STATUS=STILL EXISTS
)

echo.
echo Step 8: Removing firewall rule...
powershell -Command "Get-NetFirewallRule | Where-Object { $_.LocalPort -eq '%SSL_PORT%' } | ForEach-Object { Write-Host ('Removing rule: ' + $_.DisplayName); Remove-NetFirewallRule -DisplayName $_.DisplayName }"

REM V2: Remove environment variables if they were set
echo.
echo Step 8.1: V2 - Cleaning environment variables...
reg delete "HKCU\Environment" /v "KRB5_CONFIG" /f >nul 2>&1
reg delete "HKCU\Environment" /v "DB2_SSL_SERVER" /f >nul 2>&1
reg delete "HKCU\Environment" /v "DB2_SSL_PORT" /f >nul 2>&1
reg delete "HKCU\Environment" /v "DB2_DATABASE" /f >nul 2>&1
echo - Environment variables cleaned (if they existed)

echo.
echo ==========================================
echo SSL Configuration Teardown Completed!
echo ==========================================
echo.
echo Teardown Summary:
echo - SSL DB2 configuration parameters: RESET TO DEFAULTS
echo - SSL certificate files: %SSL_DIR_STATUS%
echo - Kerberos configuration files: %KERBEROS_DIR_STATUS%
echo - DB2 instance: RESTARTED
echo - Environment variables: CLEANED
echo - Client distribution files: REMOVED
echo.

REM V2: Enhanced status reporting
if "%CREATE_BACKUP%"=="1" (
    echo - Configuration backup: CREATED in %BACKUP_DIR%
)

echo Your DB2 server has been restored to non-SSL configuration.
echo.

REM Original JDBC connection string (kept as REM for reference)
REM echo JDBC Connection String (back to original):
REM echo    jdbc:db2://%SERVER_HOSTNAME%:3701/BASISTST:securityMechanism=11;kerberosServerPrincipal=db2/%SERVER_HOSTNAME%@DEDGE.FK.NO;

REM V2: Enhanced connection information
echo JDBC Connection String (restored to original):
echo    jdbc:db2://%SERVER_HOSTNAME%:%DATABASE_PORT%/%DATABASE_NAME%:securityMechanism=11;kerberosServerPrincipal=db2/%SERVER_HOSTNAME%@DEDGE.FK.NO;
echo.
echo Notes:
echo - SSL port %SSL_PORT% is no longer configured
echo - Standard DB2 port %DATABASE_PORT% should work as before
echo - Kerberos authentication should work as originally configured
echo - Firewall rule for SSL port %SSL_PORT% has been removed
echo - All SSL-related files and configurations have been cleaned
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

REM V2: Final logging
echo %DATE% %TIME% - SSL Configuration Teardown completed successfully >> "%LOGFILE%"
echo %DATE% %TIME% - SSL_DIR_STATUS: %SSL_DIR_STATUS%, KERBEROS_DIR_STATUS: %KERBEROS_DIR_STATUS% >> "%LOGFILE%"

echo DB2 SSL Configuration Teardown V2 completed successfully!
echo.
echo Log file location: %LOGFILE%
if "%CREATE_BACKUP%"=="1" (
    echo Backup location: %BACKUP_DIR%
)
