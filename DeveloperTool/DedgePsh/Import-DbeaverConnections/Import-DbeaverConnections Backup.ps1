# Enable error logging
$ErrorActionPreference = "Continue"
$logFile = "dbeaver_setup.log"

function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

try {
    Write-Log "Starting DBeaver configuration..."

    # Create base directories first
    $baseDir = "$env:APPDATA\DBeaverData\workspace6"
    $dbeaverConfigPath = "$baseDir\.metadata\.plugins\org.jkiss.dbeaver.core"
    $preferencesPath = "$baseDir\.metadata\.plugins\org.eclipse.core.runtime\.settings"

    # Check if DBeaver is running and kill all related processes
    $dbeaverProcesses = Get-Process | Where-Object { $_.ProcessName -match "dbeaver|java" -and $_.MainWindowTitle -match "DBeaver" } -ErrorAction SilentlyContinue
    if ($dbeaverProcesses) {
        Write-Log "WARNING: Found running DBeaver processes. Attempting to close them..."
        $dbeaverProcesses | ForEach-Object {
            Write-Log "Stopping process: $($_.ProcessName) (PID: $($_.Id))"
            Stop-Process -Id $_.Id -Force
        }
        Start-Sleep -Seconds 3
    }

    # Clean up workspace lock files
    $lockFiles = @(
        "$baseDir\.metadata\.lock",
        "$baseDir\.metadata\.plugins\org.eclipse.e4.workbench\workbench.xmi.backup",
        "$baseDir\.metadata\.plugins\org.eclipse.core.resources\.snap"
    )

    foreach ($lockFile in $lockFiles) {
        if (Test-Path $lockFile) {
            Write-Log "Removing lock file: $lockFile"
            Remove-Item -Path $lockFile -Force
        }
    }

    # Additional cleanup of workspace metadata
    $metadataPath = "$baseDir\.metadata"
    if (Test-Path $metadataPath) {
        Write-Log "Cleaning workspace metadata..."
        Get-ChildItem -Path $metadataPath -Filter "*.log" -Recurse | Remove-Item -Force
        Get-ChildItem -Path $metadataPath -Filter "*.lock" -Recurse | Remove-Item -Force
    }

    # Create directories if they don't exist
    @($baseDir, $dbeaverConfigPath, $preferencesPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Force -Path $_ | Out-Null
            Write-Log "Created directory: $_"
        }
    }

    # Set registry settings
    $registryPath = "HKCU:\Software\DBeaverCommunity"
    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
        Write-Log "Created registry path: $registryPath"
    }
    Set-ItemProperty -Path $registryPath -Name "workspace" -Value $baseDir -Force
    Write-Log "Updated registry workspace path"

    # Create connection JSON
    $connectionConfig = @{
        folders = @{}
        connections = @{
            "db2-Dedge-prod" = @{
                provider = "db2"
                driver = "db2_jdbc"
                name = "BASISPRO"
                "save-password" = $true
                configuration = @{
                    host = "t-no1fkmtst-db.DEDGE.fk.no"
                    port = "3700"
                    database = "BASISPRO"
                    url = "jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3700/BASISPRO"
                    type = "prod"
                    "auth-model" = "native_auth"
                    "auth-properties" = @{
                        "user" = $env:USERNAME
                        "password" = ""
                    }
                    "driver-properties" = @{}
                    handlers = @{}
                }
            }
            # Add your other connections here...
        }
    }

    # Save connection configuration
    $connectionConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath "$dbeaverConfigPath\data-sources.json" -Encoding UTF8 -Force
    Write-Log "Created connection configuration file"

    # Create project file
    $projectContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DBeaver</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
    </buildSpec>
    <natures>
        <nature>org.jkiss.dbeaver.DBeaverNature</nature>
    </natures>
</projectDescription>
"@
    $projectContent | Out-File -FilePath "$dbeaverConfigPath\.project" -Encoding UTF8 -Force
    Write-Log "Created project file"

    # Create preferences file
    $preferencesContent = @"
