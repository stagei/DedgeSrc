# DbExplorer Deployment Script
# This script deploys the DbExplorer application to target machines

<#
.SYNOPSIS
    Deploys DbExplorer to target machines or local directory.

.DESCRIPTION
    This script copies the published DbExplorer application to target locations,
    creates necessary directories, and verifies the deployment.

.PARAMETER TargetPath
    Target directory for deployment. Defaults to C:\Program Files\DbExplorer

.PARAMETER SourcePath
    Source directory containing published files. Defaults to bin\Release\net10.0-windows\win-x64\publish

.PARAMETER CreateShortcut
    Create desktop shortcut. Default is $true.

.PARAMETER VerifyOnly
    Only verify the deployment without copying files.

.EXAMPLE
    .\deploy.ps1
    Deploys to default location

.EXAMPLE
    .\deploy.ps1 -TargetPath "D:\Applications\DbExplorer"
    Deploys to custom location

.EXAMPLE
    .\deploy.ps1 -VerifyOnly
    Verifies existing deployment
#>

param(
    [string]$TargetPath = "C:\Program Files\DbExplorer",
    [string]$SourcePath = "bin\Release\net10.0-windows\win-x64\publish",
    [switch]$CreateShortcut = $true,
    [switch]$VerifyOnly = $false
)

$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to verify file exists
function Test-DeploymentFile {
    param([string]$FilePath, [string]$Description)
    
    if (Test-Path $FilePath) {
        Write-ColorOutput "  ✓ $Description found" "Green"
        return $true
    }
    else {
        Write-ColorOutput "  ✗ $Description missing: $FilePath" "Red"
        return $false
    }
}

Write-ColorOutput "`n========================================" "Cyan"
Write-ColorOutput "DbExplorer Deployment Script" "Cyan"
Write-ColorOutput "========================================`n" "Cyan"

# Verify source files exist
Write-ColorOutput "Verifying source files..." "Yellow"

if (-not (Test-Path $SourcePath)) {
    Write-ColorOutput "ERROR: Source path not found: $SourcePath" "Red"
    Write-ColorOutput "Please run: dotnet publish -c Release -r win-x64 --self-contained true" "Yellow"
    exit 1
}

$requiredFiles = @(
    @{Path="DbExplorer.exe"; Desc="Main executable"},
    @{Path="appsettings.json"; Desc="Configuration file"},
    @{Path="nlog.config"; Desc="Logging configuration"},
    @{Path="Resources\DB2SQL.xshd"; Desc="Syntax highlighting"}
)

$allFilesPresent = $true
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $SourcePath $file.Path
    if (-not (Test-DeploymentFile $filePath $file.Desc)) {
        $allFilesPresent = $false
    }
}

if (-not $allFilesPresent) {
    Write-ColorOutput "`nERROR: Required files missing from source!" "Red"
    exit 1
}

Write-ColorOutput "`nAll source files verified successfully!" "Green"

# If verify only, exit here
if ($VerifyOnly) {
    Write-ColorOutput "`nVerification complete!" "Green"
    exit 0
}

# Create target directory
Write-ColorOutput "`nCreating target directory..." "Yellow"
if (-not (Test-Path $TargetPath)) {
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    Write-ColorOutput "  ✓ Created: $TargetPath" "Green"
}
else {
    Write-ColorOutput "  ℹ Directory already exists: $TargetPath" "Cyan"
}

# Copy files
Write-ColorOutput "`nCopying files..." "Yellow"
try {
    Copy-Item -Path "$SourcePath\*" -Destination $TargetPath -Recurse -Force
    Write-ColorOutput "  ✓ Files copied successfully" "Green"
}
catch {
    Write-ColorOutput "  ✗ Error copying files: $_" "Red"
    exit 1
}

# Create logs directory
$logsPath = Join-Path $TargetPath "logs"
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    Write-ColorOutput "  ✓ Created logs directory" "Green"
}

# Verify deployment
Write-ColorOutput "`nVerifying deployment..." "Yellow"
$deploymentValid = $true
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $TargetPath $file.Path
    if (-not (Test-DeploymentFile $filePath $file.Desc)) {
        $deploymentValid = $false
    }
}

if (-not $deploymentValid) {
    Write-ColorOutput "`nWARNING: Some files missing from deployment!" "Yellow"
}

# Create desktop shortcut
if ($CreateShortcut) {
    Write-ColorOutput "`nCreating desktop shortcut..." "Yellow"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "DbExplorer.lnk"
        $exePath = Join-Path $TargetPath "DbExplorer.exe"
        
        if (Test-Path $exePath) {
            $shortcut = $WshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $exePath
            $shortcut.WorkingDirectory = $TargetPath
            $shortcut.Description = "DbExplorer - DB2 Database Manager"
            $shortcut.Save()
            Write-ColorOutput "  ✓ Desktop shortcut created" "Green"
        }
        else {
            Write-ColorOutput "  ✗ Executable not found, skipping shortcut" "Yellow"
        }
    }
    catch {
        Write-ColorOutput "  ⚠ Could not create shortcut: $_" "Yellow"
    }
}

# Display summary
Write-ColorOutput "`n========================================" "Cyan"
Write-ColorOutput "Deployment Summary" "Cyan"
Write-ColorOutput "========================================" "Cyan"
Write-ColorOutput "Target Path    : $TargetPath" "White"
Write-ColorOutput "Executable     : $(Join-Path $TargetPath 'DbExplorer.exe')" "White"
Write-ColorOutput "Configuration  : $(Join-Path $TargetPath 'appsettings.json')" "White"
Write-ColorOutput "Logs Directory : $logsPath" "White"

if ($deploymentValid) {
    Write-ColorOutput "`n✓ Deployment completed successfully!" "Green"
    Write-ColorOutput "`nYou can now run: $(Join-Path $TargetPath 'DbExplorer.exe')" "Cyan"
}
else {
    Write-ColorOutput "`n⚠ Deployment completed with warnings!" "Yellow"
    Write-ColorOutput "Please review the messages above." "Yellow"
}

Write-ColorOutput "`n========================================`n" "Cyan"

