@echo off
REM ========================================================================================================
REM Example usage of Generate-ClientCertificateHandlingScripts.ps1
REM ========================================================================================================

echo This script demonstrates how to call the PowerShell certificate script generator
echo.

REM Set common variables
set "SCRIPT_PATH=%~dp0Generate-ClientCertificateHandlingScripts.ps1"
set "SERVER_HOSTNAME=db2server.example.com"
set "CERT_FILE=C:\certs\db2server.crt"
set "CLIENT_CONFIG_DIR=C:\config\dbeaver"

echo Available options:
echo 1. Generate Java certificate import script
echo 2. Generate Java certificate removal script  
echo 3. Generate DBeaver certificate import script
echo 4. Generate DBeaver certificate removal script
echo 5. Exit
echo.

set /p choice="Enter your choice (1-5): "

if "%choice%"=="1" goto java_add
if "%choice%"=="2" goto java_remove
if "%choice%"=="3" goto dbeaver_add
if "%choice%"=="4" goto dbeaver_remove
if "%choice%"=="5" goto end
echo Invalid choice. Please try again.
goto end

:java_add
echo Generating Java certificate import script...
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" ^
    -outputFileName "import-ssl-cert-to-java.bat" ^
    -clientConfigDirDbeaver "%CLIENT_CONFIG_DIR%" ^
    -serverHostname "%SERVER_HOSTNAME%" ^
    -certFile "%CERT_FILE%" ^
    -action "add" ^
    -target "java"
echo Generated: import-ssl-cert-to-java.bat
goto end

:java_remove
echo Generating Java certificate removal script...
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" ^
    -outputFileName "remove-ssl-cert-from-java.bat" ^
    -clientConfigDirDbeaver "%CLIENT_CONFIG_DIR%" ^
    -serverHostname "%SERVER_HOSTNAME%" ^
    -certFile "%CERT_FILE%" ^
    -action "remove" ^
    -target "java"
echo Generated: remove-ssl-cert-from-java.bat
goto end

:dbeaver_add
echo Generating DBeaver certificate import script...
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" ^
    -outputFileName "import-ssl-cert-to-dbeaver.bat" ^
    -clientConfigDirDbeaver "%CLIENT_CONFIG_DIR%" ^
    -serverHostname "%SERVER_HOSTNAME%" ^
    -certFile "%CERT_FILE%" ^
    -action "add" ^
    -target "dbeaver"
echo Generated: import-ssl-cert-to-dbeaver.bat
goto end

:dbeaver_remove
echo Generating DBeaver certificate removal script...
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" ^
    -outputFileName "remove-ssl-cert-from-dbeaver.bat" ^
    -clientConfigDirDbeaver "%CLIENT_CONFIG_DIR%" ^
    -serverHostname "%SERVER_HOSTNAME%" ^
    -certFile "%CERT_FILE%" ^
    -action "remove" ^
    -target "dbeaver"
echo Generated: remove-ssl-cert-from-dbeaver.bat
goto end

:end
echo.
echo Done!
pause 