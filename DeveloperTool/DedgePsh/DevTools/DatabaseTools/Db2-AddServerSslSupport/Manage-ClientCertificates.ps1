param (
    [Parameter(Mandatory = $true)]
    [string]$ServerHostname,

    [Parameter(Mandatory = $false)]
    [string]$CertificateFile,

    [Parameter(Mandatory = $true)]
    [ValidateSet("add", "remove", "list")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [ValidateSet("java", "dbeaver")]
    [string]$Target,

    [Parameter(Mandatory = $false)]
    [string]$CustomJrePath,

    [Parameter(Mandatory = $false)]
    [string]$TruststorePassword = "changeit"
)

# Set console colors for better visibility
$Host.UI.RawUI.ForegroundColor = "White"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "========================================================================================================" "Cyan"
    Write-ColorOutput $Title "Yellow"
    Write-ColorOutput "========================================================================================================" "Cyan"
}

function Find-JavaEnvironment {
    param([string]$Target)

    $targetTitle = if ($Target -eq "java") { "Java" } else { "DBeaver" }
    $targetVariable = if ($Target -eq "java") { "JAVA_HOME" } else { "DBEAVER_JRE" }

    # Define paths based on target
    if ($Target -eq "dbeaver") {
        $primaryJrePath = "$env:ProgramFiles\DBeaver\jre"
        $secondaryJrePath = "$env:USERPROFILE\AppData\Local\DBeaver\jre"
    }
    else {
        $primaryJrePath = "$env:ProgramFiles\Java\jre"
        $secondaryJrePath = "$env:USERPROFILE\AppData\Local\Java\jre"
    }

    # Check if custom path is provided
    if ($CustomJrePath) {
        $targetJre = $CustomJrePath.Trim().Trim('"')
        Write-ColorOutput "Using custom JRE path: $targetJre" "Green"
    }
    # Check environment variable
    elseif (Get-Variable -Name $targetVariable -Scope Global -ErrorAction SilentlyContinue) {
        $targetJre = (Get-Variable -Name $targetVariable -Scope Global).Value.Trim().Trim('"')
        Write-ColorOutput "Using existing ${targetVariable}: $targetJre" "Green"
    }
    # Try primary path
    elseif (Test-Path "$primaryJrePath\bin\keytool.exe") {
        $targetJre = $primaryJrePath
        Write-ColorOutput "Found $targetTitle at default location: $targetJre" "Green"
    }
    # Try secondary path
    elseif (Test-Path "$secondaryJrePath\bin\keytool.exe") {
        $targetJre = $secondaryJrePath
        Write-ColorOutput "Found $targetTitle at user profile location: $targetJre" "Green"
    }
    # Manual input
    else {
        Write-ColorOutput "WARNING: $targetTitle JRE not found in standard locations" "Yellow"
        do {
            $targetJre = Read-Host "Enter path to $targetTitle JRE folder (or press Enter to exit)"
            if ([string]::IsNullOrWhiteSpace($targetJre)) {
                throw "No JRE path provided. Exiting."
            }
            $targetJre = $targetJre.Trim().Trim('"')
        } while (!(Test-Path "$targetJre\bin\keytool.exe"))
    }

    # Normalize path separators and ensure no trailing backslash
    $targetJre = $targetJre.TrimEnd('\')

    $keytoolPath = "$targetJre\bin\keytool.exe"
    $truststorePath = "$targetJre\lib\security\cacerts"

    # Validate paths
    if (!(Test-Path $keytoolPath)) {
        throw "ERROR: keytool.exe not found at $keytoolPath"
    }

    if (!(Test-Path $truststorePath)) {
        throw "ERROR: cacerts truststore not found at $truststorePath"
    }

    Write-ColorOutput "JRE Path: $targetJre" "Cyan"
    Write-ColorOutput "Keytool: $keytoolPath" "Cyan"
    Write-ColorOutput "Truststore: $truststorePath" "Cyan"

    return [PSCustomObject]@{
        JrePath        = $targetJre
        KeytoolPath    = $keytoolPath
        TruststorePath = $truststorePath
    }
}

function Invoke-KeytoolCommand {
    param(
        [string]$KeytoolPath,
        [string[]]$Arguments,
        [bool]$IgnoreError = $true
    )

    # Build the command line with proper quoting
    # If KeytoolPath contains spaces (\s), wrap it in quotes, otherwise leave it as-is
    $quotedKeytoolPath = if ($KeytoolPath -match '\s') { "`"$KeytoolPath`"" } else { $KeytoolPath }

    # Quote arguments that contain spaces but aren't already quoted
    $quotedArgs = @()
    foreach ($arg in $Arguments) {
        if ($arg -match '\s' -and -not ($arg.StartsWith('"') -and $arg.EndsWith('"'))) {
            $quotedArgs += "`"$arg`""
        }
        else {
            $quotedArgs += $arg
        }
    }

    # Build the complete command line
    $commandLine = "$quotedKeytoolPath " + ($quotedArgs -join " ")

    Write-ColorOutput "Debug - Keytool Path: $KeytoolPath" "DarkGray"
    Write-ColorOutput "Debug - Raw Arguments: $($Arguments -join ' ')" "DarkGray"
    Write-ColorOutput "Debug - Quoted Arguments: $($quotedArgs -join ' ')" "DarkGray"
    Write-ColorOutput "Debug - Full Command Line: $commandLine" "DarkGray"
    Write-ColorOutput "Executing keytool command..." "Cyan"

    try {
        # Use cmd.exe to properly handle the quoted command line

        $manualCommand = "cmd.exe /c $commandLine"

        Write-Host "Command Line: $manualCommand" -ForegroundColor White
        #$process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $commandLine -Wait -PassThru -NoNewWindow -RedirectStandardOutput "temp_output.txt" -RedirectStandardError "temp_error.txt"
        $process = Start-Process -FilePath $KeytoolPath -ArgumentList $($quotedArgs -join " ") -Wait -PassThru -NoNewWindow -RedirectStandardOutput "temp_output.txt" -RedirectStandardError "temp_error.txt"
    }
    catch {
        if (-not $IgnoreError) {
            Write-ColorOutput "ERROR: Failed to start keytool process: $($_.Exception.Message)" "Red"
            throw "Failed to execute keytool command"
        }
    }

    $output = ""
    $errorOutput = ""

    if (Test-Path "temp_output.txt") {
        $output = Get-Content "temp_output.txt" -Raw
        Remove-Item "temp_output.txt" -Force
    }

    if (Test-Path "temp_error.txt") {
        $errorOutput = Get-Content "temp_error.txt" -Raw
        Remove-Item "temp_error.txt" -Force
    }

    Write-ColorOutput "Debug - Exit Code: $($process.ExitCode)" "DarkGray"
    if ($errorOutput) {
        Write-ColorOutput "Debug - Error Output: $errorOutput" "DarkGray"
    }

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output   = $output
        Error    = $errorOutput
    }
}

