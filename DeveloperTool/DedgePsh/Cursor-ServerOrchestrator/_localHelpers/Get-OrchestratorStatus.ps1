<#
.SYNOPSIS
    Checks the state of all remote Cursor-ServerOrchestrator instances by
    sending a probe command and waiting for a response.

.DESCRIPTION
    For each valid server:
    1. Checks if the orchestrator data folder exists via UNC
    2. Reports all currently running slots (running_command_*.json)
    3. Sends a lightweight probe (hostname) to idle servers using a suffixed slot
    4. Polls up to ~70 seconds for each server to respond
    5. Reports: RESPONDING, BUSY, NO_RESPONSE, or UNREACHABLE

.PARAMETER TimeoutSeconds
    Max seconds to wait for probe responses. Default 70 (orchestrator polls every 60s).

.PARAMETER PollIntervalSeconds
    How often to check for results during the wait. Default 5.

.EXAMPLE
    .\Get-OrchestratorStatus.ps1
    .\Get-OrchestratorStatus.ps1 -TimeoutSeconds 90
#>
param(
    [int]$TimeoutSeconds = 70,
    [int]$PollIntervalSeconds = 5
)

Import-Module GlobalFunctions -Force

$_sharedPath = Join-Path (Split-Path $PSScriptRoot) "_helpers" "_Shared.ps1"
. $_sharedPath

$servers = Get-ValidServerNameList
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$probeSuffix = Get-SlotSuffix -Project "orchestrator-probe"

Write-Host ""
Write-Host "======================================================================"
Write-Host "  Cursor-ServerOrchestrator Probe  —  $timestamp"
Write-Host "======================================================================"
Write-Host ""

$probeScript = 'hostname'
$encodedProbe = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($probeScript))
$inlineScriptPath = '%OptPath%\DedgePshApps\Cursor-ServerOrchestrator\_helpers\Run-InlineScript.ps1'

$serverStates = [System.Collections.Generic.List[PSCustomObject]]::new()

# Phase 1: Classify servers, report running slots, and submit probes
Write-Host "Phase 1: Checking $($servers.Count) servers and submitting probes..."
Write-Host ""

