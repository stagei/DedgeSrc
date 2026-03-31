param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFileName,

    [Parameter(Mandatory = $true)]
    [string]$ServerHostname,

    [Parameter(Mandatory = $true)]
    [string]$CertFile,

    [Parameter(Mandatory = $true)]
    [ValidateSet("add", "remove")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [ValidateSet("java", "dbeaver", "oledb")]
    [string]$Target,

    [Parameter(Mandatory = $false)]
    [string]$Krb5IniPath = "",

    [Parameter(Mandatory = $false)]
    [string]$SslPort = "50050",

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "FKMVFT",

    [Parameter(Mandatory = $false)]
    [string]$DatabasePort = "50000",

    [Parameter(Mandatory = $false)]
    [string]$ClientConfigDir = ""
)

function Generate-JavaInstallScript {
    param($OutputFile, $ServerHostname, $CertFile, $Krb5IniPath, $SslPort, $DatabaseName, $DatabasePort, $ClientConfigDir)

    $content = @"
@echo off
REM ========================================================================================================
REM Install SSL Certificate for $ServerHostname into System Java Truststore
REM Generated: $(Get-Date)
REM ========================================================================================================
echo Installing DB2 SSL certificate into system Java truststore...
echo NOTE: This setup uses Windows SSO - no keytab required
echo.

REM Import SSL certificate
echo Importing SSL certificate for $ServerHostname...
pwsh.exe -ExecutionPolicy Bypass -File "$manageCertScript" -ServerHostname "$ServerHostname" -CertificateFile "$CertFile" -Action "add" -Target "java"
if errorlevel 1 (
    echo ERROR: Failed to import certificate
    pause
    exit /b 1
)

REM Copy Kerberos configuration (optional for JDBC)

echo - Attempting to copy krb5.ini from server share...
if exist "$ClientConfigDir\krb5.ini" (
    copy "$ClientConfigDir\krb5.ini" "C:\Windows\krb5.ini" /y >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Failed to copy krb5.ini from server share
    ) else (
        echo - Kerberos configuration copied from server share to C:\Windows\krb5.ini
    )
) else (
    echo - No Kerberos configuration file found at server share or local path, skipping krb5.ini setup
)

echo.
echo ========================================================================================================
echo Java SSL Certificate Installation Completed!
echo ========================================================================================================
echo.
echo RECOMMENDED JDBC Connection URLs for Windows SSO:
echo.
echo 1. SSL + Windows SSPI (RECOMMENDED - No krb5.ini needed):
echo    jdbc:db2://$ServerHostname`:$SslPort/$DatabaseName`:securityMechanism=15;sslConnection=true;
echo.
echo 2. SSL + Kerberos SSO (Alternative):
echo    jdbc:db2://$ServerHostname`:$SslPort/$DatabaseName`:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/$ServerHostname@DEDGE.FK.NO;
echo.
echo 3. Non-SSL Windows SSPI (Fallback):
echo    jdbc:db2://$ServerHostname`:$DatabasePort/$DatabaseName`:securityMechanism=15;
echo.
echo 4. Non-SSL Kerberos SSO (Fallback):
echo    jdbc:db2://$ServerHostname`:$DatabasePort/$DatabaseName`:securityMechanism=11;kerberosServerPrincipal=db2/$ServerHostname@DEDGE.FK.NO;
echo.
echo IMPORTANT NOTES:
echo - Option 1 (securityMechanism=15) uses Windows SSPI - simplest setup
echo - Option 2 (securityMechanism=11) uses Kerberos - may need krb5.ini
echo - No username/password required - uses your Windows login
echo - SSL certificate has been imported for SSL connections
echo - Requires IBM DB2 JDBC Driver in classpath
echo.
echo Please restart Java applications to use the new certificate.
pause
"@

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

function Generate-JavaRemoveScript {
    param($OutputFile, $ServerHostname)

    $content = @"
@echo off
REM ========================================================================================================
REM Remove SSL Certificate for $ServerHostname from System Java Truststore
REM Generated: $(Get-Date)
REM ========================================================================================================
echo Removing DB2 SSL certificate from system Java truststore...
echo NOTE: This will remove SSL certificate and Kerberos configuration
echo.

REM Remove SSL certificate
echo Removing SSL certificate for $ServerHostname...
pwsh.exe -ExecutionPolicy Bypass -File "$manageCertScript" -ServerHostname "$ServerHostname" -Action "remove" -Target "java"
if errorlevel 1 (
    echo WARNING: Failed to remove certificate (may not exist)
)

REM Remove Kerberos configuration
if exist "C:\Windows\krb5.ini" (
    echo Removing Kerberos configuration...
    del "C:\Windows\krb5.ini" /q >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Failed to remove krb5.ini from Windows directory
    ) else (
        echo - Kerberos configuration removed from C:\Windows\krb5.ini
    )
) else (
    echo - No Kerberos configuration found at C:\Windows\krb5.ini
)

