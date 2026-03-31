<#
.SYNOPSIS
    Monitors the shadow database pipeline log on the current test server.

.DESCRIPTION
    Copies today's and yesterday's log files from the remote server via UNC,
    then displays the latest entries. Repeats every N seconds until stopped
    or the pipeline finishes/fails.

    Uses the config.*.json files to determine which server to monitor.

.PARAMETER Server
    Override the target server hostname. Default: auto-detect from config.inltst.json.

.PARAMETER TailLines
    Number of lines to show from the end of each log file. Default: 60.

.PARAMETER IntervalSeconds
    Seconds between log checks. Default: 60.

.PARAMETER Once
    Run once and exit (no polling loop).

.EXAMPLE
    .\_helpers\_check_log.ps1
    .\_helpers\_check_log.ps1 -Server t-no1fkmvft-db -TailLines 100
    .\_helpers\_check_log.ps1 -Once
#>
param(
    [string]$Server,
    [int]$TailLines = 60,
    [int]$IntervalSeconds = 60,
    [switch]$Once
)

Import-Module GlobalFunctions -Force

$scriptRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $scriptRoot "_helpers\_Shared.ps1")

if ([string]::IsNullOrWhiteSpace($Server)) {
    $cfgFiles = Get-ChildItem -Path $scriptRoot -Filter "config.*.json" -File -ErrorAction SilentlyContinue
    foreach ($f in $cfgFiles) {
        $cfg = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($cfg.ServerFqdn -match 'inltst') {
            $Server = $cfg.ServerFqdn.Split('.')[0]
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($Server)) {
        $first = $cfgFiles | Select-Object -First 1
        if ($first) {
            $cfg = Get-Content $first.FullName -Raw | ConvertFrom-Json
            $Server = $cfg.ServerFqdn.Split('.')[0]
        }
    }
    if ([string]::IsNullOrWhiteSpace($Server)) {
        throw "No server found. Pass -Server or ensure config.*.json files exist."
    }
}

$logDir = "\\$Server\opt\data\AllPwshLog"
$localDir = Join-Path $env:TEMP "ShadowDbMonitor"
if (-not (Test-Path $localDir)) { New-Item -Path $localDir -ItemType Directory -Force | Out-Null }

function Copy-AndTail {
    param([string]$RemotePath, [string]$Label, [int]$Lines)

    if (-not (Test-Path $RemotePath)) {
        Write-Host "  [$Label] File not found: $RemotePath" -ForegroundColor DarkGray
        return $null
    }

    $localFile = Join-Path $localDir (Split-Path $RemotePath -Leaf)
    Copy-Item -Path $RemotePath -Destination $localFile -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $localFile)) {
        Write-Host "  [$Label] Copy failed" -ForegroundColor Red
        return $null
    }

    $content = Get-Content $localFile -Tail $Lines -ErrorAction SilentlyContinue
    return $content
}

function Get-PipelineStatus {
    param([string[]]$Lines)

    $status = "UNKNOWN"
    $lastStep = ""
    $lastError = ""

    foreach ($line in $Lines) {
        if ($line -match 'Run-FullShadowPipeline|Invoke-RemoteShadowPipeline|Invoke-CursorOrchestrator|Orchestrator received command:') { $status = "RUNNING" }
        if ($line -match '=== Starting (Step-\S+\.ps1) ===') { $lastStep = $matches[1]; $status = "RUNNING" }
        if ($line -match '=== (Step-\S+\.ps1) completed successfully ===') { $lastStep = "$($matches[1]) OK" }
        if ($line -match 'Shadow DB OK:') { $status = "COMPLETED" }
        if ($line -match 'Shadow DB FAILED:') { $status = "FAILED" }
        if ($line -match 'Shadow DB KILLED:') { $status = "KILLED" }
        if ($line -match 'CHAIN STOPPED:.*failed') { $status = "FAILED" }
        if ($line -match 'Orchestrator error:') { $status = "CRASHED" }
        if ($line -match '\|ERROR\|') { $lastError = $line }
    }

    return @{ Status = $status; LastStep = $lastStep; LastError = $lastError }
}

