<#
.SYNOPSIS
    Builds and publishes the ServerMonitorTrayIcon application
.DESCRIPTION
    Compiles the tray icon application as a self-contained single-file executable
#>

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Building and publishing ServerMonitorTrayIcon`n" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $projectRoot "src\ServerMonitor\ServerMonitorTray\yIcon\ServerMonitorTrayIcon.csproj"
$publishDir = Join-Path $projectRoot "publish"

Write-Host "Project: $projectPath" -ForegroundColor Cyan
Write-Host "Output: $publishDir" -ForegroundColor Cyan
Write-Host ""

# Clean previous publish
if (Test-Path $publishDir) {
    Remove-Item $publishDir -Recurse -Force
}

# Publish as self-contained single file
Write-Host "Publishing..." -ForegroundColor Cyan
dotnet publish $projectPath `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    --output $publishDir `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Build succeeded!" -ForegroundColor Green
    
    # List published files
    Write-Host "`nPublished files:" -ForegroundColor Cyan
    Get-ChildItem $publishDir | ForEach-Object {
        $size = [math]::Round($_.Length / 1MB, 2)
        Write-Host "  $($_.Name) ($size MB)" -ForegroundColor White
    }
} else {
    Write-Host "`n❌ Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round(((Get-Date) - $startTime).TotalSeconds, 1))s" -ForegroundColor Yellow
