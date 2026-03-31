<#
.SYNOPSIS
    Deploys the Lillestrøm Osteopati static site to one.com webspace via SFTP.

.DESCRIPTION
    Reads credentials from .env file, connects to one.com via WinSCP (SFTP),
    optionally backs up existing files, then uploads the static site to the web root.

.NOTES
    Requires: WinSCP .NET assembly (auto-installed via NuGet if missing)
    Target:   one.com webspace for lillestrom-osteopati.no
    Run with: pwsh.exe -File deploy.ps1

    Before first use:
    1. Enable SSH & SFTP access in one.com Control Panel > Advanced > SSH & SFTP Administration
    2. Set your SFTP password from the same page
    3. Note the hostname shown there and update .env accordingly
#>

[CmdletBinding()]
param(
    [switch]$BackupFirst,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Configuration
# ============================================================
$scriptRoot  = $PSScriptRoot
$envFile     = Join-Path $scriptRoot '.env'
$siteFiles   = @('index.html', 'styles.css', 'script.js')
$siteFolders = @('images')

# Files to NEVER upload
$excludeFiles = @('.env', '.gitignore', 'README.md', 'research.md', 'DEPLOY.md', 'deploy.ps1')

# ============================================================
# Helper: Parse .env file
# ============================================================
function Read-EnvFile {
    param([string]$Path)

    $envVars = @{}
    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] .env file not found at: $($Path)" -ForegroundColor Red
        Write-Host "Create it from the template. See DEPLOY.md for details." -ForegroundColor Yellow
        exit 1
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $envVars[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }
    return $envVars
}

# ============================================================
# Helper: Prompt for missing values
# ============================================================
function Get-RequiredValue {
    param(
        [hashtable]$EnvVars,
        [string]$Key,
        [string]$PromptMessage,
        [switch]$IsSecret
    )

    $value = $EnvVars[$Key]
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($IsSecret) {
            $secure = Read-Host -Prompt $PromptMessage -AsSecureString
            $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        }
        else {
            $value = Read-Host -Prompt $PromptMessage
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "[ERROR] $($Key) is required. Aborting." -ForegroundColor Red
            exit 1
        }
    }
    return $value
}

# ============================================================
# Helper: Install/Load WinSCP .NET assembly
# ============================================================
function Initialize-WinSCP {
    $winscpPath = Join-Path $scriptRoot 'lib\WinSCPnet.dll'

    if (-not (Test-Path $winscpPath)) {
        Write-Host "[INFO] WinSCP .NET assembly not found. Installing via NuGet..." -ForegroundColor Cyan

        $libDir = Join-Path $scriptRoot 'lib'
        if (-not (Test-Path $libDir)) {
            New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        }

        # Install WinSCP NuGet package
        $nugetDir = Join-Path $env:TEMP 'winscp-nuget'
        if (Test-Path $nugetDir) { Remove-Item $nugetDir -Recurse -Force }

        try {
            Register-PackageSource -Name NuGetTemp -Location 'https://api.nuget.org/v3/index.json' `
                -ProviderName NuGet -Trusted -ErrorAction SilentlyContinue | Out-Null
        }
        catch { <# Already registered, ignore #> }

        Write-Host "[INFO] Downloading WinSCP NuGet package..." -ForegroundColor Cyan
        $pkg = Save-Package -Name WinSCP -Source 'https://api.nuget.org/v3/index.json' `
            -Path $nugetDir -ProviderName NuGet -Force

        # Find and copy the DLL
        $dll = Get-ChildItem -Path $nugetDir -Filter 'WinSCPnet.dll' -Recurse | Select-Object -First 1
        $exe = Get-ChildItem -Path $nugetDir -Filter 'WinSCP.exe' -Recurse | Select-Object -First 1

        if (-not $dll) {
            Write-Host "[ERROR] Could not find WinSCPnet.dll in NuGet package." -ForegroundColor Red
            exit 1
        }

        Copy-Item $dll.FullName -Destination $libDir -Force
        if ($exe) {
            Copy-Item $exe.FullName -Destination $libDir -Force
        }

        Remove-Item $nugetDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] WinSCP installed to $($libDir)" -ForegroundColor Green
    }

    Add-Type -Path $winscpPath
    Write-Host "[OK] WinSCP .NET assembly loaded" -ForegroundColor Green
}

# ============================================================
# Main
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Lillestrøm Osteopati — Site Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Read .env ---
Write-Host "[1/5] Reading configuration from .env..." -ForegroundColor Yellow
$env = Read-EnvFile -Path $envFile

$sftpHost   = Get-RequiredValue -EnvVars $env -Key 'SFTP_HOST' `
    -PromptMessage 'Enter SFTP hostname (from one.com > Advanced > SSH & SFTP Administration)'
$sftpPort   = if ($env['SFTP_PORT']) { [int]$env['SFTP_PORT'] } else { 22 }
$remotePath = if ($env['REMOTE_PATH']) { $env['REMOTE_PATH'] } else { '/' }

$sftpUser = Get-RequiredValue -EnvVars $env -Key 'SFTP_USERNAME' `
    -PromptMessage 'Enter SFTP username (from one.com > Advanced > SSH & SFTP Administration)'