$checkCount = 0
while ($true) {
    $checkCount++
    $now = Get-Date
    $today = $now.ToString('yyyyMMdd')
    $yesterday = $now.AddDays(-1).ToString('yyyyMMdd')

    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  Shadow DB Pipeline Monitor — $Server" -ForegroundColor Cyan
    Write-Host "  Check #$checkCount at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    $allLines = @()

    $yesterdayPath = Join-Path $logDir "FkLog_$yesterday.log"
    $yesterdayLines = Copy-AndTail -RemotePath $yesterdayPath -Label "Yesterday ($yesterday)" -Lines $TailLines
    if ($yesterdayLines) {
        $allLines += $yesterdayLines
        Write-Host "`n--- Yesterday ($yesterday) — last $($yesterdayLines.Count) lines ---" -ForegroundColor DarkYellow
        foreach ($line in $yesterdayLines) {
            if ($line -match '\|ERROR\|') { Write-Host $line -ForegroundColor Red }
            elseif ($line -match '\|WARN\|') { Write-Host $line -ForegroundColor Yellow }
            elseif ($line -match 'JOB_STARTED|JOB_COMPLETED|JOB_FAILED') { Write-Host $line -ForegroundColor Magenta }
            elseif ($line -match '=== Starting|=== .* completed') { Write-Host $line -ForegroundColor Green }
            else { Write-Host $line -ForegroundColor Gray }
        }
    }

    $todayPath = Join-Path $logDir "FkLog_$today.log"
    $todayLines = Copy-AndTail -RemotePath $todayPath -Label "Today ($today)" -Lines $TailLines
    if ($todayLines) {
        $allLines += $todayLines
        Write-Host "`n--- Today ($today) — last $($todayLines.Count) lines ---" -ForegroundColor Cyan
        foreach ($line in $todayLines) {
            if ($line -match '\|ERROR\|') { Write-Host $line -ForegroundColor Red }
            elseif ($line -match '\|WARN\|') { Write-Host $line -ForegroundColor Yellow }
            elseif ($line -match 'JOB_STARTED|JOB_COMPLETED|JOB_FAILED') { Write-Host $line -ForegroundColor Magenta }
            elseif ($line -match '=== Starting|=== .* completed') { Write-Host $line -ForegroundColor Green }
            else { Write-Host $line -ForegroundColor Gray }
        }
    }

    if (-not $yesterdayLines -and -not $todayLines) {
        Write-Host "`n  No log files found on $Server" -ForegroundColor Red
    }

    $pipelineInfo = Get-PipelineStatus -Lines $allLines
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "  Pipeline: $($pipelineInfo.Status)  |  Last step: $($pipelineInfo.LastStep)" -ForegroundColor $(
        switch ($pipelineInfo.Status) {
            "COMPLETED" { "Green" }
            "RUNNING"   { "Yellow" }
            "FAILED"    { "Red" }
            "KILLED"    { "Red" }
            "CRASHED"   { "Red" }
            default     { "Gray" }
        }
    )
    if ($pipelineInfo.LastError) {
        Write-Host "  Last error: $($pipelineInfo.LastError.Substring(0, [Math]::Min(120, $pipelineInfo.LastError.Length)))" -ForegroundColor Red
    }
    Write-Host "========================================================" -ForegroundColor Cyan

    if ($Once) { break }

    if ($pipelineInfo.Status -in @("COMPLETED", "FAILED", "KILLED", "CRASHED")) {
        Write-Host "`n  Pipeline finished with status: $($pipelineInfo.Status). Monitor stopping." -ForegroundColor Magenta
        break
    }

    Write-Host "`n  Next check in $IntervalSeconds seconds... (Ctrl+C to stop)" -ForegroundColor DarkGray
    Start-Sleep -Seconds $IntervalSeconds
}
