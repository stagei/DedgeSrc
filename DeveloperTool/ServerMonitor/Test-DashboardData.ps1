#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the Dashboard API and displays all cached data from t-no1inltst-db
.DESCRIPTION
    Fetches snapshot data from the Dashboard API and displays all available metrics
    to verify that data is being correctly retrieved and formatted.
.EXAMPLE
    .\Test-DashboardData.ps1
.EXAMPLE
    .\Test-DashboardData.ps1 -ServerName "t-no1fkmmig-db"
#>

param(
    [string]$ServerName = "t-no1inltst-db",
    [string]$DashboardUrl = "http://localhost:8998",
    [switch]$UseCached = $true
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ServerMonitor Dashboard Data Test" -ForegroundColor Cyan
Write-Host "  Server: $ServerName" -ForegroundColor Cyan
Write-Host "  Dashboard: $DashboardUrl" -ForegroundColor Cyan
Write-Host "  Use Cached: $UseCached" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: Check if Dashboard API is alive
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "1. Testing Dashboard API..." -ForegroundColor Yellow
try {
    $serversResponse = Invoke-RestMethod -Uri "$DashboardUrl/api/servers" -TimeoutSec 10
    Write-Host "   ✅ Dashboard API is alive" -ForegroundColor Green
    Write-Host "   Total servers: $($serversResponse.servers.Count)" -ForegroundColor Gray
    Write-Host "   Online servers: $(($serversResponse.servers | Where-Object { $_.isAlive }).Count)" -ForegroundColor Gray
    
    # Find our target server
    $targetServer = $serversResponse.servers | Where-Object { $_.name -eq $ServerName }
    if ($targetServer) {
        Write-Host "   Target server status:" -ForegroundColor Cyan
        Write-Host "      Name: $($targetServer.name)" -ForegroundColor White
        Write-Host "      IsAlive: $($targetServer.isAlive)" -ForegroundColor $(if ($targetServer.isAlive) { 'Green' } else { 'Red' })
        Write-Host "      LastChecked: $($targetServer.lastChecked)" -ForegroundColor Gray
        Write-Host "      ResponseTimeMs: $($targetServer.responseTimeMs)" -ForegroundColor Gray
        if ($targetServer.error) {
            Write-Host "      Error: $($targetServer.error)" -ForegroundColor Red
        }
    } else {
        Write-Host "   ⚠️  Target server '$ServerName' not found in server list" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Dashboard API not responding: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: Fetch Snapshot Data
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "2. Fetching snapshot from $ServerName..." -ForegroundColor Yellow
try {
    $snapshotUrl = "$DashboardUrl/api/snapshot/$ServerName`?useCached=$($UseCached.ToString().ToLower())"
    Write-Host "   URL: $snapshotUrl" -ForegroundColor Gray
    
    $snapshot = Invoke-RestMethod -Uri $snapshotUrl -TimeoutSec 30
    Write-Host "   ✅ Snapshot received" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Failed to fetch snapshot: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: Display Metadata
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "3. Metadata" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.metadata) {
    Write-Host "   Server Name:    $($snapshot.metadata.serverName)" -ForegroundColor White
    Write-Host "   Timestamp:      $($snapshot.metadata.timestamp)" -ForegroundColor White
    Write-Host "   Snapshot ID:    $($snapshot.metadata.snapshotId)" -ForegroundColor Gray
    Write-Host "   Tool Version:   $($snapshot.metadata.toolVersion)" -ForegroundColor Gray
} else {
    Write-Host "   ⚠️  No metadata in snapshot" -ForegroundColor Yellow
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: Display Processor Data
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "4. Processor Data" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.processor) {
    $cpu = $snapshot.processor.overallUsagePercent
    $cpuColor = if ($cpu -ge 90) { 'Red' } elseif ($cpu -ge 75) { 'Yellow' } else { 'Green' }
    
    Write-Host "   Overall CPU:    $([math]::Round($cpu, 1))%" -ForegroundColor $cpuColor
    
    if ($snapshot.processor.averages) {
        Write-Host "   1-min average:  $([math]::Round($snapshot.processor.averages.oneMinute, 1))%" -ForegroundColor Gray
        Write-Host "   5-min average:  $([math]::Round($snapshot.processor.averages.fiveMinute, 1))%" -ForegroundColor Gray
        Write-Host "   15-min average: $([math]::Round($snapshot.processor.averages.fifteenMinute, 1))%" -ForegroundColor Gray
    }
    
    if ($snapshot.processor.cpuUsageHistory -and $snapshot.processor.cpuUsageHistory.Count -gt 0) {
        Write-Host "   History points: $($snapshot.processor.cpuUsageHistory.Count)" -ForegroundColor Gray
    }
} else {
    Write-Host "   ⚠️  No processor data in snapshot" -ForegroundColor Yellow
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: Display Memory Data
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "5. Memory Data" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.memory) {
    $memPercent = $snapshot.memory.usedPercent
    $memColor = if ($memPercent -ge 90) { 'Red' } elseif ($memPercent -ge 75) { 'Yellow' } else { 'Green' }
    
    $totalGb = $snapshot.memory.totalGB
    $availableGb = $snapshot.memory.availableGB
    $usedGb = $totalGb - $availableGb
    
    Write-Host "   Used Percent:   $([math]::Round($memPercent, 1))%" -ForegroundColor $memColor
    Write-Host "   Total:          $([math]::Round($totalGb, 2)) GB" -ForegroundColor White
    Write-Host "   Used:           $([math]::Round($usedGb, 2)) GB" -ForegroundColor White
    Write-Host "   Available:      $([math]::Round($availableGb, 2)) GB" -ForegroundColor White
    
    if ($snapshot.memory.topProcesses -and $snapshot.memory.topProcesses.Count -gt 0) {
        Write-Host ""
        Write-Host "   Top Processes by Memory:" -ForegroundColor Cyan
        $snapshot.memory.topProcesses | Select-Object -First 5 | ForEach-Object {
            Write-Host "      $($_.name): $($_.memoryMB) MB" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   ⚠️  No memory data in snapshot" -ForegroundColor Yellow
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 6: Display Disk Space Data
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "6. Disk Space Data" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.diskSpace -and $snapshot.diskSpace.drives) {
    foreach ($drive in $snapshot.diskSpace.drives) {
        $diskPercent = $drive.percentUsed
        $diskColor = if ($diskPercent -ge 90) { 'Red' } elseif ($diskPercent -ge 75) { 'Yellow' } else { 'Green' }
        
        Write-Host "   Drive $($drive.drive):" -ForegroundColor White
        Write-Host "      Used:      $([math]::Round($diskPercent, 1))%" -ForegroundColor $diskColor
        Write-Host "      Total:     $([math]::Round($drive.totalGB, 2)) GB" -ForegroundColor Gray
        Write-Host "      Used:      $([math]::Round($drive.usedGB, 2)) GB" -ForegroundColor Gray
        Write-Host "      Free:      $([math]::Round($drive.freeGB, 2)) GB" -ForegroundColor Gray
    }
} else {
    Write-Host "   ⚠️  No disk space data in snapshot" -ForegroundColor Yellow
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 7: Display Uptime Data
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "7. Uptime Data" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.uptime) {
    $days = [math]::Floor($snapshot.uptime.totalDays)
    $hours = [math]::Floor(($snapshot.uptime.totalDays - $days) * 24)
    Write-Host "   Total Days:     $days days, $hours hours" -ForegroundColor White
    Write-Host "   Last Boot:      $($snapshot.uptime.lastBootTime)" -ForegroundColor Gray
} else {
    Write-Host "   ⚠️  No uptime data in snapshot" -ForegroundColor Yellow
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 8: Display DB2 Diagnostics (if present)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "8. DB2 Diagnostics" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.db2Diagnostics -and $snapshot.db2Diagnostics.instances -and $snapshot.db2Diagnostics.instances.Count -gt 0) {
    Write-Host "   ✅ DB2 Diagnostics Present" -ForegroundColor Green
    
    foreach ($instance in $snapshot.db2Diagnostics.instances) {
        Write-Host ""
        Write-Host "   Instance: $($instance.instanceName)" -ForegroundColor Cyan
        Write-Host "      Log Path: $($instance.diagLogPath)" -ForegroundColor Gray
        
        if ($instance.severityCounts) {
            Write-Host "      Severity Counts:" -ForegroundColor White
            if ($instance.severityCounts.Critical -gt 0) {
                Write-Host "         Critical: $($instance.severityCounts.Critical)" -ForegroundColor Red
            }
            if ($instance.severityCounts.Severe -gt 0) {
                Write-Host "         Severe:   $($instance.severityCounts.Severe)" -ForegroundColor Red
            }
            if ($instance.severityCounts.Error -gt 0) {
                Write-Host "         Error:    $($instance.severityCounts.Error)" -ForegroundColor Yellow
            }
            if ($instance.severityCounts.Warning -gt 0) {
                Write-Host "         Warning:  $($instance.severityCounts.Warning)" -ForegroundColor Yellow
            }
            if ($instance.severityCounts.Event -gt 0) {
                Write-Host "         Event:    $($instance.severityCounts.Event)" -ForegroundColor Gray
            }
        }
        
        if ($instance.recentEntries -and $instance.recentEntries.Count -gt 0) {
            Write-Host "      Recent Entries: $($instance.recentEntries.Count)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   ℹ️  No DB2 diagnostics data (server may not have DB2)" -ForegroundColor Gray
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 9: Display Alerts (if present)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "9. Alerts" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($snapshot.alerts -and $snapshot.alerts.Count -gt 0) {
    Write-Host "   Total Alerts: $($snapshot.alerts.Count)" -ForegroundColor $(if ($snapshot.alerts.Count -gt 0) { 'Yellow' } else { 'Green' })
    
    $snapshot.alerts | Select-Object -First 5 | ForEach-Object {
        $alertColor = switch ($_.severity) {
            "Critical" { 'Red' }
            "Error" { 'Red' }
            "Warning" { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host "   [$($_.severity)] $($_.message)" -ForegroundColor $alertColor
    }
    
    if ($snapshot.alerts.Count -gt 5) {
        Write-Host "   ... and $($snapshot.alerts.Count - 5) more alerts" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✅ No active alerts" -ForegroundColor Green
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Test Complete" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Return the snapshot object for further inspection if needed
return $snapshot
