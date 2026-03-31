# Backup Environment Variables Script - Improved Version
# This script creates a backup of all environment variables as a PowerShell script that can be rerun to restore them

param(
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = "$env:OptPath\data\EnvironmentVariables-Backup"
)

# Function to safely escape PowerShell string values
function Escape-PowerShellString {
    param([string]$InputString)

    if ([string]::IsNullOrEmpty($InputString)) {
        return '""'
    }

    # Handle special PowerShell characters
    $escaped = $InputString -replace '`', '``'     # Escape backticks first
    $escaped = $escaped -replace '"', '`"'         # Escape double quotes
    $escaped = $escaped -replace '\$', '`$'        # Escape dollar signs
    $escaped = $escaped -replace "`r`n", '`r`n'    # Handle CRLF
    $escaped = $escaped -replace "`n", '`n'        # Handle LF
    $escaped = $escaped -replace "`r", '`r'        # Handle CR

    return "`"$escaped`""
}

# Create backup directory if it doesn't exist
if (-not (Test-Path $BackupPath -PathType Container)) {
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    Write-Host "Created backup directory: $BackupPath" -ForegroundColor Green
}

$externalBackupPath = Get-CommonLogPath + "\EnvironmentVariables-Backup"

# Generate timestamp for backup file
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupFileName = "EnvironmentVariables-Backup_$timestamp.ps1"
$backupFilePath = Join-Path $BackupPath $backupFileName

# Start building the restore script content
$restoreScript = @"
# Environment Variables Restore Script
# Generated on: $(Get-Date)
# Computer: $env:COMPUTERNAME
# User: $env:USERNAME

Write-Host "Restoring Environment Variables..." -ForegroundColor Green
Write-Host "Generated on: $(Get-Date)" -ForegroundColor Yellow
Write-Host "Original Computer: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "Original User: $env:USERNAME" -ForegroundColor Yellow
Write-Host ""

# Function to safely set environment variable
function Set-SafeEnvironmentVariable {
    param(
        [string]`$Name,
        [string]`$Value,
        [System.EnvironmentVariableTarget]`$Target
    )

    try {
        [Environment]::SetEnvironmentVariable(`$Name, `$Value, `$Target)
        Write-Host "Set `$Target Variable: `$Name" -ForegroundColor Gray
        return `$true
    }
    catch {
        Write-Host "Failed to set `$Target Variable: `$Name - `$(`$_.Exception.Message)" -ForegroundColor Red
        return `$false
    }
}

"@

# Get User Environment Variables
Write-Host "Backing up User Environment Variables..." -ForegroundColor Cyan
$userVars = [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User)
$restoreScript += "`n# User Environment Variables`n"
$restoreScript += "Write-Host 'Restoring User Environment Variables...' -ForegroundColor Cyan`n"

$userSuccessCount = 0
foreach ($var in $userVars.GetEnumerator()) {
    $name = $var.Key
    $escapedValue = Escape-PowerShellString $var.Value
    $restoreScript += "Set-SafeEnvironmentVariable '$name' $escapedValue ([EnvironmentVariableTarget]::User)`n"
    $userSuccessCount++
}

# Get System Environment Variables
Write-Host "Backing up System Environment Variables..." -ForegroundColor Yellow
try {
    $systemVars = [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::Machine)
    $restoreScript += "`n# System Environment Variables (requires Administrator privileges)`n"
    $restoreScript += "Write-Host 'Restoring System Environment Variables...' -ForegroundColor Yellow`n"
    $restoreScript += "if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {`n"
    $restoreScript += "    Write-Host 'Warning: Administrator privileges required for System variables. Skipping...' -ForegroundColor Red`n"
    $restoreScript += "} else {`n"

    $systemSuccessCount = 0
    foreach ($var in $systemVars.GetEnumerator()) {
        $name = $var.Key
        $escapedValue = Escape-PowerShellString $var.Value
        $restoreScript += "    Set-SafeEnvironmentVariable '$name' $escapedValue ([EnvironmentVariableTarget]::Machine)`n"
        $systemSuccessCount++
    }

    $restoreScript += "}`n"
}
catch {
    Write-Host "Warning: Could not access System Environment Variables. Administrator privileges may be required." -ForegroundColor Red
    $restoreScript += "`n# System Environment Variables could not be accessed during backup`n"
    $restoreScript += "Write-Host 'System Environment Variables were not backed up due to insufficient privileges' -ForegroundColor Red`n"
    $systemSuccessCount = 0
}

# Add completion message to restore script
$restoreScript += "`n"
$restoreScript += "Write-Host 'Environment Variables restoration completed!' -ForegroundColor Green`n"
$restoreScript += "Write-Host 'Note: You may need to restart applications or open new command prompts to see the changes.' -ForegroundColor Yellow`n"
$restoreScript += "Write-Host 'Important: Changes to PATH and other system variables may require a system restart.' -ForegroundColor Yellow`n"

# Write the restore script to file
try {
    $restoreScript | Out-File -FilePath $backupFilePath -Encoding UTF8 -Force
    Write-Host "Backup completed successfully!" -ForegroundColor Green
    Write-Host "Backup file created: $backupFilePath" -ForegroundColor Green
    Write-Host ""
    Write-Host "To restore environment variables, run:" -ForegroundColor Yellow
    Write-Host "PowerShell -ExecutionPolicy Bypass -File `"$backupFilePath`"" -ForegroundColor White
    Write-Host ""

    # Show summary
    $totalVars = $userSuccessCount

    try {
        $totalVars += $systemSuccessCount
        Write-Host "Summary: $userSuccessCount User variables + $systemSuccessCount System variables = $totalVars total variables backed up" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Summary: $userSuccessCount User variables backed up (System variables could not be accessed)" -ForegroundColor Cyan
    }

    # Show file size
    $fileSize = (Get-Item $backupFilePath).Length
    $fileSizeKB = [math]::Round($fileSize / 1024, 2)
    Write-Host "Backup file size: $fileSizeKB KB" -ForegroundColor Cyan
}
catch {
    Write-Host "Error creating backup file: $_" -ForegroundColor Red
    exit 1
}

