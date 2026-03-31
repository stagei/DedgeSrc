<#
.SYNOPSIS
    Real-time log tail for the shadow database pipeline.
    Polls the remote log every 2 seconds and shows new lines.

.PARAMETER Server
    Server hostname. Default: t-no1inltst-db

.PARAMETER IntervalSeconds
    Poll interval. Default: 2

.PARAMETER Filter
    Optional regex filter to highlight/show only matching lines.

.EXAMPLE
    .\_tail_log.ps1
    .\_tail_log.ps1 -Filter "ERROR|WARN|Step|Phase"
    .\_tail_log.ps1 -Server t-no1fkmvft-db
#>
param(
    [string]$Server = "t-no1inltst-db",
    [int]$IntervalSeconds = 2,
    [string]$Filter = ""
)

$logDir = "\\$($Server).DEDGE.fk.no\opt\data\AllPwshLog"
$localCopy = Join-Path $env:TEMP "TailLog_$($Server).log"
$lastLineCount = 0
$noNewLines = 0

Write-Host "=== Tailing log on $($Server) (Ctrl+C to stop) ===" -ForegroundColor Cyan
Write-Host "Log dir: $($logDir)" -ForegroundColor DarkGray
if ($Filter) { Write-Host "Filter: $($Filter)" -ForegroundColor DarkGray }
Write-Host ""

while ($true) {
    $today = (Get-Date).ToString('yyyyMMdd')
    $logFile = Join-Path $logDir "FkLog_$($today).log"

    if (-not (Test-Path $logFile)) {
        if ($noNewLines % 15 -eq 0) {
            Write-Host "Waiting for $($logFile)..." -ForegroundColor DarkGray
        }
        $noNewLines++
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    try {
        Copy-Item -Path $logFile -Destination $localCopy -Force -ErrorAction Stop
        $lines = Get-Content $localCopy -Encoding UTF8 -ErrorAction Stop

        if ($lines.Count -gt $lastLineCount) {
            $newLines = $lines[$lastLineCount..($lines.Count - 1)]
            foreach ($line in $newLines) {
                if ($Filter -and $line -notmatch $Filter) { continue }

                if ($line -match '\[ERROR\]|\[FATAL\]') {
                    Write-Host $line -ForegroundColor Red
                }
                elseif ($line -match '\[WARN\]') {
                    Write-Host $line -ForegroundColor Yellow
                }
                elseif ($line -match 'JOB_STARTED|JOB_COMPLETED|=== Starting|=== .* completed') {
                    Write-Host $line -ForegroundColor Green
                }
                elseif ($line -match 'Phase \d|Step \d') {
                    Write-Host $line -ForegroundColor Cyan
                }
                else {
                    Write-Host $line
                }
            }
            $lastLineCount = $lines.Count
            $noNewLines = 0
        }
        else {
            $noNewLines++
            if ($noNewLines % 30 -eq 0) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No new output for $($noNewLines * $IntervalSeconds)s..." -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Copy failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    Start-Sleep -Seconds $IntervalSeconds
}
