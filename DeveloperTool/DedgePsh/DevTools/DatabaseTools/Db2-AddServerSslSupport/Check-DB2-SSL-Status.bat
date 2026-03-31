@echo off
REM ========================================================================================================
REM DB2 SSL Status Checker and Quick Fix Script
REM ========================================================================================================
echo DB2 SSL Status Checker and Quick Fix Script
echo ==========================================
echo.

REM Set variables for common SSL configurations
set SSL_PORT=50050
set DATABASE_PORT=50000

echo === DB2 SSL CONFIGURATION STATUS ===
echo.

echo 1. Checking DB2COMM registry variable...
db2set DB2COMM
echo.

echo 2. Checking SSL Configuration Parameters...
db2 get dbm cfg | findstr -i ssl
echo.

echo 3. Checking Network Port Listeners...
echo Checking if DB2 is listening on SSL port %SSL_PORT%:
netstat -an | findstr :%SSL_PORT%
echo.

echo Checking if DB2 is listening on standard port %DATABASE_PORT%:
netstat -an | findstr :%DATABASE_PORT%
echo.

echo 4. Testing SSL Port Connectivity...
echo Testing localhost SSL port connectivity:
powershell -Command "try { $result = Test-NetConnection -ComputerName localhost -Port %SSL_PORT% -WarningAction SilentlyContinue; if ($result.TcpTestSucceeded) { Write-Host 'SUCCESS: SSL port %SSL_PORT% is accessible' -ForegroundColor Green } else { Write-Host 'FAILED: SSL port %SSL_PORT% is NOT accessible' -ForegroundColor Red } } catch { Write-Host 'ERROR: Unable to test SSL port connectivity' -ForegroundColor Yellow }"
echo.

echo 5. Checking services file entry (if SSL_SVCENAME is set)...
for /f "tokens=2 delims==" %%i in ('db2 get dbm cfg ^| findstr SSL_SVCENAME') do (
    if not "%%i"==" " (
        echo SSL Service Name: %%i
        findstr /I /C:%%i %SystemRoot%\system32\drivers\etc\services
    )
)
echo.

echo === DIAGNOSIS SUMMARY ===
echo.

REM Check if SSL port is listening
netstat -an | findstr :%SSL_PORT% | findstr LISTENING >nul
if errorlevel 1 (
    echo [ERROR] SSL port %SSL_PORT% is NOT listening
    echo.
    echo === RECOMMENDED ACTIONS ===
    echo.
    echo ACTION 1: Force DB2 restart
    echo   db2 force applications all
    echo   db2stop force
    echo   timeout /t 10
    echo   db2start
    echo.
    echo ACTION 2: Check DB2COMM includes SSL
    echo   db2set DB2COMM=TCPIP,SSL
    echo   db2stop force
    echo   db2start
    echo.
    echo ACTION 3: Check for port conflicts
    echo   netstat -ano ^| findstr :%SSL_PORT%
    echo.
    echo Would you like to attempt automatic fix? (y/n)
    set /p AUTOFIX=
    if /i "%AUTOFIX%"=="y" goto :AUTOFIX
) else (
    echo [SUCCESS] SSL port %SSL_PORT% is listening correctly!
    powershell -Command "Write-Host 'SSL service appears to be working properly' -ForegroundColor Green"
)

echo.
echo Script completed. Check the troubleshooting guide for more details:
echo DB2-SSL-Troubleshooting-Guide.md
pause
exit /b 0

:AUTOFIX
echo.
echo === ATTEMPTING AUTOMATIC FIX ===
echo.

echo Step 1: Checking DB2COMM configuration...
db2set DB2COMM | findstr /I SSL >nul
if errorlevel 1 (
    echo Adding SSL to DB2COMM...
    for /f "tokens=*" %%i in ('db2set DB2COMM') do set CURRENT_DB2COMM=%%i
    if "%CURRENT_DB2COMM%"=="" (
        echo Setting DB2COMM to SSL only...
        db2set DB2COMM=SSL
    ) else (
        echo Adding SSL to existing DB2COMM...
        db2set DB2COMM=%CURRENT_DB2COMM%,SSL
    )
    echo New DB2COMM setting:
    db2set DB2COMM
) else (
    echo SSL already in DB2COMM configuration
)

echo.
echo Step 2: Forcing complete DB2 restart...
echo Forcing applications to disconnect...
db2 force applications all

echo Stopping DB2 instance...
db2stop force

echo Waiting 10 seconds for complete shutdown...
timeout /t 10

echo Starting DB2 instance...
db2start

echo.
echo Step 3: Verifying SSL port is now listening...
timeout /t 5
netstat -an | findstr :%SSL_PORT% | findstr LISTENING >nul
if errorlevel 1 (
    echo [FAILED] SSL port still not listening after restart
    echo Please check the troubleshooting guide for additional solutions
) else (
    echo [SUCCESS] SSL port %SSL_PORT% is now listening!
    powershell -Command "Write-Host 'SSL service fixed successfully!' -ForegroundColor Green"
)

echo.
echo Testing external connectivity...
powershell -Command "try { $result = Test-NetConnection -ComputerName localhost -Port %SSL_PORT% -WarningAction SilentlyContinue; if ($result.TcpTestSucceeded) { Write-Host 'SUCCESS: SSL port is accessible externally' -ForegroundColor Green } else { Write-Host 'WARNING: SSL port may not be accessible externally' -ForegroundColor Yellow } } catch { Write-Host 'ERROR: Cannot test external connectivity' -ForegroundColor Red }"

echo.
echo Fix attempt completed. If SSL is still not working, refer to:
echo DB2-SSL-Troubleshooting-Guide.md
pause
exit /b 0