echo.
echo ========================================================================================================
echo Java SSL Certificate Removal Completed!
echo ========================================================================================================
echo.
echo SSL certificate and Kerberos configuration have been removed.
echo Please restart Java applications to apply changes.
pause
"@

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

function Generate-DbeaverInstallScript {
    param($OutputFile, $ServerHostname, $CertFile, $Krb5IniPath, $SslPort, $DatabaseName, $DatabasePort)

    $content = @"
@echo off
REM ========================================================================================================
REM Install SSL Certificate for $ServerHostname into DBeaver JRE Truststore
REM Generated: $(Get-Date)
REM ========================================================================================================
echo Installing DB2 SSL certificate into DBeaver JRE truststore...
echo NOTE: This setup uses Windows SSO - no keytab required
echo.

REM Import SSL certificate
echo Importing SSL certificate for $ServerHostname into DBeaver JRE...
pwsh.exe -ExecutionPolicy Bypass -File "$manageCertScript" -ServerHostname "$ServerHostname" -CertificateFile "$CertFile" -Action "add" -Target "dbeaver"
if errorlevel 1 (
    echo ERROR: Failed to import certificate
    pause
    exit /b 1
)

REM Copy Kerberos configuration (optional for JDBC)
echo - Attempting to copy krb5.ini from server share...
if exist "$ClientConfigDir\krb5.ini" (
    copy "$ClientConfigDir\krb5.ini" "C:\Windows\krb5.ini" /y >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Failed to copy krb5.ini from server share
    ) else (
        echo - Kerberos configuration copied from server share to C:\Windows\krb5.ini
    )
) else (
    echo - No Kerberos configuration file found at server share or local path, skipping krb5.ini setup
)

echo.
echo ========================================================================================================
echo DBeaver SSL Certificate Installation Completed!
echo ========================================================================================================
echo.
echo RECOMMENDED DBeaver Connection Settings:
echo.
echo Connection Tab:
echo - Server Host: $ServerHostname
echo - Port: $SslPort (for SSL) or $DatabasePort (for non-SSL)
echo - Database: $DatabaseName
echo - Authentication: Leave Username and Password EMPTY
echo.
echo SSL Tab:
echo - Use SSL: Yes (for SSL connections)
echo - SSL Mode: Require
echo.
echo Driver Properties (Add these as custom properties):
echo.
echo Option 1 - Windows SSPI (RECOMMENDED):
echo - securityMechanism = 15
echo - sslConnection = true (for SSL)
echo.
echo Option 2 - Kerberos SSO (Alternative):
echo - securityMechanism = 11
echo - sslConnection = true (for SSL)
echo - kerberosServerPrincipal = db2srv/$ServerHostname@DEDGE.FK.NO
echo.
echo ========================================================================================================
echo Complete JDBC URLs for Kerberos SSO:
echo ========================================================================================================
echo.
echo 1. SSL + Windows SSPI (RECOMMENDED):
echo    jdbc:db2://$ServerHostname`:$SslPort/$DatabaseName`:securityMechanism=15;sslConnection=true;
echo.
echo 2. SSL + Kerberos SSO (Alternative):
echo    jdbc:db2://$ServerHostname`:$SslPort/$DatabaseName`:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2/$ServerHostname@DEDGE.FK.NO;
echo.
echo 3. Non-SSL Windows SSPI (Fallback):
echo    jdbc:db2://$ServerHostname`:$DatabasePort/$DatabaseName`:securityMechanism=15;
echo.
echo IMPORTANT NOTES:
echo - Leave Username and Password fields EMPTY in DBeaver
echo - Uses your Windows domain login automatically
echo - Restart DBeaver to apply certificate changes
echo - Test connection after restart
echo.
echo ========================================================================================================
echo Complete JDBC URLs for Kerberos without SSO:
echo ========================================================================================================
echo 1. SSL without SSO (Basic Authentication):
echo    jdbc:db2://$ServerHostname`:$SslPort/$DatabaseName`:sslConnection=true;
echo.
echo 2. Non-SSL without SSO (Basic Authentication):
echo    jdbc:db2://$ServerHostname`:$DatabasePort/$DatabaseName;

echo.
echo Please close and reopen DBeaver to use the new certificate.
pause
"@

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

