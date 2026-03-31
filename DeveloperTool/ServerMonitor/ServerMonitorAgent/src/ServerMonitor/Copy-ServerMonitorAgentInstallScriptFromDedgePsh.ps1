Import-Module -Name GlobalFunctions -Force

# ═══════════════════════════════════════════════════════════════════════════════
# Copy-InstallScriptFromDedgePsh.ps1
# 
# Copies ServerMonitorAgent from DedgePsh to the script's directory.
# Uses $PSScriptRoot to ensure correct path resolution regardless of working directory.
# ═══════════════════════════════════════════════════════════════════════════════

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Copy ServerMonitorAgent from DedgePsh`n" -ForegroundColor Cyan

try {
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
    
    # Source file - from DedgePsh DevTools
    $sourcePath = Join-Path $env:OptPath "src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorAgent\ServerMonitorAgent.ps1"
    
    # Destination - in script's directory
    $destinationPath = Join-Path $scriptDir "ServerMonitorAgent"
    
    Write-Host "📄 Source: $sourcePath" -ForegroundColor Gray
    Write-Host "📄 Destination: $destinationPath" -ForegroundColor Gray
    
    # Check if source file exists
    if (-not (Test-Path $sourcePath)) {
        Write-Warning "⚠️  Source file not found: $sourcePath"
        Write-Host "   Check that DedgePsh is available at: $($env:OptPath)\src\DedgePsh" -ForegroundColor Yellow
        exit 1
    }
    
    # Normalize paths for comparison (resolve to absolute paths)
    $sourcePathResolved = [System.IO.Path]::GetFullPath((Resolve-Path $sourcePath).Path)
    
    if (Test-Path $destinationPath) {
        $destinationPathResolved = [System.IO.Path]::GetFullPath((Resolve-Path $destinationPath).Path)
    } else {
        $destinationPathResolved = [System.IO.Path]::GetFullPath($destinationPath)
    }
    
    # Prevent attempt to copy the file onto itself
    if ($sourcePathResolved -ieq $destinationPathResolved) {
        Write-Warning "⚠️  Source and destination are the same file: $sourcePathResolved"
        Write-Host "   Skipping copy operation." -ForegroundColor Yellow
        exit 0
    }
    
    # Ensure destination directory exists
    $destinationDir = Split-Path -Parent $destinationPath
    if (-not [string]::IsNullOrEmpty($destinationDir) -and -not (Test-Path $destinationDir)) {
        Write-Host "📁 Creating destination directory: $destinationDir" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    
    # Check if files are identical (skip copy if unchanged)
    $shouldCopy = $true
    if (Test-Path $destinationPath) {
        $sourceHash = (Get-FileHash -Path $sourcePath -Algorithm MD5).Hash
        $destHash = (Get-FileHash -Path $destinationPath -Algorithm MD5).Hash
        
        if ($sourceHash -eq $destHash) {
            Write-Host "✅ Files are identical - no copy needed" -ForegroundColor Green
            $shouldCopy = $false
        } else {
            Write-Host "📋 Files differ - will copy" -ForegroundColor Yellow
        }
    }
    
    if ($shouldCopy) {
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force -ErrorAction Stop
        Write-Host "✅ Copied ServerMonitorAgent from DedgePsh" -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ Failed to copy: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}
finally {
    $duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: ${duration}s" -ForegroundColor Yellow
}
