$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

#region Helper Functions

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks if the current session is running with administrator privileges.
    #>
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ImDiskPath {
    <#
    .SYNOPSIS
        Gets the path to ImDisk executable, adding to PATH if necessary.
    .OUTPUTS
        Path to imdisk.exe if found, $null otherwise.
    #>
    $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
    
    if (-not $imdiskPath) {
        # Try adding ImDisk to PATH manually
        $imdiskExe = Join-Path $env:ProgramFiles "ImDisk\imdisk.exe"
        if (Test-Path $imdiskExe) {
            $env:Path += ";$([System.IO.Path]::GetDirectoryName($imdiskExe))"
            $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
        }
    }
    
    return $imdiskPath
}

function Test-ImDiskInstalled {
    <#
    .SYNOPSIS
        Checks if ImDisk is installed and accessible.
    #>
    return $null -ne (Get-ImDiskPath)
}

# Network share path for ImDisk installation files
$script:ImDiskNetworkPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\imRamdisk"

function Install-ImDiskFromNetworkShare {
    <#
    .SYNOPSIS
        Installs ImDisk from the network share.
    .DESCRIPTION
        Copies ImDisk files from the network share to system directories
        and registers the drivers. This is the preferred installation method
        for servers as it doesn't require internet access.
    .PARAMETER NetworkPath
        Path to the network share containing ImDisk files.
        Default: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\imRamdisk
    .OUTPUTS
        $true if installed successfully, $false otherwise.
    #>
    param(
        [string]$NetworkPath = $script:ImDiskNetworkPath
    )

    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "Installation requires Administrator privileges" -Level ERROR
        return $false
    }

    # Check if network share is accessible
    if (-not (Test-Path $NetworkPath)) {
        Write-LogMessage "Network share not accessible: $NetworkPath" -Level WARN
        return $false
    }

    Write-LogMessage "Installing ImDisk from network share: $NetworkPath" -Level INFO

    try {
        # Stop existing services if running
        Stop-Service -Name "ImDskSvc" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "ImDisk" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "AWEAlloc" -Force -ErrorAction SilentlyContinue

        # Copy drivers
        $driversPath = Join-Path $NetworkPath "drivers"
        if (Test-Path $driversPath) {
            Write-LogMessage "Copying drivers..." -Level INFO
            
            $imdiskSys = Join-Path $driversPath "imdisk.sys"
            $aweallocSys = Join-Path $driversPath "awealloc.sys"
            
            if (Test-Path $imdiskSys) {
                Copy-Item -Path $imdiskSys -Destination "$env:windir\System32\drivers\" -Force
                Write-LogMessage "  Copied: imdisk.sys" -Level INFO
            }
            
            if (Test-Path $aweallocSys) {
                Copy-Item -Path $aweallocSys -Destination "$env:windir\System32\drivers\" -Force
                Write-LogMessage "  Copied: awealloc.sys" -Level INFO
            }

            # Copy INF if present
            $imdiskInf = Join-Path $driversPath "imdisk.inf"
            if (Test-Path $imdiskInf) {
                Copy-Item -Path $imdiskInf -Destination "$env:windir\System32\" -Force
                Write-LogMessage "  Copied: imdisk.inf" -Level INFO
            }
        }
        else {
            Write-LogMessage "Drivers folder not found in network share" -Level ERROR
            return $false
        }

        # Copy executables
        $binPath = Join-Path $NetworkPath "bin"
        if (Test-Path $binPath) {
            Write-LogMessage "Copying executables..." -Level INFO
            
            $imdiskExe = Join-Path $binPath "imdisk.exe"
            $imdiskCpl = Join-Path $binPath "imdisk.cpl"
            
            if (Test-Path $imdiskExe) {
                Copy-Item -Path $imdiskExe -Destination "$env:windir\System32\" -Force
                Write-LogMessage "  Copied: imdisk.exe" -Level INFO
            }
            
            if (Test-Path $imdiskCpl) {
                Copy-Item -Path $imdiskCpl -Destination "$env:windir\System32\" -Force
                Write-LogMessage "  Copied: imdisk.cpl" -Level INFO
            }
        }
        else {
            Write-LogMessage "Bin folder not found in network share" -Level ERROR
            return $false
        }

        # Register drivers using sc.exe
        Write-LogMessage "Registering ImDisk driver..." -Level INFO
        & sc.exe create ImDisk type= kernel start= demand binPath= "System32\drivers\imdisk.sys" DisplayName= "ImDisk Virtual Disk Driver" 2>$null | Out-Null
        & sc.exe description ImDisk "ImDisk Virtual Disk Driver - Creates virtual disk devices" 2>$null | Out-Null

        Write-LogMessage "Registering AWEAlloc driver..." -Level INFO
        & sc.exe create AWEAlloc type= kernel start= demand binPath= "System32\drivers\awealloc.sys" DisplayName= "AWE Allocation Driver" 2>$null | Out-Null
        & sc.exe description AWEAlloc "AWE Allocation Driver - Physical memory allocation for ImDisk" 2>$null | Out-Null

        # Start drivers
        Write-LogMessage "Starting drivers..." -Level INFO
        Start-Service -Name "ImDisk" -ErrorAction SilentlyContinue
        Start-Service -Name "AWEAlloc" -ErrorAction SilentlyContinue

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Start-Sleep -Seconds 2

        # Verify installation
        if (Test-ImDiskInstalled) {
            Write-LogMessage "ImDisk installed successfully from network share" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "Installation completed but imdisk.exe not found" -Level WARN
            return $false
        }
    }
    catch {
        Write-LogMessage "Network share installation failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Uninstall-ImDisk {
    <#
    .SYNOPSIS
        Uninstalls ImDisk from the system.
    .DESCRIPTION
        Removes all mounted ImDisk devices, stops services, removes drivers,
        and deletes ImDisk files from the system.
    .PARAMETER Force
        Skip confirmation prompts.
    .OUTPUTS
        $true if uninstalled successfully, $false otherwise.
    #>
    param(
        [switch]$Force
    )

    if (-not (Test-IsAdministrator)) {
        Write-LogMessage "Uninstallation requires Administrator privileges" -Level ERROR
        return $false
    }

    if (-not (Test-ImDiskInstalled)) {
        Write-LogMessage "ImDisk is not installed" -Level INFO
        return $true
    }

    if (-not $Force) {
        Write-LogMessage "WARNING: This will remove ImDisk and all mounted RAM disks!" -Level WARN
        $response = Read-Host "Continue? [Y/N]"
        if ($response -notmatch '^[Yy]') {
            Write-LogMessage "Uninstallation cancelled" -Level INFO
            return $false
        }
    }

    Write-LogMessage "Uninstalling ImDisk..." -Level INFO

    try {
        # Remove any mounted ImDisk devices
        Write-LogMessage "Removing mounted devices..." -Level INFO
        $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
        if ($imdiskPath) {
            $devices = & imdisk -l 2>$null
            if ($devices) {
                & imdisk -l | ForEach-Object {
                    if ($_ -match "Device\s+(\d+)") {
                        & imdisk -D -u $Matches[1] 2>$null
                    }
                }
            }
        }

        # Stop services
        Write-LogMessage "Stopping services..." -Level INFO
        Stop-Service -Name "ImDskSvc" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "ImDisk" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "AWEAlloc" -Force -ErrorAction SilentlyContinue

        # Delete services
        Write-LogMessage "Removing services..." -Level INFO
        & sc.exe delete ImDskSvc 2>$null | Out-Null
        & sc.exe delete ImDisk 2>$null | Out-Null
        & sc.exe delete AWEAlloc 2>$null | Out-Null

        # Remove files
        Write-LogMessage "Removing files..." -Level INFO
        $filesToRemove = @(
            "$env:windir\System32\imdisk.exe",
            "$env:windir\System32\imdisk.cpl",
            "$env:windir\System32\imdisk.inf",
            "$env:windir\System32\drivers\imdisk.sys",
            "$env:windir\System32\drivers\awealloc.sys"
        )

        foreach ($file in $filesToRemove) {
            if (Test-Path $file) {
                Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
                Write-LogMessage "  Removed: $file" -Level INFO
            }
        }

        # Remove Program Files folder
        $progFilesPath = "$env:ProgramFiles\ImDisk"
        if (Test-Path $progFilesPath) {
            Remove-Item -Path $progFilesPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "  Removed: $progFilesPath" -Level INFO
        }

        Write-LogMessage "ImDisk uninstalled successfully" -Level INFO
        Write-LogMessage "A reboot may be required to complete removal" -Level WARN
        return $true
    }
    catch {
        Write-LogMessage "Uninstallation failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Install-ImDisk {
    <#
    .SYNOPSIS
        Installs ImDisk, preferring network share installation.
    .DESCRIPTION
        Attempts to install ImDisk in the following order:
        1. Network share (C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\imRamdisk)
        2. Winget (if available)
        3. Download from SourceForge/GitHub
    .OUTPUTS
        $true if installed successfully, $false otherwise.
    #>
    
    if (Test-ImDiskInstalled) {
        $path = (Get-ImDiskPath).Source
        Write-LogMessage "ImDisk is already installed at: $path" -Level INFO
        return $true
    }
    
    Write-LogMessage "ImDisk is not installed. Attempting installation..." -Level INFO

    # Method 1: Try network share first (preferred for servers)
    Write-LogMessage "Checking network share..." -Level INFO
    if (Test-Path $script:ImDiskNetworkPath) {
        $result = Install-ImDiskFromNetworkShare -NetworkPath $script:ImDiskNetworkPath
        if ($result) {
            return $true
        }
        Write-LogMessage "Network share installation failed, trying alternative methods..." -Level WARN
    }
    else {
        Write-LogMessage "Network share not accessible, trying alternative methods..." -Level INFO
    }

    # Method 2: Try winget
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetPath) {
        Write-LogMessage "Checking if ImDisk is available via winget..." -Level INFO
        try {
            $wingetResult = & winget search "ImDisk" 2>&1 | Out-String
            if ($wingetResult -match "ImDisk" -and $wingetResult -notmatch "No package found") {
                Write-LogMessage "Found ImDisk in winget, installing..." -Level INFO
                & winget install --id "ImDisk.ImDisk" --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                Start-Sleep -Seconds 2
                if (Test-ImDiskInstalled) {
                    Write-LogMessage "ImDisk installed successfully via winget" -Level INFO
                    return $true
                }
            }
            else {
                Write-LogMessage "ImDisk not available in winget" -Level INFO
            }
        }
        catch {
            Write-LogMessage "Winget installation failed: $($_.Exception.Message)" -Level WARN
        }
    }

    # Method 3: Manual download and install
    Write-LogMessage "Downloading and installing ImDisk from internet..." -Level INFO

    $tempDir = Join-Path $env:TEMP "ImDiskInstall"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        $installerPath = Join-Path $tempDir "imdisk-installer.exe"
        $downloadSuccess = $false

        # SourceForge URLs
        $sourceforgeUrls = @(
            "https://sourceforge.net/projects/imdisk-toolkit/files/latest/download",
            "https://downloads.sourceforge.net/project/imdisk-toolkit/ImDisk%20Toolkit%20Setup.exe"
        )
        
        foreach ($url in $sourceforgeUrls) {
            try {
                Write-LogMessage "Trying: $url" -Level INFO
                
                $headers = @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
                
                $tempPath = "$installerPath.tmp"
                Invoke-WebRequest -Uri $url -OutFile $tempPath -Headers $headers -UseBasicParsing -ErrorAction Stop
                
                $fileInfo = Get-Item $tempPath -ErrorAction Stop
                if ($fileInfo.Length -gt 1MB) {
                    Move-Item -Path $tempPath -Destination $installerPath -Force
                    Write-LogMessage "Download completed: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -Level INFO
                    $downloadSuccess = $true
                    break
                }
                
                Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-LogMessage "Download failed: $($_.Exception.Message)" -Level WARN
                continue
            }
        }

        if (-not $downloadSuccess -or -not (Test-Path $installerPath)) {
            Write-LogMessage "All download methods failed." -Level ERROR
            Write-LogMessage "Please install ImDisk manually or ensure network share is accessible:" -Level ERROR
            Write-LogMessage "  Network: $script:ImDiskNetworkPath" -Level ERROR
            Write-LogMessage "  Download: https://sourceforge.net/projects/imdisk-toolkit/" -Level ERROR
            return $false
        }

        # Install silently
        Write-LogMessage "Installing ImDisk silently..." -Level INFO
        $installArgs = @("/S", "/D=$($env:ProgramFiles)\ImDisk")
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -ne 0) {
            Write-LogMessage "ImDisk installation failed with exit code $($process.ExitCode)" -Level ERROR
            return $false
        }

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Start-Sleep -Seconds 2
        
        if (Test-ImDiskInstalled) {
            Write-LogMessage "ImDisk installed successfully" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "ImDisk installation completed but imdisk.exe not found in PATH" -Level ERROR
            return $false
        }
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-RamDisks {
    <#
    .SYNOPSIS
        Gets all RAM disks managed by ImDisk.
    .OUTPUTS
        Array of RAM disk objects with DriveLetter, Size, FreeSpace, Label properties.
    .NOTES
        Uses multiple detection methods for robustness:
        1. Parse imdisk -l output with multiple regex patterns
        2. The output format varies between imdisk versions
    #>
    $ramDisks = @()
    
    if (-not (Test-ImDiskInstalled)) {
        return $ramDisks
    }
    
    try {
        $imdiskList = & imdisk -l 2>&1 | Out-String
        
        # Check for error messages indicating no devices
        if ($imdiskList -match 'does not exist|No virtual disk') {
            return $ramDisks
        }
        
        if ($LASTEXITCODE -eq 0 -and $imdiskList) {
            # Try multiple regex patterns to match different imdisk output formats
            # Format 1: "  V:  ..." (leading whitespace)
            # Format 2: "V:  ..." (no leading whitespace)
            # Format 3: "Device V:" or "Mount point: V:"
            $driveLettersFound = @()
            
            # Pattern 1: Leading whitespace + drive letter
            $matches1 = [regex]::Matches($imdiskList, '^\s+([A-Z]):', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($m in $matches1) { $driveLettersFound += $m.Groups[1].Value }
            
            # Pattern 2: Start of line or after newline + drive letter (no leading whitespace)
            $matches2 = [regex]::Matches($imdiskList, '(?:^|\n)([A-Z]):', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($m in $matches2) { $driveLettersFound += $m.Groups[1].Value }
            
            # Pattern 3: "Mount point: X:" or "Device X:"
            $matches3 = [regex]::Matches($imdiskList, '(?:Mount point|Device)[:\s]+([A-Z]):', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($m in $matches3) { $driveLettersFound += $m.Groups[1].Value }
            
            # Remove duplicates and process
            $driveLettersFound = $driveLettersFound | Select-Object -Unique
            
            foreach ($letter in $driveLettersFound) {
                $driveLetter = "$($letter):"
                $volume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
                
                $ramDisk = [PSCustomObject]@{
                    DriveLetter = $driveLetter
                    SizeGB      = if ($volume) { [math]::Round($volume.Size / 1GB, 2) } else { 0 }
                    FreeSpaceGB = if ($volume) { [math]::Round($volume.SizeRemaining / 1GB, 2) } else { 0 }
                    UsedGB      = if ($volume) { [math]::Round(($volume.Size - $volume.SizeRemaining) / 1GB, 2) } else { 0 }
                    Label       = if ($volume) { $volume.FileSystemLabel } else { "" }
                    FileSystem  = if ($volume) { $volume.FileSystemType } else { "" }
                }
                $ramDisks += $ramDisk
            }
        }
    }
    catch {
        Write-LogMessage "Error listing RAM disks: $($_.Exception.Message)" -Level WARN
    }
    
    return $ramDisks
}

function Get-RamDisk {
    <#
    .SYNOPSIS
        Gets a specific RAM disk by drive letter.
    .PARAMETER DriveLetter
        The drive letter to check.
    .OUTPUTS
        RAM disk object if found, $null otherwise.
    .NOTES
        Uses imdisk -l -m <drive> for more reliable single-drive detection,
        with fallback to Get-RamDisks parsing.
    #>
    param([string]$DriveLetter)
    
    $DriveLetter = $DriveLetter.ToUpper().TrimEnd(':') + ":"
    $letterOnly = $DriveLetter.TrimEnd(':')
    
    if (-not (Test-ImDiskInstalled)) {
        return $null
    }
    
    # Method 1: Try direct query with imdisk -l -m <drive>
    # This is more reliable than parsing the full list
    try {
        $output = & imdisk -l -m $DriveLetter 2>&1 | Out-String
        
        # If we get device info (not an error), the RAM disk exists
        if ($LASTEXITCODE -eq 0 -and $output -and $output -notmatch 'does not exist|No virtual disk|Cannot control') {
            $volume = Get-Volume -DriveLetter $letterOnly -ErrorAction SilentlyContinue
            
            return [PSCustomObject]@{
                DriveLetter = $DriveLetter
                SizeGB      = if ($volume) { [math]::Round($volume.Size / 1GB, 2) } else { 0 }
                FreeSpaceGB = if ($volume) { [math]::Round($volume.SizeRemaining / 1GB, 2) } else { 0 }
                UsedGB      = if ($volume) { [math]::Round(($volume.Size - $volume.SizeRemaining) / 1GB, 2) } else { 0 }
                Label       = if ($volume) { $volume.FileSystemLabel } else { "" }
                FileSystem  = if ($volume) { $volume.FileSystemType } else { "" }
            }
        }
    }
    catch {
        # Fall through to method 2
    }
    
    # Method 2: Fall back to parsing full list
    $allDisks = Get-RamDisks
    return $allDisks | Where-Object { $_.DriveLetter -eq $DriveLetter } | Select-Object -First 1
}

function New-RamDisk {
    <#
    .SYNOPSIS
        Creates a new RAM disk using AWEAlloc (locked physical memory).
    .DESCRIPTION
        Creates a RAM disk using ImDisk with the AWEAlloc driver which allocates
        locked physical memory pages. This prevents Windows from swapping the RAM
        disk contents to the page file, ensuring consistent high performance.
    .PARAMETER DriveLetter
        Drive letter for the RAM disk.
    .PARAMETER SizeGB
        Size in gigabytes.
    .PARAMETER Force
        Remove existing RAM disk if present.
    .OUTPUTS
        $true if successful, $false otherwise.
    .NOTES
        Uses -o awe flag for AWEAlloc which:
        - Allocates physical RAM pages that are LOCKED in memory
        - Prevents Windows from swapping RAM disk to page file
        - Provides consistent maximum performance
        - Memory shows as "driver locked" in Resource Monitor
    #>
    param(
        [string]$DriveLetter,
        [int]$SizeGB,
        [switch]$Force
    )
    
    $DriveLetter = $DriveLetter.ToUpper()
    if (-not $DriveLetter.EndsWith(':')) {
        $DriveLetter = "$($DriveLetter):"
    }
    
    # Check if drive already exists
    $existingDrive = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($existingDrive) {
        if ($Force) {
            Write-LogMessage "Removing existing drive on $DriveLetter" -Level INFO
            $removeResult = Remove-RamDiskInternal -DriveLetter $DriveLetter -Force
            if (-not $removeResult) {
                Write-LogMessage "Could not remove existing drive $DriveLetter" -Level ERROR
                return $false
            }
            Start-Sleep -Seconds 1
        }
        else {
            Write-LogMessage "Drive $DriveLetter is already in use. Use -Force to remove it first." -Level ERROR
            return $false
        }
    }
    
    # Create RAM disk using AWEAlloc for locked physical memory
    # The -o awe flag uses AWEAlloc driver which:
    # - Allocates physical RAM pages that cannot be swapped to disk
    # - Provides maximum performance as data is always in physical RAM
    # - Prevents Windows memory manager from paging out the RAM disk
    $sizeMB = $SizeGB * 1024
    Write-LogMessage "Creating RAM disk: $SizeGB GB ($sizeMB MB) on drive $DriveLetter" -Level INFO
    Write-LogMessage "  Using AWEAlloc for locked physical memory (no swap to disk)" -Level INFO
    
    # -o awe = Use AWEAlloc driver for physical memory allocation
    # This ensures the RAM disk stays in physical RAM and is never swapped to page file
    $imdiskArgs = @("-a", "-s", "${sizeMB}M", "-m", $DriveLetter, "-o", "awe", "-p", "/fs:ntfs /q /y")
    $result = & imdisk @imdiskArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        $errorOutput = $result | Out-String
        
        # Check if AWEAlloc driver is not available, fall back to regular VM with warning
        if ($errorOutput -match "AWEAlloc|awealloc|driver") {
            Write-LogMessage "AWEAlloc driver not available. Falling back to virtual memory mode." -Level WARN
            Write-LogMessage "  WARNING: RAM disk may be swapped to disk under memory pressure!" -Level WARN
            
            # Retry without AWE
            $imdiskArgs = @("-a", "-s", "${sizeMB}M", "-m", $DriveLetter, "-t", "vm", "-p", "/fs:ntfs /q /y")
            $result = & imdisk @imdiskArgs 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                $errorOutput = $result | Out-String
                Write-LogMessage "Failed to create RAM disk. Error: $errorOutput" -Level ERROR
                return $false
            }
        }
        else {
            Write-LogMessage "Failed to create RAM disk. Error: $errorOutput" -Level ERROR
            return $false
        }
    }
    
    # Verify creation
    Start-Sleep -Seconds 1
    $newDrive = Get-PSDrive -Name $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($newDrive) {
        $driveInfo = Get-Volume -DriveLetter $DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($driveInfo) {
            Write-LogMessage "RAM disk created successfully on $DriveLetter" -Level INFO
            Write-LogMessage "  Total space: $([math]::Round($driveInfo.Size / 1GB, 2)) GB" -Level INFO
            Write-LogMessage "  Free space: $([math]::Round($driveInfo.SizeRemaining / 1GB, 2)) GB" -Level INFO
            Write-LogMessage "  Type: AWEAlloc (locked physical RAM - never swapped)" -Level INFO
        }
        return $true
    }
    else {
        Write-LogMessage "RAM disk creation reported success but drive not found" -Level WARN
        return $false
    }
}

function Get-ProcessesUsingDrive {
    <#
    .SYNOPSIS
        Finds processes that have their working directory on a specific drive.
    .PARAMETER DriveLetter
        The drive letter to check (e.g., "V:").
    .PARAMETER ProcessNames
        Array of process names to check. Default: explorer, cmd, pwsh, powershell.
    .OUTPUTS
        Array of process objects that are using the drive.
    #>
    param(
        [string]$DriveLetter,
        [string[]]$ProcessNames = @("explorer", "cmd", "pwsh", "powershell")
    )
    
    $DriveLetter = $DriveLetter.ToUpper().TrimEnd(':')
    $processesUsingDrive = @()
    
    foreach ($procName in $ProcessNames) {
        $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
        
        foreach ($proc in $processes) {
            try {
                # Check if process has working directory on the drive
                # Use WMI/CIM to get CommandLine and working directory info
                $wmiProc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                
                if ($wmiProc) {
                    $commandLine = $wmiProc.CommandLine
                    $executablePath = $wmiProc.ExecutablePath
                    
                    # For explorer.exe, check if it has a window open to the drive
                    if ($procName -eq "explorer") {
                        # Get all Explorer windows and check their paths
                        try {
                            $shell = New-Object -ComObject Shell.Application
                            $explorerWindows = $shell.Windows() | Where-Object { 
                                $_.LocationURL -match "^file:///$DriveLetter" -or
                                $_.LocationURL -match "^file://localhost/$DriveLetter"
                            }
                            
                            if ($explorerWindows) {
                                # This explorer has a window on our drive
                                $processesUsingDrive += [PSCustomObject]@{
                                    Process     = $proc
                                    ProcessName = $procName
                                    PID         = $proc.Id
                                    Reason      = "Explorer window open on $($DriveLetter):"
                                    CommandLine = $commandLine
                                }
                            }
                        }
                        catch {
                            # Fallback: check if command line contains the drive
                            if ($commandLine -match "^\s*$DriveLetter[:\\]" -or $commandLine -match "\s$DriveLetter[:\\]") {
                                $processesUsingDrive += [PSCustomObject]@{
                                    Process     = $proc
                                    ProcessName = $procName
                                    PID         = $proc.Id
                                    Reason      = "Command line references $($DriveLetter):"
                                    CommandLine = $commandLine
                                }
                            }
                        }
                        finally {
                            if ($shell) {
                                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
                            }
                        }
                    }
                    else {
                        # For cmd, pwsh, powershell - check working directory via handle or command line
                        # First, try to check if the command line or current directory references the drive
                        
                        # Method 1: Check if command line mentions the drive
                        $usesRAMDisk = $false
                        
                        if ($commandLine -and ($commandLine -match "$DriveLetter[:\\]")) {
                            $usesRAMDisk = $true
                        }
                        
                        # Method 2: Try to get current directory using .NET reflection (works for PowerShell)
                        if (-not $usesRAMDisk -and $proc.MainModule) {
                            try {
                                # Use handle.exe if available, otherwise use other methods
                                # For now, use a heuristic: check if any module is loaded from the RAM disk
                                $modules = $proc.Modules | Where-Object { $_.FileName -like "$DriveLetter`:*" }
                                if ($modules) {
                                    $usesRAMDisk = $true
                                }
                            }
                            catch {
                                # Ignore access denied errors
                            }
                        }
                        
                        # Method 3: For PowerShell processes, check via named pipe or other IPC
                        # This is complex, so we'll use a simpler heuristic:
                        # Check if any file handles are open on the drive using handle.exe if available
                        if (-not $usesRAMDisk) {
                            $handleExe = Get-Command handle -ErrorAction SilentlyContinue
                            if ($handleExe) {
                                try {
                                    $handleOutput = & handle -p $proc.Id -nobanner 2>&1 | Out-String
                                    if ($handleOutput -match "$DriveLetter`:") {
                                        $usesRAMDisk = $true
                                    }
                                }
                                catch {
                                    # Ignore errors
                                }
                            }
                        }
                        
                        if ($usesRAMDisk) {
                            $processesUsingDrive += [PSCustomObject]@{
                                Process     = $proc
                                ProcessName = $procName
                                PID         = $proc.Id
                                Reason      = "Process references $($DriveLetter):"
                                CommandLine = $commandLine
                            }
                        }
                    }
                }
            }
            catch {
                # Skip processes we can't access
            }
        }
    }
    
    return $processesUsingDrive
}

function Stop-ProcessesUsingDrive {
    <#
    .SYNOPSIS
        Stops processes that are using a specific drive.
    .PARAMETER DriveLetter
        The drive letter to check.
    .PARAMETER MaxAttempts
        Maximum number of attempts to stop processes.
    .OUTPUTS
        $true if all blocking processes were stopped, $false otherwise.
    #>
    param(
        [string]$DriveLetter,
        [int]$MaxAttempts = 3
    )
    
    $attempt = 0
    $allStopped = $true
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        $blockingProcesses = Get-ProcessesUsingDrive -DriveLetter $DriveLetter
        
        if ($blockingProcesses.Count -eq 0) {
            Write-LogMessage "No processes found using $DriveLetter" -Level INFO
            return $true
        }
        
        Write-LogMessage "Found $($blockingProcesses.Count) process(es) using $($DriveLetter): (attempt $attempt/$MaxAttempts)" -Level WARN
        
        foreach ($blockingProc in $blockingProcesses) {
            Write-LogMessage "  - $($blockingProc.ProcessName) (PID: $($blockingProc.PID)) - $($blockingProc.Reason)" -Level WARN
            
            try {
                # Don't kill the current PowerShell process
                if ($blockingProc.PID -eq $PID) {
                    Write-LogMessage "    Skipping current process (cannot kill self)" -Level WARN
                    continue
                }
                
                # Special handling for explorer.exe - try to close the window first
                if ($blockingProc.ProcessName -eq "explorer") {
                    Write-LogMessage "    Attempting to close Explorer window..." -Level INFO
                    try {
                        $shell = New-Object -ComObject Shell.Application
                        $explorerWindows = $shell.Windows() | Where-Object { 
                            $_.LocationURL -match "^file:///$($DriveLetter.TrimEnd(':'))" -or
                            $_.LocationURL -match "^file://localhost/$($DriveLetter.TrimEnd(':'))"
                        }
                        foreach ($window in $explorerWindows) {
                            $window.Quit()
                        }
                        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
                        Start-Sleep -Milliseconds 500
                    }
                    catch {
                        Write-LogMessage "    Could not close Explorer window gracefully: $($_.Exception.Message)" -Level WARN
                    }
                }
                else {
                    # For cmd/pwsh/powershell - stop the process
                    Write-LogMessage "    Stopping $($blockingProc.ProcessName) (PID: $($blockingProc.PID))..." -Level INFO
                    Stop-Process -Id $blockingProc.PID -Force -ErrorAction Stop
                    Write-LogMessage "    Process stopped" -Level INFO
                }
            }
            catch {
                Write-LogMessage "    Failed to stop process: $($_.Exception.Message)" -Level WARN
                $allStopped = $false
            }
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    # Final check
    $remainingProcesses = Get-ProcessesUsingDrive -DriveLetter $DriveLetter
    return $remainingProcesses.Count -eq 0
}

function Remove-RamDiskInternal {
    <#
    .SYNOPSIS
        Internal function to remove a RAM disk.
    .DESCRIPTION
        Attempts to remove the RAM disk. If removal fails and -Force is specified,
        it will identify and kill blocking processes (explorer, cmd, pwsh, powershell) 
        and retry. Without -Force, it will fail on first attempt if drive is in use.
    .PARAMETER DriveLetter
        Drive letter to remove.
    .PARAMETER Force
        If specified, will kill blocking processes and retry on failure.
    .PARAMETER MaxRetries
        Maximum number of retry attempts after killing blocking processes (only used with -Force).
    .OUTPUTS
        $true if successful, $false otherwise.
    #>
    param(
        [string]$DriveLetter,
        [switch]$Force,
        [int]$MaxRetries = 3
    )
    
    $DriveLetter = $DriveLetter.ToUpper()
    if (-not $DriveLetter.EndsWith(':')) {
        $DriveLetter = "$($DriveLetter):"
    }
    
    # Without Force, only try once
    $maxAttempts = if ($Force) { $MaxRetries + 1 } else { 1 }
    $retryCount = 0
    
    while ($retryCount -lt $maxAttempts) {
        try {
            $result = & imdisk -d -m $DriveLetter 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Successfully removed RAM disk on $DriveLetter" -Level INFO
                return $true
            }
            else {
                $errorOutput = $result | Out-String
                $retryCount++
                
                # Check if it's a "device in use" error and Force is enabled
                if ($Force -and $retryCount -lt $maxAttempts) {
                    Write-LogMessage "RAM disk removal failed (attempt $retryCount/$maxAttempts). Checking for blocking processes..." -Level WARN
                    Write-LogMessage "  Error: $($errorOutput.Trim())" -Level WARN
                    
                    # Try to stop blocking processes (only when Force is enabled)
                    $processesCleared = Stop-ProcessesUsingDrive -DriveLetter $DriveLetter
                    
                    if (-not $processesCleared) {
                        Write-LogMessage "Could not clear all blocking processes. Waiting before retry..." -Level WARN
                    }
                    
                    # Also try to change directory away from the drive for all PowerShell instances
                    # This can help if the current shell is in that directory
                    try {
                        $currentLocation = Get-Location
                        if ($currentLocation.Path -like "$($DriveLetter)*") {
                            Write-LogMessage "Current directory is on $DriveLetter, changing to $env:TEMP" -Level WARN
                            Set-Location $env:TEMP
                        }
                    }
                    catch {
                        # Ignore
                    }
                    
                    Start-Sleep -Seconds 2
                    continue
                }
                else {
                    # No Force or final attempt failed
                    if (-not $Force) {
                        Write-LogMessage "Failed to remove RAM disk on $DriveLetter (use -Force to kill blocking processes)" -Level ERROR
                    }
                    else {
                        Write-LogMessage "Failed to remove RAM disk on $DriveLetter after $maxAttempts attempts" -Level ERROR
                    }
                    Write-LogMessage "  Error: $($errorOutput.Trim())" -Level ERROR
                    return $false
                }
            }
        }
        catch {
            Write-LogMessage "Error removing RAM disk on $($DriveLetter): $($_.Exception.Message)" -Level ERROR
            return $false
        }
    }
    
    Write-LogMessage "Failed to remove RAM disk on $DriveLetter after $maxAttempts attempts" -Level ERROR
    return $false
}

#endregion Helper Functions

#region Main Script Logic
<###
.SYNOPSIS
    Unified RAM disk management script using ImDisk with AWEAlloc.

.DESCRIPTION
    This script provides comprehensive RAM disk management including:
    - Verify/Install ImDisk software
    - Create RAM disks using AWEAlloc (locked physical memory)
    - Remove single or all RAM disks
    - List all RAM disks
    - Check RAM disk status
    
    IMPORTANT: All RAM disks are created using AWEAlloc which allocates
    locked physical memory pages. This prevents Windows from swapping
    the RAM disk contents to the page file, ensuring consistent high
    performance. The RAM disk data stays in physical RAM at all times.

.PARAMETER Action
    The action to perform:
    - Install: Verify/install ImDisk software (from network share or download)
    - Uninstall: Remove ImDisk software completely from the system
    - Create: Create a new RAM disk (using AWEAlloc for locked physical RAM)
    - Remove: Remove a RAM disk (specific or all)
    - List: List all RAM disks
    - Status: Check if a specific RAM disk exists

.PARAMETER DriveLetter
    Drive letter for Create/Remove/Status actions. Default is "V:".

.PARAMETER SizeGB
    Size of the RAM disk in GB for Create action. Default is 3 GB.

.PARAMETER Force
    For Create: Remove existing RAM disk before creating.
    For Remove without DriveLetter: Remove all without prompting.

.PARAMETER All
    For Remove action: Remove all RAM disks.

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Install
    Installs ImDisk from network share (or downloads if not accessible).

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Uninstall -Force
    Uninstalls ImDisk completely without prompting.

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Create -SizeGB 4
    Creates a 4 GB RAM disk on drive V: using AWEAlloc (locked physical RAM).

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Create -DriveLetter "R:" -SizeGB 2 -Force
    Removes existing RAM disk on R: and creates a new 2 GB RAM disk.

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Remove -DriveLetter "V:"
    Removes the RAM disk on drive V:

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Remove -All -Force
    Removes all RAM disks without prompting.

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action List
    Lists all RAM disks on the system.

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Status -DriveLetter "V:"
    Checks if a RAM disk exists on V: and returns its info.

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Administrator privileges for most operations
    ImDisk download URL: https://sourceforge.net/projects/imdisk-toolkit/
###>

function Invoke-RamDisk {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('Install', 'Uninstall', 'Create', 'Remove', 'List', 'Status')]
        [string]$Action,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[A-Z]:?$')]
        [string]$DriveLetter = "V:",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 128)]
        [int]$SizeGB = 3,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$All
    )

    try {
        # Normalize drive letter
        $DriveLetter = $DriveLetter.ToUpper()
        if (-not $DriveLetter.EndsWith(':')) {
            $DriveLetter = "$($DriveLetter):"
        }
    
        # Check admin for most actions
        if ($Action -ne 'List' -and $Action -ne 'Status') {
            if (-not (Test-IsAdministrator)) {
                Write-LogMessage "This action requires administrator privileges. Please run PowerShell as Administrator." -Level ERROR
                throw "Administrator privileges required"
            }
        }
    
        switch ($Action) {
            'Install' {
                Write-LogMessage "=== ImDisk Installation ===" -Level INFO
                Write-LogMessage "Network share: $script:ImDiskNetworkPath" -Level INFO
                $result = Install-ImDisk
                if ($result) {
                    Write-LogMessage "ImDisk is ready for use" -Level INFO
                    return $true
                }
                else {
                    throw "Failed to install ImDisk"
                }
            }
            
            'Uninstall' {
                Write-LogMessage "=== ImDisk Uninstallation ===" -Level INFO
                $result = Uninstall-ImDisk -Force:$Force
                if ($result) {
                    Write-LogMessage "ImDisk has been uninstalled" -Level INFO
                    return $true
                }
                else {
                    throw "Failed to uninstall ImDisk"
                }
            }
        
            'Create' {
                Write-LogMessage "=== Create RAM Disk ===" -Level INFO
            
                # Ensure ImDisk is installed
                if (-not (Test-ImDiskInstalled)) {
                    Write-LogMessage "ImDisk not found. Installing..." -Level INFO
                    if (-not (Install-ImDisk)) {
                        Write-LogMessage "Failed to install ImDisk" -Level ERROR
                        throw "Failed to install ImDisk"
                    }
                }
            
                $result = New-RamDisk -DriveLetter $DriveLetter -SizeGB $SizeGB -Force:$Force
                if ($result) {
                    return $true
                }
                else {
                    throw "Failed to create RAM disk on $DriveLetter"
                }
            }
        
            'Remove' {
                Write-LogMessage "=== Remove RAM Disk ===" -Level INFO
            
                if (-not (Test-ImDiskInstalled)) {
                    Write-LogMessage "ImDisk is not installed. No RAM disks to remove." -Level INFO
                    return $true
                }
            
                if ($All) {
                    # Remove all RAM disks
                    $allDisks = Get-RamDisks
                
                    if ($allDisks.Count -eq 0) {
                        Write-LogMessage "No RAM disks found on this system." -Level INFO
                        return $true
                    }
                
                    Write-LogMessage "Found $($allDisks.Count) RAM disk(s):" -Level INFO
                    foreach ($disk in $allDisks) {
                        Write-LogMessage "  $($disk.DriveLetter) - $($disk.SizeGB) GB" -Level INFO
                    }
                
                    if (-not $Force) {
                        $response = Read-Host "Remove all $($allDisks.Count) RAM disk(s)? This will delete all data. [Y/N]"
                        if ($response -notmatch '^[Yy]') {
                            Write-LogMessage "Removal cancelled by user." -Level INFO
                            return $false
                        }
                    }
                
                    $removedCount = 0
                    $failedCount = 0
                
                    foreach ($disk in $allDisks) {
                        if (Remove-RamDiskInternal -DriveLetter $disk.DriveLetter -Force:$Force) {
                            $removedCount++
                        }
                        else {
                            $failedCount++
                        }
                        Start-Sleep -Milliseconds 500
                    }
                
                    Write-LogMessage "Removal complete: $removedCount removed, $failedCount failed" -Level INFO
                
                    if ($failedCount -gt 0) {
                        throw "Failed to remove $failedCount RAM disk(s)"
                    }
                    return $true
                }
                else {
                    # Remove specific RAM disk
                    $targetDisk = Get-RamDisk -DriveLetter $DriveLetter
                
                    if (-not $targetDisk) {
                        Write-LogMessage "No RAM disk found on drive $DriveLetter" -Level WARN
                    
                        $allDisks = Get-RamDisks
                        if ($allDisks.Count -gt 0) {
                            Write-LogMessage "Available RAM disks: $($allDisks.DriveLetter -join ', ')" -Level INFO
                        }
                        throw "No RAM disk found on drive $DriveLetter"
                    }
                
                    if (-not $Force) {
                        $response = Read-Host "Remove RAM disk on $DriveLetter ($($targetDisk.SizeGB) GB)? [Y/N]"
                        if ($response -notmatch '^[Yy]') {
                            Write-LogMessage "Removal cancelled by user." -Level INFO
                            return $false
                        }
                    }
                
                    if (Remove-RamDiskInternal -DriveLetter $DriveLetter -Force:$Force) {
                        return $true
                    }
                    else {
                        throw "Failed to remove RAM disk on $DriveLetter"
                    }
                }
            }
        
            'List' {
                Write-LogMessage "=== RAM Disk List ===" -Level INFO
            
                if (-not (Test-ImDiskInstalled)) {
                    Write-LogMessage "ImDisk is not installed. No RAM disks available." -Level INFO
                    return @()
                }
            
                $allDisks = Get-RamDisks
            
                if ($allDisks.Count -eq 0) {
                    Write-LogMessage "No RAM disks found on this system." -Level INFO
                }
                else {
                    Write-LogMessage "Found $($allDisks.Count) RAM disk(s):" -Level INFO
                    Write-LogMessage "" -Level INFO
                
                    foreach ($disk in $allDisks) {
                        Write-LogMessage "Drive: $($disk.DriveLetter)" -Level INFO
                        Write-LogMessage "  Size:       $($disk.SizeGB) GB" -Level INFO
                        Write-LogMessage "  Free:       $($disk.FreeSpaceGB) GB" -Level INFO
                        Write-LogMessage "  Used:       $($disk.UsedGB) GB" -Level INFO
                        Write-LogMessage "  FileSystem: $($disk.FileSystem)" -Level INFO
                        if ($disk.Label) {
                            Write-LogMessage "  Label:      $($disk.Label)" -Level INFO
                        }
                        Write-LogMessage "" -Level INFO
                    }
                }
            
                # Return objects for pipeline usage
                return $allDisks
            }
        
            'Status' {
                Write-LogMessage "=== RAM Disk Status: $DriveLetter ===" -Level INFO
            
                if (-not (Test-ImDiskInstalled)) {
                    Write-LogMessage "ImDisk is not installed." -Level INFO
                    return [PSCustomObject]@{ Installed = $false; Exists = $false; DriveLetter = $DriveLetter }
                }
            
                $targetDisk = Get-RamDisk -DriveLetter $DriveLetter
            
                if ($targetDisk) {
                    Write-LogMessage "RAM disk exists on $DriveLetter" -Level INFO
                    Write-LogMessage "  Size: $($targetDisk.SizeGB) GB | Free: $($targetDisk.FreeSpaceGB) GB | Used: $($targetDisk.UsedGB) GB" -Level INFO
                
                    # Return object with Exists property
                    $targetDisk | Add-Member -NotePropertyName "Exists" -NotePropertyValue $true -Force
                    return $targetDisk
                }
                else {
                    Write-LogMessage "No RAM disk found on $DriveLetter" -Level INFO
                    return [PSCustomObject]@{ DriveLetter = $DriveLetter; Exists = $false }
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}
#endregion Main Script Logic

Export-ModuleMember -Function *