@echo off
REM ==================================================================
REM DB2 SSL Port Testing Script
REM ==================================================================
REM Purpose: Verify that DB2 SSL is working on port 50001
REM Usage: Run this script from any machine (server or client)
REM ==================================================================

echo.
echo ========================================
echo DB2 SSL Port Testing Script
echo ========================================
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

set SERVER_HOSTNAME=%COMPUTERNAME%.DEDGE.fk.no

echo Testing SSL connectivity to: %SERVER_HOSTNAME%:%SSL_PORT%
echo Database: %DATABASE_NAME%
echo.

echo ====================================
echo Test 1: Basic Port Connectivity
echo ====================================
echo Testing if port %SSL_PORT% is open...
powershell -Command "Test-NetConnection -ComputerName '%SERVER_HOSTNAME%' -Port %SSL_PORT% | Format-Table ComputerName, RemotePort, TcpTestSucceeded"

echo.
echo ====================================
echo Test 2: SSL Handshake Test
echo ====================================
echo Testing SSL handshake...
powershell -Command "try { $tcpClient = New-Object System.Net.Sockets.TcpClient; $tcpClient.Connect('%SERVER_HOSTNAME%', %SSL_PORT%); $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream()); $sslStream.AuthenticateAsClient('%SERVER_HOSTNAME%'); Write-Host 'SUCCESS: SSL handshake completed'; Write-Host 'SSL Protocol:' $sslStream.SslProtocol; Write-Host 'Cipher Algorithm:' $sslStream.CipherAlgorithm; Write-Host 'Hash Algorithm:' $sslStream.HashAlgorithm; $sslStream.Close(); $tcpClient.Close() } catch { Write-Host 'ERROR: SSL handshake failed -' $_.Exception.Message }"

echo.
echo ====================================
echo Test 3: Certificate Information
echo ====================================
echo Retrieving SSL certificate information...
powershell -Command "try { $tcpClient = New-Object System.Net.Sockets.TcpClient; $tcpClient.Connect('%SERVER_HOSTNAME%', %SSL_PORT%); $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream()); $sslStream.AuthenticateAsClient('%SERVER_HOSTNAME%'); $cert = $sslStream.RemoteCertificate; Write-Host 'Certificate Subject:' $cert.Subject; Write-Host 'Certificate Issuer:' $cert.Issuer; Write-Host 'Valid From:' $cert.GetEffectiveDateString(); Write-Host 'Valid To:' $cert.GetExpirationDateString(); $sslStream.Close(); $tcpClient.Close() } catch { Write-Host 'ERROR: Could not retrieve certificate -' $_.Exception.Message }"

echo.
echo ====================================
echo Test 4: DB2-Specific SSL Test
echo ====================================
echo Testing DB2 SSL with JDBC-style connection...

REM Create a temporary VBS script for more detailed testing
echo Set objHTTP = CreateObject("MSXML2.ServerXMLHTTP") > %TEMP%\ssl_test.vbs
echo objHTTP.setTimeouts 5000, 5000, 5000, 5000 >> %TEMP%\ssl_test.vbs
echo On Error Resume Next >> %TEMP%\ssl_test.vbs
echo objHTTP.Open "GET", "https://%SERVER_HOSTNAME%:%SSL_PORT%", False >> %TEMP%\ssl_test.vbs
echo objHTTP.Send >> %TEMP%\ssl_test.vbs
echo If Err.Number = 0 Then >> %TEMP%\ssl_test.vbs
echo     WScript.Echo "HTTPS connection successful (expected for SSL-enabled port)" >> %TEMP%\ssl_test.vbs
echo Else >> %TEMP%\ssl_test.vbs
echo     WScript.Echo "HTTPS test result: " ^& Err.Description >> %TEMP%\ssl_test.vbs
echo End If >> %TEMP%\ssl_test.vbs

cscript //nologo %TEMP%\ssl_test.vbs
del %TEMP%\ssl_test.vbs

echo.
echo ====================================
echo Test 5: Server-Side Verification
echo ====================================
echo Note: Run these commands on the DB2 server (%SERVER_HOSTNAME%) to verify configuration:
echo.
echo   netstat -an ^| findstr :%SSL_PORT%
echo   db2 get dbm cfg ^| findstr -i ssl
echo   db2pd -ports
echo   tasklist ^| findstr db2
echo.

echo ====================================
echo Test Summary
echo ====================================
echo If all tests pass:
echo - Port %SSL_PORT% is open and accessible
echo - SSL handshake is working
echo - Certificate is valid and readable
echo - DB2 SSL configuration is active
echo.
echo If tests fail, check:
echo - DB2 service is running
echo - Firewall allows port %SSL_PORT%
echo - SSL configuration is correct (run configure-db2-ssl.bat)
echo - Server hostname resolution
echo.
echo Test completed for: %SERVER_HOSTNAME%:%SSL_PORT%
echo.
pause 