#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys compiled COBOL objects and sources to the runtime directory on t-no1fkmvct-app.
.DESCRIPTION
    After local compilation via Invoke-VcFullPipeline.ps1, this script copies:
      - Compiled objects (.int, .gnt) to \\t-no1fkmvct-app\opt\FkCblApps\FKMVCT\Objects
      - COBOL sources (.cbl)          to \\t-no1fkmvct-app\opt\FkCblApps\FKMVCT\Source\cbl
      - Copybooks (.cpy)              to \\t-no1fkmvct-app\opt\FkCblApps\FKMVCT\Source\cpy
      - Bind files (.bnd) optionally  to \\t-no1fkmvct-app\opt\FkCblApps\FKMVCT\Objects\bnd

    The server-side COBOL runtime (COBPATH, COBDIR) should point at FkCblApps\FKMVCT\Objects.
    Sources are deployed for reference and debugging.

    The *_uncertain source collections are explicitly excluded.

    SAFETY: Only t-no1fkmvct-app is allowed as target server.
.PARAMETER VcPath
    Local compilation workspace. Defaults to C:\fkavd\Dedge2.
.PARAMETER CblSourceFolder
    Local folder containing the authoritative .cbl source files.
    Defaults to the Step1 collection output.
.PARAMETER CpySourceFolder
    Local folder containing the authoritative .cpy copybook files.
    Defaults to the Step1 collection output.
.PARAMETER ServerName
    Target server. MUST be t-no1fkmvct-app (enforced).
.PARAMETER IncludeBnd
    Also transfer .bnd files for DB2 binding on the server.
.PARAMETER DryRun
    Show what would be copied without actually copying.
.EXAMPLE
    .\Deploy-VcCompiledToServer.ps1
.EXAMPLE
    .\Deploy-VcCompiledToServer.ps1 -IncludeBnd -DryRun
