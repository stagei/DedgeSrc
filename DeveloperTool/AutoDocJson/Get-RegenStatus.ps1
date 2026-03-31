#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Shows live status of the AutoDocJson regeneration job on dedge-server.
.PARAMETER Watch
    Continuously refresh every N seconds (0 = single run).
.PARAMETER Project
    Orchestrator project name (default: autodocjson-regen).
.PARAMETER Server
    Target server (default: dedge-server).
.EXAMPLE
    .\Get-RegenStatus.ps1
.EXAMPLE
    .\Get-RegenStatus.ps1 -Watch 30
#>
[CmdletBinding()]
param(
    [int]$Watch = 0,
    [string]$Project = "autodocjson-regen",
    [string]$Server = "dedge-server"
)

$ErrorActionPreference = "Stop"

$orchestratorBase = "\\$Server\opt\data\Cursor-ServerOrchestrator"
$localCache = Join-Path $env:TEMP "autodoc-regen-status"
New-Item $localCache -ItemType Directory -Force | Out-Null

function Get-JobStatus {
    $slot = "FKGEISTA_$Project"
    $runningFile = Join-Path $orchestratorBase "running_command_$($slot).json"
    $completedFile = Join-Path $orchestratorBase "completed_command_$($slot).json"
    $stdoutFile = Join-Path $orchestratorBase "stdout_capture_$($slot).txt"
    $stderrFile = Join-Path $orchestratorBase "stderr_capture_$($slot).txt"

    $isRunning = Test-Path $runningFile
    $isCompleted = Test-Path $completedFile

    if ($isCompleted) { return "COMPLETED" }
    if ($isRunning) { return "RUNNING" }
    return "NOT_FOUND"
}