function Add-Certificate {
    param(
        [PSCustomObject]$JavaEnv,
        [string]$ServerHostname,
        [string]$CertificateFile,
        [string]$TruststorePassword
    )

    Write-Header "Adding SSL Certificate for $ServerHostname"

    # Normalize certificate file path
    $CertificateFile = $CertificateFile.Trim().Trim('"')

    if (!(Test-Path $CertificateFile)) {
        throw "ERROR: Certificate file not found: $CertificateFile"
    }

    Write-ColorOutput "Certificate file: $CertificateFile" "Cyan"
    Write-ColorOutput "Server hostname: $ServerHostname" "Cyan"
    Write-ColorOutput "Truststore: $($JavaEnv.TruststorePath)" "Cyan"

    $removeArgs = @("-delete", "-alias", $ServerHostname, "-cacerts", "-storepass", $TruststorePassword)
    $removeResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $removeArgs

    $importArgs = @("-import", "-alias", $ServerHostname, "-file", $CertificateFile, "-cacerts", "-storepass", $TruststorePassword, "-noprompt", "-v")
    $importResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $importArgs

    $cacertsPathCacerts = ""
    try {
        if ($importResult.Error -match "Storing\s+(.+?)\]") {
            $cacertsPathCacerts = $matches[1].Trim()
        }
    }
    catch {}

    $removeArgs = @("-delete", "-alias", $ServerHostname, "-keystore", $JavaEnv.TruststorePath, "-storepass", $TruststorePassword)
    $removeResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $removeArgs

    $importArgs = @("-import", "-alias", $ServerHostname, "-file", $CertificateFile, "-keystore", $JavaEnv.TruststorePath, "-storepass", $TruststorePassword, "-noprompt", "-v")
    $importResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $importArgs
    $cacertsPathKeystore = ""
    try {
        if ($importResult.Error -match "Storing\s+(.+?)\]") {
            $cacertsPathKeystore = $matches[1].Trim()
        }
    }
    catch {}
    $cacertsPath = ""
    if ($cacertsPathCacerts -ne $cacertsPathKeystore -and $cacertsPathCacerts -ne "") {
        Write-ColorOutput "Cacerts path mismatch between cacerts update and keystore update. Both is up to date. Always use the cacerts path." "Yellow"
        Write-ColorOutput "Cacerts path: $cacertsPathCacerts" "Yellow"
        Write-ColorOutput "Keystore path: $cacertsPathKeystore" "Yellow"
        $cacertsPath = $cacertsPathCacerts

    }
    elseif ($cacertsPathCacerts -ne "") {
        Write-ColorOutput "Cacerts path is up to date." "Green"
        $cacertsPath = $cacertsPathCacerts
    }

    if ($cacertsPath -ne "") {
        $cacertsPath | Set-Clipboard
        $global:CacertsPath = $cacertsPath
        # Set machine environment variable for cacerts path
        [Environment]::SetEnvironmentVariable("FKA_DB2_CACERTS", $cacertsPath, [EnvironmentVariableTarget]::Machine)
        [Environment]::SetEnvironmentVariable("FKA_DB2_CACERTS", $cacertsPath, [EnvironmentVariableTarget]::User)
        Write-ColorOutput "Set FKA_DB2_CACERTS environment variable to: $cacertsPath" "Green"
    }
    else {
        Write-ColorOutput "No cacerts path found" "Yellow"
    }

    if ($importResult.ExitCode -eq 0) {
        Write-ColorOutput "Certificate imported successfully!" "Green"
        Write-ColorOutput "You can now use Windows SSO with SSL connections to $ServerHostname" "Green"
    }
    elseif ($($importResult.Output) -like "*already exists*") {
        Write-ColorOutput "Certificate already exists!" "Yellow"
        Write-ColorOutput "You can now use Windows SSO with SSL connections to $ServerHostname" "Green"
    }
    else {
        Write-ColorOutput "ERROR: Failed to import certificate" "Red"
        Write-ColorOutput "Error details: $($importResult.Error)" "Red"
        Write-ColorOutput "Command output: $($importResult.Output)" "Red"
        throw "Certificate import failed"
    }
}

