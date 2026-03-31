#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Checks which monitored servers are offline and matches them to RDP files.

.DESCRIPTION
    Reads the central ComputerInfo.json, probes each active server's agent on
    port 8999, and generates a report of offline servers matched to local RDP
    files for easy remote access.

.PARAMETER RdpFolder
    Path to the folder containing .rdp files.

.PARAMETER ComputerInfoPath
    UNC path to ComputerInfo.json. Defaults to the Dashboard config value.

.PARAMETER AgentPort
    Port the ServerMonitor agent listens on. Default: 8999.

.PARAMETER TimeoutSeconds
    HTTP timeout per server probe. Default: 3.

.PARAMETER OutputFile
    Where to save the report. Defaults to offline-servers-rdp.txt in RdpFolder.

.PARAMETER TypeFilter
    Only check servers of this type (e.g. "Server"). Default: "Server".

.PARAMETER IncludeOnline
    Also list online servers in the report.

.EXAMPLE
    .\Get-OfflineServers.ps1
    # Uses defaults: probes all active servers, writes report next to RDP files.

.EXAMPLE
    .\Get-OfflineServers.ps1 -IncludeOnline -TypeFilter ""
    # Check all active machines (including dev), show online too.
#>

param(
    [string]$RdpFolder = "$env:USERPROFILE\OneDrive - Dedge AS\Dokumenter\RDP\30237-FK",
    [string]$ComputerInfoPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json",
    [int]$AgentPort = 8999,
    [int]$TimeoutSeconds = 3,
    [string]$OutputFile = "",
    [string]$TypeFilter = "Server",
    [switch]$IncludeOnline
)

Import-Module GlobalFunctions -Force

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
Write-LogMessage "Starting $($scriptName)" -Level INFO

# --- Validate inputs ---
if (-not (Test-Path $RdpFolder)) {
    Write-LogMessage "RDP folder not found: $($RdpFolder)" -Level ERROR
    exit 1
}

if (-not (Test-Path $ComputerInfoPath)) {
    Write-LogMessage "ComputerInfo.json not found: $($ComputerInfoPath)" -Level ERROR
    exit 1
}

if ([string]::IsNullOrEmpty($OutputFile)) {
    $OutputFile = Join-Path $RdpFolder "offline-servers-rdp.txt"
}

# --- Load data ---
Write-LogMessage "Reading ComputerInfo from $($ComputerInfoPath)" -Level INFO
$allServers = Get-Content $ComputerInfoPath -Raw | ConvertFrom-Json

$activeServers = $allServers | Where-Object { $_.IsActive -eq $true }
if (-not [string]::IsNullOrEmpty($TypeFilter)) {
    $activeServers = $activeServers | Where-Object { $_.Type -eq $TypeFilter }
}

Write-LogMessage "Found $($activeServers.Count) active servers (Type=$($TypeFilter))" -Level INFO

$rdpFiles = Get-ChildItem $RdpFolder -Filter *.rdp -ErrorAction SilentlyContinue
Write-LogMessage "Found $($rdpFiles.Count) RDP files in $($RdpFolder)" -Level INFO

# --- Probe each server ---
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$total = $activeServers.Count
$index = 0

foreach ($srv in $activeServers) {
    $index++
    $pct = [math]::Round(($index / $total) * 100)
    Write-Progress -Activity "Probing servers" -Status "$($srv.Name) ($($index)/$($total))" -PercentComplete $pct

    $online = $false
    try {
        $null = Invoke-RestMethod -Uri "http://$($srv.Name):$($AgentPort)/api/health" -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        $online = $true
    }
    catch {
        $online = $false
    }

    $rdpMatch = $rdpFiles | Where-Object { $_.BaseName -eq $srv.Name }

    $results.Add([PSCustomObject]@{
        Name     = $srv.Name
        Online   = $online
        Type     = $srv.Type
        Platform = $srv.Platform
        RdpFile  = if ($rdpMatch) { $rdpMatch.FullName } else { $null }
    })

    $statusIcon = if ($online) { "ONLINE" } else { "OFFLINE" }
    $rdpIcon    = if ($rdpMatch) { "RDP" } else { "NO-RDP" }
    Write-LogMessage "$($statusIcon) $($srv.Name) [$($rdpIcon)]" -Level $(if ($online) { "DEBUG" } else { "WARN" })
}

