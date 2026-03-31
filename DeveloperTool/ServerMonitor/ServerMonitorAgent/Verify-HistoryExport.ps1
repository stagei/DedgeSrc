$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Verifying history arrays in exported files`n" -ForegroundColor Cyan

# Check for JSON snapshots
$snapshotDir = $env:OptPath + "\data\ServerMonitor\Snapshots"
if (-not (Test-Path $snapshotDir)) {
    Write-Host "❌ Snapshot directory not found: $snapshotDir" -ForegroundColor Red
    exit 1
}

Write-Host "📁 Checking snapshot directory: $snapshotDir" -ForegroundColor Cyan
$jsonFiles = Get-ChildItem -Path $snapshotDir -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$htmlFiles = Get-ChildItem -Path $snapshotDir -Filter "*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($jsonFiles) {
    Write-Host "`n✅ Found JSON snapshot: $($jsonFiles.Name)" -ForegroundColor Green
    $jsonContent = Get-Content $jsonFiles.FullName -Raw | ConvertFrom-Json
    
    # Check Processor history
    if ($jsonContent.processor.cpuUsageHistory) {
        $cpuHistoryCount = $jsonContent.processor.cpuUsageHistory.Count
        Write-Host "   ✓ CPU Usage History: $cpuHistoryCount measurements" -ForegroundColor Green
        if ($cpuHistoryCount -gt 0) {
            $first = $jsonContent.processor.cpuUsageHistory[0]
            Write-Host "      First: timestamp=$($first.timestamp), value=$($first.value)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ❌ CPU Usage History: NOT FOUND" -ForegroundColor Red
    }
    
    # Check Memory history
    if ($jsonContent.memory.memoryUsageHistory) {
        $memHistoryCount = $jsonContent.memory.memoryUsageHistory.Count
        Write-Host "   ✓ Memory Usage History: $memHistoryCount measurements" -ForegroundColor Green
        if ($memHistoryCount -gt 0) {
            $first = $jsonContent.memory.memoryUsageHistory[0]
            Write-Host "      First: timestamp=$($first.timestamp), value=$($first.value)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ❌ Memory Usage History: NOT FOUND" -ForegroundColor Red
    }
    
    # Check Virtual Memory history
    if ($jsonContent.virtualMemory.virtualMemoryUsageHistory) {
        $vmHistoryCount = $jsonContent.virtualMemory.virtualMemoryUsageHistory.Count
        Write-Host "   ✓ Virtual Memory Usage History: $vmHistoryCount measurements" -ForegroundColor Green
        if ($vmHistoryCount -gt 0) {
            $first = $jsonContent.virtualMemory.virtualMemoryUsageHistory[0]
            Write-Host "      First: timestamp=$($first.timestamp), value=$($first.value)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ❌ Virtual Memory Usage History: NOT FOUND" -ForegroundColor Red
    }
    
    # Check Disk history
    if ($jsonContent.disks.usage) {
        foreach ($disk in $jsonContent.disks.usage) {
            $drive = $disk.drive
            if ($disk.queueLengthHistory) {
                $qHistoryCount = $disk.queueLengthHistory.Count
                Write-Host "   ✓ Disk $drive Queue Length History: $qHistoryCount measurements" -ForegroundColor Green
            } else {
                Write-Host "   ❌ Disk $drive Queue Length History: NOT FOUND" -ForegroundColor Red
            }
            if ($disk.responseTimeHistory) {
                $rHistoryCount = $disk.responseTimeHistory.Count
                Write-Host "   ✓ Disk $drive Response Time History: $rHistoryCount measurements" -ForegroundColor Green
            } else {
                Write-Host "   ❌ Disk $drive Response Time History: NOT FOUND" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "❌ No JSON snapshot files found" -ForegroundColor Red
}

if ($htmlFiles) {
    Write-Host "`n✅ Found HTML snapshot: $($htmlFiles.Name)" -ForegroundColor Green
    $htmlContent = Get-Content $htmlFiles.FullName -Raw
    
    # Check for JavaScript arrays in HTML
    $checks = @(
        @{Name="CPU Usage History"; Pattern="var cpuUsageHistory = \["},
        @{Name="Memory Usage History"; Pattern="var memoryUsageHistory = \["},
        @{Name="Virtual Memory Usage History"; Pattern="var virtualMemoryUsageHistory = \["},
        @{Name="Disk Queue Length History"; Pattern="var disk_.*_QueueLengthHistory = \["},
        @{Name="Disk Response Time History"; Pattern="var disk_.*_ResponseTimeHistory = \["}
    )
    
    foreach ($check in $checks) {
        if ($htmlContent -match $check.Pattern) {
            Write-Host "   ✓ $($check.Name): Found in HTML" -ForegroundColor Green
        } else {
            Write-Host "   ❌ $($check.Name): NOT FOUND in HTML" -ForegroundColor Red
        }
    }
} else {
    Write-Host "`n❌ No HTML snapshot files found" -ForegroundColor Red
}

# Check alert logs
$logDir = "C:\opt\data\ServerMonitor"
$alertLogs = Get-ChildItem -Path $logDir -Filter "*_Alerts_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($alertLogs) {
    Write-Host "`n✅ Found alert log: $($alertLogs.Name)" -ForegroundColor Green
    $logContent = Get-Content $alertLogs.FullName -Tail 20
    Write-Host "   Last 20 lines:" -ForegroundColor Cyan
    $logContent | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
} else {
    Write-Host "`n⚠️  No alert log files found" -ForegroundColor Yellow
}

Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round(((Get-Date) - $startTime).TotalSeconds, 1))s" -ForegroundColor Yellow