#>
[CmdletBinding()]
param(
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [string]$CblSourceFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cbl',

    [string]$CpySourceFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cpy',

    [string]$ServerName = 't-no1fkmvct-app',

    [switch]$IncludeBnd,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

if ($ServerName -ne 't-no1fkmvct-app') {
    Write-LogMessage "SAFETY: This script ONLY deploys to t-no1fkmvct-app. Requested: $($ServerName)" -Level ERROR
    exit 1
}

$uncBase = "\\$($ServerName)\opt\FkCblApps\FKMVCT"
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "Deploy COBOL to Server - $($timestamp)" -Level INFO
Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "Source VCPATH:   $($VcPath)" -Level INFO
Write-LogMessage "CBL sources:     $($CblSourceFolder)" -Level INFO
Write-LogMessage "CPY sources:     $($CpySourceFolder)" -Level INFO
Write-LogMessage "Target server:   $($ServerName)" -Level INFO
Write-LogMessage "UNC base:        $($uncBase)" -Level INFO
Write-LogMessage "Include .bnd:    $($IncludeBnd)" -Level INFO
Write-LogMessage "Dry run:         $($DryRun)" -Level INFO

$uncParent = "\\$($ServerName)\opt"
if (-not (Test-Path $uncParent)) {
    Write-LogMessage "Cannot access UNC share: $($uncParent)" -Level ERROR
    exit 1
}

$fkCblAppsPath = "\\$($ServerName)\opt\FkCblApps"
if (-not (Test-Path $fkCblAppsPath)) {
    if ($DryRun) {
        Write-LogMessage "[DRY] Would create: $($fkCblAppsPath)" -Level INFO
    } else {
        New-Item -ItemType Directory -Path $fkCblAppsPath -Force | Out-Null
        Write-LogMessage "Created: $($fkCblAppsPath)" -Level INFO
    }
}

# --- Transfer definitions ---
# Each entry: Name (log label), LocalDir, RemoteDir, Filter, Required
$transfers = @(
    @{
        Name      = 'Objects (.int)'
        LocalDir  = Join-Path $VcPath 'int'
        RemoteDir = Join-Path $uncBase 'Objects'
        Filter    = '*.int'
        Required  = $true
    }
    @{
        Name      = 'Objects (.gnt)'
        LocalDir  = Join-Path $VcPath 'gs'
        RemoteDir = Join-Path $uncBase 'Objects'
        Filter    = '*.gnt'
        Required  = $false
    }
    @{
        Name      = 'Source (.cbl)'
        LocalDir  = $CblSourceFolder
        RemoteDir = Join-Path $uncBase 'Source\cbl'
        Filter    = '*.cbl'
        Required  = $true
    }
    @{
        Name      = 'Source (.cpy)'
        LocalDir  = $CpySourceFolder
        RemoteDir = Join-Path $uncBase 'Source\cpy'
        Filter    = '*.cpy'
        Required  = $false
    }
)

if ($IncludeBnd) {
    $transfers += @{
        Name      = 'Bind files (.bnd)'
        LocalDir  = Join-Path $VcPath 'bnd'
        RemoteDir = Join-Path $uncBase 'Objects\bnd'
        Filter    = '*.bnd'
        Required  = $false
    }
}

$totalCopied = 0
$totalSkipped = 0
$totalErrors = 0

foreach ($xfer in $transfers) {
    $localDir = $xfer.LocalDir
    $remoteDir = $xfer.RemoteDir

    if (-not (Test-Path $localDir)) {
        if ($xfer.Required) {
            Write-LogMessage "Required local folder missing: $($localDir)" -Level ERROR
            exit 1
        }
        Write-LogMessage "Local folder not found (skipping): $($localDir)" -Level WARN
        continue
    }

    $files = @(Get-ChildItem -Path $localDir -Filter $xfer.Filter -File)
    if ($files.Count -eq 0) {
        Write-LogMessage "No $($xfer.Filter) files in $($localDir)" -Level WARN
        continue
    }

    Write-LogMessage "--- $($xfer.Name): $($files.Count) files ---" -Level INFO

    if (-not $DryRun) {
        if (-not (Test-Path $remoteDir)) {
            New-Item -ItemType Directory -Path $remoteDir -Force | Out-Null
            Write-LogMessage "  Created: $($remoteDir)" -Level INFO
        }
    }

    $folderCopied = 0
    $folderSkipped = 0

    foreach ($file in $files) {
        $destFile = Join-Path $remoteDir $file.Name

        $needsCopy = $true
        if (Test-Path $destFile) {
            $remoteItem = Get-Item $destFile
            if ($remoteItem.LastWriteTime -ge $file.LastWriteTime -and $remoteItem.Length -eq $file.Length) {
                $needsCopy = $false
                $folderSkipped++
            }
        }

        if ($needsCopy) {
            if ($DryRun) {
                $folderCopied++
            } else {
                try {
                    Copy-Item -Path $file.FullName -Destination $destFile -Force
                    $folderCopied++
                } catch {
                    Write-LogMessage "  Failed to copy $($file.Name): $($_.Exception.Message)" -Level ERROR
                    $totalErrors++
                }
            }
        }
    }

    if ($DryRun) {
        Write-LogMessage "  [DRY] Would copy: $($folderCopied), Unchanged: $($folderSkipped)" -Level INFO
    } else {
        Write-LogMessage "  Copied: $($folderCopied), Unchanged: $($folderSkipped)" -Level INFO
    }

    $totalCopied += $folderCopied
    $totalSkipped += $folderSkipped
}

Write-LogMessage '======================================================' -Level INFO
if ($DryRun) {
    Write-LogMessage "DRY RUN complete. No files were copied." -Level INFO
} else {
    Write-LogMessage "Transfer complete: $($totalCopied) copied, $($totalSkipped) unchanged, $($totalErrors) errors" -Level INFO
}
Write-LogMessage '======================================================' -Level INFO

if ($totalErrors -gt 0) { exit 1 }
exit 0