function Remove-Certificate {
    param(
        [PSCustomObject]$JavaEnv,
        [string]$ServerHostname,
        [string]$TruststorePassword
    )

    Write-Header "Removing SSL Certificate for $ServerHostname"

    $removeArgs = @("-delete", "-alias", $ServerHostname, "-keystore", $JavaEnv.TruststorePath, "-storepass", $TruststorePassword)
    $removeResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $removeArgs

    if ($removeResult.ExitCode -eq 0) {
        Write-ColorOutput "Certificate removed successfully!" "Green"
    }
    else {
        Write-ColorOutput "WARNING: Certificate with alias $ServerHostname not found or could not be removed" "Yellow"
        Write-ColorOutput "Error details: $($removeResult.Error)" "Yellow"
    }
}

function List-Certificates {
    param(
        [PSCustomObject]$JavaEnv,
        [string]$TruststorePassword,
        [string]$ServerHostname
    )

    Write-Header "Listing Certificates in Truststore"

    $listArgs = @("-list", "-keystore", $JavaEnv.TruststorePath, "-storepass", $TruststorePassword, "-alias", $ServerHostname)
    $listResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $listArgs

    if ($listResult.ExitCode -eq 0) {
        Write-ColorOutput "Truststore contents:" "Green"
        Write-Host $listResult.Output
    }
    else {
        Write-ColorOutput "ERROR: Failed to list certificates" "Red"
        Write-ColorOutput "Error details: $($listResult.Error)" "Red"
    }
}