function Get-RunningCommand {
    $slot = "FKGEISTA_$Project"
    $runningFile = Join-Path $orchestratorBase "running_command_$($slot).json"
    if (Test-Path $runningFile) {
        return Get-Content $runningFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Copy-StdoutLocal {
    $slot = "FKGEISTA_$Project"
    $src = Join-Path $orchestratorBase "stdout_capture_$($slot).txt"
    $dst = Join-Path $localCache "stdout.txt"
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        return $dst
    }
    return $null
}

function Show-Status {
    $status = Get-JobStatus
    $cmdInfo = Get-RunningCommand
    $localStdout = Copy-StdoutLocal

    if (-not $localStdout -or -not (Test-Path $localStdout)) {
        Write-Host "  No stdout log found. Job may not have started." -ForegroundColor Red
        return
    }

    $logContent = Get-Content $localStdout -Encoding utf8
    $logSize = [math]::Round((Get-Item $localStdout).Length / 1MB, 2)

    # --- Parse key metrics ---

    $startedAt = $null
    if ($cmdInfo -and $cmdInfo.startedAt) {
        $startedAt = [datetime]::Parse($cmdInfo.startedAt, [System.Globalization.CultureInfo]::InvariantCulture)
    }

    # Work queue breakdown
    $totalFiles = 0
    $queueBreakdown = ""
    foreach ($line in $logContent) {
        if ($line -match 'Work queue: (.+)\| Total=(\d+)') {
            $totalFiles = [int]$matches[2]
            $queueBreakdown = $matches[1].Trim().TrimEnd('|').Trim()
            break
        }
    }
    if ($totalFiles -eq 0) { $totalFiles = 7811 }

    # Thread count
    $threadCount = 1
    foreach ($line in $logContent) {
        if ($line -match 'Parallel processing ENABLED: (\d+) threads') {
            $threadCount = [int]$matches[1]
            break
        }
    }

    # Completed files
    $completedCount = 0
    $dispatched = 0
    $lastDispatchLine = ""
    $errorLines = @()
    $typeCounters = @{}

    foreach ($line in $logContent) {
        if ($line -match 'Completed successfully:') {
            $completedCount++
        }
        if ($line -match '\[(\d+)/\d+\] (\w+):') {
            $num = [int]$matches[1]
            $fileType = $matches[2]
            if ($num -gt $dispatched) {
                $dispatched = $num
                $lastDispatchLine = $line
            }
            if (-not $typeCounters.ContainsKey($fileType)) {
                $typeCounters[$fileType] = 0
            }
            $typeCounters[$fileType]++
        }
        if ($line -match '\[ERROR\]') {
            $errorLines += $line
        }
    }

    # Current file
    $currentFile = ""
    if ($lastDispatchLine -match '\[\d+/\d+\] \w+: (.+)$') {
        $currentFile = $matches[1].Trim()
    }

    # Last completed file
    $lastCompleted = ""
    $lastCompletedTime = ""
    for ($i = $logContent.Count - 1; $i -ge 0; $i--) {
        if ($logContent[$i] -match 'Completed successfully: (.+)$') {
            $lastCompleted = $matches[1].Trim()
            if ($logContent[$i] -match '^\[(\d{2}:\d{2}:\d{2})') {
                $lastCompletedTime = $matches[1]
            }
            break
        }
    }

    # Source file cache info
    $cachedFiles = 0
    $cachedSize = ""
    $cacheTime = ""
    foreach ($line in $logContent) {
        if ($line -match 'Preloaded (\d+) files \(([^)]+)\) in ([\d,.]+)s') {
            $cachedFiles = [int]$matches[1]
            $cachedSize = $matches[2]
            $cacheTime = "$($matches[3])s"
        }
    }

    # Calculate rates and ETA
    $now = Get-Date
    $elapsed = $null
    $rate = 0
    $eta = "unknown"
    $elapsedStr = "unknown"

    if ($startedAt) {
        $elapsed = $now - $startedAt
        $elapsedStr = "{0}h {1}m {2}s" -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
        if ($elapsed.TotalMinutes -gt 0 -and $completedCount -gt 0) {
            $rate = [math]::Round($completedCount / $elapsed.TotalMinutes, 2)
            $remaining = $totalFiles - $completedCount
            if ($rate -gt 0) {
                $etaMinutes = $remaining / $rate
                $etaHours = [math]::Floor($etaMinutes / 60)
                $etaMins = [int]($etaMinutes % 60)
                $eta = "{0}h {1}m" -f $etaHours, $etaMins
                $etaFinish = $now.AddMinutes($etaMinutes).ToString("yyyy-MM-dd HH:mm")
                $eta = "$eta (finish ~$etaFinish)"
            }
        }
    }

    $pct = if ($totalFiles -gt 0) { [math]::Round(($completedCount / $totalFiles) * 100, 1) } else { 0 }

    # Progress bar
    $barWidth = 40
    $filledWidth = [math]::Floor($barWidth * $pct / 100)
    $emptyWidth = $barWidth - $filledWidth
    $bar = ("█" * $filledWidth) + ("░" * $emptyWidth)

    # Status color
    $statusColor = switch ($status) {
        "RUNNING"   { "Green" }
        "COMPLETED" { "Cyan" }
        default     { "Yellow" }
    }

    # --- Display ---
    try { Clear-Host } catch { 1..3 | ForEach-Object { Write-Host "" } }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║          AutoDocJson Regeneration Status                        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Job info
    Write-Host "  ┌─ Job Info ──────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Server:       " -NoNewline -ForegroundColor DarkGray; Write-Host "$Server" -ForegroundColor White
    Write-Host "  │  Status:       " -NoNewline -ForegroundColor DarkGray; Write-Host "$status" -ForegroundColor $statusColor
    Write-Host "  │  Started:      " -NoNewline -ForegroundColor DarkGray; Write-Host "$(if ($startedAt) { $startedAt.ToString('yyyy-MM-dd HH:mm:ss') } else { 'unknown' })" -ForegroundColor White
    Write-Host "  │  Elapsed:      " -NoNewline -ForegroundColor DarkGray; Write-Host "$elapsedStr" -ForegroundColor White
    Write-Host "  │  Threads:      " -NoNewline -ForegroundColor DarkGray; Write-Host "$threadCount" -ForegroundColor White
    Write-Host "  │  Log size:     " -NoNewline -ForegroundColor DarkGray; Write-Host "$($logSize) MB" -ForegroundColor White
    Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    # Progress
    Write-Host "  ┌─ Progress ──────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │" -NoNewline -ForegroundColor DarkGray
    Write-Host "  $bar " -NoNewline -ForegroundColor $(if ($pct -ge 75) { "Green" } elseif ($pct -ge 25) { "Yellow" } else { "Red" })
    Write-Host "$($pct)%" -ForegroundColor White
    Write-Host "  │" -ForegroundColor DarkGray
    Write-Host "  │  Completed:    " -NoNewline -ForegroundColor DarkGray; Write-Host "$completedCount / $totalFiles" -ForegroundColor White
    Write-Host "  │  Dispatched:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$dispatched / $totalFiles" -ForegroundColor White
    Write-Host "  │  Rate:         " -NoNewline -ForegroundColor DarkGray; Write-Host "$rate files/min" -ForegroundColor $(if ($rate -gt 2) { "Green" } elseif ($rate -gt 0.5) { "Yellow" } else { "Red" })
    Write-Host "  │  ETA:          " -NoNewline -ForegroundColor DarkGray; Write-Host "$eta" -ForegroundColor White
    Write-Host "  │  Errors:       " -NoNewline -ForegroundColor DarkGray; Write-Host "$($errorLines.Count)" -ForegroundColor $(if ($errorLines.Count -eq 0) { "Green" } else { "Red" })
    Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    # File type breakdown
    Write-Host "  ┌─ File Types Dispatched ─────────────────────────────────────────┐" -ForegroundColor DarkGray
    if ($queueBreakdown) {
        Write-Host "  │  Queue:  $queueBreakdown" -ForegroundColor DarkGray
        Write-Host "  │" -ForegroundColor DarkGray
    }
    $sortedTypes = $typeCounters.GetEnumerator() | Sort-Object Value -Descending
    foreach ($t in $sortedTypes) {
        $typePct = if ($dispatched -gt 0) { [math]::Round(($t.Value / $dispatched) * 100, 0) } else { 0 }
        $typeBar = "█" * [math]::Min([math]::Floor($typePct / 5), 20)
        Write-Host "  │  " -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0,-8}" -f $t.Key) -NoNewline -ForegroundColor Cyan
        Write-Host ("{0,5}" -f $t.Value) -NoNewline -ForegroundColor White
        Write-Host "  $typeBar $($typePct)%" -ForegroundColor DarkCyan
    }
    Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    # Current activity
    Write-Host "  ┌─ Current Activity ──────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Processing:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$currentFile" -ForegroundColor Yellow
    Write-Host "  │  Last done:    " -NoNewline -ForegroundColor DarkGray; Write-Host "$lastCompleted" -NoNewline -ForegroundColor Green; Write-Host " ($lastCompletedTime)" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray

    # Errors
    if ($errorLines.Count -gt 0) {
        Write-Host ""
        Write-Host "  ┌─ Errors ────────────────────────────────────────────────────────┐" -ForegroundColor Red
        foreach ($err in $errorLines | Select-Object -Last 5) {
            $shortErr = $err
            if ($shortErr.Length -gt 64) { $shortErr = $shortErr.Substring($shortErr.Length - 64) }
            Write-Host "  │  $shortErr" -ForegroundColor Red
        }
        if ($errorLines.Count -gt 5) {
            Write-Host "  │  ... and $($errorLines.Count - 5) more" -ForegroundColor DarkRed
        }
        Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor Red
    }

    # Cache info
    if ($cachedFiles -gt 0) {
        Write-Host ""
        Write-Host "  ┌─ Source Cache ──────────────────────────────────────────────────┐" -ForegroundColor DarkGray
        Write-Host "  │  Cached:       $cachedFiles files ($cachedSize) in $($cacheTime)" -ForegroundColor DarkGray
        Write-Host "  └─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    }

    Write-Host ""
    $ts = Get-Date -Format "HH:mm:ss"
    if ($Watch -gt 0) {
        Write-Host "  Last refresh: $ts  |  Refreshing every $($Watch)s  |  Press Ctrl+C to stop" -ForegroundColor DarkGray
    } else {
        Write-Host "  Snapshot at: $ts  |  Run with -Watch 30 for live updates" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# --- Main ---
if ($Watch -gt 0) {
    while ($true) {
        try {
            Show-Status
            Start-Sleep -Seconds $Watch
        }
        catch [System.Management.Automation.PipelineStoppedException] {
            break
        }
    }
} else {
    Show-Status
}
