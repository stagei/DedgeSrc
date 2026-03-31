#Requires -Version 5.1
<#
.SYNOPSIS
    Checks Generic Log Handler apps and database import status; reports in console.

.DESCRIPTION
    Verifies:
    1. Web API – process and /health (and /api/dashboard/health for log stats).
    2. Import Service – process (and optionally Alert Agent).
    3. Database import – GET /api/maintenance/import-status (sources, records, last import).
    4. Database (direct) – manual connection to PostgreSQL (when psql is available).
    5. Table summary – numrows and last create datetime for all tables (log_entries, import_status, saved_filters, alert_history). Shown at end of report.

    Outputs a clear status report to the console (OK / WARN / FAIL).

.PARAMETER ApiBaseUrl
    Base URL of the Web API. Default: http://localhost:8110

.PARAMETER ConfigPath
    Path to appsettings.json for DB connection string. Default: repo root appsettings.json

.PARAMETER SkipDirectDb
    Skip the direct database check (e.g. when psql is not available).

.EXAMPLE
    .\Get-LogHandlerStatus.ps1
.EXAMPLE
    .\Get-LogHandlerStatus.ps1 -ApiBaseUrl http://localhost:8110
.EXAMPLE
    .\Get-LogHandlerStatus.ps1 -SkipDirectDb
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl,  # Auto-detect if not specified

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "appsettings.json"),

    [Parameter(Mandatory = $false)]
    [switch]$SkipDirectDb
)

try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
} catch {
    function Write-LogMessage { param([string]$Message, [string]$Level = "INFO") Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" }
}

$ErrorActionPreference = "Stop"

# Auto-detect API port if not specified
if (-not $ApiBaseUrl) {
    $detectedPort = $null
    $portsToCheck = @(8110, 5000, 5001, 80, 8080)
    
    # First, try to find the WebApi process and its listening port
    $webApiProc = Get-Process -Name "GenericLogHandler.WebApi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($webApiProc) {
        try {
            $conn = Get-NetTCPConnection -OwningProcess $webApiProc.Id -State Listen -ErrorAction SilentlyContinue | 
                    Where-Object { $_.LocalAddress -in @("0.0.0.0", "127.0.0.1", "::1", "::") } |
                    Select-Object -First 1
            if ($conn) { $detectedPort = $conn.LocalPort }
        } catch { }
    }
    
    # If not found via process, check known ports
    if (-not $detectedPort) {
        foreach ($port in $portsToCheck) {
            try {
                $testUrl = "http://localhost:$port/health"
                $r = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
                if ($r.StatusCode -eq 200) {
                    $detectedPort = $port
                    break
                }
            } catch { }
        }
    }
    
    if ($detectedPort) {
        $ApiBaseUrl = "http://localhost:$detectedPort"
        Write-Host "  [Auto] Detected API at $ApiBaseUrl" -ForegroundColor DarkCyan
    } else {
        $ApiBaseUrl = "http://localhost:8110"  # Default fallback
    }
}

$healthUrl = "$ApiBaseUrl/health"
$dashboardHealthUrl = "$ApiBaseUrl/api/dashboard/health"
$importStatusUrl = "$ApiBaseUrl/api/maintenance/import-status"

# Collected in direct DB block; shown in end report (section 5)
$script:tableSummary = @()

function Write-Status { param([string]$Label, [string]$Status, [string]$Detail = "") if ($Detail) { Write-Host "  $Label : $Status - $Detail" } else { Write-Host "  $Label : $Status" } }
function Status-Ok   { param([string]$Detail = "") Write-Host "  [OK]   $Detail" -ForegroundColor Green }
function Status-Warn { param([string]$Detail = "") Write-Host "  [WARN] $Detail" -ForegroundColor Yellow }
function Status-Fail { param([string]$Detail = "") Write-Host "  [FAIL] $Detail" -ForegroundColor Red }

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Generic Log Handler – Status Report" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── 1. Process checks ───────────────────────────────────────────────────────
Write-Host "  1. Apps (processes)" -ForegroundColor White
Write-Host "  ───────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$webApiProcess = $null
$webApiPort = $null