foreach ($server in $servers) {
    $hostname = $server.Split('.')[0]
    $serverPath = Get-OrchestratorServerPath -ServerName $server

    if (-not (Test-Path $serverPath)) {
        $serverStates.Add([PSCustomObject]@{
            Server           = $hostname
            FullName         = $server
            Status           = "UNREACHABLE"
            Detail           = "Folder not found"
            RunningSlots     = @()
            Probed           = $false
            BaselineModTime  = $null
            ResponseTime     = $null
        })
        Write-Host "  $($hostname): UNREACHABLE (no data folder)" -ForegroundColor Red
        continue
    }

    # Report all running slots on this server
    $runningFiles = Get-ChildItem -Path $serverPath -Filter "running_command_*.json" -File -ErrorAction SilentlyContinue
    $runningSlots = @()
    if ($runningFiles) {
        foreach ($rf in $runningFiles) {
            try {
                $rContent = Get-Content $rf.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                $startedAt = if ($rContent.startedAt -is [datetime]) { $rContent.startedAt } else {
                    [datetime]::Parse($rContent.startedAt, [System.Globalization.CultureInfo]::InvariantCulture)
                }
                $elapsed = (Get-Date) - $startedAt
                $elapsedFmt = '{0:D2}:{1:D2}:{2:D2}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
                $slotInfo = "PID=$($rContent.pid) | $($rContent.command) | $($elapsedFmt) | project=$($rContent.project)"
                $runningSlots += $slotInfo
                Write-Host "  $($hostname): RUNNING [$($rf.Name -replace '^running_command_|\.json$','')] — $($slotInfo)" -ForegroundColor Yellow
            } catch {
                Write-Host "  $($hostname): RUNNING [$($rf.Name)] — (parse error)" -ForegroundColor Yellow
            }
        }
    }

    # Also check for legacy running_command.json
    $legacyRunning = Join-Path $serverPath "running_command.json"
    if (Test-Path $legacyRunning) {
        try {
            $rContent = Get-Content $legacyRunning -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            $startedAt = if ($rContent.startedAt -is [datetime]) { $rContent.startedAt } else {
                [datetime]::Parse($rContent.startedAt, [System.Globalization.CultureInfo]::InvariantCulture)
            }
            $elapsed = (Get-Date) - $startedAt
            $elapsedFmt = '{0:D2}:{1:D2}:{2:D2}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
            $slotInfo = "PID=$($rContent.pid) | $($rContent.command) | $($elapsedFmt) | (legacy)"
            $runningSlots += $slotInfo
            Write-Host "  $($hostname): RUNNING [legacy] — $($slotInfo)" -ForegroundColor Yellow
        } catch {}
    }

    # Get baseline for probe result file
    $probeResultFile = Join-Path $serverPath "last_result_$($probeSuffix).json"
    $baselineMod = $null
    if (Test-Path $probeResultFile) {
        $baselineMod = (Get-Item $probeResultFile).LastWriteTime
    }

    # Submit probe (probes use their own slot, so they don't conflict with running jobs)
    try {
        Write-CommandFile -ServerName $server `
            -Command $inlineScriptPath `
            -Arguments "-EncodedCommand $encodedProbe" `
            -Project "orchestrator-probe" `
            -CaptureOutput $true | Out-Null

        $serverStates.Add([PSCustomObject]@{
            Server           = $hostname
            FullName         = $server
            Status           = "WAITING"
            Detail           = ""
            RunningSlots     = $runningSlots
            Probed           = $true
            BaselineModTime  = $baselineMod
            ResponseTime     = $null
        })
        if ($runningSlots.Count -eq 0) {
            Write-Host "  $($hostname): Probe sent (idle)" -ForegroundColor Cyan
        } else {
            Write-Host "  $($hostname): Probe sent ($($runningSlots.Count) slot(s) running)" -ForegroundColor Cyan
        }
    }
    catch {
        $serverStates.Add([PSCustomObject]@{
            Server           = $hostname
            FullName         = $server
            Status           = "PROBE_FAILED"
            Detail           = "Could not write command file: $($_.Exception.Message)"
            RunningSlots     = $runningSlots
            Probed           = $false
            BaselineModTime  = $null
            ResponseTime     = $null
        })
        Write-Host "  $($hostname): PROBE FAILED — $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Phase 2: Poll for results from the probe slot
$probedServers = $serverStates | Where-Object { $_.Probed -eq $true }

if ($probedServers.Count -eq 0) {
    Write-Host ""
    Write-Host "No servers to probe."
}
else {
    Write-Host ""
    Write-Host "Phase 2: Waiting up to $($TimeoutSeconds)s for $($probedServers.Count) server(s) to respond..."
    Write-Host "  (Orchestrator polls every ~60s, checking every $($PollIntervalSeconds)s)"
    Write-Host ""

    $probeStart = Get-Date
    $remaining = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in $probedServers) { $remaining.Add($p) }

    while ($remaining.Count -gt 0 -and ((Get-Date) - $probeStart).TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $PollIntervalSeconds
        $elapsed = [math]::Round(((Get-Date) - $probeStart).TotalSeconds)

        $stillWaiting = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($entry in $remaining) {
            $serverPath = Get-OrchestratorServerPath -ServerName $entry.FullName
            $probeResultFile = Join-Path $serverPath "last_result_$($probeSuffix).json"

            $responded = $false
            if (Test-Path $probeResultFile) {
                $currentMod = (Get-Item $probeResultFile).LastWriteTime
                if ($null -eq $entry.BaselineModTime -or $currentMod -gt $entry.BaselineModTime) {
                    $responded = $true
                }
            }

            if ($responded) {
                $result = Read-ResultFile -ServerName $entry.FullName -Project "orchestrator-probe"
                $responseSeconds = [math]::Round(((Get-Date) - $probeStart).TotalSeconds)
                $entry.Status = "RESPONDING"
                $entry.Detail = "$($entry.Server) - $($result.completedAt)"
                $entry.ResponseTime = $responseSeconds
                Write-Host "  $($entry.Server): RESPONDING after $($responseSeconds)s — [$($result.status)] output=$($result.output.Trim())" -ForegroundColor Green
            }
            else {
                $stillWaiting.Add($entry)
            }
        }

        $remaining = $stillWaiting

        if ($remaining.Count -gt 0) {
            Write-Host "  ... $($elapsed)s elapsed, $($remaining.Count) still waiting" -ForegroundColor DarkGray
        }
    }

    foreach ($entry in $remaining) {
        $entry.Status = "NO_RESPONSE"
        $entry.Detail = "No result after $($TimeoutSeconds)s"
        Write-Host "  $($entry.Server): NO RESPONSE within $($TimeoutSeconds)s" -ForegroundColor Red
    }
}

# Phase 3: Final report as summary table
$responding  = $serverStates | Where-Object { $_.Status -eq "RESPONDING" }
$busy        = $serverStates | Where-Object { $_.RunningSlots.Count -gt 0 }
$noResponse  = $serverStates | Where-Object { $_.Status -eq "NO_RESPONSE" }
$unreachable = $serverStates | Where-Object { $_.Status -eq "UNREACHABLE" }
$probeFailed = $serverStates | Where-Object { $_.Status -eq "PROBE_FAILED" }

$respondTimes = ($responding | ForEach-Object { $_.ResponseTime }) | Sort-Object
$minTime = if ($respondTimes.Count -gt 0) { $respondTimes[0] } else { 0 }
$maxTime = if ($respondTimes.Count -gt 0) { $respondTimes[-1] } else { 0 }

$respondingDetail = if ($responding.Count -gt 0) {
    "All replied within $($minTime)-$($maxTime)s with correct hostname"
} else { "--" }

$busyDetail = if ($busy.Count -gt 0) {
    ($busy | ForEach-Object { "$($_.Server) ($($_.RunningSlots.Count) slot(s))" }) -join ', '
} else { "--" }

$noResponseDetail = if ($noResponse.Count -gt 0) {
    ($noResponse | ForEach-Object { $_.Server }) -join ', '
} else { "--" }

$unreachableDetail = if ($unreachable.Count -gt 0) {
    (($unreachable | ForEach-Object { $_.Server }) -join ', ') + " (no data folder)"
} else { "--" }

$probeFailedDetail = if ($probeFailed.Count -gt 0) {
    ($probeFailed | ForEach-Object { $_.Server }) -join ', '
} else { "--" }

$reportRows = @(
    [PSCustomObject]@{ Status = "RESPONDING";   Count = $responding.Count;  Details = $respondingDetail }
    [PSCustomObject]@{ Status = "RUNNING SLOTS"; Count = ($busy | ForEach-Object { $_.RunningSlots.Count } | Measure-Object -Sum).Sum; Details = $busyDetail }
    [PSCustomObject]@{ Status = "NO RESPONSE";  Count = $noResponse.Count;  Details = $noResponseDetail }
    [PSCustomObject]@{ Status = "UNREACHABLE";  Count = $unreachable.Count; Details = $unreachableDetail }
)
if ($probeFailed.Count -gt 0) {
    $reportRows += [PSCustomObject]@{ Status = "PROBE FAILED"; Count = $probeFailed.Count; Details = $probeFailedDetail }
}

Write-Host ""
Write-Host "======================================================================"
Write-Host "  Final Report  —  $($serverStates.Count) servers checked"
Write-Host "======================================================================"
Write-Host ""

$reportRows | Format-Table -Property Status, Count, Details -AutoSize | Out-String | Write-Host

return $serverStates