$sftpPass = Get-RequiredValue -EnvVars $env -Key 'SFTP_PASSWORD' `
    -PromptMessage 'Enter SFTP password' -IsSecret

Write-Host "  Host: $($sftpHost):$($sftpPort)" -ForegroundColor Gray
Write-Host "  User: $($sftpUser)" -ForegroundColor Gray
Write-Host "  Remote path: $($remotePath)" -ForegroundColor Gray
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] No files will be modified on the server." -ForegroundColor Magenta
    Write-Host ""
}

# --- Load WinSCP ---
Write-Host "[2/5] Loading WinSCP..." -ForegroundColor Yellow
Initialize-WinSCP

# --- Connect ---
Write-Host "[3/5] Connecting to $($sftpHost)..." -ForegroundColor Yellow

$sessionOptions = New-Object WinSCP.SessionOptions -Property @{
    Protocol  = [WinSCP.Protocol]::Sftp
    HostName  = $sftpHost
    PortNumber = $sftpPort
    UserName  = $sftpUser
    Password  = $sftpPass
    GiveUpSecurityAndAcceptAnySshHostKey = $true
}

$session = New-Object WinSCP.Session
# Point to WinSCP.exe in lib folder
$winscpExe = Join-Path $scriptRoot 'lib\WinSCP.exe'
if (Test-Path $winscpExe) {
    $session.ExecutablePath = $winscpExe
}

try {
    if (-not $DryRun) {
        $session.Open($sessionOptions)
        Write-Host "[OK] Connected successfully" -ForegroundColor Green
    }
    else {
        Write-Host "[DRY RUN] Would connect to $($sftpHost)" -ForegroundColor Magenta
    }

    # --- List local files ---
    Write-Host ""
    Write-Host "[3a] Local files to upload:" -ForegroundColor Yellow
    Write-Host "  Source: $($scriptRoot)" -ForegroundColor Gray
    Write-Host ""
    foreach ($file in $siteFiles) {
        $localPath = Join-Path $scriptRoot $file
        if (Test-Path $localPath) {
            $info = Get-Item $localPath
            $size = '{0:N0}' -f $info.Length
            Write-Host "  $($file)  ($($size) bytes, modified $($info.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor White
        }
        else {
            Write-Host "  $($file)  [NOT FOUND]" -ForegroundColor Red
        }
    }
    foreach ($folder in $siteFolders) {
        $localFolder = Join-Path $scriptRoot $folder
        if (Test-Path $localFolder) {
            $files = Get-ChildItem $localFolder -File
            Write-Host "  $($folder)/  ($($files.Count) files)" -ForegroundColor White
            foreach ($f in $files) {
                $size = '{0:N0}' -f $f.Length
                Write-Host "    $($f.Name)  ($($size) bytes)" -ForegroundColor DarkGray
            }
        }
    }

    # --- List remote files ---
    if (-not $DryRun) {
        Write-Host ""
        Write-Host "[3b] Existing remote files on server:" -ForegroundColor Yellow
        Write-Host "  Remote: $($remotePath)" -ForegroundColor Gray
        Write-Host ""

        $remoteDir = $session.ListDirectory($remotePath)
        $remoteItems = $remoteDir.Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' }

        if ($remoteItems.Count -eq 0) {
            Write-Host "  (empty directory)" -ForegroundColor DarkGray
        }
        else {
            foreach ($item in $remoteItems) {
                if ($item.IsDirectory) {
                    # List subfolder contents
                    $subPath = "$($remotePath)/$($item.Name)"
                    try {
                        $subDir = $session.ListDirectory($subPath)
                        $subFiles = $subDir.Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' }
                        Write-Host "  $($item.Name)/  ($($subFiles.Count) files)" -ForegroundColor White
                        foreach ($sf in $subFiles) {
                            $size = '{0:N0}' -f $sf.Length
                            Write-Host "    $($sf.Name)  ($($size) bytes)" -ForegroundColor DarkGray
                        }
                    }
                    catch {
                        Write-Host "  $($item.Name)/  (could not list contents)" -ForegroundColor Yellow
                    }
                }
                else {
                    $size = '{0:N0}' -f $item.Length
                    Write-Host "  $($item.Name)  ($($size) bytes, modified $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor White
                }
            }
        }

        # --- Confirm before proceeding ---
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor DarkGray
        $confirm = Read-Host -Prompt "Proceed with deployment? Files above will be overwritten. (y/N)"
        if ($confirm -notin @('y', 'Y', 'yes', 'Yes')) {
            Write-Host ""
            Write-Host "[ABORTED] Deployment cancelled by user." -ForegroundColor Yellow
            exit 0
        }
    }

    # --- Optional backup ---
    if ($BackupFirst -and -not $DryRun) {
        Write-Host ""
        Write-Host "[3c] Backing up existing remote files..." -ForegroundColor Yellow
        $backupDir = Join-Path $scriptRoot "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        $transferResult = $session.GetFilesToDirectory("$($remotePath)/*", $backupDir, $false)
        Write-Host "[OK] Backup saved to: $($backupDir)" -ForegroundColor Green
        Write-Host "  Files downloaded: $($transferResult.Transfers.Count)" -ForegroundColor Gray
    }

    # --- Upload files ---
    Write-Host ""
    Write-Host "[4/5] Uploading site files..." -ForegroundColor Yellow

    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

    $uploadCount = 0

    # Upload individual files
    foreach ($file in $siteFiles) {
        $localPath = Join-Path $scriptRoot $file
        if (Test-Path $localPath) {
            $remoteFile = "$($remotePath)/$($file)"
            if ($DryRun) {
                Write-Host "  [DRY RUN] Would upload: $($file) -> $($remoteFile)" -ForegroundColor Magenta
            }
            else {
                $result = $session.PutFileToDirectory($localPath, $remotePath, $false, $transferOptions)
                Write-Host "  Uploaded: $($file)" -ForegroundColor Green
            }
            $uploadCount++
        }
        else {
            Write-Host "  [SKIP] File not found: $($file)" -ForegroundColor Yellow
        }
    }

    # Upload folders (images/)
    foreach ($folder in $siteFolders) {
        $localFolder = Join-Path $scriptRoot $folder
        if (Test-Path $localFolder) {
            $remoteFolder = "$($remotePath)/$($folder)"

            if ($DryRun) {
                $fileCount = (Get-ChildItem $localFolder -File).Count
                Write-Host "  [DRY RUN] Would upload folder: $($folder)/ ($($fileCount) files)" -ForegroundColor Magenta
            }
            else {
                # Ensure remote directory exists
                if (-not $session.FileExists($remoteFolder)) {
                    $session.CreateDirectory($remoteFolder)
                }

                $result = $session.PutFilesToDirectory($localFolder, $remoteFolder, $false, $transferOptions)
                $result.Check()
                $fileCount = $result.Transfers.Count
                Write-Host "  Uploaded: $($folder)/ ($($fileCount) files)" -ForegroundColor Green
            }
            $uploadCount++
        }
    }

    Write-Host ""
    Write-Host "[OK] Upload complete. $($uploadCount) items transferred." -ForegroundColor Green

    # --- Verify ---
    Write-Host ""
    Write-Host "[5/5] Verifying deployment..." -ForegroundColor Yellow

    if (-not $DryRun) {
        $remoteFiles = $session.ListDirectory($remotePath)
        $expectedFiles = @('index.html', 'styles.css', 'script.js')
        $allFound = $true

        foreach ($expected in $expectedFiles) {
            $found = $remoteFiles.Files | Where-Object { $_.Name -eq $expected }
            if ($found) {
                Write-Host "  [OK] $($expected) ($($found.Length) bytes)" -ForegroundColor Green
            }
            else {
                Write-Host "  [MISSING] $($expected)" -ForegroundColor Red
                $allFound = $false
            }
        }

        # Check images folder
        $imgFolder = $remoteFiles.Files | Where-Object { $_.Name -eq 'images' -and $_.IsDirectory }
        if ($imgFolder) {
            $imgFiles = $session.ListDirectory("$($remotePath)/images")
            $imgCount = ($imgFiles.Files | Where-Object { -not $_.IsDirectory -and $_.Name -ne '..' }).Count
            Write-Host "  [OK] images/ ($($imgCount) files)" -ForegroundColor Green
        }
        else {
            Write-Host "  [MISSING] images/ folder" -ForegroundColor Red
            $allFound = $false
        }

        if ($allFound) {
            Write-Host ""
            Write-Host "============================================" -ForegroundColor Green
            Write-Host " Deployment successful!" -ForegroundColor Green
            Write-Host " Site: https://lillestrom-osteopati.no" -ForegroundColor Green
            Write-Host "============================================" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "[WARN] Some files may be missing. Check the site manually." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[DRY RUN] Skipping verification." -ForegroundColor Magenta
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host " Dry run complete. No changes were made." -ForegroundColor Green
        Write-Host " Run without -DryRun to deploy for real." -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor Yellow
    Write-Host "  - Check SFTP_USERNAME and SFTP_PASSWORD in .env" -ForegroundColor Gray
    Write-Host "  - Log in to https://www.domeneshop.no > Webhotell tab to find/reset credentials" -ForegroundColor Gray
    Write-Host "  - Ensure your IP is not blocked (try from a different network)" -ForegroundColor Gray
    exit 1
}
finally {
    if ($session -and $session.Opened) {
        $session.Dispose()
        Write-Host ""
        Write-Host "[INFO] SFTP session closed." -ForegroundColor Gray
    }
}