Write-Progress -Activity "Probing servers" -Completed

# --- Summarize ---
$offline = $results | Where-Object { -not $_.Online }
$online  = $results | Where-Object { $_.Online }
$offlineWithRdp    = $offline | Where-Object { $_.RdpFile }
$offlineWithoutRdp = $offline | Where-Object { -not $_.RdpFile }

Write-LogMessage "Results: $($online.Count) online, $($offline.Count) offline ($($offlineWithRdp.Count) with RDP, $($offlineWithoutRdp.Count) without)" -Level INFO

# --- Build report ---
$report = [System.Text.StringBuilder]::new()
$null = $report.AppendLine("Offline Servers - ServerMonitor Agent not responding on port $($AgentPort)")
$null = $report.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$null = $report.AppendLine("Source: $($ComputerInfoPath)")
$null = $report.AppendLine("Total active: $($results.Count) | Online: $($online.Count) | Offline: $($offline.Count)")
$null = $report.AppendLine("Offline with RDP: $($offlineWithRdp.Count) | No RDP file: $($offlineWithoutRdp.Count)")
$null = $report.AppendLine("")

# Group offline servers by prefix
$prodServers = $offlineWithRdp | Where-Object { $_.Name -match '^p-' } | Sort-Object Name
$testServers = $offlineWithRdp | Where-Object { $_.Name -match '^t-' } | Sort-Object Name
$otherServers = $offlineWithRdp | Where-Object { $_.Name -notmatch '^[pt]-' } | Sort-Object Name

if ($prodServers.Count -gt 0) {
    $null = $report.AppendLine("=== PRODUCTION SERVERS ($($prodServers.Count)) ===")
    $null = $report.AppendLine("")
    foreach ($s in $prodServers) {
        $null = $report.AppendLine("`"$($s.RdpFile)`"")
    }
    $null = $report.AppendLine("")
}

if ($testServers.Count -gt 0) {
    $null = $report.AppendLine("=== TEST SERVERS ($($testServers.Count)) ===")
    $null = $report.AppendLine("")
    foreach ($s in $testServers) {
        $null = $report.AppendLine("`"$($s.RdpFile)`"")
    }
    $null = $report.AppendLine("")
}

if ($otherServers.Count -gt 0) {
    $null = $report.AppendLine("=== OTHER SERVERS ($($otherServers.Count)) ===")
    $null = $report.AppendLine("")
    foreach ($s in $otherServers) {
        $null = $report.AppendLine("`"$($s.RdpFile)`"")
    }
    $null = $report.AppendLine("")
}

if ($offlineWithoutRdp.Count -gt 0) {
    $null = $report.AppendLine("=== NO RDP FILE ($($offlineWithoutRdp.Count)) ===")
    $null = $report.AppendLine("")
    foreach ($s in $offlineWithoutRdp) {
        $null = $report.AppendLine($s.Name)
    }
    $null = $report.AppendLine("")
}

if ($IncludeOnline -and $online.Count -gt 0) {
    $null = $report.AppendLine("=== ONLINE SERVERS ($($online.Count)) ===")
    $null = $report.AppendLine("")
    foreach ($s in ($online | Sort-Object Name)) {
        $null = $report.AppendLine($s.Name)
    }
    $null = $report.AppendLine("")
}

# --- Write report ---
$report.ToString() | Out-File -FilePath $OutputFile -Encoding utf8
Write-LogMessage "Report saved to $($OutputFile)" -Level INFO

# --- Console summary ---
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Offline Server Report" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Online:  $($online.Count)" -ForegroundColor Green
Write-Host "  Offline: $($offline.Count)" -ForegroundColor $(if ($offline.Count -gt 0) { "Red" } else { "Green" })
Write-Host "    With RDP:    $($offlineWithRdp.Count)" -ForegroundColor Yellow
Write-Host "    Without RDP: $($offlineWithoutRdp.Count)" -ForegroundColor $(if ($offlineWithoutRdp.Count -gt 0) { "Red" } else { "Gray" })
Write-Host ""
Write-Host "  Report: $($OutputFile)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
