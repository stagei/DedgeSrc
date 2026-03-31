#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Starts ServerMonitor with a specific appsettings configuration file

.DESCRIPTION
    Starts ServerMonitor application using the specified appsettings file.
    Extracts the environment name from the filename and sets DOTNET_ENVIRONMENT accordingly.
    Kills any existing ServerMonitor processes before starting.

.PARAMETER AppSettingsFile
    The appsettings file to use (e.g., "LowLimitsTest", "Production", or empty for default)
    Examples:
        -AppSettingsFile "LowLimitsTest"  → uses appsettings.LowLimitsTest.json
        -AppSettingsFile "Production"      → uses appsettings.Production.json
        -AppSettingsFile ""               → uses appsettings.json only (default)

.EXAMPLE
    .\Start-ServerMonitor.ps1 -AppSettingsFile "LowLimitsTest"
    Starts ServerMonitor with appsettings.LowLimitsTest.json

.EXAMPLE
    .\Start-ServerMonitor.ps1 -AppSettingsFile "Production"
    Starts ServerMonitor with appsettings.Production.json

.EXAMPLE
    .\Start-ServerMonitor.ps1
    Starts ServerMonitor with default appsettings.json
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$AppSettingsFile = ""
)

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Starting ServerMonitor with configuration`n" -ForegroundColor Cyan

# Determine environment name from appsettings file parameter
$envName = if ([string]::IsNullOrWhiteSpace($AppSettingsFile)) {
    "Production"  # Default
} else {
    $AppSettingsFile
}

# Path to executable (relative to script directory)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $scriptDir "src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"

# Check if executable exists
if (-not (Test-Path $exePath)) {
    Write-Host "❌ Executable not found: $exePath" -ForegroundColor Red
    Write-Host "💡 Please build the project first:" -ForegroundColor Yellow
    Write-Host "   dotnet build -c Release --project src\ServerMonitor" -ForegroundColor Gray
    exit 1
}

# Kill any existing ServerMonitor processes
Write-Host "🔪 Killing existing ServerMonitor processes..." -ForegroundColor Red
$existingProcesses = Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue
if ($existingProcesses) {
    $existingProcesses | Stop-Process -Force
    $processCount = $existingProcesses.Count
    $processText = if ($processCount -eq 1) { "process" } else { "processes" }
    Write-Host "   Stopped $processCount existing $processText" -ForegroundColor Gray
    Start-Sleep -Seconds 2
} else {
    Write-Host "   No existing processes found" -ForegroundColor Gray
}

# Display configuration info
Write-Host "`n📋 Configuration:" -ForegroundColor Cyan
if ([string]::IsNullOrWhiteSpace($AppSettingsFile)) {
    Write-Host "   Profile: Default (Production)" -ForegroundColor White
    Write-Host "   Files: appsettings.json + appsettings.Production.json" -ForegroundColor White
} else {
    Write-Host "   Profile: $envName" -ForegroundColor White
    Write-Host "   Files: appsettings.json + appsettings.$envName.json" -ForegroundColor White
}
Write-Host "   DOTNET_ENVIRONMENT: $envName" -ForegroundColor White

# Check if appsettings file exists
$appSettingsPath = Join-Path $scriptDir "src\ServerMonitor\ServerMonitorAgent\appsettings.$envName.json"
if ($envName -ne "Production" -and -not (Test-Path $appSettingsPath)) {
    Write-Host "`n⚠️  Warning: appsettings.$envName.json not found at: $appSettingsPath" -ForegroundColor Yellow
    Write-Host "   The application will use appsettings.json only" -ForegroundColor Gray
}

# Set environment variable and start process
Write-Host "`n🚀 Starting ServerMonitor..." -ForegroundColor Cyan

# Use cmd /c to set environment variable and start process in one command
# This ensures the environment variable is passed to the new process
$exeDir = Split-Path -Parent $exePath
$exeName = Split-Path -Leaf $exePath

try {
    # Start process using cmd /c to set environment variable
    # Use Start-Process with cmd /c to ensure env var is passed correctly
    $process = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", "set DOTNET_ENVIRONMENT=$envName && cd /d `"$exeDir`" && start `"`" `"$exeName`"" `
        -PassThru `
        -WindowStyle Hidden
    
    # Wait a moment for process to initialize
    Start-Sleep -Milliseconds 1000
    
    # Verify process is running (look for ServerMonitor.exe, not cmd.exe)
    $verifyProcess = Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | 
        Where-Object { $_.StartTime -gt (Get-Date).AddSeconds(-5) } | 
        Sort-Object StartTime -Descending | 
        Select-Object -First 1
    
    if ($verifyProcess) {
        Write-Host "✅ ServerMonitor started successfully!" -ForegroundColor Green
        Write-Host "   Process ID: $($verifyProcess.Id)" -ForegroundColor Gray
        Write-Host "   Process Name: $($verifyProcess.ProcessName)" -ForegroundColor Gray
        Write-Host "   Start Time: $($verifyProcess.StartTime)" -ForegroundColor Gray
        Write-Host "`n📄 Logs location: C:\opt\data\ServerMonitor\" -ForegroundColor Cyan
        Write-Host "🌐 REST API: http://localhost:8999/swagger (if enabled)" -ForegroundColor Cyan
        
        if ($envName -eq "LowLimitsTest") {
            Write-Host "`n💡 LowLimitsTest profile active:" -ForegroundColor Yellow
            Write-Host "   - DevMode: true (CommonAppsettingsFile sync disabled)" -ForegroundColor Gray
            Write-Host "   - Low thresholds enabled for quick alert testing" -ForegroundColor Gray
        }
    } else {
        Write-Host "❌ Process started but could not be verified" -ForegroundColor Red
        Write-Host "   Process may have exited immediately. Check logs for errors." -ForegroundColor Yellow
        Write-Host "   Checking for any ServerMonitor processes..." -ForegroundColor Yellow
        $allProcesses = Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue
        if ($allProcesses) {
            Write-Host "   Found $($allProcesses.Count) ServerMonitor process(es)" -ForegroundColor Gray
            $allProcesses | ForEach-Object {
                Write-Host "     PID: $($_.Id), Started: $($_.StartTime)" -ForegroundColor Gray
            }
        } else {
            Write-Host "   No ServerMonitor processes found" -ForegroundColor Red
        }
        exit 1
    }
} catch {
    Write-Host "❌ Failed to start ServerMonitor: $_" -ForegroundColor Red
    exit 1
}

$totalElapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round($totalElapsed, 1))s" -ForegroundColor Yellow

