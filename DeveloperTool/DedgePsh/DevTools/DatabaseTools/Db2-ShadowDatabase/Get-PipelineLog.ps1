param(
    [Parameter(Mandatory)]
    [string]$ServerFqdn,

    [Parameter(Mandatory = $false)]
    [string]$SearchPattern = "Shadow|CHAIN|Orchestrator|ERROR|FAILED|Step-|exit code"
)

$today = (Get-Date).ToString('yyyyMMdd')
$logDir = "\\$($ServerFqdn)\opt\data\AllPwshLog"

if (-not (Test-Path $logDir)) {
    Write-Host "ERROR: Cannot access $($logDir)"
    exit 1
}

$logFiles = Get-ChildItem -Path $logDir -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*$($today)*" -and $_.Extension -eq '.log' } |
    Sort-Object LastWriteTime -Descending

if (-not $logFiles) {
    Write-Host "No log files for today at $($logDir)"
    exit 1
}

$logFile = $logFiles[0]
Write-Host "Source: $($logFile.FullName) ($($logFile.Length) bytes)"

$localCopy = Join-Path $env:TEMP "PipelineLog_$($ServerFqdn.Split('.')[0])_$($today).log"
Copy-Item -Path $logFile.FullName -Destination $localCopy -Force

$lines = Get-Content $localCopy
$matched = $lines | Where-Object { $_ -match $SearchPattern }
Write-Host "--- Matched $($matched.Count) lines out of $($lines.Count) total ---"
$matched | ForEach-Object { Write-Host $_ }