function Set-ParsedDate {
    param(
        [string]$DateString,
        [string]$VariableName
    )
    $result = $null
    try {
        if ($DateString -match '\w{3}\s+\w{3}\s+\d{2}\s+\d{2}:\d{2}:\d{2}\s+(CET|CEST)\s+\d{4}') {
            try {
                $result = [DateTime]::ParseExact($DateString, "ddd MMM dd HH:mm:ss 'CEST' yyyy", [System.Globalization.CultureInfo]::InvariantCulture).ToString("yyyy-MM-dd HH:mm:ss")
                return $result
            }
            catch {}
        }

        if ($DateString -match '\w{3}\s+\w{3}\s+\d{2}\s+\d{2}:\d{2}:\d{2}\s+CET\s+\d{4}') {
            try {
                $result = [DateTime]::ParseExact($DateString, "ddd MMM dd HH:mm:ss 'CET' yyyy", [System.Globalization.CultureInfo]::InvariantCulture).ToString("yyyy-MM-dd HH:mm:ss")
                continue
            }
            catch {}
        }
        if ($DateString -match '\w{3}\s+\w{3}\s+\d{2}\s+\d{2}:\d{2}:\d{2}\s+CET\s+\d{4}') {
            try {
                $result = [DateTime]::ParseExact($DateString, "ddd MMM dd HH:mm:ss 'CET' yyyy", [System.Globalization.CultureInfo]::InvariantCulture).ToString("yyyy-MM-dd HH:mm:ss")
                return $result
            }
            catch {}
        }
        if ($obj.ValidUntil -match '\w{3}\s+\w{3}\s+\d{2}\s+\d{2}:\d{2}:\d{2}\s+CEST\s+\d{4}') {
            try {
                $result = [DateTime]::ParseExact($DateString, "ddd MMM dd HH:mm:ss 'CEST' yyyy", [System.Globalization.CultureInfo]::InvariantCulture).ToString("yyyy-MM-dd HH:mm:ss")
                return $result
            }
            catch {}
        }
        if ($obj.ValidUntil -match '\w{3}\s+\w{3}\s+\d{2}\s+\d{2}:\d{2}:\d{2}\s+CET\s+\d{4}') {
            try {
                $result = [DateTime]::ParseExact($DateString, "ddd MMM dd HH:mm:ss 'CET' yyyy", [System.Globalization.CultureInfo]::InvariantCulture).ToString("yyyy-MM-dd HH:mm:ss")
                return $result
            }
            catch {}
        }
        throw "Could not parse $VariableName date: $DateString"
    }
    catch {
        Write-ColorOutput "Could not parse $VariableName date: $DateString" "Red"
        return $null
    }
}

function List-CertificatesAllDb2Servers {
    param(
        [PSCustomObject]$JavaEnv,
        [string]$TruststorePassword
    )

    Write-Header "Listing Certificates in Truststore"
    $pattern = "*-no1*-db*"
    $listArgs = @("-list", "-cacerts", "-storepass", $TruststorePassword, "-v")
    $listResult = Invoke-KeytoolCommand -KeytoolPath $JavaEnv.KeytoolPath -Arguments $listArgs

    $outputRaw = $listResult.Output
    $pos = $outputRaw.IndexOf("Alias name:")
    $outputRaw = $outputRaw.Substring($pos) + "`nAlias name: EOF"
    $outputArray = $outputRaw -split "Alias name: "

    $result = @()
    $dbResult = @()
    foreach ($element in $outputArray) {
        $completeElement = $element
        Write-ColorOutput $completeElement "Cyan"

        $obj = [PSCustomObject]@{
            Alias              = ""
            IsDb2Server        = $false
            CreationDate       = ""
            EntryType          = ""
            Owner              = ""
            Issuer             = ""
            SerialNumber       = ""
            ValidFrom          = ""
            ValidUntil         = ""
            ValidFromDateTime  = ""
            ValidUntilDateTime = ""
            SHA1Fingerprint    = ""
            SHA256Fingerprint  = ""
            SignatureAlgorithm = ""
            PublicKeyAlgorithm = ""
            Version            = ""
            Extensions         = ""
            Content            = ""
        }
        foreach ($line in $completeElement -split "`n") {
            if ([string]::IsNullOrEmpty($line)) {
                continue
            }
            if ($obj.Alias -eq "") {
                $obj.Alias = $line.Replace("`r ", " ")
                $obj.Content = "Alias name: " + $line
                continue
            }
            elseif ($obj.CreationDate -eq "" -and $line -like "Creation date:*") {
                $obj.CreationDate = $line.Substring($line.IndexOf(":") + 1).Trim().Replace("`r ", " ")
            }
            elseif ($obj.EntryType -eq "" -and $line -like "Entry type:*") {
                $obj.EntryType = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.Owner -eq "" -and $line -like "Owner:*") {
                $obj.Owner = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.Issuer -eq "" -and $line -like "Issuer:*") {
                $obj.Issuer = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.SerialNumber -eq "" -and $line -like "Serial number:*") {
                $obj.SerialNumber = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.ValidFrom -eq "" -and $line -like "Valid from:*") {
                $obj.ValidFrom = $line.Substring($line.IndexOf(":") + 1).Trim().Split("until:")[0].Trim()
                $obj.ValidUntil = $line.Substring($line.IndexOf(":") + 1).Trim().Split("until:")[1].Trim()

                $obj.ValidFromDateTime = Set-ParsedDate -DateString $obj.ValidFrom -VariableName "ValidFrom"
                $obj.ValidUntilDateTime = Set-ParsedDate -DateString $obj.ValidUntil -VariableName "ValidUntil"

            }
            elseif ($obj.SHA1Fingerprint -eq "" -and $line -like "SHA1:*") {
                $obj.SHA1Fingerprint = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.SHA256Fingerprint -eq "" -and $line -like "SHA256:*") {
                $obj.SHA256Fingerprint = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.SignatureAlgorithm -eq "" -and $line -like "Signature algorithm name:*") {
                $obj.SignatureAlgorithm = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.PublicKeyAlgorithm -eq "" -and $line -like "Subject Public Key Algorithm:*") {
                $obj.PublicKeyAlgorithm = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.Version -eq "" -and $line -like "Version:*") {
                $obj.Version = $line.Substring($line.IndexOf(":") + 1).Trim()
            }
            elseif ($obj.Extensions -eq "" -and $line -like "Extensions:*") {
                $obj.Extensions = $($line.Substring($line.IndexOf(":") + 1).Trim() + " ")
            }
            $obj.Content += $line + "`n"
        }
        if ($obj.Alias -eq "EOF") {
            break
        }
        if ($obj.Alias -eq "") {
            continue
        }
        if ($obj.Alias -like "*$pattern*" -or $obj.Content -like "*$pattern*") {
            $obj.IsDb2Server = $true
            $objCopy = $obj.PSObject.Copy()
            # $objCopy.Extensions = ""
            # $objCopy.Content = ""
            #Write-Host ($objCopy | ConvertTo-Json)
            $dbResult += $obj
        }
        $obj.Extensions = $obj.Extensions.Trim()

        # Convert date strings to standard format
        $result += $obj
    }
    return [PSCustomObject]@{
        ExitCode = $listResult.ExitCode
        Output   = $listResult.Output
        Error    = $listResult.Error
        DbResult = $dbResult
    }
}

