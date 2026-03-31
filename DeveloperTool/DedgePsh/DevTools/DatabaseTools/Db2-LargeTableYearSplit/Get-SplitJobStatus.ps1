param(
    [Parameter(Mandatory = $false)]
    [string]$ServerName = "t-no1fkmmig-db",
    [Parameter(Mandatory = $false)]
    [int]$DaysBack = 7,
    [Parameter(Mandatory = $false)]
    [string]$LocalTempFolder = (Join-Path $env:TEMP "SplitJobStatus"),
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = (Join-Path $PSScriptRoot "ArchiveTables.json")
)

<#
.SYNOPSIS
    Gathers Db2-LargeTableYearSplit execution status from a remote server.

.DESCRIPTION
    Copies log files from the remote server to a local temp folder, parses them
    for job runs, errors, durations, and table status. Outputs a structured
    summary to the console and optionally to a markdown file in ExecLogs/.

.PARAMETER ServerName
    Target server hostname. Default: t-no1fkmmig-db

.PARAMETER DaysBack
    How many days of logs to check. Default: 7

.PARAMETER LocalTempFolder
    Local folder for copied log files. Default: $env:TEMP\SplitJobStatus

.PARAMETER ConfigFilePath
    Path to ArchiveTables.json. Default: <scriptroot>\ArchiveTables.json
#>

if (-not (Test-Path $LocalTempFolder)) {
    New-Item -ItemType Directory -Path $LocalTempFolder -Force | Out-Null
}

$appLogBase = "\\$($ServerName)\opt\data\Db2-LargeTableYearSplit"
$centralLogBase = "\\$($ServerName)\opt\data\AllPwshLog"

$today = Get-Date
$dates = @()
for ($i = 0; $i -le $DaysBack; $i++) {
    $dates += ($today.AddDays(-$i)).ToString("yyyyMMdd")
}

Write-Host "`n=== Db2-LargeTableYearSplit Status Report ===" -ForegroundColor Cyan
Write-Host "Server: $($ServerName)"
Write-Host "Checking dates: $($dates[0]) to $($dates[-1])"
Write-Host ""

# --- Step 1: Copy log files locally ---
Write-Host "--- Step 1: Copying log files locally ---" -ForegroundColor Yellow
$copiedFiles = @()
foreach ($d in $dates) {
    foreach ($logSource in @(
        @{ Path = "$($appLogBase)\FkLog_$($d).log"; Label = "app" },
        @{ Path = "$($centralLogBase)\FkLog_$($d).log"; Label = "central" }
    )) {
        if (Test-Path $logSource.Path) {
            $localName = "$($logSource.Label)_$($d).log"
            $localPath = Join-Path $LocalTempFolder $localName
            Copy-Item -Path $logSource.Path -Destination $localPath -Force
            $sizeMB = [math]::Round((Get-Item $localPath).Length / 1MB, 2)
            Write-Host "  Copied $($logSource.Label) $($d): $($sizeMB) MB"
            $copiedFiles += [PSCustomObject]@{
                Label    = $logSource.Label
                Date     = $d
                Path     = $localPath
                SizeMB   = $sizeMB
            }
        }
    }
}

if ($copiedFiles.Count -eq 0) {
    Write-Host "  No log files found for the specified date range." -ForegroundColor Red
    exit 0
}

# --- Step 2: Parse job runs (JOB_STARTED / JOB_COMPLETED / JOB_FAILED) ---
Write-Host "`n--- Step 2: Job Runs ---" -ForegroundColor Yellow
$appLogFiles = @($copiedFiles | Where-Object { $_.Label -eq "app" } | Select-Object -ExpandProperty Path)
$centralLogFiles = @($copiedFiles | Where-Object { $_.Label -eq "central" } | Select-Object -ExpandProperty Path)
$allLogFiles = @($appLogFiles) + @($centralLogFiles)

$jobEntries = @()
foreach ($logFile in $allLogFiles) {
    $selectResults = Select-String -Path $logFile -Pattern 'LargeTableYearSplit.*(JOB_STARTED|JOB_COMPLETED|JOB_FAILED)' -ErrorAction SilentlyContinue
    foreach ($m in $selectResults) {
        $parts = $m.Line -split '\|'
        if ($parts.Count -ge 6) {
            $jobEntries += [PSCustomObject]@{
                Timestamp = $parts[0].Trim()
                Level     = $parts[2].Trim()
                PID       = $parts[4].Trim()
                Source    = (Split-Path $logFile -Leaf)
            }
        }
    }
}

$jobEntries = $jobEntries | Sort-Object Timestamp -Unique

