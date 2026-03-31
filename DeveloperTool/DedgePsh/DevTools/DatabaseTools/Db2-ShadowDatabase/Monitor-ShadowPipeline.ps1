Import-Module GlobalFunctions -Force

$today = (Get-Date).ToString('yyyyMMdd')
$smsNumber = "+4797188358"
$checkIntervalSeconds = 600
$maxChecks = 60
$cutoffTime = (Get-Date).AddMinutes(-90)

$servers = @(
    @{ Name = "INLTST"; Host = "t-no1inltst-db.DEDGE.fk.no" }
    @{ Name = "INLDEV"; Host = "t-no1inltst-db.DEDGE.fk.no" }
)

$finished = @{}
foreach ($srv in $servers) { $finished[$srv.Name] = $false }

function Get-RecentLogLines {
    param([string]$LogPath, [datetime]$After)
    $lines = Get-Content $LogPath -ErrorAction SilentlyContinue
    if (-not $lines) { return @() }
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            try {
                $ts = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                if ($ts -ge $After) { $result.Add($line) }
            } catch {}
        }
    }
    return $result
}

for ($check = 1; $check -le $maxChecks; $check++) {
    $allDone = $true

    foreach ($srv in $servers) {
        if ($finished[$srv.Name]) { continue }
        $allDone = $false

        $logDir = "\\$($srv.Host)\opt\data\AllPwshLog"
        if (-not (Test-Path $logDir)) {
            Write-LogMessage "[$($srv.Name)] Log dir not accessible: $($logDir)" -Level WARN
            continue
        }

        $logFiles = Get-ChildItem -Path $logDir -Filter "*$($today).log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if (-not $logFiles) {
            Write-LogMessage "[$($srv.Name)] No log files for today" -Level WARN
            continue
        }

        $logFile = $logFiles[0].FullName
        $localCopy = Join-Path $env:TEMP "Monitor_$($srv.Name)_$($today).log"
        Copy-Item -Path $logFile -Destination $localCopy -Force

        $content = Get-RecentLogLines -LogPath $localCopy -After $cutoffTime

        $lastStep = ""
        $status = "WAITING"
        foreach ($line in $content) {
            if ($line -match "JOB_STARTED\|.*\|(Run-FullShadowPipeline|Invoke-RemoteShadowPipeline|Invoke-CursorOrchestrator)\|") { $status = "RUNNING" }
            if ($line -match "Starting Step (\d+) \(([^)]+)\)") { $lastStep = "Step $($matches[1]): $($matches[2])"; $status = "RUNNING" }
            if ($line -match "=== Starting (Step-\d+-\S+\.ps1)") { $lastStep = $matches[1] }
            if ($line -match "=== (Step-\d+-\S+\.ps1) completed successfully") { $lastStep = "$($matches[1]) OK" }
            if ($line -match "PIPELINE SUMMARY.*SUCCESS") { $status = "COMPLETED"; $finished[$srv.Name] = $true }
            if ($line -match "Shadow DB OK:") { $status = "COMPLETED"; $finished[$srv.Name] = $true }
            if ($line -match "PIPELINE FAILED|PIPELINE SUMMARY.*FAILED") { $status = "FAILED"; $finished[$srv.Name] = $true }
            if ($line -match "Shadow DB FAILED:") { $status = "FAILED"; $finished[$srv.Name] = $true }
            if ($line -match "Shadow DB KILLED:") { $status = "KILLED"; $finished[$srv.Name] = $true }
            if ($line -match "CHAIN STOPPED:") { $status = "FAILED"; $finished[$srv.Name] = $true }
            if ($line -match "Orchestrator error:") { $status = "CRASHED"; $finished[$srv.Name] = $true }
            if ($line -match "Orchestrator CRASHED:") { $status = "CRASHED"; $finished[$srv.Name] = $true }
        }

        Write-LogMessage "[$($srv.Name)] Check $($check): Status=$($status), LastStep=$($lastStep)" -Level INFO

        if ($finished[$srv.Name]) {
            $smsDetail = ($content | Where-Object { $_ -match "Shadow DB|CHAIN STOPPED|Orchestrator" } | Select-Object -Last 1)
            if ([string]::IsNullOrEmpty($smsDetail)) { $smsDetail = "$($status): $($lastStep)" }
            $smsMsg = "$($srv.Name) pipeline $($status). $($smsDetail)"
            if ($smsMsg.Length -gt 1024) { $smsMsg = $smsMsg.Substring(0, 1024) }
            Send-Sms -Receiver $smsNumber -Message $smsMsg
            Write-LogMessage "[$($srv.Name)] SMS sent: $($smsMsg)" -Level INFO
        }
        elseif ($status -eq "RUNNING" -and $lastStep) {
            $smsMsg = "$($srv.Name) $($status): $($lastStep) (check $check)"
            if ($smsMsg.Length -gt 1024) { $smsMsg = $smsMsg.Substring(0, 1024) }
            Send-Sms -Receiver $smsNumber -Message $smsMsg
            Write-LogMessage "[$($srv.Name)] Progress SMS: $($smsMsg)" -Level INFO
        }
    }

    if ($allDone) {
        Write-LogMessage "All pipelines finished. Monitor exiting." -Level INFO
        $summaryMsg = "Monitor: INLTST=$($finished['INLTST'] ? 'done' : 'unknown'), INLDEV=$($finished['INLDEV'] ? 'done' : 'unknown'). Both complete."
        Send-Sms -Receiver $smsNumber -Message $summaryMsg
        break
    }

    Write-LogMessage "Waiting $($checkIntervalSeconds)s before next check ($($check)/$($maxChecks))..." -Level INFO
    Start-Sleep -Seconds $checkIntervalSeconds
}

if (-not $allDone) {
    $smsMsg = "Monitor timeout ($($maxChecks) checks). INLTST=$($finished['INLTST']), INLDEV=$($finished['INLDEV'])"
    Send-Sms -Receiver $smsNumber -Message $smsMsg
    Write-LogMessage $smsMsg -Level WARN
}