function Save-CertificateInstallInformation {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$JavaEnv,

        [Parameter(Mandatory = $true)]
        [string]$ServerHostname,

        [Parameter(Mandatory = $true)]
        [string]$TruststorePassword
    )

    $certInfo = List-CertificatesAllDb2Servers -JavaEnv $JavaEnv -TruststorePassword $TruststorePassword
    $result = @()
    foreach ($cert in $certInfo.DbResult) {
        $result += [PSCustomObject]@{
            Timestamp                     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ComputerName                  = $env:COMPUTERNAME
            DomainName                    = $env:USERDOMAIN
            UserName                      = $env:USERNAME
            JavaHome                      = $JavaEnv.JavaHome
            CertTruststorePath            = $JavaEnv.TruststorePath
            ServerHostname                = $ServerHostname
            CertificateAlias              = $cert.Alias
            CertificateCreationDate       = $cert.CreationDate
            CertificateEntryType          = $cert.EntryType
            CertificateOwner              = $cert.Owner
            CertificateIssuer             = $cert.Issuer
            CertificateSerialNumber       = $cert.SerialNumber
            CertificateValidFrom          = $cert.ValidFrom
            CertificateValidUntil         = $cert.ValidUntil
            CertificateValidFromDateTime  = $cert.ValidFromDateTime
            CertificateValidUntilDateTime = $cert.ValidUntilDateTime
            CertificateVersion            = $cert.Version
        }
    }

    # Create logs directory if it doesn't exist
    $logsDir = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Client\SslCertificateUsers"

    if (Test-Path $logsDir) {
        # Save to JSON file
        $logFile = Join-Path $logsDir "certificate_install_$($ServerHostname)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $installInfo | ConvertTo-Json -Depth 10 | Out-File $logFile

        Write-ColorOutput "Certificate installation information saved to: $logFile" "Green"
    }
    else {
        Write-ColorOutput "WARNING: Could not find Db2\Client\SslCertificateUsers at: $logsDir" "Yellow"
    }
}

