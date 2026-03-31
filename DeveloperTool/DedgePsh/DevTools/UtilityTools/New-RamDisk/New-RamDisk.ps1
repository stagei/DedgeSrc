<###
.SYNOPSIS
    Creates a RAM disk using ImDisk, automatically downloading and installing ImDisk if missing.

.DESCRIPTION
    This script creates a RAM disk with the specified size in GB. If ImDisk is not installed,
    it will automatically download and install it silently. The RAM disk is created as an NTFS
    formatted drive with the specified drive letter.

.PARAMETER SizeGB
    Size of the RAM disk in gigabytes. Default is 1 GB.

.PARAMETER DriveLetter
    Drive letter to assign to the RAM disk. Default is 'R:'.

.PARAMETER Force
    If specified, removes any existing RAM disk on the specified drive letter before creating a new one.

.EXAMPLE
    .\New-RamDisk.ps1 -SizeGB 2
    Creates a 2 GB RAM disk on drive R:

.EXAMPLE
    .\New-RamDisk.ps1 -SizeGB 4 -DriveLetter "T:"
    Creates a 4 GB RAM disk on drive T:

.EXAMPLE
    .\New-RamDisk.ps1 -SizeGB 1 -Force
    Removes any existing RAM disk on R: and creates a new 1 GB RAM disk

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Administrator privileges for installing ImDisk and creating RAM disks
    ImDisk download URL: https://sourceforge.net/projects/imdisk-toolkit/
###>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 128)]
    [int]$SizeGB = 2,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]:$')]
    [string]$DriveLetter = "V:",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

