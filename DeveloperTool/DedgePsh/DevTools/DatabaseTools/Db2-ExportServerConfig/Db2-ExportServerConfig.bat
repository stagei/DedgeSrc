@echo off
REM ==================================================================
REM DB2 Server Configuration Export Script
REM ==================================================================
REM Purpose: Extract comprehensive DB2 server and database information
REM Usage: Run this script in db2cmd.exe environment with admin rights
REM Output: %OptPath%\data\Db2-ExportServerConfig\%Computername%.log
REM Requirements: Must be run as DB2 instance owner with admin rights
REM ==================================================================
REM Check if input parameter is provided
set OUTPUT_TO_FILE=%1%
if "%OUTPUT_TO_FILE%"=="" (
    set OUTPUT_TO_FILE=0
)

setlocal enabledelayedexpansion

REM Set variables
set SCRIPT_NAME=DB2 Server Configuration Export
set SCRIPT_VERSION=1.1

set DAY=%DATE:~0,2%
set MONTH=%DATE:~3,2%
set YEAR=%DATE:~6,4%

set HOUR=%TIME:~0,2%
set MINUTE=%TIME:~3,2%
set SECOND=%TIME:~6,2%

set TIMESTAMP=%YEAR%%MONTH%%DAY%%HOUR%%MINUTE%%SECOND%
set OUTPUT_DIR=%OptPath%\data\Db2-ExportServerConfig
set OUTPUT_FILE=%OUTPUT_DIR%\%COMPUTERNAME%_%TIMESTAMP%.log
set COMMON_OUTPUT_FOLDER=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\Db2-ExportServerConfig
set COMMON_OUTPUT_FILE=%COMMON_OUTPUT_FOLDER%\%COMPUTERNAME%_%TIMESTAMP%.log

echo.
echo ====================================
echo %SCRIPT_NAME%
echo Version: %SCRIPT_VERSION%
echo ====================================
echo.
echo Starting comprehensive DB2 server analysis...
echo Output will be saved to: %OUTPUT_FILE%
echo.

REM Create output directory if it doesn't exist
if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to create output directory: %OUTPUT_DIR%
        pause
        exit /b 1
    )
)

REM Initialize output file
echo ================================================================== > "%OUTPUT_FILE%"
echo %SCRIPT_NAME% >> "%OUTPUT_FILE%"
echo Version: %SCRIPT_VERSION% >> "%OUTPUT_FILE%"
echo Generated: %TIMESTAMP% >> "%OUTPUT_FILE%"
echo Computer: %COMPUTERNAME% >> "%OUTPUT_FILE%"
echo Service Account: %USERDOMAIN%\%USERNAME% >> "%OUTPUT_FILE%"
echo User: %USERNAME% >> "%OUTPUT_FILE%"
echo Common Output File: %COMMON_OUTPUT_FILE% >> "%OUTPUT_FILE%"
echo ================================================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo Gathering system information...
echo ================================================================== >> "%OUTPUT_FILE%"
echo SYSTEM INFORMATION >> "%OUTPUT_FILE%"
echo ================================================================== >> "%OUTPUT_FILE%"
systeminfo | findstr /C:"OS Name" /C:"OS Version" /C:"System Type" /C:"Total Physical Memory" /C:"Available Physical Memory" | more /E >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo Gathering regional, language, and format settings...
echo ================================================================== >> "%OUTPUT_FILE%"
echo REGIONAL, LANGUAGE, AND FORMAT SETTINGS >> "%OUTPUT_FILE%"
echo ================================================================== >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Windows System Locale Information >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
systeminfo | findstr /C:"System Locale" /C:"Input Locale" /C:"Time Zone" | more /E >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo Windows Regional Settings from Registry: >> "%OUTPUT_FILE%"
reg query "HKCU\Control Panel\International" /v sCountry >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sLanguage >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sShortDate >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sLongDate >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sTimeFormat >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sCurrency >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sDecimal >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v sThousand >> "%OUTPUT_FILE%" 2>&1
reg query "HKCU\Control Panel\International" /v iFirstDayOfWeek >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Language and Locale Environment Variables >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Current Language Environment Variables: >> "%OUTPUT_FILE%"
echo   LANG: %LANG% >> "%OUTPUT_FILE%"
echo   LC_ALL: %LC_ALL% >> "%OUTPUT_FILE%"
echo   LC_MESSAGES: %LC_MESSAGES% >> "%OUTPUT_FILE%"
echo   LC_CTYPE: %LC_CTYPE% >> "%OUTPUT_FILE%"
echo   LC_NUMERIC: %LC_NUMERIC% >> "%OUTPUT_FILE%"
echo   LC_TIME: %LC_TIME% >> "%OUTPUT_FILE%"
echo   LC_MONETARY: %LC_MONETARY% >> "%OUTPUT_FILE%"
echo   LC_COLLATE: %LC_COLLATE% >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo All Environment Variables with Language/Locale Keywords: >> "%OUTPUT_FILE%"
set | findstr /I "LANG\|LOCALE\|LC_\|NLS\|COUNTRY\|TERRITORY" | more /E >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 Language and Locale Configuration >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 Language/Locale Related Registry Variables (if any): >> "%OUTPUT_FILE%"
db2set -all 2>nul | findstr /I "LOCALE\|LANG\|TERRITORY\|CODEPAGE\|NLS" | more /E >> "%OUTPUT_FILE%" 2>&1
if errorlevel 1 (
    echo   No DB2 language/locale registry variables are currently set >> "%OUTPUT_FILE%"
)
echo. >> "%OUTPUT_FILE%"