$runs = @()
$starts = @($jobEntries | Where-Object { $_.Level -eq "JOB_STARTED" })
foreach ($start in $starts) {
    $end = $jobEntries | Where-Object {
        ($_.Level -eq "JOB_COMPLETED" -or $_.Level -eq "JOB_FAILED") -and
        $_.PID -eq $start.PID -and
        $_.Timestamp -gt $start.Timestamp
    } | Select-Object -First 1

    $duration = "RUNNING"
    $result = "RUNNING"
    if ($end) {
        $result = if ($end.Level -eq "JOB_COMPLETED") { "OK" } else { "FAILED" }
        try {
            $startDt = [datetime]::ParseExact($start.Timestamp, 'yyyy-MM-dd HH:mm:ss', $null)
            $endDt = [datetime]::ParseExact($end.Timestamp, 'yyyy-MM-dd HH:mm:ss', $null)
            $dur = $endDt - $startDt
            $duration = "{0:0}h {1:00}m" -f [math]::Floor($dur.TotalHours), $dur.Minutes
        }
        catch { $duration = "?" }
    }

    $runs += [PSCustomObject]@{
        Start    = $start.Timestamp
        End      = if ($end) { $end.Timestamp } else { "(running)" }
        PID      = $start.PID
        Duration = $duration
        Result   = $result
    }
}

if ($runs.Count -gt 0) {
    $runs | Format-Table -AutoSize | Out-String | Write-Host
}
else {
    Write-Host "  No job runs found in logs." -ForegroundColor DarkGray
}

# --- Step 3: Parse errors ---
Write-Host "--- Step 3: Errors ---" -ForegroundColor Yellow
$errors = @()
foreach ($logFile in $allLogFiles) {
    $errMatches = Select-String -Path $logFile -Pattern 'LargeTableYearSplit.*\|ERROR\|' -ErrorAction SilentlyContinue
    foreach ($m in $errMatches) {
        $parts = $m.Line -split '\|'
        if ($parts.Count -ge 10) {
            $errors += [PSCustomObject]@{
                Timestamp = $parts[0].Trim()
                PID       = $parts[4].Trim()
                Function  = $parts[6].Trim()
                Message   = ($parts[9..($parts.Count - 1)] -join '|').Trim()
            }
        }
    }
}

$errors = $errors | Sort-Object Timestamp -Unique
if ($errors.Count -gt 0) {
    Write-Host "  Found $($errors.Count) error(s):" -ForegroundColor Red
    foreach ($e in $errors) {
        $shortMsg = if ($e.Message.Length -gt 120) { $e.Message.Substring(0, 120) + "..." } else { $e.Message }
        Write-Host "  [$($e.Timestamp)] PID $($e.PID) / $($e.Function): $($shortMsg)" -ForegroundColor Red
    }
}
else {
    Write-Host "  No errors found." -ForegroundColor Green
}

# --- Step 4: Parse table status from logs ---
Write-Host "`n--- Step 4: Table Status (from logs) ---" -ForegroundColor Yellow

$archiveConfig = @()
if (Test-Path $ConfigFilePath) {
    $archiveConfig = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
    Write-Host "  Tables in config: $(($archiveConfig | ForEach-Object { $_.TableName }) -join ', ')"
}

foreach ($logFile in $allLogFiles) {
    $statusLines = Select-String -Path $logFile -Pattern 'RenameAndReload COMPLETE|New DBM\.|All rows are already|Total rows:|_TMP.*rows' -ErrorAction SilentlyContinue
    foreach ($m in $statusLines) {
        $parts = $m.Line -split '\|'
        if ($parts.Count -ge 10) {
            $msg = ($parts[9..($parts.Count - 1)] -join '|').Trim()
            Write-Host "  [$($parts[0].Trim())] $($msg)"
        }
    }
}

# --- Step 5: Check _TMP table existence via log references ---
Write-Host "`n--- Step 5: _TMP Table References ---" -ForegroundColor Yellow
foreach ($logFile in $allLogFiles) {
    $tmpLines = Select-String -Path $logFile -Pattern 'TMP DBM\.' -ErrorAction SilentlyContinue
    foreach ($m in $tmpLines) {
        $parts = $m.Line -split '\|'
        if ($parts.Count -ge 10) {
            $msg = ($parts[9..($parts.Count - 1)] -join '|').Trim()
            Write-Host "  [$($parts[0].Trim())] $($msg)"
        }
    }
}

# --- Step 6: Check for currently running process ---
Write-Host "`n--- Step 6: Currently Running ---" -ForegroundColor Yellow
$orchStdout = "\\$($ServerName)\opt\data\Cursor-ServerOrchestrator\stdout_capture.txt"
$orchResult = "\\$($ServerName)\opt\data\Cursor-ServerOrchestrator\result.json"

if (Test-Path $orchStdout) {
    $localStdout = Join-Path $LocalTempFolder "orch_stdout.txt"
    Copy-Item $orchStdout $localStdout -Force
    Write-Host "  Last 5 lines of orchestrator stdout:"
    Get-Content $localStdout -Tail 5 | ForEach-Object { Write-Host "    $_" }
}

if (Test-Path $orchResult) {
    $localResult = Join-Path $LocalTempFolder "orch_result.json"
    Copy-Item $orchResult $localResult -Force
    $resultData = Get-Content $localResult -Raw | ConvertFrom-Json
    Write-Host "  Orchestrator result: status=$($resultData.status), exitCode=$($resultData.exitCode)"
}
else {
    Write-Host "  No orchestrator result file found." -ForegroundColor DarkGray
}

# --- Summary ---
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Runs found: $($runs.Count)"
Write-Host "Errors found: $($errors.Count)"
Write-Host "Log files copied to: $($LocalTempFolder)"
Write-Host "Local log files available for detailed analysis with Read/Grep tools.`n"
