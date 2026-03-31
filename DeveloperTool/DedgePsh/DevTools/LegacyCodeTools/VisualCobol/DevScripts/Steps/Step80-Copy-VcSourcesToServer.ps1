#Requires -Version 7.0
<#
.SYNOPSIS
    Copies all COBOL source files and copybooks to a remote server via UNC.
.DESCRIPTION
    Copies the collected CBL and CPY files from the local Step1 output to a
    target server's opt\data\VisualCobol\Sources folder via UNC share.

    This enables compilation on the server without requiring the original
    source collection to be re-run.

    Files retain their ANSI-1252 encoding (binary copy).
.PARAMETER SourceFolder
    Root folder containing cbl/, cpy/, cbl_uncertain/, cpy_uncertain/ subfolders.
.PARAMETER TargetServer
    Server name for UNC path (e.g. dedge-server).
.PARAMETER TargetBasePath
    Base path on the server under opt share. Defaults to data\VisualCobol\Sources.
.PARAMETER Force
    Overwrite existing files on target.
.EXAMPLE
    .\Copy-VcSourcesToServer.ps1
.EXAMPLE
    .\Copy-VcSourcesToServer.ps1 -TargetServer 't-no1fkxtst-db'
#>
[CmdletBinding()]
param(
    [string]$SourceFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources',

    [string]$TargetServer = 'dedge-server',

    [string]$TargetBasePath = 'data\VisualCobol\Sources',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$targetRoot = "\\$($TargetServer)\opt\$($TargetBasePath)"

Write-LogMessage "=== Copy COBOL Sources to Server ===" -Level INFO
Write-LogMessage "Source:  $($SourceFolder)" -Level INFO
Write-LogMessage "Target:  $($targetRoot)" -Level INFO

if (-not (Test-Path $SourceFolder)) {
    Write-LogMessage "Source folder not found: $($SourceFolder)" -Level ERROR
    exit 1
}

$testUncParent = "\\$($TargetServer)\opt\data"
if (-not (Test-Path $testUncParent)) {
    Write-LogMessage "Cannot access UNC share: $($testUncParent)" -Level ERROR
    exit 1
}

$subfolders = @('cbl', 'cpy', 'cbl_uncertain', 'cpy_uncertain')

$totalCopied = 0
$totalSkipped = 0

foreach ($sub in $subfolders) {
    $srcSub = Join-Path $SourceFolder $sub
    $dstSub = Join-Path $targetRoot $sub

    if (-not (Test-Path $srcSub)) {
        Write-LogMessage "Source subfolder not found (skipping): $($srcSub)" -Level WARN
        continue
    }

    if (-not (Test-Path $dstSub)) {
        New-Item -ItemType Directory -Path $dstSub -Force | Out-Null
        Write-LogMessage "Created target folder: $($dstSub)" -Level INFO
    }

    $files = @(Get-ChildItem -Path $srcSub -File)
    Write-LogMessage "Copying $($files.Count) files from $($sub)..." -Level INFO

    $copied = 0
    $skipped = 0
    foreach ($f in $files) {
        $dstFile = Join-Path $dstSub $f.Name
        if (-not $Force -and (Test-Path $dstFile)) {
            $srcTime = $f.LastWriteTime
            $dstTime = (Get-Item $dstFile).LastWriteTime
            if ($srcTime -le $dstTime) {
                $skipped++
                continue
            }
        }
        Copy-Item -Path $f.FullName -Destination $dstFile -Force
        $copied++
    }

    Write-LogMessage "  $($sub): copied=$($copied), skipped=$($skipped)" -Level INFO
    $totalCopied += $copied
    $totalSkipped += $skipped
}

Write-LogMessage "=== Copy Complete ===" -Level INFO
Write-LogMessage "Total copied:  $($totalCopied)" -Level INFO
Write-LogMessage "Total skipped: $($totalSkipped)" -Level INFO

if ($totalCopied -gt 0) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    Send-Sms -Receiver $smsNumber -Message "COBOL sources copied to $($TargetServer): $($totalCopied) files copied, $($totalSkipped) skipped."
}

exit 0
