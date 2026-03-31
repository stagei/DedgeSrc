Import-Module -Name GlobalFunctions -Force

# ═══════════════════════════════════════════════════════════════════════════════
# Copy-AppSettingsFromConfigFolder.ps1
# 
# Copies appsettings.ServerMonitorAgent.json FROM the ServerMonitor config folder
# to the local project as appsettings.json.
# Source: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\
# 
# The config folder is the "source of truth" - editable via Dashboard.
# This script syncs the local project with the centralized configuration.
# ═══════════════════════════════════════════════════════════════════════════════

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Copy appsettings from Config folder to local project`n" -ForegroundColor Cyan

# Get the script directory (should be src/ServerMonitor)
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir)) {
    # Fallback for older PowerShell versions or when run via Invoke-Expression
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Normalize script directory path
if (-not [string]::IsNullOrEmpty($scriptDir)) {
    $scriptDir = [System.IO.Path]::GetFullPath($scriptDir)
}

Write-Host "📁 Script directory: $scriptDir" -ForegroundColor Gray

# Source: Config folder (the "source of truth")
$sourceDir = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor"
$sourceFile = Join-Path $sourceDir "appsettings.ServerMonitorAgent.json"

# Destination: Local project
$destinationFile = Join-Path $scriptDir "appsettings.json"

Write-Host "📄 Source: $sourceFile" -ForegroundColor Gray
Write-Host "📄 Destination: $destinationFile" -ForegroundColor Gray

# Check if source file exists on the config share
if (-not (Test-Path $sourceFile)) {
    Write-Host "⚠️  Source file not found on config share: $sourceFile" -ForegroundColor Yellow
    Write-Host "   The config folder may not have been initialized yet." -ForegroundColor Gray
    Write-Host "   Using local appsettings.json as-is." -ForegroundColor Gray
    $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: ${duration}s" -ForegroundColor Yellow
    exit 0
}

# Normalize paths for comparison
$sourceFileResolved = [System.IO.Path]::GetFullPath((Resolve-Path $sourceFile).Path)
$destinationFileResolved = [System.IO.Path]::GetFullPath($destinationFile)

# Prevent attempt to copy the file onto itself
if ($sourceFileResolved -ieq $destinationFileResolved) {
    Write-Warning "⚠️  Source and destination are the same file: $sourceFileResolved"
    Write-Host "   Skipping copy operation." -ForegroundColor Yellow
    $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: ${duration}s" -ForegroundColor Yellow
    exit 0
}

try {
    # Check if files are identical (skip copy if unchanged)
    $shouldCopy = $true
    if (Test-Path $destinationFile) {
        $sourceHash = (Get-FileHash -Path $sourceFile -Algorithm MD5).Hash
        $destHash = (Get-FileHash -Path $destinationFile -Algorithm MD5).Hash
        
        if ($sourceHash -eq $destHash) {
            Write-Host "✅ Files are identical - no copy needed" -ForegroundColor Green
            $shouldCopy = $false
        } else {
            Write-Host "📋 Files differ - will copy from config folder" -ForegroundColor Yellow
        }
    }
    
    if ($shouldCopy) {
        Copy-Item -Path $sourceFile -Destination $destinationFile -Force -ErrorAction Stop
        Write-Host "✅ Successfully synced appsettings.json from config folder" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Failed to copy from config folder: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Using local appsettings.json as-is." -ForegroundColor Yellow
    # Don't exit with error - the local file can still be used
} finally {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: ${duration}s" -ForegroundColor Yellow
}
