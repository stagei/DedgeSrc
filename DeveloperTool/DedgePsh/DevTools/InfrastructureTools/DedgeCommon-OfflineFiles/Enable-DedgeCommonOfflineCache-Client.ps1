#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$UncPaths = @(
        "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles",
        "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientConfig",
        "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor"
    )
)

Import-Module GlobalFunctions -Force

$markerFile = Join-Path $env:LOCALAPPDATA "DedgeCommon-OfflineFiles-PendingPin.json"
$isServer = Test-IsServer -Quiet $true

if ($isServer) {
    Write-LogMessage "Running on Windows Server" -Level INFO
}
else {
    Write-LogMessage "Running on Windows client (workstation)" -Level INFO
}

Write-LogMessage "Folders to pin for offline access: $($UncPaths.Count)" -Level INFO
foreach ($p in $UncPaths) {
    Write-LogMessage "  $($p)" -Level INFO
}

# --- Step 1: Check and enable CscService (Offline Files) ---

$cscService = Get-Service -Name CscService -ErrorAction SilentlyContinue

if (-not $cscService) {
    Write-LogMessage "CscService (Offline Files) not found on this machine. Feature may not be available (e.g. Server Core)." -Level ERROR
    exit 1
}

Write-LogMessage "CscService status: $($cscService.Status), StartupType: $($cscService.StartType)" -Level INFO

$needsReboot = $false
$registryChanged = $false

if ($cscService.StartType -eq "Disabled") {
    Write-LogMessage "CscService is disabled. Enabling with StartupType = Automatic..." -Level WARN
    try {
        Set-Service -Name CscService -StartupType Automatic -ErrorAction Stop
        Write-LogMessage "CscService StartupType set to Automatic" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to set CscService startup type" -Level ERROR -Exception $_
        exit 1
    }
}

if ($cscService.Status -ne "Running") {
    Write-LogMessage "Attempting to start CscService..." -Level INFO
    try {
        Start-Service -Name CscService -ErrorAction Stop
        Start-Sleep -Seconds 2
        $cscService = Get-Service -Name CscService
        Write-LogMessage "CscService is now: $($cscService.Status)" -Level INFO
    }
    catch {
        Write-LogMessage "CscService could not start. Checking CSC driver configuration..." -Level WARN

        $cscDriverKey = "HKLM:\SYSTEM\CurrentControlSet\Services\CSC"
        if (Test-Path $cscDriverKey) {
            $drvStart = (Get-ItemProperty $cscDriverKey -Name Start).Start
            if ($drvStart -gt 1) {
                Write-LogMessage "CSC driver Start=$($drvStart), setting to 1 (System) for boot-time loading" -Level INFO
                Set-ItemProperty -Path $cscDriverKey -Name "Start" -Value 1 -Type DWord -Force
                $registryChanged = $true
            }

            $instancesKey = "$($cscDriverKey)\Instances"
            if (-not (Test-Path $instancesKey)) {
                Write-LogMessage "CSC minifilter Instances key missing. Creating filter registration..." -Level INFO
                New-Item -Path $instancesKey -Force | Out-Null
                Set-ItemProperty -Path $instancesKey -Name "DefaultInstance" -Value "CSC Instance" -Type String -Force
                $defaultInstanceKey = "$($instancesKey)\CSC Instance"
                New-Item -Path $defaultInstanceKey -Force | Out-Null
                Set-ItemProperty -Path $defaultInstanceKey -Name "Altitude" -Value "180100" -Type String -Force
                Set-ItemProperty -Path $defaultInstanceKey -Name "Flags" -Value 0 -Type DWord -Force
                Write-LogMessage "CSC minifilter registered: Altitude=180100" -Level INFO
                $registryChanged = $true
            }

            $cscParamsKey = "$($cscDriverKey)\Parameters"
            if (-not (Test-Path $cscParamsKey)) {
                Write-LogMessage "Creating CSC Parameters key with FormatDatabase=1 (initializes cache on boot)" -Level INFO
                New-Item -Path $cscParamsKey -Force | Out-Null
                Set-ItemProperty -Path $cscParamsKey -Name "FormatDatabase" -Value 1 -Type DWord -Force
                $registryChanged = $true
            }
            elseif (-not (Test-Path -Path (Join-Path $env:SystemRoot "CSC"))) {
                Write-LogMessage "CSC cache directory missing. Setting FormatDatabase=1 to initialize on boot" -Level INFO
                Set-ItemProperty -Path $cscParamsKey -Name "FormatDatabase" -Value 1 -Type DWord -Force
                $registryChanged = $true
            }
        }

        $needsReboot = $true
    }
}

