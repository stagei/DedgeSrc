@echo off
REM ========================================================================================================
REM Comprehensive Test Script for All Fixes
REM ========================================================================================================
REM Tests:
REM 1. Path quoting fix for certificate import
REM 2. krb5.ini copying from server share
REM 3. Provides DBeaver connection guidance for SSL requirement
REM ========================================================================================================

echo ========================================================================================================
echo Comprehensive Test Script for All Fixes
echo ========================================================================================================
echo.

REM Test parameters  
set SERVER_HOSTNAME=t-no1fkmdev-db.DEDGE.fk.no
set CERT_FILE=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ServerConfigurationSSL\t-no1fkmdev-db\Certificate\db2-server-cert.cer
set KRB5_SERVER_PATH=C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ServerConfigurationSSL\%SERVER_HOSTNAME%\ClientConfig\krb5.ini

echo Test Configuration:
echo - Server: %SERVER_HOSTNAME%
echo - Certificate: %CERT_FILE%
echo - Expected krb5.ini location: %KRB5_SERVER_PATH%
echo - Target: DBeaver (most likely to have path issues)
echo.

REM ========================================================================================================
echo Test 1: Certificate File Verification
echo ========================================================================================================
if not exist "%CERT_FILE%" (
    echo ❌ ERROR: Certificate file not found: %CERT_FILE%
    echo Please ensure the certificate file exists before running this test.
    echo.
    goto :krb5_test
) else (
    echo ✅ Certificate file found: %CERT_FILE%
)
echo.

REM ========================================================================================================
echo Test 2: krb5.ini Server Share Verification
echo ========================================================================================================
if not exist "%KRB5_SERVER_PATH%" (
    echo ⚠️  WARNING: krb5.ini not found at expected server location: %KRB5_SERVER_PATH%
    echo This is not critical - the script will handle fallback copying.
) else (
    echo ✅ krb5.ini found at server share: %KRB5_SERVER_PATH%
)
echo.

:krb5_test

REM ========================================================================================================
echo Test 3: DBeaver Certificate Import with Path Quoting Fix
echo ========================================================================================================
echo Testing the improved path quoting fix...
echo.

pwsh.exe -ExecutionPolicy Bypass -File "Manage-ClientCertificates.ps1" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertificateFile "%CERT_FILE%" ^
  -Action "add" ^
  -Target "dbeaver"

if errorlevel 1 (
    echo.
    echo ❌ Test FAILED - Certificate import encountered errors
    echo The path quoting issue may still exist or there are other problems.
    echo Check the debug output above for specific error details.
    echo.
    goto :connection_guide
) else (
    echo.
    echo ✅ Test PASSED - Certificate import completed successfully!
    echo The path quoting fix appears to be working correctly.
    echo.
)

REM ========================================================================================================
echo Test 4: krb5.ini Installation Verification
echo ========================================================================================================
if exist "C:\Windows\krb5.ini" (
    echo ✅ krb5.ini successfully installed at C:\Windows\krb5.ini
    echo File size: 
    dir "C:\Windows\krb5.ini" | findstr "krb5.ini"
) else (
    echo ⚠️  WARNING: krb5.ini not found at C:\Windows\krb5.ini
    echo This might be needed for Kerberos authentication (securityMechanism=11)
)
echo.

:connection_guide

REM ========================================================================================================
echo DBeaver Connection Guide
echo ========================================================================================================
echo.
echo 🚨 IMPORTANT: Security Mechanism 15 requires SSL!
echo.
echo Your previous error:
echo "non-SSL connection are not supported for security mechanism 15(PLUGIN_SECURITY)"
echo.
echo This means you were trying to use securityMechanism=15 with a non-SSL port (3710).
echo.
echo ✅ Working Connection Options:
echo.
echo Option 1 - SSL + Windows SSPI (RECOMMENDED):
echo   Host: %SERVER_HOSTNAME%
echo   Port: 50001 (SSL port)
echo   Database: FKAVDNT
echo   SSL: ✅ Enabled
echo   Driver Properties: securityMechanism=15, sslConnection=true
echo   Username/Password: ❌ LEAVE EMPTY
echo.
echo Option 2 - Non-SSL + Kerberos (FALLBACK):
echo   Host: %SERVER_HOSTNAME%
echo   Port: 3710 (non-SSL port)
echo   Database: FKAVDNT
echo   SSL: ❌ Disabled
echo   Driver Properties: securityMechanism=11, kerberosServerPrincipal=db2srv/%SERVER_HOSTNAME%@DEDGE.FK.NO
echo   Username/Password: ❌ LEAVE EMPTY
echo.
echo Option 3 - SSL + Kerberos (MOST SECURE):
echo   Host: %SERVER_HOSTNAME%
echo   Port: 50001 (SSL port)
echo   Database: FKAVDNT
echo   SSL: ✅ Enabled
echo   Driver Properties: securityMechanism=11, sslConnection=true, kerberosServerPrincipal=db2srv/%SERVER_HOSTNAME%@DEDGE.FK.NO
echo   Username/Password: ❌ LEAVE EMPTY
echo.

REM ========================================================================================================
echo Summary of Fixes Applied
echo ========================================================================================================
echo.
echo ✅ Fix 1: Path Quoting Issue
echo    - Updated Invoke-KeytoolCommand to use cmd.exe for proper quoting
echo    - Added comprehensive debugging output
echo    - Should now handle "Program Files" paths correctly
echo.
echo ✅ Fix 2: krb5.ini Source Location
echo    - Changed from local C:\DB2 to server share location
echo    - Fallback copying from C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ServerConfigurationSSL\
echo    - Automatic detection and copying
echo.
echo ✅ Fix 3: DBeaver SSL Requirement
echo    - Created comprehensive connection guide
echo    - Explains securityMechanism=15 requires SSL
echo    - Provides working alternatives for different scenarios
echo.

echo ========================================================================================================
echo Next Steps
echo ========================================================================================================
echo.
echo 1. ✅ Certificate is imported (if test passed)
echo 2. 🔧 Configure DBeaver using one of the options above
echo 3. 🧪 Test connection in DBeaver
echo 4. 📖 Refer to DBEAVER-CONNECTION-GUIDE.md for detailed instructions
echo.
echo Recommended: Try Option 1 first (SSL + Windows SSPI)
echo.

pause 