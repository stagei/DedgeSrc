<###
.SYNOPSIS
    Unified RAM disk management script using ImDisk.

.DESCRIPTION
    This script provides comprehensive RAM disk management including:
    - Verify/Install ImDisk software
    - Create RAM disks (with or without force)
    - Remove single or all RAM disks
    - List all RAM disks
    - Check RAM disk status

.PARAMETER Action
    The action to perform:
    - Install: Verify/install ImDisk software
    - Create: Create a new RAM disk
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
    Verifies and installs ImDisk if not present.

.EXAMPLE
    .\Handle-RamDisk.ps1 -Action Create -SizeGB 4
    Creates a 4 GB RAM disk on drive V:

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

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('Install', 'Create', 'Remove', 'List', 'Status')]
    [string]$Action = 'Remove',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[A-Z]:?$')]
    [string]$DriveLetter = "V:",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 128)]
    [int]$SizeGB = 3,

    [Parameter(Mandatory = $false)]
    [bool]$Force = $true,

    [Parameter(Mandatory = $false)]
    [bool]$All = $false
)

$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force
Import-Module Handle-RamDisk -Force

try {
    Invoke-RamDisk -Action $Action -DriveLetter $DriveLetter -SizeGB $SizeGB -Force:$Force -All:$All
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}

#endregion Main Script Logic