if ($needsReboot) {
    $marker = @{
        UncPaths        = $UncPaths
        CreatedAt       = (Get-Date).ToString("o")
        RegistryChanged = $registryChanged
        Message         = "Reboot required to load CSC driver. Re-run this script after reboot to complete pinning."
    }
    $marker | ConvertTo-Json | Out-File -FilePath $markerFile -Encoding utf8 -Force
    Write-LogMessage "Reboot required. Marker saved to $($markerFile)" -Level WARN
    if ($registryChanged) {
        Write-LogMessage "Registry was updated (driver Start, filter registration, FormatDatabase). Reboot will initialize CSC." -Level WARN
    }
    Write-LogMessage "Please reboot the machine, then re-run this script to complete the offline files setup." -Level WARN
    exit 2
}

# --- Step 2: Pin each folder for offline access ---

$totalPinned = 0
$totalFailed = 0

foreach ($uncPath in $UncPaths) {
    Write-LogMessage "--- Processing: $($uncPath) ---" -Level INFO

    if (-not (Test-Path -Path $uncPath)) {
        Write-LogMessage "UNC path '$($uncPath)' is not reachable. Skipping." -Level WARN
        $totalFailed++
        continue
    }

    Write-LogMessage "Pinning '$($uncPath)' for offline access (recursive)..." -Level INFO

    $pinSucceeded = $false

    # attrib +P sets the Pinned attribute which is the reliable way to pin offline files from scripts.
    # CIM Win32_OfflineFilesCache::Pin returns success but silently does nothing on Windows 11.
    # Shell.Application InvokeVerb only works from an interactive Explorer process.
    Write-LogMessage "Pinning via attrib +P (recursive)..." -Level INFO
    try {
        & "$env:SystemRoot\System32\attrib.exe" +P "$uncPath" 2>&1 | Out-Null
        & "$env:SystemRoot\System32\attrib.exe" +P /S /D "$uncPath\*" 2>&1 | Out-Null

        $verifyAttr = & "$env:SystemRoot\System32\attrib.exe" "$uncPath" 2>&1
        if ($verifyAttr -match '\bP\b') {
            Write-LogMessage "Pin attribute set on '$($uncPath)'" -Level INFO
            $pinSucceeded = $true
        }
        else {
            Write-LogMessage "attrib +P did not set Pinned attribute: $($verifyAttr)" -Level WARN
        }
    }
    catch {
        Write-LogMessage "attrib +P failed: $($_.Exception.Message)" -Level WARN
    }

    if ($pinSucceeded) {
        $totalPinned++
        $fileCount = (Get-ChildItem -Path $uncPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-LogMessage "Files in '$($uncPath)': $($fileCount)" -Level INFO
    }
    else {
        $totalFailed++
        Write-LogMessage "Failed to pin '$($uncPath)'" -Level ERROR
    }
}

# --- Step 3: Force sync for all pinned paths ---

Write-LogMessage "Forcing initial synchronization for all pinned paths..." -Level INFO

try {
    $syncResult = Invoke-CimMethod -ClassName Win32_OfflineFilesCache `
        -Namespace "root\cimv2" `
        -MethodName "Synchronize" `
        -Arguments @{
            Paths = [string[]]$UncPaths
            Flags = [uint32]0x00000001
        } -ErrorAction Stop

    if ($syncResult.ReturnValue -eq 0) {
        Write-LogMessage "Initial synchronization completed successfully" -Level INFO
    }
    else {
        Write-LogMessage "Synchronization returned code $($syncResult.ReturnValue)" -Level WARN
    }
}
catch {
    Write-LogMessage "CIM Synchronize method failed: $($_.Exception.Message). Files will sync in background." -Level WARN
}

# --- Step 4: Verify ---

Write-LogMessage "Verifying offline files configuration..." -Level INFO

$cscDir = Join-Path $env:SystemRoot "CSC"
if (Test-Path -Path $cscDir) {
    Write-LogMessage "CSC cache directory exists at $($cscDir)" -Level INFO
}
else {
    Write-LogMessage "CSC cache directory not found at $($cscDir) - cache may be in a different location or still initializing" -Level WARN
}

$cscService2 = Get-Service -Name CscService -ErrorAction SilentlyContinue
Write-LogMessage "CscService final status: $($cscService2.Status), StartupType: $($cscService2.StartType)" -Level INFO

# --- Step 5: Clean up marker file if it existed ---

if (Test-Path -Path $markerFile) {
    Remove-Item -Path $markerFile -Force -ErrorAction SilentlyContinue
    Write-LogMessage "Removed pending-pin marker file" -Level DEBUG
}

$serverName = $UncPaths[0].Split('\')[2]
Write-LogMessage "Offline Files setup complete: $($totalPinned) pinned, $($totalFailed) failed out of $($UncPaths.Count) paths" -Level INFO
Write-LogMessage "Files will be available locally when '$($serverName)' is unreachable" -Level INFO

if ($totalFailed -gt 0) {
    exit 1
}
exit 0