# Check by process name first (GenericLogHandler.WebApi.exe)
$webApiByName = Get-Process -Name "GenericLogHandler.WebApi" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($webApiByName) {
    $webApiProcess = $webApiByName
    # Try to find which port it's listening on
    try {
        $conn = Get-NetTCPConnection -OwningProcess $webApiByName.Id -State Listen -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -in @("0.0.0.0", "127.0.0.1", "::1", "::") } |
                Select-Object -First 1
        if ($conn) { $webApiPort = $conn.LocalPort }
    } catch { }
}

# Also check common ports for any listening process
if (-not $webApiProcess) {
    $portsToCheck = @(8110, 5000, 5001)
    foreach ($port in $portsToCheck) {
        try {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($conn -and $conn.OwningProcess) {
                $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                if ($proc -and $proc.ProcessName -match "GenericLogHandler") {
                    $webApiProcess = $proc
                    $webApiPort = $port
                    break
                }
            }
        } catch { }
    }
}

if ($webApiProcess) {
    $portInfo = if ($webApiPort) { " (port $webApiPort)" } else { "" }
    Status-Ok "Web API is running: $($webApiProcess.ProcessName)$portInfo"
} else {
    Status-Fail "Web API not detected (no 'GenericLogHandler.WebApi' process found)"
}

$importProcess = Get-Process -Name "GenericLogHandler.ImportService" -ErrorAction SilentlyContinue | Select-Object -First 1
$importViaDotnet = 0
try {
    Get-CimInstance Win32_Process -Filter "Name = 'dotnet.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cmd = $_.CommandLine ?? ""
        # Match GenericLogHandler.ImportService in command line or path
        if ($cmd -match "GenericLogHandler[.\\/]ImportService" -or $cmd -match "ImportService\.dll") {
            $script:importViaDotnet++
        }
    }
} catch { }
# Also check if there's a dotnet process whose parent is running from ImportService folder
if (-not $importProcess -and $importViaDotnet -eq 0) {
    try {
        Get-CimInstance Win32_Process -Filter "Name = 'dotnet.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
            $parentId = $_.ParentProcessId
            if ($parentId) {
                $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $parentId" -ErrorAction SilentlyContinue
                if ($parent -and ($parent.CommandLine -match "ImportService")) { $script:importViaDotnet++ }
            }
        }
    } catch { }
}
if ($importProcess -or $importViaDotnet -gt 0) {
    Status-Ok "Import Service is running"
} else {
    Status-Warn "Import Service not detected (no 'GenericLogHandler.ImportService' exe or dotnet ImportService process)"
}

$alertProcess = Get-Process -Name "GenericLogHandler.AlertAgent" -ErrorAction SilentlyContinue | Select-Object -First 1
$alertViaDotnet = 0
try {
    Get-CimInstance Win32_Process -Filter "Name = 'dotnet.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cmd = $_.CommandLine ?? ""
        if ($cmd -match "GenericLogHandler[.\\/]AlertAgent" -or $cmd -match "AlertAgent\.dll") {
            $script:alertViaDotnet++
        }
    }
} catch { }
if ($alertProcess -or $alertViaDotnet -gt 0) {
    Status-Ok "Alert Agent is running"
} else {
    Write-Host "  [  - ] Alert Agent not running (optional)" -ForegroundColor DarkGray
}
Write-Host ""

# ─── 2. Web API health and dashboard ─────────────────────────────────────────
Write-Host "  2. Web API (HTTP)" -ForegroundColor White
Write-Host "  ───────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$apiReachable = $false
$dashboardHealth = $null
try {
    $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($r.StatusCode -eq 200) {
        $apiReachable = $true
        Status-Ok "GET $healthUrl returned 200"
    } else {
        Status-Warn "GET $healthUrl returned $($r.StatusCode)"
    }
} catch {
    Status-Fail "GET $healthUrl failed: $($_.Exception.Message)"
}

if ($apiReachable) {
    try {
        $response = Invoke-RestMethod -Uri $dashboardHealthUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($response.Success -and $response.Data) {
            $dashboardHealth = $response.Data
            $logsLastHour = $response.Data.LogsLastHour
            $lastLog = $response.Data.LastLogReceived
            $status = $response.Data.Status
            Status-Ok "Dashboard health: Status=$status, LogsLastHour=$logsLastHour, LastLogReceived=$lastLog"
        } else {
            Status-Warn "Dashboard health returned no data or Success=false"
        }
    } catch {
        Status-Warn "GET $dashboardHealthUrl failed: $($_.Exception.Message)"
    }
}
Write-Host ""

