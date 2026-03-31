# Enable error logging
$ErrorActionPreference = "Continue"
$logFile = ".\dbeaver_setup.log"

function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Add-Content -Path $logFile -Value $logMessage
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Status = "DONE",
        [bool]$Log = $true
    )
    $checkMark = [char]0x221A
    $bullet = $checkMark

    if ($Status -eq "DONE") {
        Write-Host "  $checkMark $Message" -ForegroundColor White
    }
    elseif ($Status -eq "WAIT") {
        Write-Host "  $bullet $Message" -ForegroundColor White
    }
    elseif ($Status -eq "ERROR") {
        Write-Host "$Message" -ForegroundColor Red
    }

    if ($Log) {
        Write-Log $Message
    }
}

function Show-Menu {
    param (
        [string]$Title = 'DBeaver Configuration'
    )
    $checkMark = [char]0x221A

    Clear-Host
    Write-Host "================ $Title ================" -ForegroundColor White
    Write-Host
    Write-Host "Current Settings:" -ForegroundColor White
    Write-Host "  $checkMark Found DBeaver: " -NoNewline
    Write-Host "$dbeaverExe" -ForegroundColor White
    Write-Host "  $checkMark Found Workspace: " -NoNewline
    Write-Host "$workspacePath" -ForegroundColor White
    Write-Host
    Write-Host "Configuration Steps:" -ForegroundColor White
    Write-Host
}

function Get-UserChoice {
    param (
        [string]$prompt,
        [string]$default = "n"
    )
    Write-Host $prompt -ForegroundColor White -NoNewline
    $choice = Read-Host
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $default }
    return $choice.ToLower()
}

function Get-SecureInput {
    param (
        [string]$prompt
    )
    Write-Host $prompt -ForegroundColor White -NoNewline
    $secureString = Read-Host -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    return $password.Trim()
}