try {
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "This script requires administrator privileges. Please run PowerShell as Administrator." -Level ERROR
        throw "Administrator privileges required"
    }

    # Normalize drive letter (ensure uppercase and colon)
    $DriveLetter = $DriveLetter.ToUpper()
    if (-not $DriveLetter.EndsWith(':')) {
        $DriveLetter = "$($DriveLetter):"
    }

    # Check if drive letter is already in use
    $existingDrive = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($existingDrive) {
        if ($Force) {
            Write-LogMessage "Removing existing RAM disk on $DriveLetter" -Level INFO
            try {
                & imdisk -d -m $DriveLetter 2>&1 | Out-Null
                Start-Sleep -Seconds 1
            }
            catch {
                Write-LogMessage "Could not remove existing drive using ImDisk. Attempting to remove using Remove-PSDrive." -Level WARN
                Remove-PSDrive -Name $DriveLetter.TrimEnd(':') -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-LogMessage "Drive $DriveLetter is already in use. Use -Force to remove it first." -Level ERROR
            throw "Drive $DriveLetter is already in use"
        }
    }

    # Check if ImDisk is installed
    $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
    if (-not $imdiskPath) {
        Write-LogMessage "ImDisk is not installed. Attempting installation..." -Level INFO

        # Try winget first (though ImDisk is not available in winget, this follows best practices)
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            Write-LogMessage "Checking if ImDisk is available via winget..." -Level INFO
            try {
                $wingetResult = & winget search "ImDisk" 2>&1 | Out-String
                if ($wingetResult -match "ImDisk" -and $wingetResult -notmatch "No package found") {
                    Write-LogMessage "Found ImDisk in winget, installing..." -Level INFO
                    & winget install --id "ImDisk.ImDisk" --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                    Start-Sleep -Seconds 2
                    $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
                    if ($imdiskPath) {
                        Write-LogMessage "ImDisk installed successfully via winget" -Level INFO
                    }
                }
                else {
                    Write-LogMessage "ImDisk not available in winget, using manual download method" -Level INFO
                }
            }
            catch {
                Write-LogMessage "Winget check failed, using manual download method: $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-LogMessage "Winget not available, using manual download method" -Level INFO
        }

        # If still not installed, download and install manually
        if (-not $imdiskPath) {
            Write-LogMessage "Downloading and installing ImDisk manually..." -Level INFO

            # Create temp directory for download
            $tempDir = Join-Path $env:TEMP "ImDiskInstall"
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            try {
                $installerPath = Join-Path $tempDir "imdisk-installer.exe"
                $downloadSuccess = $false

                # Try SourceForge first (most reliable for ImDisk)
                Write-LogMessage "Attempting to download from SourceForge..." -Level INFO
                try {
                    # SourceForge direct download URLs (try multiple patterns)
                    $sourceforgeUrls = @(
                        "https://sourceforge.net/projects/imdisk-toolkit/files/latest/download",
                        "https://downloads.sourceforge.net/project/imdisk-toolkit/ImDisk%20Toolkit%20Setup.exe",
                        "https://sourceforge.net/projects/imdisk-toolkit/files/ImDisk%20Toolkit%20Setup.exe/download"
                    )
                    
                    foreach ($url in $sourceforgeUrls) {
                        try {
                            Write-LogMessage "Trying SourceForge URL: $url" -Level INFO
                            
                            # Use proper headers to avoid bot detection
                            $headers = @{
                                'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                                'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,application/octet-stream;q=0.8,*/*;q=0.7'
                                'Accept-Language' = 'en-US,en;q=0.9'
                                'Accept-Encoding' = 'gzip, deflate, br'
                                'Connection' = 'keep-alive'
                                'Upgrade-Insecure-Requests' = '1'
                            }
                            
                            # Create a web session to handle cookies and redirects
                            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                            
                            # Download to temp file first
                            $tempPath = "$installerPath.tmp"
                            Invoke-WebRequest -Uri $url -OutFile $tempPath -Headers $headers -WebSession $session -UseBasicParsing -ErrorAction Stop
                            
                            # Validate downloaded file
                            $fileInfo = Get-Item $tempPath -ErrorAction Stop
                            $fileSize = $fileInfo.Length
                            
                            # Check if it's a valid executable (PE header)
                            if ($fileSize -gt 1MB) {
                                $bytes = [System.IO.File]::ReadAllBytes($tempPath)
                                # PE files start with "MZ" (0x4D 0x5A)
                                if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
                                    Move-Item -Path $tempPath -Destination $installerPath -Force
                                    Write-LogMessage "Download completed: $([math]::Round($fileSize / 1MB, 2)) MB" -Level INFO
                                    $downloadSuccess = $true
                                    break
                                }
                                elseif ($fileSize -gt 5MB) {
                                    # Large file, assume it's valid even if header check fails
                                    Move-Item -Path $tempPath -Destination $installerPath -Force
                                    Write-LogMessage "Download completed: $([math]::Round($fileSize / 1MB, 2)) MB (large file, assuming valid)" -Level INFO
                                    $downloadSuccess = $true
                                    break
                                }
                            }
                            
                            # File too small or invalid, try next URL
                            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
                            Write-LogMessage "Downloaded file invalid (size: $([math]::Round($fileSize / 1KB, 2)) KB), trying next URL..." -Level WARN
                        }
                        catch {
                            Write-LogMessage "URL failed: $($_.Exception.Message)" -Level WARN
                            continue
                        }
                    }
                }
                catch {
                    Write-LogMessage "SourceForge download failed: $($_.Exception.Message)" -Level WARN
                }
                
                # Try GitHub releases as fallback
                if (-not $downloadSuccess) {
                    Write-LogMessage "Attempting to download from GitHub releases..." -Level INFO
                    try {
                        # Get latest release from GitHub API (correct repository: LTRData/ImDisk)
                        $githubApiUrl = "https://api.github.com/repos/LTRData/ImDisk/releases/latest"
                        $ProgressPreference = 'SilentlyContinue'
                        $releaseInfo = Invoke-RestMethod -Uri $githubApiUrl -UseBasicParsing -ErrorAction Stop
                        
                        # Find the .exe installer in assets
                        $installerAsset = $releaseInfo.assets | Where-Object { 
                            $_.name -match '\.exe$' -and 
                            $_.name -notmatch 'src' -and 
                            $_.name -notmatch 'source'
                        } | Select-Object -First 1
                        
                        if ($installerAsset) {
                            $installerUrl = $installerAsset.browser_download_url
                            Write-LogMessage "Downloading from GitHub: $($installerAsset.name) ($([math]::Round($installerAsset.size / 1MB, 2)) MB)" -Level INFO
                            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
                            
                            # Validate downloaded file size
                            $downloadedSize = (Get-Item $installerPath).Length
                            if ($downloadedSize -lt 1MB) {
                                throw "Downloaded file is too small ($([math]::Round($downloadedSize / 1KB, 2)) KB)"
                            }
                            
                            $downloadSuccess = $true
                        }
                    }
                    catch {
                        Write-LogMessage "GitHub download failed: $($_.Exception.Message)" -Level WARN
                    }
                }


                if (-not $downloadSuccess -or -not (Test-Path $installerPath)) {
                    Write-LogMessage "All automatic download methods failed." -Level ERROR
                    Write-LogMessage "Please download ImDisk manually from one of these sources:" -Level ERROR
                    Write-LogMessage "  1. SourceForge: https://sourceforge.net/projects/imdisk-toolkit/" -Level ERROR
                    Write-LogMessage "  2. Official site: https://imdisktoolkit.com/" -Level ERROR
                    Write-LogMessage "  3. GitHub: https://github.com/LTRData/ImDisk" -Level ERROR
                    Write-LogMessage "After downloading, place the installer in: $installerPath" -Level ERROR
                    Write-LogMessage "Then run this script again to continue with installation." -Level ERROR
                    throw "Failed to download ImDisk installer from any source. Please download manually and retry."
                }

                # Final validation of downloaded file
                $fileInfo = Get-Item $installerPath
                $fileSize = $fileInfo.Length / 1MB
                
                if ($fileSize -lt 1) {
                    throw "Downloaded file is too small ($([math]::Round($fileSize * 1024, 2)) KB), likely corrupted or a redirect page"
                }
                
                # Verify it's a valid PE executable
                $bytes = [System.IO.File]::ReadAllBytes($installerPath)
                if ($bytes.Length -lt 2 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
                    throw "Downloaded file does not appear to be a valid Windows executable (missing PE header)"
                }
                
                Write-LogMessage "Downloaded installer validated: $([math]::Round($fileSize, 2)) MB" -Level INFO

                Write-LogMessage "Installing ImDisk silently..." -Level INFO
                # Install ImDisk silently
                $installArgs = @(
                    "/S"           # Silent installation
                    "/D=$($env:ProgramFiles)\ImDisk"  # Installation directory
                )
                $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -ne 0) {
                    throw "ImDisk installation failed with exit code $($process.ExitCode)"
                }

                # Refresh PATH environment variable
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

                # Wait a moment for PATH to update and verify installation
                Start-Sleep -Seconds 2
                $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
                if (-not $imdiskPath) {
                    # Try adding ImDisk to PATH manually
                    $imdiskExe = Join-Path $env:ProgramFiles "ImDisk\imdisk.exe"
                    if (Test-Path $imdiskExe) {
                        $env:Path += ";$([System.IO.Path]::GetDirectoryName($imdiskExe))"
                        $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
                    }
                }

                if (-not $imdiskPath) {
                    throw "ImDisk installation completed but imdisk.exe not found in PATH"
                }

                Write-LogMessage "ImDisk installed successfully" -Level INFO
            }
            finally {
                # Cleanup temp directory
                if (Test-Path $tempDir) {
                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    else {
        Write-LogMessage "ImDisk is already installed at: $($imdiskPath.Source)" -Level INFO
    }

    # Create RAM disk
    $sizeMB = $SizeGB * 1024
    Write-LogMessage "Creating RAM disk: $SizeGB GB ($sizeMB MB) on drive $DriveLetter" -Level INFO

    # Use ImDisk to create the RAM disk
    # -a: attach/create
    # -s: size in MB
    # -m: mount point (drive letter)
    # -p: partition/format options
    $imdiskArgs = @(
        "-a"
        "-s", "${sizeMB}M"
        "-m", $DriveLetter
        "-p", "/fs:ntfs /q /y"
    )

    $result = & imdisk @imdiskArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errorOutput = $result | Out-String
        Write-LogMessage "Failed to create RAM disk. ImDisk output: $errorOutput" -Level ERROR
        throw "Failed to create RAM disk: $errorOutput"
    }

    # Verify the drive was created
    Start-Sleep -Seconds 1
    $newDrive = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($newDrive) {
        $driveInfo = Get-Volume -DriveLetter $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($driveInfo) {
            $freeSpaceGB = [math]::Round($driveInfo.SizeRemaining / 1GB, 2)
            $totalSpaceGB = [math]::Round($driveInfo.Size / 1GB, 2)
            Write-LogMessage "RAM disk created successfully on $DriveLetter" -Level INFO
            Write-LogMessage "  Total space: $totalSpaceGB GB" -Level INFO
            Write-LogMessage "  Free space: $freeSpaceGB GB" -Level INFO
        }
        else {
            Write-LogMessage "RAM disk created on $DriveLetter (size verification unavailable)" -Level INFO
        }
    }
    else {
        Write-LogMessage "RAM disk creation reported success but drive not found" -Level WARN
    }
}
catch {
    Write-LogMessage "Error creating RAM disk: $($_.Exception.Message)" -Level ERROR -Exception $_
    throw
}