# ─── 3. Import status (sources and database import) ───────────────────────────
Write-Host "  3. Database import (per source)" -ForegroundColor White
Write-Host "  ───────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$importStatusList = $null
if ($apiReachable) {
    try {
        $response = Invoke-RestMethod -Uri $importStatusUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($response.Success -and $null -ne $response.Data) {
            $importStatusList = $response.Data
            if ($importStatusList.Count -eq 0) {
                Status-Warn "No import sources configured or no import-status records yet"
            } else {
                $anyRecent = $false
                $anyFailed = $false
                foreach ($item in $importStatusList) {
                    $lastImport = $item.LastImportTimestamp
                    $records = $item.RecordsProcessed
                    $statusStr = $item.Status
                    $name = $item.SourceName
                    $path = $item.FilePath
                    if ($statusStr -eq "Failed") { $anyFailed = $true }
                    $recent = $false
                    if ($lastImport) {
                        # Use TryParse for robust date parsing across different formats
                        $dt = [DateTime]::MinValue
                        $parsed = [DateTime]::TryParse($lastImport, [ref]$dt)
                        if ($parsed) {
                            $recent = ((Get-Date) - $dt).TotalMinutes -lt 60
                            if ($recent -and $records -gt 0) { $anyRecent = $true }
                        }
                    }
                    $recentStr = if ($recent) { "recent" } else { "stale" }
                    $color = if ($statusStr -eq "Failed") { "Red" } elseif ($recent) { "Green" } else { "Yellow" }
                    Write-Host "     $name | $path" -ForegroundColor Gray
                    Write-Host "       Status=$statusStr, RecordsProcessed=$records, LastImport=$lastImport ($recentStr)" -ForegroundColor $color
                }
                if ($anyFailed) { Status-Warn "At least one source has status Failed" }
                elseif ($anyRecent) { Status-Ok "At least one source has recent import with records" }
                else { Status-Warn "No source with recent import in the last hour" }
            }
        } else {
            Status-Warn "Import status returned no data or Success=false"
        }
    } catch {
        Status-Fail "GET $importStatusUrl failed: $($_.Exception.Message)"
    }
} else {
    Status-Fail "Skipped (Web API not reachable)"
}
Write-Host ""

# ─── 4. Database (direct) – manual PostgreSQL check ───────────────────────────
Write-Host "  4. Database (direct)" -ForegroundColor White
Write-Host "  ───────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