eclipse.preferences.version=1
org.jkiss.dbeaver.core.confirm.exit=false
ui.auto.update.check.time=0
"@
    $preferencesContent | Out-File -FilePath "$preferencesPath\org.jkiss.dbeaver.core.prefs" -Encoding UTF8 -Force
    Write-Log "Created preferences file"

    # Monitor DBeaver log file
    $dbeaverLogPath = "$env:APPDATA\DBeaverData\workspace6\.metadata\.log"
    Write-Log "Configuration complete. Starting DBeaver..."

    # Find DBeaver executable
    $dbeaverPaths = @(
        "${env:USERPROFILE}\AppData\Local\DBeaver\dbeaver.exe",  # User-specific installation
        "${env:ProgramFiles}\DBeaver\dbeaver.exe",
        "${env:ProgramFiles(x86)}\DBeaver\dbeaver.exe",
        "${env:LocalAppData}\Programs\DBeaver\dbeaver.exe",
        "${env:ProgramFiles}\DBeaverCE\dbeaver.exe",
        "${env:ProgramFiles(x86)}\DBeaverCE\dbeaver.exe",
        "${env:LocalAppData}\Programs\DBeaverCE\dbeaver.exe"
    )

    $dbeaverExe = $dbeaverPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $dbeaverExe) {
        throw "DBeaver executable not found. Please ensure DBeaver is installed."
    }

    Write-Log "Found DBeaver executable at: $dbeaverExe"

    # Before starting DBeaver, ensure metadata directory exists
    if (-not (Test-Path "$baseDir\.metadata")) {
        New-Item -ItemType Directory -Force -Path "$baseDir\.metadata" | Out-Null
        Write-Log "Created .metadata directory"
    }

    # Create a custom import file in XML format
    $importXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<connections>
    <connection
        name="Dedge Utvikling"
        description="Dedge Utvikling"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3710"
        database="FKAVDNT"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3710/FKAVDNT"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>dev</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge Test"
        description="Dedge Test"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3701"
        database="BASISTST"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3701/BASISTST"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>test</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge Prod"
        description="Dedge Prod"
        host="p-no1fkmprd-db.DEDGE.fk.no"
        port="3700"
        database="BASISPRO"
        url="jdbc:db2://p-no1fkmprd-db.DEDGE.fk.no:3700/BASISPRO"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>prod</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge Rapportering"
        description="Dedge Rapportering"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3700"
        database="BASISRAP"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3700/BASISRAP"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>prod</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge Historikk"
        description="Dedge Historikk"
        host="p-no1fkmprd-db.DEDGE.fk.no"
        port="3700"
        database="BASISHST"
        url="jdbc:db2://p-no1fkmprd-db.DEDGE.fk.no:3700/BASISHST"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>prod</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Fkkonto Prod"
        description="Fkkonto Prod"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3705"
        database="FKKONTO"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3705/FKKONTO"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>prod</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge Migrering D365"
        description="Dedge Migrering D365"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3711"
        database="BASISMIG"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISMIG"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>prod</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge SIT D365"
        description="Dedge SIT D365"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3711"
        database="BASISSIT"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISSIT"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>test</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge Test D365"
        description="Dedge Test D365"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3711"
        database="BASISVFT"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISVFT"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>test</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge VFK D365"
        description="Dedge VFK D365"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3711"
        database="BASISVFK"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3711/BASISVFK"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>dev</type>
            <read-only>true</read-only>
        </general>
    />
    <connection
        name="Visual Cobol POC Development"
        description="Visual Cobol POC Development"
        host="t-no1fkmtst-db.DEDGE.fk.no"
        port="3715"
        database="DB2DEV"
        url="jdbc:db2://t-no1fkmtst-db.DEDGE.fk.no:3715/DB2DEV"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>dev</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge POC Test DB2 Version 11.5"
        description="Dedge POC Test DB2 Version 11.5"
        host="p-Dedge-vm02.DEDGE.fk.no"
        port="50000"
        database="FKMTST"
        url="jdbc:db2://dedge-server.DEDGE.fk.no:50000/FKMTST"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>dev</type>
            <read-only>false</read-only>
        </general>
    />
    <connection
        name="Dedge POC Production DB2 Version 11.5"
        description="Dedge POC Production DB2 Version 11.5"
        host="p-Dedge-vm01.DEDGE.fk.no"
        port="50000"
        database="FKMPRD"
        url="jdbc:db2://p-Dedge-vm01.DEDGE.fk.no:50000/FKMPRD"
        user="$env:USERDOMAIN\$env:USERNAME"
        <general>
            <type>prod</type>
            <read-only>false</read-only>
        </general>
    />
</connections>
"@

    # Ask user if they want to use database as connection name
    $userInput = Read-Host "Do you want to use database as connection name? (y/n)"
    if ($userInput.ToLower() -eq "y") {
        # For each connection in $importXml, replace name with database
        $importXml = $importXml -replace '(?s)(<connection[^>]*\bname=")[^"]*(".*?\bdatabase=")([^"]*)', '$1$3$2$3'
        Write-Log "Updated connection names to use database names"

    }

    # Ask user if they want to add password to connections
    $addPassword = Read-Host "Do you want to add password to connections? (y/n)"
    if ($addPassword.ToLower() -eq "y") {
        $password = (Read-Host "Enter password").Trim()
        # First replace any $env:USERNAME with actual username
        $importXml = $importXml -replace 'DEDGE\\\$env:USERNAME', "$env:USERDOMAIN\$env:USERNAME"
        # Then add password attribute to all DEDGE domain users (simpler pattern)
        $importXml = $importXml -replace 'user="$env:USERDOMAIN\\[^"]*"', "`$0 password=""$password"""
        Write-Log "Added password to connections"
    }

    # Current directory
    $currentDir = Get-Location
    $importPath = Join-Path $currentDir "dbeaver_import.xml"
    $importXml | Out-File -FilePath $importPath -Encoding UTF8 -Force
    Write-Log "Created import file at: $importPath"

    # Create import script
    # Get workspace path from registry or use default
    $workspacePath = (Get-ItemProperty -Path "HKCU:\Software\DBeaverCommunity" -Name "workspace" -ErrorAction SilentlyContinue).workspace
    if (-not $workspacePath) {
        $workspacePath = "$env:APPDATA\DBeaverData\workspace6"
    }
    Write-Log "Using workspace path: $workspacePath"

    # Create import script with workspace path
    $importScript = @"
@echo off
"$dbeaverExe" -nosplash -data "$workspacePath" -import "$importPath" -exit
"@
    $importScriptPath = Join-Path $currentDir "import_dbeaver.bat"
    $importScript | Out-File -FilePath $importScriptPath -Encoding ASCII -Force
    Write-Log "Created import script at: $importScriptPath"

    # Execute import script
    Write-Log "Starting DBeaver with import command..."
    Start-Process -FilePath $importScriptPath -Wait
    Remove-Item $importScriptPath -Force
    Remove-Item $importPath -Force
    Write-Log "Cleaned up temporary files"

    Write-Log "Import completed. Connections should now be available in DBeaver."

} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "ERROR: $errorMessage"
    Write-Log "Stack Trace: $($_.Exception.StackTrace)"
}

Write-Log "Script execution completed. Check $logFile for details."

