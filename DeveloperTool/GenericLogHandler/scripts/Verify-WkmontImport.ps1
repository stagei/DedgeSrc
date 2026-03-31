<#
.SYNOPSIS
    Verifies that \\DEDGE.fk.no\erpprog\COBNT\WKMONIT.LOG is imported into log_entries and as jobs.

.DESCRIPTION
    Calls the Web API to:
    1. Count log entries whose source_file contains WKMONIT.LOG
    2. List job names/status from the job log (entries with JobName/JobStatus from WKMONIT parsing)

.PARAMETER ApiBaseUrl
    Base URL of the Web API. Default: http://localhost:8110
#>
[CmdletBinding()]
param(
    [string]$ApiBaseUrl = "http://localhost:8110"
)

$ErrorActionPreference = "Stop"
try {
    Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
} catch {
    function Write-LogMessage { param([string]$Message, [string]$Level = "INFO") Write-Host "[$Level] $Message" }
}

Write-Host ""
Write-Host "Verifying WKMONIT.LOG import at $ApiBaseUrl" -ForegroundColor Cyan
Write-Host ""

# Health
try {
    $health = Invoke-WebRequest -Uri "$ApiBaseUrl/health" -UseBasicParsing -TimeoutSec 10 -AllowUnencryptedAuthentication -ErrorAction Stop
    Write-Host "[OK] API health: $($health.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] API not reachable: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Ensure Web API and Import Service are running (e.g. via Build-And-Publish.ps1)." -ForegroundColor Yellow
    exit 1
}

# 1. Log entries from WKMONIT.LOG (source_file contains WKMONIT.LOG)
Write-Host ""
Write-Host "--- Log entries (source_file contains WKMONIT.LOG) ---" -ForegroundColor Yellow
try {
    $body = @{ SourceFile = "WKMONIT.LOG"; PageSize = 5 } | ConvertTo-Json
    $search = Invoke-RestMethod -Uri "$ApiBaseUrl/api/Logs/search" -Method POST -ContentType "application/json" -Body $body -AllowUnencryptedAuthentication -ErrorAction Stop
    $total = $search.Data.TotalCount
    $items = $search.Data.Items
    if ($null -eq $total) { $total = 0 }
    Write-Host "Total log entries: $total" -ForegroundColor $(if ($total -gt 0) { "Green" } else { "Yellow" })
    if ($items -and $items.Count -gt 0) {
        Write-Host "Sample (first 2):"
        $items[0..([Math]::Min(1, $items.Count - 1))] | ForEach-Object {
            $msg = if ($_.Message.Length -gt 70) { $_.Message.Substring(0, 70) + "..." } else { $_.Message }
            Write-Host "  $($_.Timestamp) | $($_.Level) | JobName=$($_.JobName) | JobStatus=$($_.JobStatus) | $msg"
        }
    } else {
        Write-Host "No entries yet. Wait for Import Service to run a cycle (e.g. 60–90s) and run this script again." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[FAIL] Log search: $($_.Exception.Message)" -ForegroundColor Red
}

# 2. Jobs (job log: entries with JobName/JobStatus from WKMONIT)
Write-Host ""
Write-Host "--- Job log (entries with JobName/JobStatus from WKMONIT) ---" -ForegroundColor Yellow
try {
    $jobs = Invoke-RestMethod -Uri "$ApiBaseUrl/api/JobStatus/jobs?limit=50" -Method GET -AllowUnencryptedAuthentication -ErrorAction Stop
    $list = $jobs.Data
    if (-not $list) { $list = @() }
    # Filter to job names that look like WKMONIT (WKSTYR, D4BSALG, WKNATT1, P-NO1FKMPR, etc.)
    $wkmontJobs = $list | Where-Object { $_.JobName -match "^(WK|D4B|P-NO1|DB2|STREAMSERV|FKSNAPDB|WKOPTORD|WKEDIUT)" }
    $count = if ($wkmontJobs) { $wkmontJobs.Count } else { 0 }
    Write-Host "Job names from WKMONIT (WK*, D4B*, P-NO1*, etc.): $count" -ForegroundColor $(if ($count -gt 0) { "Green" } else { "Yellow" })
    if ($wkmontJobs -and $wkmontJobs.Count -gt 0) {
        Write-Host "Sample (first 5):"
        $wkmontJobs[0..([Math]::Min(4, $wkmontJobs.Count - 1))] | ForEach-Object {
            Write-Host "  $($_.JobName) | $($_.JobStatus) | Count=$($_.OccurrenceCount) | Last=$($_.LastSeen)"
        }
    } else {
        Write-Host "No WKMONIT job names yet. Ensure Import Service has run and COBNT WKMONIT source is enabled." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[FAIL] Job status: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host ""