echo All DB2 Registry Variables: >> "%OUTPUT_FILE%"
db2set -all | more /E >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Character Encoding and Code Page Information >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Active Code Page: >> "%OUTPUT_FILE%"
chcp >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo System Code Page Information: >> "%OUTPUT_FILE%"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v ACP >> "%OUTPUT_FILE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v OEMCP >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Date, Time, and Number Format Settings >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Current Date and Time Formats: >> "%OUTPUT_FILE%"
echo   Current Date: %DATE% >> "%OUTPUT_FILE%"
echo   Current Time: %TIME% >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo PowerShell Culture Information: >> "%OUTPUT_FILE%"
powershell -Command "Get-Culture | Select-Object Name, DisplayName, DateTimeFormat, NumberFormat | Format-List" >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo PowerShell UI Culture Information: >> "%OUTPUT_FILE%"
powershell -Command "Get-UICulture | Select-Object Name, DisplayName | Format-List" >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Database Locale and Character Set Information >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Note: Database-specific locale information will be collected per database >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo Gathering DB2 version and installation information...
echo ================================================================== >> "%OUTPUT_FILE%"
echo DB2 VERSION AND INSTALLATION INFORMATION >> "%OUTPUT_FILE%"
echo ================================================================== >> "%OUTPUT_FILE%"
db2level >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 Installation Registry Information >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 Installation Path: >> "%OUTPUT_FILE%"
db2set DB2PATH >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"
echo DB2 Instance Information: >> "%OUTPUT_FILE%"
db2set DB2INSTANCE >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"
echo DB2 Copy Name: >> "%OUTPUT_FILE%"
reg query "HKLM\SOFTWARE\IBM\DB2\Copies" /s 2>nul | findstr /i "Name\|InstalledLocation" >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering DB2 instance information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 INSTANCE INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Current Instance: >> "%OUTPUT_FILE%"
db2 get instance >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Instance List: >> "%OUTPUT_FILE%"
db2ilist >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering database manager configuration...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DATABASE MANAGER CONFIGURATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
db2 get dbm cfg >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering SSL configuration...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo SSL CONFIGURATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo SSL Settings from DBM Config: >> "%OUTPUT_FILE%"
db2 get dbm cfg | findstr -i ssl >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering database list...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DATABASE LIST >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
db2 list db directory >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DATABASE CATALOG INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Node Directory: >> "%OUTPUT_FILE%"
db2 list node directory >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo DCS Directory: >> "%OUTPUT_FILE%"
db2 list dcs directory >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering database-specific configurations...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DATABASE-SPECIFIC CONFIGURATIONS >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"

REM Get list of databases and process each one
for /f "tokens=*" %%i in ('db2 list db directory ^| findstr "Database alias"') do (
    set DB_LINE=%%i
    for /f "tokens=4" %%j in ("!DB_LINE!") do (
        set DB_NAME=%%j
        echo. >> "%OUTPUT_FILE%"
        echo ========================================== >> "%OUTPUT_FILE%"
        echo DATABASE: !DB_NAME! >> "%OUTPUT_FILE%"
        echo ========================================== >> "%OUTPUT_FILE%"

        echo Connecting to database !DB_NAME!...
        echo Database Connection Status: >> "%OUTPUT_FILE%"
        db2 connect to !DB_NAME! >> "%OUTPUT_FILE%" 2>&1

        if not errorlevel 1 (
            echo. >> "%OUTPUT_FILE%"
            echo Database Configuration for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 get db cfg for !DB_NAME! >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Tablespace Information for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 list tablespaces >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Table List for !DB_NAME! ^(first 50^): >> "%OUTPUT_FILE%"
            db2 "select tabschema, tabname, type from syscat.tables fetch first 50 rows only" >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Active Applications for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 list applications >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Database Size Information for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 "call get_dbsize_info(?, ?, ?, 0)" >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Database Locale and Character Set Information for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 "select * from sysibmadm.dbcfg where name in ('territory', 'codepage', 'collate_info')" >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Current Database Locale Settings for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 "VALUES CURRENT LOCALE LC_MESSAGES" >> "%OUTPUT_FILE%" 2>&1
            db2 "VALUES CURRENT LOCALE LC_CTYPE" >> "%OUTPUT_FILE%" 2>&1
            db2 "VALUES CURRENT LOCALE LC_TIME" >> "%OUTPUT_FILE%" 2>&1
            db2 "VALUES CURRENT LOCALE LC_NUMERIC" >> "%OUTPUT_FILE%" 2>&1
            db2 "VALUES CURRENT LOCALE LC_MONETARY" >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Database Territory and Code Page for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 get db cfg for !DB_NAME! | findstr /I "territory\|codepage\|collate" >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Last Backup Information for !DB_NAME!: >> "%OUTPUT_FILE%"
            db2 "select backup_id, backup_timestamp, backup_type from sysibmadm.db_history where operation='B' order by backup_timestamp desc fetch first 10 rows only" >> "%OUTPUT_FILE%" 2>&1
            echo. >> "%OUTPUT_FILE%"

            echo Disconnecting from !DB_NAME!...
            db2 disconnect >> "%OUTPUT_FILE%" 2>&1
        ) else (
            echo Failed to connect to database !DB_NAME! >> "%OUTPUT_FILE%"
        )
        echo. >> "%OUTPUT_FILE%"
    )
)

