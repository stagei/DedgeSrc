# Author: Geir Helge Starholm, www.dEdge.no
# Purpose: Kill all PowerShell processes running AutoDoc parsers or batch runner
# Usage: .\Stop-AutoDocProcesses.ps1

param()

$ErrorActionPreference = 'Continue'

# Patterns to match AutoDoc-related processes
$autoDocPatterns = @(
    'AutoDoc',
    'AutoDocBatchRunner',
    'CblParse',
    'Ps1Parse',
    'RexParse',
    'BatParse',
    'SqlParse',
    'CSharpParse',
    'CSharpEcosystemParse',
    'AutodocFunctions'
)

# Get current process ID to avoid killing ourselves
$currentPid = $PID

Write-Host "=== AutoDoc Process Killer ===" -ForegroundColor Cyan
Write-Host "Current PID: $currentPid (will be preserved)" -ForegroundColor Gray
Write-Host ""

# Get all pwsh processes except current one
$pwshProcesses = Get-Process -Name pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentPid }

if (-not $pwshProcesses -or $pwshProcesses.Count -eq 0) {
    Write-Host "No other PowerShell processes found." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($pwshProcesses.Count) PowerShell processes to check..." -ForegroundColor Yellow
Write-Host ""

$processesToKill = @()

foreach ($proc in $pwshProcesses) {
    try {
        $cmdLine = $proc.CommandLine
        if (-not $cmdLine) {
            # Try alternative method to get command line
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
        }
        
        $isAutoDoc = $false
        $matchedPattern = ""
        
        foreach ($pattern in $autoDocPatterns) {
            if ($cmdLine -match $pattern) {
                $isAutoDoc = $true
                $matchedPattern = $pattern
                break
            }
        }
        
        if ($isAutoDoc) {
            $processesToKill += [PSCustomObject]@{
                Id = $proc.Id
                StartTime = $proc.StartTime
                Runtime = if ($proc.StartTime) { (Get-Date) - $proc.StartTime } else { "Unknown" }
                MatchedPattern = $matchedPattern
                CommandLine = if ($cmdLine.Length -gt 80) { $cmdLine.Substring(0, 80) + "..." } else { $cmdLine }
            }
        }
    }
    catch {
        Write-Host "  Could not inspect process $($proc.Id): $_" -ForegroundColor DarkGray
    }
}

if ($processesToKill.Count -eq 0) {
    Write-Host "No AutoDoc-related processes found." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($processesToKill.Count) AutoDoc-related process(es):" -ForegroundColor Yellow
Write-Host ""

$processesToKill | Format-Table -AutoSize -Property Id, Runtime, MatchedPattern, CommandLine

$killed = 0
$failed = 0

foreach ($proc in $processesToKill) {
    try {
        Stop-Process -Id $proc.Id -ErrorAction Stop
        Write-Host "  Killed: PID $($proc.Id) - $($proc.MatchedPattern)" -ForegroundColor Green
        $killed++
    }
    catch {
        Write-Host "  Failed to kill PID $($proc.Id): $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "  Killed: $killed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed: $failed" -ForegroundColor Red
}
Write-Host ""
