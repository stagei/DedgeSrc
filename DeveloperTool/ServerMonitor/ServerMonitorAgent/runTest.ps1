Write-Host "🚀 Starting app and monitoring for snapshot export...`n" -ForegroundColor Cyan

# Copy config
Copy-Item "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\appsettings.json" `
          -Destination "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\appsettings.json" `
          -Force

cd C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64

$env:DOTNET_ENVIRONMENT = "Development"
$env:ASPNETCORE_ENVIRONMENT = "Development"

Write-Host "Start time: $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor Gray

# Start app in background
$job = Start-Job -ScriptBlock {
    param($exePath, $envDev)
    $env:DOTNET_ENVIRONMENT = $envDev
    $env:ASPNETCORE_ENVIRONMENT = $envDev
    & $exePath 2>&1
} -ArgumentList (Get-Location).Path + "\ServerMonitor.exe", "Development"

Write-Host "Monitoring log file for 40 seconds...`n" -ForegroundColor Yellow

$logFile = "C:\opt\data\ServerMonitor\ServerMonitor_$(Get-Date -Format 'yyyy-MM-dd').log"
$startTime = Get-Date
$found = $false

for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 5
    
    $logs = Get-Content $logFile -Tail 50 -ErrorAction SilentlyContinue |
        Select-String "Creating snapshot|Saving files|exported successfully|HTML saved|copied to server share"
    
    if ($logs) {
        Write-Host "[$i/8] Export activity detected:" -ForegroundColor Green
        $logs | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        
        if ($logs -match "exported successfully") {
            $found = $true
            Write-Host "`n🎉 SNAPSHOT EXPORT SUCCESSFUL!" -ForegroundColor Green
            break
        }
    } else {
        Write-Host "[$i/8] Waiting for export..." -ForegroundColor Gray
    }
}

Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -ErrorAction SilentlyContinue

if ($found) {
    Write-Host "`n📁 Checking files...`n" -ForegroundColor Cyan
    
    $today = Get-Date -Format "yyyyMMdd"
    $snapshots = Get-ChildItem "C:\opt\data\ServerMonitor\Snapshots\" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $today -and $_.LastWriteTime -gt $startTime }
    
    if ($snapshots) {
        Write-Host "✅ Snapshot files created:" -ForegroundColor Green
        $snapshots | Select-Object -First 5 | ForEach-Object {
            Write-Host "  $($_.Name) - $([math]::Round($_.Length/1KB, 2)) KB" -ForegroundColor White
        }
    }
    
    $serverPath = "dedge-server\FkAdminWebContent\Server\30237-FK\"
    if (Test-Path $serverPath) {
        $html = Get-ChildItem $serverPath -Filter "*.html" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $startTime }
        if ($html) {
            Write-Host "`n✅ HTML in server share:" -ForegroundColor Green
            $html | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor White }
        }
    }
} else {
    Write-Host "`n❌ Export did NOT complete within 40 seconds" -ForegroundColor Red
}

Get-Process ServerMonitor -ErrorAction SilentlyContinue | Stop-Process -Force