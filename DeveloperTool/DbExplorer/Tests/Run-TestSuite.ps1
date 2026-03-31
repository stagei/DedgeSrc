# Standardized test suite runner: kill processes, compile, ensure PG18 profile, run tests, check app logs
# Usage: .\Tests\Run-TestSuite.ps1 [-Profile FKKTOTST] [-Provider PostgreSQL] [-SkipKill] [-SkipBuild] [-StartApp] [-Tests (Connection|AllCLI|All|Statements)]

param(
    [string]$Profile,
    [ValidateSet('', 'DB2', 'PostgreSQL')]
    [string]$Provider = 'PostgreSQL',
    [switch]$SkipKill,
    [switch]$SkipBuild,
    [switch]$StartApp,
    [ValidateSet('Connection', 'AllCLI', 'All', 'Statements', '')]
    [string]$Tests = 'Connection',
    [switch]$EnsurePg18Only
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $projectRoot "CLI_Test_Output"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $logDir "testsuite_$timestamp.log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-SuiteLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [$Level] $Message"
    Add-Content -Path $script:logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
    $color = switch ($Level) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'White' } }
    Write-Host $line -ForegroundColor $color
}

# Start log
"" | Out-File -FilePath $logPath -Encoding utf8
Write-SuiteLog "============================================="
Write-SuiteLog "  TEST SUITE RUN - $timestamp"
Write-SuiteLog "  Profile: $(if ($Profile) { $Profile } else { 'default' }) | Provider: $(if ($Provider) { $Provider } else { 'all' })"
Write-SuiteLog "============================================="

# 1. Kill existing processes (unless -SkipKill)
if (-not $SkipKill) {
    Write-SuiteLog "Step 1: Killing existing app processes..."
    $killed = 0
    foreach ($proc in @('DbExplorer', 'DbExplorerTray')) {
        $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($p) {
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
            $killed++
            Write-SuiteLog "  Killed $proc" "INFO"
        }
    }
    if ($killed -eq 0) { Write-SuiteLog "  No running app processes." "INFO" }
    Start-Sleep -Seconds 1
} else {
    Write-SuiteLog "Step 1: Skip kill (SkipKill)." "WARN"
}

# 2. Ensure PostgreSQL_Local profile exists (so tests can use it)
Write-SuiteLog "Step 2: Ensuring PostgreSQL_Local connection profile..."
try {
    $null = & (Join-Path $PSScriptRoot "Ensure-Pg18Profile.ps1")
    Write-SuiteLog "  Profile PostgreSQL_Local ensured (Documents\DbExplorer\connections.json)." "PASS"
} catch {
    Write-SuiteLog "  Ensure-Pg18Profile failed: $($_.Exception.Message)" "ERROR"
}
if ($EnsurePg18Only) {
    Write-SuiteLog "EnsurePg18Only: exiting after profile setup." "INFO"
    exit 0
}

# 3. Build (unless -SkipBuild)
if (-not $SkipBuild) {
    Write-SuiteLog "Step 3: Building solution..."
    Push-Location $projectRoot
    try {
        $buildOut = dotnet build DbExplorerTray\DbExplorerTray.csproj --verbosity minimal 2>&1
        $buildOut | ForEach-Object { Write-SuiteLog "  $_" "DEBUG" }
        if ($LASTEXITCODE -ne 0) {
            Write-SuiteLog "  Tray build failed." "FAIL"
            Pop-Location
            exit 1
        }
        $buildOut = dotnet build --verbosity minimal 2>&1
        $buildOut | ForEach-Object { Write-SuiteLog "  $_" "DEBUG" }
        if ($LASTEXITCODE -ne 0) {
            Write-SuiteLog "  Main build failed." "FAIL"
            Pop-Location
            exit 1
        }
        Write-SuiteLog "  Build succeeded." "PASS"
    } finally {
        Pop-Location
    }
} else {
    Write-SuiteLog "Step 3: Skip build (SkipBuild)." "WARN"
}

# 4. Run tests (with output teed to log)
$exePath = Join-Path $projectRoot "bin\Debug\net10.0-windows\DbExplorer.exe"
if (-not (Test-Path $exePath)) {
    Write-SuiteLog "Exe not found: $exePath" "ERROR"
    exit 1
}

$env:WDE_TEST_PROFILE = if ($Profile) { $Profile } else { 'PostgreSQL_Local' }
$env:WDE_TEST_PROVIDER = $Provider
$env:WDE_TEST_LOG_PATH = $logPath

Write-SuiteLog "Step 4: Running tests (Profile=$($env:WDE_TEST_PROFILE), Provider=$Provider)..."

