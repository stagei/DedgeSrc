#Requires -Version 7.0
<#
.SYNOPSIS
    Checks if specific COBOL files exist across multiple directories.
.DESCRIPTION
    Quick sanity check that verifies expected files exist across configured
    directories. Used during migration validation to confirm files are
    in the correct locations.

    Replaces: OldScripts\VisualCobolCompareSrcToInt\CheckFiles.ps1
    Changes from old version:
    - Uses GlobalFunctions Write-LogMessage
    - Parameterized file list and search folders
    - Outputs structured results instead of plain text
    - Exits with non-zero code if any files are missing
.EXAMPLE
    .\Test-VcFileExistence.ps1
    .\Test-VcFileExistence.ps1 -FileNames 'GMSTART', 'GMAMONI' -SearchFolders 'C:\fkavd\Dedge2\src\cbl', 'C:\fkavd\Dedge2\int'
#>
[CmdletBinding()]
param(
    [string[]]$FileNames = @('BRHDEBX', 'BSFOPVA', 'D4BCUSTP', 'DBFBRAPG', 'DRHRRAPG', 'GMAMONI', 'GMVOKLT', 'M3MITMAS', 'OKHRSPT'),
    [string[]]$SearchFolders = @(
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT'
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt'
        '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV'
    )
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

Write-LogMessage "Checking existence of $($FileNames.Count) file(s) across $($SearchFolders.Count) folder(s)" -Level INFO

$results = @()
$missingCount = 0

foreach ($fileName in $FileNames) {
    foreach ($folder in $SearchFolders) {
        if (-not (Test-Path $folder)) {
            Write-LogMessage "Folder not accessible: $($folder)" -Level WARN
            $results += [PSCustomObject]@{ File = $fileName; Folder = $folder; Status = 'FOLDER_NOT_FOUND' }
            continue
        }

        $found = Get-ChildItem -Path $folder -Recurse -Filter "$($fileName)*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-LogMessage "FOUND: $($fileName) in $($folder) -> $($found.FullName)" -Level INFO
            $results += [PSCustomObject]@{ File = $fileName; Folder = $folder; Status = 'FOUND'; Path = $found.FullName }
        } else {
            Write-LogMessage "MISSING: $($fileName) not found in $($folder)" -Level WARN
            $results += [PSCustomObject]@{ File = $fileName; Folder = $folder; Status = 'MISSING'; Path = '' }
            $missingCount++
        }
    }
}

$results | Format-Table -AutoSize

if ($missingCount -gt 0) {
    Write-LogMessage "$($missingCount) file-folder combination(s) missing" -Level WARN
    exit 1
} else {
    Write-LogMessage "All files found" -Level INFO
    exit 0
}