# Main execution
try {
    $actionTitle = switch ($Action) {
        "add" { "Import" }
        "remove" { "Remove" }
        "list" { "List" }
    }

    $mainPath = Split-Path -Parent $CertificateFile
    $mainPath = Split-Path -Parent $mainPath
    $targetTitle = if ($Target -eq "java") { "Java" } else { "DBeaver" }

    Write-Header "$actionTitle SSL Certificate - $targetTitle JRE Truststore Management"
    Write-ColorOutput "NOTE: This setup uses Windows SSO - no keytab required" "Cyan"

    # Find Java environment
    $javaEnv = Find-JavaEnvironment -Target $Target

    # Execute action
    switch ($Action) {
        "add" {
            if ([string]::IsNullOrWhiteSpace($CertificateFile)) {
                throw "Certificate file path is required for add action. Use -CertificateFile parameter."
            }
            Add-Certificate -JavaEnv $javaEnv -ServerHostname $ServerHostname -CertificateFile $CertificateFile -TruststorePassword $TruststorePassword
        }
        "remove" {
            Remove-Certificate -JavaEnv $javaEnv -ServerHostname $ServerHostname -TruststorePassword $TruststorePassword
        }
        "list" {
            List-Certificates -JavaEnv $javaEnv -TruststorePassword $TruststorePassword -ServerHostname $ServerHostname
        }
    }
    List-Certificates -JavaEnv $javaEnv -TruststorePassword $TruststorePassword -ServerHostname $ServerHostname

    if ($Target -eq "dbeaver") {
        # Open DBeaver.ini in Notepad
        $dbeaverIniPath = Join-Path ($JavaEnv.TruststorePath.ToUpper().Split("\JRE")[0]) "dbeaver.ini"
        # Check for running DBeaver processes
        $dbeaverProcesses = Get-Process | Where-Object { $_.ProcessName -like "*dbeaver*" }
        if ($dbeaverProcesses) {
            Write-ColorOutput "`nWARNING: DBeaver processes are currently running" "Yellow"
            $confirmation = Read-Host "Would you like to kill all DBeaver processes before continuing? (y/n)"
            if ($confirmation -eq 'y') {
                Write-Host "Stopping DBeaver processes..."
                $dbeaverProcesses | ForEach-Object {
                    try {
                        $_ | Stop-Process -Force
                        Write-Host "Stopped process: $($_.ProcessName) (PID: $($_.Id))"
                    }
                    catch {
                        Write-ColorOutput "Failed to stop process $($_.ProcessName) (PID: $($_.Id))" "Red"
                    }
                }
            }
        }
        if (Test-Path $dbeaverIniPath -PathType Leaf) {
            if ($global:CacertsPath -and $global:CacertsPath -ne "") {
                Write-Host "`nOpening DBeaver configuration file: $dbeaverIniPath"
                $dbeaverIniContent = Get-Content $dbeaverIniPath
                $dbeaverIniContent | ForEach-Object {
                    if ($_ -like "*-Djavax.net.ssl.trustStore*") {
                        Write-ColorOutput "Found DBeaver.ini JVM parameter: $_" "Cyan"
                    }
                }
            }

            Write-ColorOutput "Modify the DBeaver.ini file to use the new cacerts path like this:" "Yellow"
            Write-ColorOutput "-Djavax.net.ssl.trustStore=`"$global:CacertsPath`"" "Yellow"

            Start-Process "notepad.exe" -ArgumentList $dbeaverIniPath
        }
        else {
            Write-ColorOutput "WARNING: Could not find DBeaver.ini at: $dbeaverIniPath" "Yellow"
        }
    }
    # Create shortcut to connection guide on user's desktop
    $guideSource = Join-Path $PSScriptRoot "clientConfig" "DBeaver-Java-FKAVDNT-Connection-Guide.md"
    $shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "DBeaver-Java-FKAVDNT-Connection-Guide.lnk"
    if (Test-Path $guideSource) {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $guideSource
        $shortcut.Save()
        Write-ColorOutput "Connection guide shortcut created on desktop: $shortcutPath" "Green"
    } else {
        Write-ColorOutput "Warning: Could not find connection guide at $guideSource" "Yellow"
    }
    try {
        Save-CertificateInstallInformation -JavaEnv $javaEnv -ServerHostname $ServerHostname -TruststorePassword $TruststorePassword
    }
    catch {
        Write-ColorOutput "`nERROR: $($_.Exception.Message)" "Yellow"
    }
    Write-ColorOutput "`nOperation completed successfully!" "Green"
}
catch {
    Write-ColorOutput "`nERROR: $($_.Exception.Message)" "Red"
    exit 1
}
finally {
    # Cleanup any temporary files
    @("temp_output.txt", "temp_error.txt") | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force }
    }
}

