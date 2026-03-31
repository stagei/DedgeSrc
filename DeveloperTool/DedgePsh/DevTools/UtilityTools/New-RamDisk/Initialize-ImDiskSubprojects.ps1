<###
.SYNOPSIS
    Initializes the subprojects directory structure for ImDisk extensions.

.DESCRIPTION
    Creates the subprojects directory structure under C:\opt\src\imdisk\subprojects\
    with example templates for custom PowerShell modules, C# extensions, and documentation.

.PARAMETER SubprojectsPath
    Path to subprojects directory. Default: C:\opt\src\imdisk\subprojects

.PARAMETER Force
    Overwrite existing directories if they exist.

.EXAMPLE
    .\Initialize-ImDiskSubprojects.ps1
    Creates the subprojects structure

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
###>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubprojectsPath = "C:\opt\src\imdisk\subprojects",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

try {
    Write-LogMessage "Initializing ImDisk subprojects structure..." -Level INFO

    # Create base subprojects directory
    New-Item -Path $SubprojectsPath -ItemType Directory -Force | Out-Null

    # Define subproject structure
    $subprojects = @{
        "PowerShellModules" = @{
            "ImDisk-Manager" = @{
                "ImDisk-Manager.psm1" = @"
# ImDisk Manager Module
# Custom PowerShell module for managing ImDisk RAM disks

function Get-ImDiskInfo {
    <#
    .SYNOPSIS
        Gets information about all ImDisk RAM disks.
    #>
    param()
    
    $imdiskList = & imdisk -l 2>&1
    return $imdiskList
}

function New-ImDiskRamDisk {
    <#
    .SYNOPSIS
        Creates a new RAM disk using ImDisk.
    .PARAMETER SizeGB
        Size in gigabytes
    .PARAMETER DriveLetter
        Drive letter (e.g., "R:")
    #>
    param(
        [int]$SizeGB = 1,
        [string]$DriveLetter = "R:"
    )
    
    $sizeMB = $SizeGB * 1024
    & imdisk -a -s "${sizeMB}M" -m $DriveLetter -p "/fs:ntfs /q /y"
}

Export-ModuleMember -Function Get-ImDiskInfo, New-ImDiskRamDisk
"@
            }
        }
        "CSharpExtensions" = @{
            "README.md" = @"
# C# Extensions for ImDisk

Place your C# extension projects here.

## Example Structure

```
CSharpExtensions/
├── ImDiskWrapper/          # C# wrapper library
│   ├── ImDiskWrapper.csproj
│   └── ImDiskWrapper.cs
└── ImDiskService/          # Windows service wrapper
    ├── ImDiskService.csproj
    └── ImDiskService.cs
```
"@
        }
        "Documentation" = @{
            "README.md" = @"
# ImDisk Internal Documentation

Internal documentation, modifications, and notes about your ImDisk build.

## Structure

- `BuildNotes.md` - Build configuration and modifications
- `Customizations.md` - Custom changes made to ImDisk
- `UsageExamples.md` - Internal usage examples
"@
            "BuildNotes.md" = @"
# ImDisk Build Notes

## Build Configuration

- **Source**: https://github.com/LTRData/ImDisk.git
- **Branch**: master
- **Build Date**: $(Get-Date -Format 'yyyy-MM-dd')
- **Build By**: $env:USERNAME

## Modifications

List any modifications made to the source code here.

## Build Requirements

- Visual Studio 2019 or later
- .NET Framework 4.8
- Windows Driver Kit (for driver build)
"@
        }
        "Scripts" = @{
            "README.md" = @"
# ImDisk Utility Scripts

Custom PowerShell scripts for ImDisk management.

## Examples

- `Backup-RamDisk.ps1` - Backup RAM disk contents
- `Monitor-RamDisk.ps1` - Monitor RAM disk usage
- `Auto-CreateRamDisks.ps1` - Auto-create RAM disks on startup
"@
        }
    }

    # Create subproject structure
    foreach ($category in $subprojects.Keys) {
        $categoryPath = Join-Path $SubprojectsPath $category
        Write-LogMessage "Creating category: $category" -Level INFO
        
        if (Test-Path $categoryPath -PathType Container) {
            if ($Force) {
                Write-LogMessage "  Removing existing directory..." -Level WARN
                Remove-Item -Path $categoryPath -Recurse -Force
                New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null
            }
            else {
                Write-LogMessage "  Directory exists, skipping..." -Level INFO
                continue
            }
        }
        else {
            New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null
        }

        # Create files in this category
        foreach ($itemName in $subprojects[$category].Keys) {
            $itemPath = Join-Path $categoryPath $itemName
            
            if ($itemName -match '\.(psm1|ps1|md)$') {
                # It's a file
                if (-not (Test-Path $itemPath) -or $Force) {
                    $content = $subprojects[$category][$itemName]
                    Set-Content -Path $itemPath -Value $content -Force
                    Write-LogMessage "  Created: $itemName" -Level INFO
                }
            }
            else {
                # It's a directory
                if (-not (Test-Path $itemPath) -or $Force) {
                    New-Item -Path $itemPath -ItemType Directory -Force | Out-Null
                    Write-LogMessage "  Created directory: $itemName" -Level INFO
                }
            }
        }
    }

    # Create main README
    $mainReadme = @"
# ImDisk Subprojects

This directory contains custom extensions, modifications, and utilities for ImDisk.

## Structure

- **PowerShellModules/** - Custom PowerShell modules for ImDisk management
- **CSharpExtensions/** - C# wrapper libraries and extensions
- **Documentation/** - Internal documentation and build notes
- **Scripts/** - Utility scripts for RAM disk management

## Getting Started

1. Review the example modules in PowerShellModules/
2. Add your custom projects to the appropriate category
3. Document your changes in Documentation/

## Author

Geir Helge Starholm, www.dEdge.no
"@

    $mainReadmePath = Join-Path $SubprojectsPath "README.md"
    Set-Content -Path $mainReadmePath -Value $mainReadme -Force

    Write-LogMessage "Subprojects structure initialized at: $SubprojectsPath" -Level INFO
    Write-LogMessage "Categories created:" -Level INFO
    foreach ($category in $subprojects.Keys) {
        Write-LogMessage "  - $category" -Level INFO
    }
}
catch {
    Write-LogMessage "Error initializing subprojects: $($_.Exception.Message)" -Level ERROR -Exception $_
    throw
}