echo Gathering memory and performance information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo MEMORY AND PERFORMANCE INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 Memory Configuration from DBM Config: >> "%OUTPUT_FILE%"
db2 get dbm cfg | findstr -i "heap\|memory\|pool" >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Database Memory Usage from snapshots: >> "%OUTPUT_FILE%"
db2 get snapshot for dbm | findstr -i "memory\|heap" >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 PROCESS AND CONNECTION INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Current Database Connections: >> "%OUTPUT_FILE%"
db2 list applications >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering network and port information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo NETWORK AND PORT INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Service Names: >> "%OUTPUT_FILE%"
db2 get dbm cfg | findstr -i svcename >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Network Listening Ports: >> "%OUTPUT_FILE%"
netstat -an | findstr :50000 >> "%OUTPUT_FILE%" 2>&1
netstat -an | findstr :50001 >> "%OUTPUT_FILE%" 2>&1
netstat -an | findstr :3700 >> "%OUTPUT_FILE%" 2>&1
netstat -an | findstr :3701 >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering security and authentication information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo SECURITY AND AUTHENTICATION INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Authentication Configuration: >> "%OUTPUT_FILE%"
db2 get dbm cfg | findstr -i authentication >> "%OUTPUT_FILE%" 2>&1
db2 get dbm cfg | findstr -i kerberos >> "%OUTPUT_FILE%" 2>&1
db2 get dbm cfg | findstr -i gssplugin >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering log and diagnostic information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo LOG AND DIAGNOSTIC INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo Diagnostic Log Path: >> "%OUTPUT_FILE%"
db2 get dbm cfg | findstr -i diagpath >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Instance Log Information ^(Recent entries^): >> "%OUTPUT_FILE%"
db2diag -A >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering registry variables...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 REGISTRY VARIABLES >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
db2set -all >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering license information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 LICENSE INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
db2licm -l >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Gathering fixpack and patch information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo FIXPACK AND PATCH INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2 Installation Details: >> "%OUTPUT_FILE%"
echo DB2 Level Information: >> "%OUTPUT_FILE%"
db2level -v >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"
echo DB2 Product Installation: >> "%OUTPUT_FILE%"
if exist "%DB2PATH%\bin\db2ls.exe" (
    db2ls >> "%OUTPUT_FILE%" 2>&1
) else (
    echo DB2 Installation Information from Registry: >> "%OUTPUT_FILE%"
    reg query "HKLM\SOFTWARE\IBM\DB2" /s 2>nul | findstr -i "Version\|Edition\|Level" >> "%OUTPUT_FILE%" 2>&1
)
echo. >> "%OUTPUT_FILE%"

echo Gathering environment variables...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo ENVIRONMENT VARIABLES >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2-related environment variables: >> "%OUTPUT_FILE%"
set | findstr /I DB2 >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo PATH variable: >> "%OUTPUT_FILE%"
echo %PATH% >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

echo Gathering Windows service information...
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo WINDOWS SERVICE INFORMATION >> "%OUTPUT_FILE%"
echo ------------------------------------------------------------------ >> "%OUTPUT_FILE%"
echo DB2-related Windows Services: >> "%OUTPUT_FILE%"
sc query | findstr /I DB2 >> "%OUTPUT_FILE%" 2>&1
echo. >> "%OUTPUT_FILE%"

echo Finalizing report...
echo ================================================================== >> "%OUTPUT_FILE%"
echo REPORT COMPLETION >> "%OUTPUT_FILE%"
echo ================================================================== >> "%OUTPUT_FILE%"
echo Report generation completed: %DATE% %TIME% >> "%OUTPUT_FILE%"
echo Comprehensive DB2 server analysis has been completed.
echo.
echo Report saved to: %OUTPUT_FILE%
echo.
echo Report contains:
echo - System information
echo - DB2 version and installation details
echo - Instance and database manager configuration
echo - SSL configuration
echo - Database-specific configurations
echo - Memory and performance information
echo - Network and security settings
echo - Log and diagnostic information
echo - Registry variables and environment
echo - License and patch information
echo - Windows service status
echo.
echo You can now analyze the report file for:
echo - Configuration issues
echo - Performance problems
echo - Security settings
echo - Version compatibility
echo - Database health status
echo.
md %COMMON_OUTPUT_FOLDER% 2>nul
copy /Y %OUTPUT_FILE% %COMMON_OUTPUT_FILE%
if %OUTPUT_TO_FILE% equ 1 (
    start code %OUTPUT_FILE%
)

