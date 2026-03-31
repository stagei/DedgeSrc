@echo off
REM ========================================================================================================
REM Example: Manual Generation of Client Certificate Handling Scripts
REM ========================================================================================================
REM This script demonstrates how to manually call Generate-ClientCertificateHandlingScripts.ps1
REM to create install/uninstall scripts for different client types.
REM ========================================================================================================

echo Example: Manual Client Script Generation
echo.

REM Set your parameters
set SERVER_HOSTNAME=p-no1db-vm02.DEDGE.fk.no
set CERT_FILE=C:\DB2\ssl\certificates\db2-server-cert.cer
set KRB5_INI_PATH=C:\DB2\kerberos\krb5.ini
set SSL_PORT=50001
set DATABASE_NAME=FKMVFT
set DATABASE_PORT=50000
set OUTPUT_DIR=C:\temp\ClientConfig

REM Create output directories
echo Creating output directories...
mkdir "%OUTPUT_DIR%\Jdbc" 2>nul
mkdir "%OUTPUT_DIR%\Dbeaver" 2>nul
mkdir "%OUTPUT_DIR%\OleDb" 2>nul

echo.
echo ========================================================================================================
echo Generating Java/JDBC Scripts
echo ========================================================================================================

REM Generate Java/JDBC install script
echo Generating Java certificate import script...
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "%OUTPUT_DIR%\Jdbc\install-java-ssl-certificate.bat" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertFile "%CERT_FILE%" ^
  -Action "add" ^
  -Target "java" ^
  -Krb5IniPath "%KRB5_INI_PATH%" ^
  -SslPort "%SSL_PORT%" ^
  -DatabaseName "%DATABASE_NAME%" ^
  -DatabasePort "%DATABASE_PORT%"

REM Generate Java/JDBC remove script
echo Generating Java certificate removal script...
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "%OUTPUT_DIR%\Jdbc\remove-java-ssl-certificate.bat" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertFile "%CERT_FILE%" ^
  -Action "remove" ^
  -Target "java"

echo.
echo ========================================================================================================
echo Generating DBeaver Scripts
echo ========================================================================================================

REM Generate DBeaver install script
echo Generating DBeaver certificate import script...
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "%OUTPUT_DIR%\Dbeaver\install-dbeaver-ssl-certificate.bat" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertFile "%CERT_FILE%" ^
  -Action "add" ^
  -Target "dbeaver" ^
  -Krb5IniPath "%KRB5_INI_PATH%" ^
  -SslPort "%SSL_PORT%" ^
  -DatabaseName "%DATABASE_NAME%" ^
  -DatabasePort "%DATABASE_PORT%"

REM Generate DBeaver remove script
echo Generating DBeaver certificate removal script...
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "%OUTPUT_DIR%\Dbeaver\remove-dbeaver-ssl-certificate.bat" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertFile "%CERT_FILE%" ^
  -Action "remove" ^
  -Target "dbeaver"

echo.
echo ========================================================================================================
echo Generating OLE DB Scripts
echo ========================================================================================================

REM Generate OLE DB install script
echo Generating OLE DB certificate import script...
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "%OUTPUT_DIR%\OleDb\install-oledb-ssl-certificate.bat" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertFile "%CERT_FILE%" ^
  -Action "add" ^
  -Target "oledb" ^
  -Krb5IniPath "%KRB5_INI_PATH%" ^
  -SslPort "%SSL_PORT%" ^
  -DatabaseName "%DATABASE_NAME%" ^
  -DatabasePort "%DATABASE_PORT%"

REM Generate OLE DB remove script
echo Generating OLE DB certificate removal script...
pwsh.exe -ExecutionPolicy Bypass -File "Generate-ClientCertificateHandlingScripts.ps1" ^
  -OutputFileName "%OUTPUT_DIR%\OleDb\remove-oledb-ssl-certificate.bat" ^
  -ServerHostname "%SERVER_HOSTNAME%" ^
  -CertFile "%CERT_FILE%" ^
  -Action "remove" ^
  -Target "oledb"

echo.
echo ========================================================================================================
echo Script Generation Completed!
echo ========================================================================================================
echo.
echo Generated scripts in: %OUTPUT_DIR%
echo.
echo Java/JDBC Scripts:
echo - %OUTPUT_DIR%\Jdbc\install-java-ssl-certificate.bat
echo - %OUTPUT_DIR%\Jdbc\remove-java-ssl-certificate.bat
echo.
echo DBeaver Scripts:
echo - %OUTPUT_DIR%\Dbeaver\install-dbeaver-ssl-certificate.bat
echo - %OUTPUT_DIR%\Dbeaver\remove-dbeaver-ssl-certificate.bat
echo.
echo OLE DB Scripts:
echo - %OUTPUT_DIR%\OleDb\install-oledb-ssl-certificate.bat
echo - %OUTPUT_DIR%\OleDb\remove-oledb-ssl-certificate.bat
echo.
echo USAGE EXAMPLES:
echo.
echo 1. For Java/JDBC applications:
echo    "%OUTPUT_DIR%\Jdbc\install-java-ssl-certificate.bat"
echo.
echo 2. For DBeaver:
echo    "%OUTPUT_DIR%\Dbeaver\install-dbeaver-ssl-certificate.bat"
echo.
echo 3. For OLE DB applications:
echo    "%OUTPUT_DIR%\OleDb\install-oledb-ssl-certificate.bat"
echo.
echo Each script includes:
echo - SSL certificate import to appropriate truststore
echo - Kerberos configuration (krb5.ini) setup
echo - Detailed connection string examples
echo - Client-specific configuration instructions
echo.

REM Open the output directory
echo Opening output directory...
explorer "%OUTPUT_DIR%"

echo.
echo NEXT STEPS:
echo 1. Review the generated scripts in %OUTPUT_DIR%
echo 2. Run the appropriate install script for your client type
echo 3. Follow the configuration instructions in the script output
echo 4. Test your connection
echo.
pause 