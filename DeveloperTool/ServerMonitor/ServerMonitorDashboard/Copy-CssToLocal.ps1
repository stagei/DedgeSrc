# Copy-CssToLocal.ps1
# Quick script to copy CSS files from source to deployed dashboard for instant preview
# Usage: .\Copy-CssToLocal.ps1

$source = "$PSScriptRoot\src\ServerMonitorDashboard\wwwroot\css"
$dest = "C:\opt\DedgeWinApps\ServerMonitorDashboard\wwwroot\css"

# Check if destination exists
if (-not (Test-Path $dest)) {
    Write-Host "❌ Dashboard not found at: $dest" -ForegroundColor Red
    Write-Host "   Make sure ServerMonitorDashboard is installed locally." -ForegroundColor Yellow
    exit 1
}

Write-Host "📁 Copying CSS files..." -ForegroundColor Cyan
Write-Host "   From: $source" -ForegroundColor Gray
Write-Host "   To:   $dest" -ForegroundColor Gray
Write-Host ""

$files = Get-ChildItem -Path "$source\*.css"
foreach ($file in $files) {
    Copy-Item -Path $file.FullName -Destination $dest -Force
    Write-Host "   ✅ $($file.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "🔄 Done! Hard refresh browser with Ctrl+Shift+R" -ForegroundColor Yellow
Write-Host ""
