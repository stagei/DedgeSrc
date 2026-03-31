<#
.SYNOPSIS
    Reports pipeline progress for INLTST and INLDEV every 10 minutes.
#>
Import-Module GlobalFunctions -Force

$servers = @(
    @{ Name = "INLTST"; Host = "t-no1inltst-db.DEDGE.fk.no" }
)
$today = (Get-Date).ToString('yyyyMMdd')
$cutoff = (Get-Date).AddMinutes(-20)

foreach ($srv in $servers) {
    $logPath = "\\$($srv.Host)\opt\data\AllPwshLog\FkLog_$($today).log"
    $localCopy = Join-Path $env:TEMP "Report_$($srv.Name).log"
    try {
        Copy-Item $logPath $localCopy -Force -ErrorAction Stop
        $lines = Get-Content $localCopy -ErrorAction SilentlyContinue
        $recent = $lines | ForEach-Object {
            if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
                $ts = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                if ($ts -ge $cutoff) { $_ }
            }
        }
        $status = "RUNNING"
        $lastStep = ""
        foreach ($line in $recent) {
            if ($line -match "JOB_STARTED\|.*\|(Run-FullShadowPipeline|Invoke-RemoteShadowPipeline|Invoke-CursorOrchestrator)\|") { $lastStep = "Pipeline started" }
            if ($line -match "Starting Step (\d+)") { $lastStep = "Step $($matches[1])" }
            if ($line -match "JOB_STARTED\|.*\|(Step-\d+-\S+)\|") { $lastStep = $matches[1] }
            if ($line -match "PIPELINE SUMMARY.*SUCCESS") { $status = "COMPLETED"; break }
            if ($line -match "PIPELINE FAILED") { $status = "FAILED"; break }
        }
        Write-LogMessage "[$($srv.Name)] $($status): $($lastStep)" -Level INFO
    }
    catch {
        Write-LogMessage "[$($srv.Name)] Error: $($_.Exception.Message)" -Level WARN
    }
}