function Generate-DbeaverRemoveScript {
    param($OutputFile, $ServerHostname)

    $content = @"
@echo off
REM ========================================================================================================
REM Remove SSL Certificate for $ServerHostname from DBeaver JRE Truststore
REM Generated: $(Get-Date)
REM ========================================================================================================
echo Removing DB2 SSL certificate from DBeaver JRE truststore...
echo NOTE: This will remove SSL certificate and Kerberos configuration
echo.

REM Remove SSL certificate
echo Removing SSL certificate for $ServerHostname from DBeaver JRE...
pwsh.exe -ExecutionPolicy Bypass -File "$manageCertScript" -ServerHostname "$ServerHostname" -Action "remove" -Target "dbeaver"
if errorlevel 1 (
    echo WARNING: Failed to remove certificate (may not exist)
)

REM Remove Kerberos configuration
if exist "C:\Windows\krb5.ini" (
    echo Removing Kerberos configuration...
    del "C:\Windows\krb5.ini" /q >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Failed to remove krb5.ini from Windows directory
    ) else (
        echo - Kerberos configuration removed from C:\Windows\krb5.ini
    )
) else (
    echo - No Kerberos configuration found at C:\Windows\krb5.ini
)

echo.
echo ========================================================================================================
echo DBeaver SSL Certificate Removal Completed!
echo ========================================================================================================
echo.
echo SSL certificate and Kerberos configuration have been removed.
echo Please restart DBeaver to apply changes.
pause
"@

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

function Generate-OleDbInstallScript {
    param($OutputFile, $ServerHostname, $CertFile, $Krb5IniPath, $SslPort, $DatabaseName, $DatabasePort)

    $content = @"
@echo off
REM ========================================================================================================
REM Install SSL Certificate for $ServerHostname into Windows Certificate Store
REM Generated: $(Get-Date)
REM ========================================================================================================
echo Installing DB2 SSL certificate into Windows certificate store...
echo NOTE: This setup uses Windows SSO - no username/password required
echo.

REM Import SSL certificate into Windows certificate store
echo Importing SSL certificate for $ServerHostname into Windows certificate store...
certutil -addstore "Root" "$CertFile"
if errorlevel 1 (
    echo WARNING: Failed to import into Root store, trying Personal store...
    certutil -addstore "My" "$CertFile"
    if errorlevel 1 (
        echo ERROR: Failed to import certificate into Windows certificate store
        pause
        exit /b 1
    ) else (
        echo - Certificate imported into Personal certificate store
    )
) else (
    echo - Certificate imported into Trusted Root certificate store
)

REM Copy Kerberos configuration (optional for OLE DB)
echo - Attempting to copy krb5.ini from server share...
if exist "$ClientConfigDir\krb5.ini" (
    copy "$ClientConfigDir\krb5.ini" "C:\Windows\krb5.ini" /y >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Failed to copy krb5.ini from server share
    ) else (
        echo - Kerberos configuration copied from server share to C:\Windows\krb5.ini
    )
) else (
    echo - No Kerberos configuration file found at server share or local path, skipping krb5.ini setup
)

echo.
echo ========================================================================================================
echo OLE DB SSL Certificate Installation Completed!
echo ========================================================================================================
echo.
echo RECOMMENDED OLE DB Connection Strings for Windows SSO:
echo.
echo 1. SSL + Windows SSPI (RECOMMENDED):
echo    Provider=IBMDADB2;Data Source=$DatabaseName;Hostname=$ServerHostname;Port=$SslPort;Protocol=TCPIP;Security=SSPI;SSL=True;
echo.
echo 2. SSL + Kerberos SSO (Alternative):
echo    Provider=IBMDADB2;Data Source=$DatabaseName;Hostname=$ServerHostname;Port=$SslPort;Protocol=TCPIP;Authentication=Kerberos;SSL=True;
echo.
echo 3. Non-SSL Windows SSPI (Fallback):
echo    Provider=IBMDADB2;Data Source=$DatabaseName;Hostname=$ServerHostname;Port=$DatabasePort;Protocol=TCPIP;Security=SSPI;
echo.
echo 4. Non-SSL Kerberos SSO (Fallback):
echo    Provider=IBMDADB2;Data Source=$DatabaseName;Hostname=$ServerHostname;Port=$DatabasePort;Protocol=TCPIP;Authentication=Kerberos;
echo.
echo IMPORTANT NOTES:
echo - Option 1 (Security=SSPI) uses Windows SSPI - simplest setup
echo - Option 2 (Authentication=Kerberos) uses Kerberos - may need krb5.ini
echo - No username/password required - uses your Windows login
echo - SSL certificate has been imported for SSL connections
echo - Requires IBM DB2 OLE DB Provider to be installed
echo.
echo Please restart applications to use the new certificate.
pause
"@

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

