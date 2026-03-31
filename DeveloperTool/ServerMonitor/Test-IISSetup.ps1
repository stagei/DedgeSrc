# Test-IISSetup.ps1 - Run this on dedge-server to diagnose IIS issues
# Usage: pwsh -File "\\path\to\Test-IISSetup.ps1"
#
# IMPORTANT: ServerMonitorDashboard runs as a VIRTUAL APP under "Default Web Site",
# NOT as a standalone site on port 8998. The correct physical path is DedgeWinApps,
# not IIS. Creating a standalone site conflicts with the virtual app (HTTP 500.35).

$appcmd      = "$($env:SystemRoot)\System32\inetsrv\appcmd.exe"
$appPoolName = "ServerMonitorDashboard"
$siteName    = "ServerMonitorDashboard"
$parentSite  = "Default Web Site"
$virtualAppId = "$parentSite/$siteName"
$correctPath = Join-Path $env:OptPath "DedgeWinApps\$siteName"
$logsPath    = Join-Path $correctPath "logs"
$healthUrl   = "http://localhost/ServerMonitorDashboard/api/IsAlive"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  IIS Diagnostic Script" -ForegroundColor Cyan
Write-Host "  Server: $($env:COMPUTERNAME)" -ForegroundColor Cyan
Write-Host "  Correct path: $correctPath" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Check appcmd exists
Write-Host "`n=== 1. Check appcmd.exe ===" -ForegroundColor Yellow
if (Test-Path $appcmd) {
    Write-Host "OK: appcmd.exe found at $appcmd" -ForegroundColor Green
} else {
    Write-Host "ERROR: appcmd.exe NOT found — IIS may not be installed" -ForegroundColor Red
    exit 1
}

# 2. Check correct physical path exists
Write-Host "`n=== 2. Check Correct Physical Path (DedgeWinApps) ===" -ForegroundColor Yellow
if (Test-Path $correctPath) {
    Write-Host "OK: Path exists: $correctPath" -ForegroundColor Green
    Get-ChildItem $correctPath | Select-Object Name, Length, LastWriteTime | Format-Table
} else {
    Write-Host "ERROR: Path NOT found: $correctPath" -ForegroundColor Red
    Write-Host "       Run: .\IIS-DeployApp.ps1 -SiteName $siteName" -ForegroundColor Red
}

# 3. Check web.config
Write-Host "`n=== 3. Check web.config ===" -ForegroundColor Yellow
$webConfig = Join-Path $correctPath "web.config"
if (Test-Path $webConfig) {
    Write-Host "OK: web.config exists" -ForegroundColor Green
    Get-Content $webConfig
} else {
    Write-Host "ERROR: web.config NOT found at $webConfig" -ForegroundColor Red
}

# 4. Check logs folder
Write-Host "`n=== 4. Check logs folder ===" -ForegroundColor Yellow
if (Test-Path $logsPath) {
    Write-Host "OK: logs folder exists: $logsPath" -ForegroundColor Green
    $logFiles = Get-ChildItem $logsPath -Recurse -ErrorAction SilentlyContinue
    if ($logFiles) {
        $logFiles | Select-Object Name, Length, LastWriteTime | Format-Table
        $lastLog = $logFiles | Where-Object { $_.Name -like "*.log" } |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastLog) {
            Write-Host "Last log content ($($lastLog.Name)):" -ForegroundColor Cyan
            Get-Content $lastLog.FullName -Tail 30
        }
    } else {
        Write-Host "No log files yet (app may not have started yet)"
    }
} else {
    Write-Host "WARNING: logs folder NOT found — app cannot write stdout logs" -ForegroundColor Yellow
    Write-Host "         Run Fix-ServerMonitorDashboard.ps1 to create it"
}

# 5. List App Pools
Write-Host "`n=== 5. List App Pools ===" -ForegroundColor Yellow
& $appcmd list apppool

# 6. Check the dedicated App Pool
Write-Host "`n=== 6. Check App Pool: $appPoolName ===" -ForegroundColor Yellow
$poolResult = & $appcmd list apppool /name:$appPoolName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: App Pool exists" -ForegroundColor Green
    Write-Host $poolResult
    & $appcmd list apppool /apppool.name:$appPoolName /config
    # Check exclusivity — should only have one app
    $allApps    = & $appcmd list app 2>&1 | Out-String
    $poolUsers  = @($allApps -split "`n" | Where-Object { $_ -match "applicationPool:$appPoolName" })
    if ($poolUsers.Count -gt 1) {
        Write-Host "WARNING: App Pool is shared by $($poolUsers.Count) apps (should be 1):" -ForegroundColor Red
        $poolUsers | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    } else {
        Write-Host "OK: App Pool is exclusive to one app" -ForegroundColor Green
    }
} else {
    Write-Host "ERROR: App Pool NOT found" -ForegroundColor Red
}

# 7. Check for rogue standalone site (should NOT exist)
Write-Host "`n=== 7. Check for standalone site (should NOT exist) ===" -ForegroundColor Yellow
$standaloneCheck = & $appcmd list site /name:$siteName 2>&1 | Out-String
if ($standaloneCheck -match 'SITE "') {
    Write-Host "ERROR: Standalone site '$siteName' EXISTS — this conflicts with the virtual app!" -ForegroundColor Red
    Write-Host "       Run: .\Fix-ServerMonitorDashboard.ps1 to remove it" -ForegroundColor Red
    Write-Host $standaloneCheck
} else {
    Write-Host "OK: No standalone site '$siteName' (correct)" -ForegroundColor Green
}

# 8. Check virtual app under Default Web Site (this is the correct deployment)
Write-Host "`n=== 8. Check Virtual App: $virtualAppId ===" -ForegroundColor Yellow
$vappResult = & $appcmd list app /app.name:"$virtualAppId" 2>&1 | Out-String
if ($vappResult -match 'APP "') {
    Write-Host "OK: Virtual app '$virtualAppId' exists" -ForegroundColor Green
    Write-Host $vappResult
    & $appcmd list app /app.name:"$virtualAppId" /config
} else {
    Write-Host "ERROR: Virtual app '$virtualAppId' NOT found" -ForegroundColor Red
    Write-Host "       Run: .\IIS-DeployApp.ps1 -SiteName $siteName" -ForegroundColor Red
}

# 9. Port check — port 80 (virtual app), port 8998 should NOT be bound to SMD standalone
Write-Host "`n=== 9. Port Check ===" -ForegroundColor Yellow
$port80 = netstat -ano | Select-String ":80 "
if ($port80) {
    Write-Host "OK: Port 80 is listening (Default Web Site / virtual app)" -ForegroundColor Green
} else {
    Write-Host "WARNING: Port 80 is not listening — Default Web Site may be stopped" -ForegroundColor Yellow
}
$port8998 = netstat -ano | Select-String ":8998"
if ($port8998) {
    Write-Host "WARNING: Port 8998 is in use — a standalone site may be running:" -ForegroundColor Red
    $port8998
} else {
    Write-Host "OK: Port 8998 is NOT listening (no rogue standalone site)" -ForegroundColor Green
}

# 10. Test API via correct virtual-app URL
Write-Host "`n=== 10. Test API ===" -ForegroundColor Yellow
Write-Host "URL: $healthUrl"
try {
    $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "OK: HTTP $($response.StatusCode)" -ForegroundColor Green
    Write-Host $response.Content
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code) {
        Write-Host "FAIL: HTTP $code" -ForegroundColor Red
    } else {
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Diagnostic Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
