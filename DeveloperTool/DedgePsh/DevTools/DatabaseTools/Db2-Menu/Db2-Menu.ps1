# Smart DB2 12.1 Menu for Dedge
# Enhanced DB2 Management Tool

param(
    [switch]$NoExit = $false
)
Import-Module Db2-Handler -Force
Import-Module Db2-Handler -Force
# Initialize DB2 command path
try {
    $db2cmdPath = Get-CommandPathWithFallback "db2cmd"
    Write-Host "DB2 Command found at: $db2cmdPath" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: DB2 command not found. Please ensure DB2 is installed and in PATH." -ForegroundColor Red
    if (-not $NoExit) { Read-Host "Press Enter to exit"; exit 1 }
}

# Function to execute DB2 commands
function Invoke-Db2CommandOld {
    param(
        [string]$Command,
        [string]$Description = "Executing DB2 command"
    )

    Write-Host "`n$Description..." -ForegroundColor Yellow
    Write-Host "Command: $Command" -ForegroundColor Cyan

    try {
        $result = & cmd /c "db2cmd -c -w -i `"$Command`""

        Test-OutputForErrors -Output $result
        # Write-Host $result -ForegroundColor White
        return $true
    }
    catch {
        Write-Host "Error executing command: $_" -ForegroundColor Red
        return $false
    }
}

# Function to set DB2 instance
function Set-DB2Instance {
    param([string]$InstanceName)

    Write-Host "`nSetting DB2INSTANCE to: $InstanceName" -ForegroundColor Yellow
    $env:DB2INSTANCE = $InstanceName
    [Environment]::SetEnvironmentVariable("DB2INSTANCE", $InstanceName, "Process")

    # Verify the change
    $currentInstance = $env:DB2INSTANCE
    if ($currentInstance -eq $InstanceName) {
        Write-Host "✓ DB2INSTANCE successfully set to: $currentInstance" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to set DB2INSTANCE" -ForegroundColor Red
    }

    # Show current instance info
    Invoke-Db2CommandOld "db2 get instance" "Getting current instance information"
}

# Function to perform full database restart and activation
function Restart-AllDatabases {
    Write-Host "`n=== DB2 Full Restart and Database Activation ===" -ForegroundColor Magenta

    # Step 1: Force stop DB2
    Write-Host "`nStep 1: Forcing DB2 to stop..." -ForegroundColor Yellow
    Invoke-Db2CommandOld "db2stop force" "Forcing DB2 to stop"
    Start-Sleep -Seconds 3

    # Step 2: Start DB2
    Write-Host "`nStep 2: Starting DB2..." -ForegroundColor Yellow
    Invoke-Db2CommandOld "db2start" "Starting DB2"
    Start-Sleep -Seconds 5

    # Step 3: Get list of databases and activate them
    Write-Host "`nStep 3: Getting database list and activating databases..." -ForegroundColor Yellow

    try {
        $dbListOutput = & cmd /c "db2cmd -c -w -i `"db2 list database directory`""

        # Parse database names from output
        $databases = @()
        $lines = $dbListOutput -split "`n"
        foreach ($line in $lines) {
            if ($line -match "Database name\s+=\s+(.+)") {
                $dbName = $matches[1].Trim()
                $databases += $dbName
            }
        }

        if ($databases.Count -gt 0) {
            Write-Host "Found $($databases.Count) database(s): $($databases -join ', ')" -ForegroundColor Cyan

            foreach ($db in $databases) {
                Write-Host "`nActivating database: $db" -ForegroundColor Yellow
                Invoke-Db2CommandOld "db2 activate database $db" "Activating database $db"
            }
        } else {
            Write-Host "No databases found in directory." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error processing database list: $_" -ForegroundColor Red
    }

    Write-Host "`n=== Database restart and activation completed ===" -ForegroundColor Green
}

# Function to open services file
function Open-ServicesFile {
    $servicesPath = "$env:SystemRoot\System32\drivers\etc\services"

    if (Test-Path $servicesPath) {
        Write-Host "`nOpening services file: $servicesPath" -ForegroundColor Blue
        try {
            # Try to open with notepad
            Start-Process notepad.exe -ArgumentList $servicesPath
            Write-Host "✓ Services file opened in Notepad" -ForegroundColor Green
        }
        catch {
            Write-Host "Error opening services file: $_" -ForegroundColor Red
            Write-Host "File location: $servicesPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Services file not found at: $servicesPath" -ForegroundColor Red
    }
}

# Function to display current DB2 status
function Show-DB2Status {
    Write-Host "`n=== DB2 Status Information ===" -ForegroundColor Magenta

    Write-Host "`nCurrent Environment:" -ForegroundColor Cyan
    Write-Host "DB2INSTANCE: $($env:DB2INSTANCE)" -ForegroundColor White
    Write-Host "DB2 Command Path: $db2cmdPath" -ForegroundColor White

    Write-Host "`n" -NoNewline
    Invoke-Db2CommandOld "db2 get instance" "Getting instance information"

    Write-Host "`n" -NoNewline
    Invoke-Db2CommandOld "db2pd -" "Getting DB2 process information"

    Write-Host "`n" -NoNewline
    Invoke-Db2CommandOld "db2 list database directory" "Listing databases"
}

# Main Menu Function
function Show-MainMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║              Smart DB2 12.1 Menu - Dedge          ║" -ForegroundColor Blue
    Write-Host "║                     Database Management Tool                  ║" -ForegroundColor Blue
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Current DB2INSTANCE: " -NoNewline -ForegroundColor Yellow
    Write-Host "$($env:DB2INSTANCE)" -ForegroundColor Green
    Write-Host ""
    Write-Host "┌─ Instance Management ─────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  1. Set DB2INSTANCE to DB2                                    │" -ForegroundColor White
    Write-Host "│  2. Set DB2INSTANCE to DB2FED                                 │" -ForegroundColor White
    Write-Host "└───────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "┌─ Database Operations ─────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  3. Full DB2 Restart + Activate All Databases                 │" -ForegroundColor White
    Write-Host "│  4. Show DB2 Status & Database List                           │" -ForegroundColor White
    Write-Host "└───────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "┌─ System Operations ───────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  5. Open Services File (system32\drivers\etc\services)        │" -ForegroundColor White
    Write-Host "└───────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "┌─ Menu Options ────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  0. Exit                                                      │" -ForegroundColor White
    Write-Host "└───────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please select an option (0-5): " -NoNewline -ForegroundColor Yellow
}

# Main execution loop
do {
    Show-MainMenu
    $choice = Read-Host

    switch ($choice) {
        "1" {
            Set-DB2Instance "DB2"
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            Read-Host
        }
        "2" {
            Set-DB2Instance "DB2FED"
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            Read-Host
        }
        "3" {
            Restart-AllDatabases
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            Read-Host
        }
        "4" {
            Show-DB2Status
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            Read-Host
        }
        "5" {
            Open-ServicesFile
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            Read-Host
        }
        "0" {
            Write-Host "`nExiting DB2 Menu. Thank you!" -ForegroundColor Green
            break
        }
        default {
            Write-Host "`nInvalid option. Please select 0-5." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($choice -ne "0")

if (-not $NoExit) {
    Write-Host "Press Enter to exit..." -ForegroundColor Gray
    Read-Host
}