function Generate-OleDbRemoveScript {
    param($OutputFile, $ServerHostname, $CertFile)

    $content = @"
@echo off
REM ========================================================================================================
REM Remove SSL Certificate for $ServerHostname from Windows Certificate Store
REM Generated: $(Get-Date)
REM ========================================================================================================
echo Removing DB2 SSL certificate from Windows certificate store...
echo NOTE: This will remove SSL certificate and Kerberos configuration
echo.

REM Remove SSL certificate from Windows certificate store
echo Removing SSL certificate for $ServerHostname from Windows certificate store...

REM Try to remove from Root store first
certutil -delstore "Root" "$ServerHostname" >nul 2>&1
if errorlevel 1 (
    echo Trying to remove from Personal store...
    certutil -delstore "My" "$ServerHostname" >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Certificate not found in Windows certificate stores
        echo Attempting PowerShell removal...
        powershell -Command "Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { `$_.Subject -like '*$ServerHostname*' } | Remove-Item -Force" >nul 2>&1
        powershell -Command "Get-ChildItem -Path Cert:\CurrentUser\Root | Where-Object { `$_.Subject -like '*$ServerHostname*' } | Remove-Item -Force" >nul 2>&1
        echo - Attempted PowerShell certificate removal
    ) else (
        echo - Certificate removed from Personal certificate store
    )
) else (
    echo - Certificate removed from Trusted Root certificate store
)

REM Remove Kerberos configuration
if exist "C:\Windows\krb5.ini" (
    echo Removing Kerberos configuration...
    del "C:\Windows\krb5.ini" /q >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Failed to remove krb5.ini from Windows directory
    ) else (
        echo - Kerberos configuration removed from C:\Windows\krb5.ini
    )
) else (
    echo - No Kerberos configuration found at C:\Windows\krb5.ini
)

echo.
echo ========================================================================================================
echo OLE DB SSL Certificate Removal Completed!
echo ========================================================================================================
echo.
echo SSL certificate and Kerberos configuration have been removed.
echo Please restart applications to apply changes.
pause
"@

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

# Main execution

# Output all parameters received
Write-Host "Generate-ClientCertificateHandlingScripts Parameters received:"
Write-Host "===================="
Write-Host "OutputFileName: $OutputFileName"
Write-Host "ServerHostname: $ServerHostname"
Write-Host "CertFile: $CertFile"
Write-Host "Action: $Action"
Write-Host "Target: $Target"
Write-Host "Krb5IniPath: $Krb5IniPath"
Write-Host "SslPort: $SslPort"
Write-Host "DatabaseName: $DatabaseName"
Write-Host "DatabasePort: $DatabasePort"
Write-Host "ClientConfigDir: $ClientConfigDir"
Write-Host ""

# Determine script directory (where Manage-ClientCertificates.ps1 is located)
if ($Action -eq "add") {
    $manageCertScript = Join-Path $ClientConfigDir "Manage-ClientCertificates.ps1"
}

# Get the directory where the output file will be created
$outputDir = Split-Path -Parent $OutputFileName

try {
    Write-Host "Generating $Action script for $Target target..." -ForegroundColor Green

    # Ensure output directory exists
    if (!(Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    # Generate appropriate script based on target and action
    if ($Target -eq "java") {
        if ($Action -eq "add") {
            Generate-JavaInstallScript -OutputFile $OutputFileName -ServerHostname $ServerHostname -CertFile $CertFile -Krb5IniPath $Krb5IniPath -SslPort $SslPort -DatabaseName $DatabaseName -DatabasePort $DatabasePort -ClientConfigDir $ClientConfigDir
        } else {
            Generate-JavaRemoveScript -OutputFile $OutputFileName -ServerHostname $ServerHostname
        }
    }
    elseif ($Target -eq "dbeaver") {
        if ($Action -eq "add") {
            Generate-DbeaverInstallScript -OutputFile $OutputFileName -ServerHostname $ServerHostname -CertFile $CertFile -Krb5IniPath $Krb5IniPath -SslPort $SslPort -DatabaseName $DatabaseName -DatabasePort $DatabasePort
        } else {
            Generate-DbeaverRemoveScript -OutputFile $OutputFileName -ServerHostname $ServerHostname
        }
    }
    elseif ($Target -eq "oledb") {
        if ($Action -eq "add") {
            Generate-OleDbInstallScript -OutputFile $OutputFileName -ServerHostname $ServerHostname -CertFile $CertFile -Krb5IniPath $Krb5IniPath -SslPort $SslPort -DatabaseName $DatabaseName -DatabasePort $DatabasePort
        } else {
            Generate-OleDbRemoveScript -OutputFile $OutputFileName -ServerHostname $ServerHostname -CertFile $CertFile
        }
    }

    Write-Host "Script generated successfully: $OutputFileName" -ForegroundColor Green

    # Make the generated BAT file executable
    if (Test-Path $OutputFileName) {
        # No need to set executable on Windows, but we can verify it was created
        $fileInfo = Get-Item $OutputFileName
        Write-Host "File size: $($fileInfo.Length) bytes" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

