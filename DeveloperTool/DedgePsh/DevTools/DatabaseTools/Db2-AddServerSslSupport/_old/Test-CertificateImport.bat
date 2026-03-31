@echo off
REM ========================================================================================================
REM Test Certificate Import with Path Quoting Fix
REM ========================================================================================================
REM This script tests the fixed Manage-ClientCertificates.ps1 script
REM to ensure proper handling of paths with spaces
REM ========================================================================================================

echo Testing Certificate Import with Path Quoting Fix
echo.

REM Test parameters
set SERVER_HOSTNAME=t-no1fkmdev-db.DEDGE.fk.no
set CERT_FILE=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ServerConfigurationSSL\t-no1fkmdev-db\Certificate\db2-server-cert.cer

echo Test Configuration:
echo - Server: %SERVER_HOSTNAME%
echo - Certificate: %CERT_FILE%
echo - Target: DBeaver (most likely to have spaces in path)
echo.

REM Test if certificate file exists
if not exist "%CERT_FILE%" (
    echo ERROR: Certificate file not found: %CERT_FILE%
    echo Please ensure the certificate file exists before running this test.
    pause
    exit /b 1
)

echo Certificate file found: %CERT_FILE%
echo.

echo ========================================================================================================
echo Testing DBeaver Certificate Import (Target most likely to fail with spaces)
echo ========================================================================================================

pwsh.exe -ExecutionPolicy Bypass -File "Manage-ClientCertificates.ps1" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertificateFile "%CERT_FILE%" ^
  -Action "add" ^
  -Target "dbeaver"

if errorlevel 1 (
    echo.
    echo ========================================================================================================
    echo Test FAILED - Certificate import encountered errors
    echo ========================================================================================================
    echo.
    echo This indicates the path quoting issue may still exist.
    echo Check the debug output above for specific error details.
    pause
    exit /b 1
) else (
    echo.
    echo ========================================================================================================
    echo Test PASSED - Certificate import completed successfully!
    echo ========================================================================================================
    echo.
    echo The path quoting fix appears to be working correctly.
    echo DBeaver should now be able to connect using SSL with Windows SSO.
    echo.
    echo Recommended connection string:
    echo jdbc:db2://%SERVER_HOSTNAME%:50001/FKMVFT:securityMechanism=15;sslConnection=true;
    echo.
    echo Remember to:
    echo 1. Leave username/password empty in DBeaver
    echo 2. Configure SSL settings in DBeaver
    echo 3. Add securityMechanism=15 as a driver property
)

echo.
echo ========================================================================================================
echo Test Complete
echo ========================================================================================================
pause 