#Requires -Version 7.0
<#
.SYNOPSIS
    Configures the COBOL Server runtime environment on t-no1fkmvct-app.
.DESCRIPTION
    Sets machine-level environment variables required by the Rocket COBOL Server
    runtime (run.exe, runw.exe, dswin.exe) to find compiled objects and copybooks
    in the FkCblApps\FKMVCT directory structure.

    Based on the environment variable pattern from Switch-CobolEnvironment.ps1
    which was tested and working in the earlier (2024) pilot.

    Server directory structure:
      %OptPath%\FkCblApps\FKMVCT\Objects\        .int and .gnt files
      %OptPath%\FkCblApps\FKMVCT\Objects\bnd\    .bnd files (optional)
      %OptPath%\FkCblApps\FKMVCT\Source\cbl\     .cbl source files
      %OptPath%\FkCblApps\FKMVCT\Source\cpy\     .cpy copybook files

    SAFETY: This script configures t-no1fkmvct-app ONLY.
    It must be deployed to and run on that server (via /autocur or manual).
.PARAMETER CobMode
    Compiler bit mode: 32 or 64. Defaults to 32.
.PARAMETER DryRun
    Show what would be changed without actually modifying environment variables.
.EXAMPLE
    .\Configure-VcServerRuntime.ps1
.EXAMPLE
    .\Configure-VcServerRuntime.ps1 -CobMode 64 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('32', '64')]
    [string]$CobMode = '32',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$computerName = $env:COMPUTERNAME.ToLower()
if ($computerName -notlike '*fkmvct*') {
    Write-LogMessage "SAFETY: This script should only run on t-no1fkmvct-app. Current machine: $($env:COMPUTERNAME)" -Level WARN
}

$optPath = $env:OptPath
if ([string]::IsNullOrWhiteSpace($optPath)) {
    $optPath = 'E:\opt'
    Write-LogMessage "OptPath not set, defaulting to $($optPath)" -Level WARN
}

$appBase = Join-Path $optPath 'FkCblApps\FKMVCT'
$objectsDir = Join-Path $appBase 'Objects'
$sourceCblDir = Join-Path $appBase 'Source\cbl'
$sourceCpyDir = Join-Path $appBase 'Source\cpy'

$binSuffix = if ($CobMode -eq '64') { 'bin64' } else { 'bin' }
$libSuffix = if ($CobMode -eq '64') { 'lib64' } else { 'lib' }

$rocketBase = 'C:\Program Files (x86)\Rocket Software\COBOL Server'
$rocketBaseAlt = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$mfBase = 'C:\Program Files (x86)\Micro Focus\Visual COBOL'

$vcBase = if (Test-Path "$($rocketBase)\$($binSuffix)") {
    $rocketBase
} elseif (Test-Path "$($rocketBaseAlt)\$($binSuffix)") {
    $rocketBaseAlt
} elseif (Test-Path "$($mfBase)\$($binSuffix)") {
    Write-LogMessage "Using legacy Micro Focus path" -Level WARN
    $mfBase
} else {
    Write-LogMessage "No COBOL Server/Visual COBOL installation found" -Level ERROR
    exit 1
}

Write-LogMessage "COBOL Server base: $($vcBase)" -Level INFO
Write-LogMessage "Application base:  $($appBase)" -Level INFO
Write-LogMessage "Objects dir:       $($objectsDir)" -Level INFO
Write-LogMessage "Source CBL dir:    $($sourceCblDir)" -Level INFO
Write-LogMessage "Source CPY dir:    $($sourceCpyDir)" -Level INFO
Write-LogMessage "Mode:              $($CobMode)-bit" -Level INFO

$dirs = @($appBase, $objectsDir, $sourceCblDir, $sourceCpyDir, (Join-Path $objectsDir 'bnd'))
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        if ($DryRun) {
            Write-LogMessage "[DRY] Would create: $($dir)" -Level INFO
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-LogMessage "Created: $($dir)" -Level INFO
        }
    }
}

$envVars = [ordered]@{
    COBDIR  = "$($vcBase);$($objectsDir);$($sourceCblDir)"
    COBPATH = "$($objectsDir);$($sourceCblDir)"
    COBCPY  = "$($sourceCpyDir);$($sourceCblDir)"
    COBMODE = $CobMode
    MFVSSW  = '/c /f'
    LIB     = "$($vcBase)\$($libSuffix)"
}

Write-LogMessage '--- Machine Environment Variables ---' -Level INFO
foreach ($entry in $envVars.GetEnumerator()) {
    $current = [System.Environment]::GetEnvironmentVariable($entry.Key, [System.EnvironmentVariableTarget]::Machine)
    if ($current -eq $entry.Value) {
        Write-LogMessage "  $($entry.Key) = $($entry.Value) (unchanged)" -Level DEBUG
    } else {
        if ($DryRun) {
            Write-LogMessage "  [DRY] $($entry.Key) = $($entry.Value)" -Level INFO
        } else {
            [System.Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, [System.EnvironmentVariableTarget]::Machine)
            Write-LogMessage "  Set $($entry.Key) = $($entry.Value)" -Level INFO
        }
    }
}

$binFolder = "$($vcBase)\$($binSuffix)"
$libFolder = "$($vcBase)\$($libSuffix)"
$db2Bin = 'C:\Program Files\IBM\SQLLIB\BIN'

$currentPath = [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine)
$pathEntries = $currentPath.Split(';') |
    Where-Object { $_.Trim().Length -gt 0 } |
    Select-Object -Unique

$requiredPaths = @($binFolder, $libFolder, $db2Bin)
$pathChanged = $false

foreach ($reqPath in $requiredPaths) {
    if ($pathEntries -notcontains $reqPath) {
        if ($DryRun) {
            Write-LogMessage "  [DRY] Would add to PATH: $($reqPath)" -Level INFO
        } else {
            $pathEntries = @($reqPath) + $pathEntries
            $pathChanged = $true
            Write-LogMessage "  Added to PATH: $($reqPath)" -Level INFO
        }
    } else {
        Write-LogMessage "  Already in PATH: $($reqPath)" -Level DEBUG
    }
}

if ($pathChanged -and -not $DryRun) {
    $newPath = ($pathEntries | Select-Object -Unique) -join ';'
    [System.Environment]::SetEnvironmentVariable('PATH', $newPath, [System.EnvironmentVariableTarget]::Machine)
    Write-LogMessage "Machine PATH updated" -Level INFO
}

Write-LogMessage '======================================================' -Level INFO
if ($DryRun) {
    Write-LogMessage "DRY RUN complete. No changes were made." -Level INFO
} else {
    Write-LogMessage "COBOL Server runtime environment configured for $($CobMode)-bit" -Level INFO
    Write-LogMessage "Reboot or restart services for PATH changes to take effect" -Level INFO
}
Write-LogMessage '======================================================' -Level INFO

exit 0