function Convert-DatabaseInfoToXml {
    $fkDatabasesJson = Get-DatabasesV2Json

    # Ask user about naming preference
    # $useHistoricNamesChar = Get-UserChoice -prompt "Use historic database names? (y/N): " -default "n"
    $useHistoricNamesChar = "y"
    $useHistoricNames = $(if ($useHistoricNamesChar.ToLower() -ne "n") { $true } else { $false })
    if ($useHistoricNames) {
        Write-Host "Using historic database names" -ForegroundColor Green
    }
    else {
        Write-Host "Using new database names" -ForegroundColor Green
    }
    $xmlBuilder = [System.Text.StringBuilder]::new()
    [void]$xmlBuilder.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$xmlBuilder.AppendLine('<connections>')

    foreach ($db in $databases) {
        # Skip if not a database object (some entries might be strings or other types)
        if (-not ($db.PSObject.Properties.Match('Database'))) {
            continue
        }

        $namePrefix = if ($db.ConnectionInfo.Version -eq "1.0") { "Digiplex" } else { "Azure" }
        if ($useHistoricNames -eq 'y') {
            if ($db.ConnectionInfo.Version -ne "1.0" -and $db.ConnectionInfo.Aliases.Count -gt 0) {
                $connectionName = "$namePrefix - $($db.ConnectionInfo.Aliases[0])"
            }
            else {
                $connectionName = "$namePrefix - $($db.ConnectionInfo.Database)"
            }
        }
        else {
            $connectionName = "$namePrefix - $($db.ConnectionInfo.Application)$($db.ConnectionInfo.Environment)"
        }
        if ($db.ConnectionInfo.Version -ne "1.0") {
            $db.ConnectionInfo.Port = 50010
            $db.ConnectionInfo.Database = "X" + $db.ConnectionInfo.Database
        }
        if ($db.ConnectionInfo.Version -ne "1.0") {
            [void]$xmlBuilder.AppendLine(@"
    <connection
        name="$connectionName"
        description="$($db.NorwegianDescription)"
        host="$($db.ConnectionInfo.Server)"
        port="$($db.ConnectionInfo.Port)"
        database="$($db.ConnectionInfo.Database)"
        url="jdbc:db2://$($db.ConnectionInfo.Server):$($db.ConnectionInfo.Port)/$($db.ConnectionInfo.Database)"
        user="$env:USERDOMAIN\db2nt"
          password="ntdb2"
        />
"@)
        }
    }
    else {
        [void]$xmlBuilder.AppendLine(@"
        <connection
            name="$connectionName"
            description="$($db.NorwegianDescription)"
            host="$($db.ConnectionInfo.Server)"
            port="$($db.ConnectionInfo.Port)"
            database="$($db.ConnectionInfo.Database)"
            url="jdbc:db2://$($db.ConnectionInfo.Server):$($db.ConnectionInfo.Port)/$($db.ConnectionInfo.Database)"
            user="$env:USERDOMAIN\%$env:USERNAME"
        />
"@)
    }

    [void]$xmlBuilder.AppendLine('</connections>')
    return $xmlBuilder.ToString()
}

try {
    # Get workspace path
    $workspacePath = (Get-ItemProperty -Path "HKCU:\Software\DBeaverCommunity" -Name "workspace" -ErrorAction SilentlyContinue).workspace
    if (-not $workspacePath) {
        $workspacePath = "$env:APPDATA\DBeaverData\workspace6"
    }

    # Find DBeaver executable
    $dbeaverPaths = @(
        "${env:USERPROFILE}\AppData\Local\DBeaver\dbeaver.exe",
        "${env:ProgramFiles}\DBeaver\dbeaver.exe",
        "${env:ProgramFiles(x86)}\DBeaver\dbeaver.exe",
        "${env:LocalAppData}\Programs\DBeaver\dbeaver.exe",
        "${env:ProgramFiles}\DBeaverCE\dbeaver.exe",
        "${env:ProgramFiles(x86)}\DBeaverCE\dbeaver.exe",
        "${env:LocalAppData}\Programs\DBeaverCE\dbeaver.exe"
    )

    $dbeaverExe = $dbeaverPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $dbeaverExe) {
        Write-Status "DBeaver not found" "ERROR"
        throw "DBeaver executable not found. Please ensure DBeaver is installed."
    }
    Write-Status "DBeaver found" "DONE"

    Show-Menu
    Write-Status "Checking DBeaver installation..." "WAIT"

    # # Create base directories first
    # $baseDir = "$env:APPDATA\DBeaverData\workspace6"
    # $dbeaverConfigPath = "$baseDir\.metadata\.plugins\org.jkiss.dbeaver.core"
    # $preferencesPath = "$baseDir\.metadata\.plugins\org.eclipse.core.runtime\.settings"

    # Check if DBeaver is running and kill all related processes
    $dbeaverProcesses = Get-Process | Where-Object { $_.ProcessName -match "dbeaver|java" -and $_.MainWindowTitle -match "DBeaver" } -ErrorAction SilentlyContinue
    if ($dbeaverProcesses) {
        Write-Status "Closing running DBeaver instances..." "WAIT"
        $dbeaverProcesses | ForEach-Object {
            Stop-Process -Id $_.Id -Force
        }
        Start-Sleep -Seconds 3
        Write-Status "DBeaver instances closed" "DONE"
    }

    Write-Status "Preparing workspace..." "WAIT"
    # Clean up workspace lock files
    $lockFiles = @(
        "$baseDir\.metadata\.lock",
        "$baseDir\.metadata\.plugins\org.eclipse.e4.workbench\workbench.xmi.backup",
        "$baseDir\.metadata\.plugins\org.eclipse.core.resources\.snap"
    )

    foreach ($lockFile in $lockFiles) {
        if (Test-Path $lockFile) {
            Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    # # Additional cleanup of workspace metadata
    # $metadataPath = "$baseDir\.metadata"
    # if (Test-Path $metadataPath) {
    #     Get-ChildItem -Path $metadataPath -Filter "*.log" -Recurse | Remove-Item -Force
    #     Get-ChildItem -Path $metadataPath -Filter "*.lock" -Recurse | Remove-Item -Force
    # }

    #     # Create directories if they don't exist
    #     @($baseDir, $dbeaverConfigPath, $preferencesPath) | ForEach-Object {
    #         if (-not (Test-Path $_)) {
    #             New-Item -ItemType Directory -Force -Path $_ | Out-Null
    #         }
    #     }

    #     # Set registry settings
    #     $registryPath = "HKCU:\Software\DBeaverCommunity"
    #     if (-not (Test-Path $registryPath)) {
    #         New-Item -Path $registryPath -Force | Out-Null
    #     }
    #     Set-ItemProperty -Path $registryPath -Name "workspace" -Value $baseDir -Force

    #     # Create project file
    #     $projectContent = @"
    # <?xml version="1.0" encoding="UTF-8"?>
    # <projectDescription>
    #     <name>DBeaver</name>
    #     <comment></comment>
    #     <projects>
    #     </projects>
    #     <buildSpec>
    #     </buildSpec>
    #     <natures>
    #         <nature>org.jkiss.dbeaver.DBeaverNature</nature>
    #     </natures>
    # </projectDescription>
    # "@
    #     $projectContent | Out-File -FilePath "$dbeaverConfigPath\.project" -Encoding UTF8 -Force

    #     # Create preferences file
    #     $preferencesContent = @"
    # eclipse.preferences.version=1
    # org.jkiss.dbeaver.core.confirm.exit=false
    # ui.auto.update.check.time=0
    # "@
    #     $preferencesContent | Out-File -FilePath "$preferencesPath\org.jkiss.dbeaver.core.prefs" -Encoding UTF8 -Force

    #     # Monitor DBeaver log file
    #     $dbeaverLogPath = "$env:APPDATA\DBeaverData\workspace6\.metadata\.log"

    # Get database information and convert to XML
    $importXml = Convert-DatabaseInfoToXml

    Write-Host "Database connections from FkDatabasesJson:"
    $fkDatabasesJson | Format-List

    Write-Host ""

    # # Ask user if they want to use database as connection name
    # $userInput = Get-UserChoice "Use database names for connections? (Y/N) [N]: "
    # if ($userInput -eq "y") {
    #     Write-Status "Updating connection names..." "WAIT"
    #     $importXml = $importXml -replace '(?s)(<connection[^>]*\bname=")[^"]*(".*?\bdatabase=")([^"]*)', '$1$3$2$3'
    #     Write-Status "Connection names updated" "DONE"
    # }
    # Write-Host ""

    # Ask user if they want to add password to connections
    # $addPassword = Get-UserChoice "Add password to connections? (Y/N) [N]: "
    Write-Host "Only used for Digiplex connections" -ForegroundColor Yellow
    $password = Get-SecureInput "Enter your password: "
    Write-Host ""

    Write-Status "Adding password to connections..." "WAIT"
    $importXml = $importXml -replace 'DEDGE\\\$env:USERNAME', "$env:USERDOMAIN\$env:USERNAME"
    $importXml = $importXml -replace 'user="$env:USERDOMAIN\\[^"]*"', "`$0 password=""$password"""
    Write-Status "Password added to connections" "DONE"

    Write-Status "Creating import files..." "WAIT"
    # Current directory
    $currentDir = Get-Location
    $importPath = Join-Path $currentDir "dbeaver_import.xml"
    $importXml | Out-File -FilePath $importPath -Encoding UTF8 -Force

    # Create and execute import script
    $importScript = @"
@echo off
"$dbeaverExe" -import "$importPath" -exit
"@
    $importScriptPath = Join-Path $currentDir "import_dbeaver.bat"
    $importScript | Out-File -FilePath $importScriptPath -Encoding ASCII -Force
    Write-Status "Import files created" "DONE"

    Write-Status "Importing connections..." "WAIT"

    Write-Host "`nWhen DBeaver starts, follow these steps in DBeaver:" -ForegroundColor White
    Write-Host "  $([char]0x221A) 1. Go to 'File -> Import'" -ForegroundColor White
    Write-Host "  $([char]0x221A) 2. Select 'Third Party Configuration -> Custom'" -ForegroundColor White
    Write-Host "  $([char]0x221A) 3. Click 'Next'" -ForegroundColor White
    Write-Host "  $([char]0x221A) 4. In 'Driver selection' select 'DB2 for LUW'" -ForegroundColor White
    Write-Host "  $([char]0x221A) 5. Click 'Next'" -ForegroundColor White
    Write-Host "  $([char]0x221A) 6. In 'Input settings' Leave XML checked and click the orange folder icon" -ForegroundColor White
    Write-Host "  $([char]0x221A) 7. Open XML file: $importPath" -ForegroundColor White
    Write-Host "  $([char]0x221A) 8. Select the connections you want to import and click 'Finish'" -ForegroundColor White
    Write-Status "Configuration complete. Starting DBeaver..." "DONE"
    Start-Process -FilePath $importScriptPath -Wait
    Remove-Item $importScriptPath -Force
    Remove-Item $importPath -Force
    Write-Status "Connections imported successfully" "DONE"

    Write-Host "`nSetup Complete!" -ForegroundColor White

}
catch {
    Write-Status $_.Exception.Message "ERROR"
    Write-Log "Stack Trace: $($_.Exception.StackTrace)"
}

Write-Host "`nCheck $logFile for detailed logs`n" -ForegroundColor White