if ($SkipDirectDb) {
    Write-Host "  [  - ] Direct DB check skipped (-SkipDirectDb)" -ForegroundColor DarkGray
    Write-Host ""
} else {
    $dbHost = $null
    $dbPort = "5432"
    $dbName = $null
    $dbUser = $null
    $dbPassword = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $json = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            $connStr = if ($json.ConnectionStrings.Postgres) { $json.ConnectionStrings.Postgres } else { $json.ConnectionStrings.DefaultConnection }
            if ($connStr) {
                foreach ($pair in ($connStr -split ';')) {
                    if ($pair -match '^\s*([^=]+)=(.*)$') {
                        $key = $matches[1].Trim().ToLowerInvariant()
                        $val = $matches[2].Trim()
                        switch -Regex ($key) {
                            '^host$'       { $dbHost = $val }
                            '^port$'       { $dbPort = $val }
                            '^database$'   { $dbName = $val }
                            '^username$'   { $dbUser = $val }
                            '^password$'   { $dbPassword = $val }
                        }
                    }
                }
            }
        } catch {
            Status-Warn "Could not parse connection string from $ConfigPath"
        }
    } else {
        Status-Warn "Config not found: $ConfigPath"
    }

    if (-not $dbHost -or -not $dbName -or -not $dbUser) {
        Status-Warn "Direct DB check skipped (missing Host/Database/Username in $ConfigPath or config not found)"
    } else {
        $psqlExe = $null
        if (Get-Command psql -ErrorAction SilentlyContinue) {
            $psqlExe = "psql"
        } else {
            # Check common PostgreSQL installation paths (newest first)
            $pgBins = @(
                "${env:ProgramFiles}\PostgreSQL\18\bin\psql.exe",
                "${env:ProgramFiles}\PostgreSQL\17\bin\psql.exe",
                "${env:ProgramFiles}\PostgreSQL\16\bin\psql.exe",
                "${env:ProgramFiles}\PostgreSQL\15\bin\psql.exe",
                "${env:ProgramFiles}\PostgreSQL\14\bin\psql.exe",
                "${env:ProgramFiles}\PostgreSQL\13\bin\psql.exe",
                "${env:ProgramFiles}\PostgreSQL\12\bin\psql.exe"
            )
            foreach ($p in $pgBins) {
                if (Test-Path -LiteralPath $p) { $psqlExe = $p; break }
            }
        }

        if (-not $psqlExe) {
            Status-Warn "Direct DB check skipped (psql not in PATH and not found under Program Files\PostgreSQL). Install PostgreSQL client or use -SkipDirectDb."
        } else {
            $env:PGPASSWORD = $dbPassword
            try {
                $connectArgs = @("-h", $dbHost, "-p", $dbPort, "-U", $dbUser, "-d", $dbName, "-t", "-A", "-c", "SELECT 1")
                $connectOut = & $psqlExe @connectArgs 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Status-Fail "Direct DB connect failed: $connectOut"
                } else {
                    Status-Ok "Connected to $dbHost`:$dbPort/$dbName"
                }

                if ($LASTEXITCODE -eq 0) {
                    # Tables and their "last datetime" column for end report
                    $tablesForSummary = @(
                        @{ Table = "log_entries";      LastCol = "timestamp" },
                        @{ Table = "import_status";   LastCol = "last_import_timestamp" },
                        @{ Table = "saved_filters";   LastCol = "created_at" },
                        @{ Table = "alert_history";   LastCol = "triggered_at" }
                    )
                    $baseArgs = @("-h", $dbHost, "-p", $dbPort, "-U", $dbUser, "-d", $dbName, "-t", "-A")
                    $script:tableSummary = @()
                    foreach ($t in $tablesForSummary) {
                        $countOut = & $psqlExe @baseArgs -c "SELECT COUNT(*) FROM $($t.Table)" 2>&1
                        $countStr = ($countOut -replace '\s', '') -replace '[^\d]', ''
                        $numRows = if ($countStr -match '^\d+$') { [long]$countStr } else { $null }
                        $lastColQuoted = if ($t.LastCol -eq "timestamp") { '"timestamp"' } else { $t.LastCol }
                        $maxOut = & $psqlExe @baseArgs -c "SELECT COALESCE(MAX($lastColQuoted)::text, '') FROM $($t.Table)" 2>&1
                        $lastDt = ($maxOut -replace '\s+$', '').Trim()
                        if (-not $lastDt -or $lastDt -match '^\s*$') { $lastDt = "(no rows)" }
                        $script:tableSummary += @{ Table = $t.Table; NumRows = $numRows; LastDatetime = $lastDt }
                    }
                }
            } catch {
                Status-Fail "Direct DB check failed: $($_.Exception.Message)"
            } finally {
                $env:PGPASSWORD = $null
            }
        }
    }
    Write-Host ""
}

# ─── 5. End report – all tables (numrows + last create datetime) ─────────────
Write-Host "  5. Table summary (all tables)" -ForegroundColor White
Write-Host "  ───────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($script:tableSummary -and $script:tableSummary.Count -gt 0) {
    $colTable = "Table"
    $colRows = "NumRows"
    $colLast = "Last datetime"
    $wTable = [Math]::Max($colTable.Length, 20)
    $wRows = [Math]::Max($colRows.Length, 10)
    $fmt = "  {0,-$wTable}  {1,$wRows}  {2}" -f $colTable, $colRows, $colLast
    Write-Host $fmt -ForegroundColor Gray
    Write-Host "  $('-' * $wTable)  $('-' * $wRows)  $('-' * 28)" -ForegroundColor DarkGray
    foreach ($row in $script:tableSummary) {
        $rowsStr = if ($null -eq $row.NumRows) { "?" } else { $row.NumRows.ToString() }
        $fmtRow = "  {0,-$wTable}  {1,$wRows}  {2}" -f $row.Table, $rowsStr, $row.LastDatetime
        Write-Host $fmtRow -ForegroundColor White
    }
} else {
    Write-Host "  (No data – direct DB check was skipped or failed. Run without -SkipDirectDb and ensure psql is available.)" -ForegroundColor DarkGray
}
Write-Host ""

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  End of status report" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