switch ($Tests) {
    'Connection' {
        Write-SuiteLog "  Running Test-Connection.ps1..."
        & (Join-Path $PSScriptRoot "CLI\Test-Connection.ps1") *>&1 | ForEach-Object {
            $line = $_.ToString()
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            Write-Host $line
        }
        if ($LASTEXITCODE -eq 0) { Write-SuiteLog "  Test-Connection passed." "PASS" } else { Write-SuiteLog "  Test-Connection failed." "FAIL" }
    }
    'AllCLI' {
        Write-SuiteLog "  Running Test-AllCliCommands.ps1..."
        & (Join-Path $PSScriptRoot "CLI\Test-AllCliCommands.ps1") -Provider $Provider *>&1 | ForEach-Object {
            $line = $_.ToString()
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            Write-Host $line
        }
    }
    'Statements' {
        Write-SuiteLog "  Running Test-PostgreSQLStatements.ps1 (log + execute; 0 rows OK, SQL error FAIL)..."
        & (Join-Path $PSScriptRoot "Validation\Test-PostgreSQLStatements.ps1") -Profile $Profile -Provider $Provider -Execute *>&1 | ForEach-Object {
            $line = $_.ToString()
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            Write-Host $line
        }
        if ($LASTEXITCODE -eq 0) { Write-SuiteLog "  Test-PostgreSQLStatements passed." "PASS" } else { Write-SuiteLog "  Test-PostgreSQLStatements failed." "FAIL" }
    }
    'All' {
        Write-SuiteLog "  Running Test-Connection then Test-AllCliCommands..."
        & (Join-Path $PSScriptRoot "CLI\Test-Connection.ps1") *>&1 | ForEach-Object {
            $line = $_.ToString()
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            Write-Host $line
        }
        & (Join-Path $PSScriptRoot "CLI\Test-AllCliCommands.ps1") -Provider $Provider *>&1 | ForEach-Object {
            $line = $_.ToString()
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            Write-Host $line
        }
        if ($Provider -eq 'PostgreSQL') {
            Write-SuiteLog "  Running Test-PostgreSQLStatements.ps1 (log + execute; 0 rows OK, SQL error FAIL)..."
            & (Join-Path $PSScriptRoot "Validation\Test-PostgreSQLStatements.ps1") -Profile $Profile -Provider $Provider -Execute *>&1 | ForEach-Object {
                $line = $_.ToString()
                Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
                Write-Host $line
            }
            if ($LASTEXITCODE -eq 0) { Write-SuiteLog "  Test-PostgreSQLStatements passed." "PASS" } else { Write-SuiteLog "  Test-PostgreSQLStatements failed." "FAIL" }
        }
    }
    default {
        & (Join-Path $PSScriptRoot "CLI\Test-Connection.ps1") *>&1 | ForEach-Object {
            $line = $_.ToString()
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            Write-Host $line
        }
    }
}

# 5. Check application logs for errors (if app was run during tests)
$appLogDir = Join-Path $projectRoot "bin\Debug\net10.0-windows\logs"
if (Test-Path $appLogDir) {
    Write-SuiteLog "Step 5: Checking application logs in $appLogDir..."
    $today = Get-Date -Format "yyyy-MM-dd"
    $logFile = Join-Path $appLogDir "db2editor-$today.log"
    if (Test-Path $logFile) {
        $errors = Get-Content $logFile -Tail 500 -ErrorAction SilentlyContinue | Select-String -Pattern "ERROR|FATAL|Exception"
        if ($errors) {
            Write-SuiteLog "  Found $($errors.Count) error/exception line(s) in app log:" "WARN"
            $errors | Select-Object -First 10 | ForEach-Object { Write-SuiteLog "    $_" "WARN" }
        } else {
            Write-SuiteLog "  No ERROR/FATAL/Exception in last 500 lines." "PASS"
        }
    } else {
        Write-SuiteLog "  No app log file yet: $logFile" "INFO"
    }
} else {
    Write-SuiteLog "Step 5: App log directory not found (app may not have run)." "INFO"
}

# 6. Optionally start the app
if ($StartApp) {
    Write-SuiteLog "Step 6: Starting DbExplorer..."
    Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath -Parent)
    Write-SuiteLog "  App started." "INFO"
} else {
    Write-SuiteLog "Step 6: Skip start app (omit -StartApp to launch)." "INFO"
}

Write-SuiteLog "============================================="
Write-SuiteLog "  Test suite log: $logPath"
Write-SuiteLog "============================================="
