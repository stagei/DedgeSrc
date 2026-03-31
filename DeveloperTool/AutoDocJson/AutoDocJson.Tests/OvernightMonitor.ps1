<#
.SYNOPSIS
    Overnight Monitor - Sends SMS statistics every 30 minutes
#>

$script:Config = @{
    SmsRecipient = "+4797188358"
    OutputFolder = "C:\opt\Webs\AutoDoc"
    IntervalMinutes = 30
    DeadlineTime = (Get-Date).Date.AddDays(1).AddHours(9)  # 09:00 AM tomorrow
    StartTime = Get-Date
    LastHtmlCount = 0
    LastMmdCount = 0
}

function Send-StatsSms {
    param([string]$Message)
    
    try {
        Import-Module GlobalFunctions -Force -ErrorAction Stop
        Send-Sms -Receiver $script:Config.SmsRecipient -Message $Message
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] SMS sent: $Message" -ForegroundColor Green
    }
    catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] SMS failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-FileStats {
    $html = @(Get-ChildItem $script:Config.OutputFolder -Filter "*.html" -ErrorAction SilentlyContinue)
    $mmd = @(Get-ChildItem $script:Config.OutputFolder -Filter "*.mmd" -ErrorAction SilentlyContinue)
    $err = @(Get-ChildItem $script:Config.OutputFolder -Filter "*.err" -ErrorAction SilentlyContinue)
    
    return @{
        HtmlCount = $html.Count
        MmdCount = $mmd.Count
        ErrCount = $err.Count
        HtmlDelta = $html.Count - $script:Config.LastHtmlCount
        MmdDelta = $mmd.Count - $script:Config.LastMmdCount
    }
}

function Get-ProcessStatus {
    $runner = Get-Process -Id 27868 -ErrorAction SilentlyContinue
    $autodoc = Get-Process -Id 29800 -ErrorAction SilentlyContinue
    
    # Also check for any AutoDoc processes if PIDs changed
    if (-not $autodoc) {
        $autodoc = Get-Process pwsh -ErrorAction SilentlyContinue | Where-Object {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -EA 0).CommandLine
            $cmd -match 'AutoDocBatchRunner'
        } | Select-Object -First 1
    }
    
    return @{
        RunnerOk = $null -ne $runner
        AutoDocOk = $null -ne $autodoc
        AutoDocCpu = if ($autodoc) { [int]$autodoc.CPU } else { 0 }
    }
}

# Main monitoring loop
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "AutoDoc Overnight Monitor Started" -ForegroundColor Cyan
Write-Host "SMS every 30 minutes to $($script:Config.SmsRecipient)" -ForegroundColor Cyan
Write-Host "Deadline: $($script:Config.DeadlineTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

$updateCount = 0

while ((Get-Date) -lt $script:Config.DeadlineTime) {
    $updateCount++
    $elapsed = (Get-Date) - $script:Config.StartTime
    $elapsedStr = "{0:hh\:mm}" -f $elapsed
    
    $stats = Get-FileStats
    $proc = Get-ProcessStatus
    
    $status = if ($proc.AutoDocOk) { "Running" } else { "Stopped" }
    
    $msg = "AutoDocJson $($elapsedStr): HTML=$($stats.HtmlCount)(+$($stats.HtmlDelta)) MMD=$($stats.MmdCount)(+$($stats.MmdDelta)) Err=$($stats.ErrCount) [$status]"
    
    if ($msg.Length -gt 1024) {
        $msg = $msg.Substring(0, 1021) + "..."
    }
    
    Send-StatsSms -Message $msg
    
    # Update last counts
    $script:Config.LastHtmlCount = $stats.HtmlCount
    $script:Config.LastMmdCount = $stats.MmdCount
    
    # Log to console
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Update #$updateCount - HTML: $($stats.HtmlCount), MMD: $($stats.MmdCount), Errors: $($stats.ErrCount)" -ForegroundColor White
    
    # Check if processes died and need restart
    if (-not $proc.AutoDocOk -and -not $proc.RunnerOk) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WARNING: Both processes stopped!" -ForegroundColor Red
        Send-StatsSms -Message "AutoDocJson ALERT: Processes stopped! Check system."
    }
    
    # Wait 30 minutes
    $nextCheck = (Get-Date).AddMinutes($script:Config.IntervalMinutes)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Next update at $($nextCheck.ToString('HH:mm'))" -ForegroundColor Gray
    
    # Break into smaller sleep intervals to check deadline
    $sleepEnd = [Math]::Min($nextCheck.Ticks, $script:Config.DeadlineTime.Ticks)
    while ((Get-Date).Ticks -lt $sleepEnd) {
        Start-Sleep -Seconds 60
    }
}

# Final status at deadline
$stats = Get-FileStats
$proc = Get-ProcessStatus
$elapsed = (Get-Date) - $script:Config.StartTime

$finalMsg = "AutoDocJson FINAL: HTML=$($stats.HtmlCount) MMD=$($stats.MmdCount) Err=$($stats.ErrCount) Time=$("{0:hh\:mm}" -f $elapsed)"
Send-StatsSms -Message $finalMsg

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Overnight Monitor Complete at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
