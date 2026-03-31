<###
.SYNOPSIS
    Removes one or all RAM disks created by ImDisk.

.DESCRIPTION
    This script removes RAM disks created by ImDisk. It can remove a specific RAM disk
    by drive letter, or remove all RAM disks on the system. The script lists all RAM disks
    before removal for confirmation.

.PARAMETER DriveLetter
    Drive letter of the specific RAM disk to remove (format: "R:"). If not specified,
    all RAM disks will be removed.

.PARAMETER Force
    If specified, removes RAM disks without prompting for confirmation.

.PARAMETER ListOnly
    If specified, only lists RAM disks without removing them.

.EXAMPLE
    .\Remove-RamDisk.ps1
    Lists all RAM disks and prompts to remove them all

.EXAMPLE
    .\Remove-RamDisk.ps1 -DriveLetter "R:"
    Removes the RAM disk on drive R:

.EXAMPLE
    .\Remove-RamDisk.ps1 -Force
    Removes all RAM disks without prompting

.EXAMPLE
    .\Remove-RamDisk.ps1 -ListOnly
    Lists all RAM disks without removing them

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Administrator privileges and ImDisk installed
###>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]:$')]
    [string]$DriveLetter,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$ListOnly
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

    # Check if ImDisk is installed
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
        Write-LogMessage "ImDisk is not installed. Please install ImDisk first using New-RamDisk.ps1" -Level ERROR
        throw "ImDisk not found"
    }

    # Function to get all RAM disks
    function Get-RamDisks {
        $ramDisks = @()
        
        try {
            # Use ImDisk to list all mounted drives
            $imdiskList = & imdisk -l 2>&1 | Out-String
            
            if ($LASTEXITCODE -eq 0 -and $imdiskList) {
                # Parse ImDisk output to find drive letters
                # ImDisk output format: "ImDisk Virtual Disk Driver version X.X.X" followed by drive info
                $lines = $imdiskList -split "`n" | Where-Object { $_ -match '^\s+[A-Z]:\s+' }
                
                foreach ($line in $lines) {
                    # Extract drive letter from line (format: "  R:  ...")
                    if ($line -match '^\s+([A-Z]):\s+') {
                        $driveLetter = "$($matches[1]):"
                        
                        # Get volume information
                        $volume = Get-Volume -DriveLetter $matches[1] -ErrorAction SilentlyContinue
                        
                        $ramDisk = [PSCustomObject]@{
                            DriveLetter = $driveLetter
                            Size = if ($volume) { [math]::Round($volume.Size / 1GB, 2) } else { "Unknown" }
                            FreeSpace = if ($volume) { [math]::Round($volume.SizeRemaining / 1GB, 2) } else { "Unknown" }
                            Label = if ($volume) { $volume.FileSystemLabel } else { "" }
                        }
                        $ramDisks += $ramDisk
                    }
                }
            }
        }
        catch {
            # If ImDisk list fails, fall back to checking all drives
            Write-LogMessage "Could not list ImDisk drives directly, scanning all drives..." -Level WARN
            
            $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -match '^[A-Z]$' }
            
            foreach ($drive in $drives) {
                $driveLetter = "$($drive.Name):"
                try {
                    # Check if this is an ImDisk RAM disk by querying ImDisk
                    $imdiskInfo = & imdisk -l -m $driveLetter 2>&1
                    if ($LASTEXITCODE -eq 0 -and $imdiskInfo -match 'ImDisk') {
                        $volume = Get-Volume -DriveLetter $drive.Name -ErrorAction SilentlyContinue
                        $ramDisk = [PSCustomObject]@{
                            DriveLetter = $driveLetter
                            Size = if ($volume) { [math]::Round($volume.Size / 1GB, 2) } else { "Unknown" }
                            FreeSpace = if ($volume) { [math]::Round($volume.SizeRemaining / 1GB, 2) } else { "Unknown" }
                            Label = if ($volume) { $volume.FileSystemLabel } else { "" }
                        }
                        $ramDisks += $ramDisk
                    }
                }
                catch {
                    # Not an ImDisk drive, skip
                }
            }
        }
        
        return $ramDisks
    }

    # Get all RAM disks
    Write-LogMessage "Scanning for RAM disks..." -Level INFO
    $allRamDisks = Get-RamDisks

    if ($allRamDisks.Count -eq 0) {
        Write-LogMessage "No RAM disks found on this system." -Level INFO
        return
    }

    # Display found RAM disks
    Write-LogMessage "Found $($allRamDisks.Count) RAM disk(s):" -Level INFO
    foreach ($disk in $allRamDisks) {
        Write-LogMessage "  Drive: $($disk.DriveLetter) | Size: $($disk.Size) GB | Free: $($disk.FreeSpace) GB | Label: $($disk.Label)" -Level INFO
    }

    # If ListOnly, just display and exit
    if ($ListOnly) {
        Write-LogMessage "List-only mode: No RAM disks were removed." -Level INFO
        return
    }

    # Determine which RAM disks to remove
    $disksToRemove = @()
    
    if ($DriveLetter) {
        # Normalize drive letter
        $DriveLetter = $DriveLetter.ToUpper()
        if (-not $DriveLetter.EndsWith(':')) {
            $DriveLetter = "$($DriveLetter):"
        }

        # Find the specified RAM disk
        $targetDisk = $allRamDisks | Where-Object { $_.DriveLetter -eq $DriveLetter } | Select-Object -First 1
        
        if ($targetDisk) {
            $disksToRemove = @($targetDisk)
        }
        else {
            Write-LogMessage "RAM disk on drive $DriveLetter not found." -Level WARN
            Write-LogMessage "Available RAM disks: $($allRamDisks.DriveLetter -join ', ')" -Level INFO
            return
        }
    }
    else {
        # Remove all RAM disks
        $disksToRemove = $allRamDisks
    }

    # Confirm removal unless Force is specified
    if (-not $Force) {
        $removeCount = $disksToRemove.Count
        $driveList = ($disksToRemove | ForEach-Object { $_.DriveLetter }) -join ', '
        
        if ($removeCount -eq 1) {
            $confirmMessage = "Remove RAM disk on drive $driveList? This will delete all data on the RAM disk. [Y/N]: "
        }
        else {
            $confirmMessage = "Remove $removeCount RAM disk(s) on drive(s): $driveList? This will delete all data on the RAM disks. [Y/N]: "
        }

        $response = Read-Host $confirmMessage
        if ($response -notmatch '^[Yy]') {
            Write-LogMessage "Removal cancelled by user." -Level INFO
            return
        }
    }

    # Remove each RAM disk
    $removedCount = 0
    $failedCount = 0

    foreach ($disk in $disksToRemove) {
        try {
            Write-LogMessage "Removing RAM disk on drive $($disk.DriveLetter)..." -Level INFO
            
            # Use ImDisk to detach/remove the RAM disk
            # -d: detach/remove
            # -m: mount point (drive letter)
            $result = & imdisk -d -m $disk.DriveLetter 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Successfully removed RAM disk on drive $($disk.DriveLetter)" -Level INFO
                $removedCount++
                
                # Wait a moment for the drive to be fully removed
                Start-Sleep -Seconds 1
            }
            else {
                $errorOutput = $result | Out-String
                Write-LogMessage "Failed to remove RAM disk on drive $($disk.DriveLetter). Error: $errorOutput" -Level ERROR
                $failedCount++
            }
        }
        catch {
            Write-LogMessage "Error removing RAM disk on drive $($disk.DriveLetter): $($_.Exception.Message)" -Level ERROR -Exception $_
            $failedCount++
        }
    }

    # Summary
    Write-LogMessage "Removal complete: $removedCount removed, $failedCount failed" -Level INFO
    
    if ($failedCount -gt 0) {
        Write-LogMessage "Some RAM disks could not be removed. They may be in use or require a system restart." -Level WARN
    }
}
catch {
    Write-LogMessage "Error removing RAM disk(s): $($_.Exception.Message)" -Level ERROR -Exception $_
    throw
}
