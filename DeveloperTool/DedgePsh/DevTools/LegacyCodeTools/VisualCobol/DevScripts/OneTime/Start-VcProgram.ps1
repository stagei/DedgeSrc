#Requires -Version 7.0
<#
.SYNOPSIS
    Runs a compiled COBOL program using Rocket Visual COBOL runw.exe.
.DESCRIPTION
    PowerShell replacement for VcRunWin.bat and VcRunBat.bat. Launches a compiled
    COBOL .int program via runw.exe with the proper environment variables set.

    Replaces: OldScripts\VisualCobolRunScripts\VcRunWin.bat, VcRunBat.bat

    Source: Rocket Visual COBOL Documentation Version 11 - Command line reference
.EXAMPLE
    .\Start-VcProgram.ps1 -ProgramName GMSTART -DbAlias DB2DEV
    .\Start-VcProgram.ps1 -ProgramName GMSTART -CobMode 64
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProgramName,

    [string]$DbAlias,

    [ValidateSet('32', '64')]
    [string]$CobMode = '32',

    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$binSuffix = if ($CobMode -eq '64') { 'bin64' } else { 'bin' }
$libSuffix = if ($CobMode -eq '64') { 'lib64' } else { 'lib' }

$rocketBase = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$mfBase = 'C:\Program Files (x86)\Micro Focus\Visual COBOL'

$vcBase = if (Test-Path "$($rocketBase)\$($binSuffix)\runw.exe") {
    $rocketBase
} elseif (Test-Path "$($mfBase)\$($binSuffix)\runw.exe") {
    $mfBase
} else {
    Write-LogMessage "runw.exe not found in Rocket Software or Micro Focus paths" -Level ERROR
    exit 1
}

$runwExe = Join-Path $vcBase "$($binSuffix)\runw.exe"
$binFolder = Join-Path $vcBase $binSuffix
$libFolder = Join-Path $vcBase $libSuffix

$env:COBDIR = "$($vcBase);$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl"
$env:COBCPY = "$($VcPath)\src\cbl\cpy;$($VcPath)\src\cbl\cpy\sys\cpy;$($VcPath)\src\cbl"
$env:COBPATH = "$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl"
$env:COBMODE = $CobMode
$env:MFVSSW = '/c /f'
$env:LIB = $libFolder

if ($env:PATH -notlike "*$($binFolder)*") {
    $env:PATH = "$($binFolder);$($env:PATH)"
}

$runArgs = @($ProgramName)
if ($DbAlias) { $runArgs += $DbAlias }
if ($ExtraArgs) { $runArgs += $ExtraArgs }

Write-LogMessage "Starting COBOL program: $($ProgramName) ($($CobMode)-bit)" -Level INFO
Start-Process -FilePath $runwExe -ArgumentList $runArgs -WindowStyle Minimized
