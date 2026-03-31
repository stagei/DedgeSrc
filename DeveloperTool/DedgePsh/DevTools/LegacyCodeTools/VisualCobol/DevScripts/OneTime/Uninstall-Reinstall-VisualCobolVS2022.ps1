#Requires -Version 7.0
<#
.SYNOPSIS
    Uninstalls (and optionally reinstalls) Rocket Visual COBOL 11.0 for Visual Studio 2022.
.DESCRIPTION
    Uses the same installer (vcvs2022_110.exe) with /uninstall then /install.
    Logs each step. Reinstall uses ignorechecks=1 if the normal install would
    fail due to VS2022ValidInstance=0 (installer not detecting VS 2022).

    Source: Rocket Visual COBOL Documentation Version 11 - Installing Visual COBOL Build Tools for Windows
.EXAMPLE
    .\Uninstall-Reinstall-VisualCobolVS2022.ps1 -UninstallOnly
    .\Uninstall-Reinstall-VisualCobolVS2022.ps1 -UseIgnoreChecksOnInstall
#>
[CmdletBinding()]
param(
    [string]$InstallerPath = "C:\Users\$($env:USERNAME)\Downloads\vcvs2022_110.exe",
    [string]$ReportFolder = $PSScriptRoot,
    [switch]$UseIgnoreChecksOnInstall,
    [switch]$UninstallOnly
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$altPath = "C:\Users\$($env:USERNAME)\Downloads\Rocket Visual Cobol For Visual Studio 2022 Version 11\vcvs2022_110.exe"
if (-not (Test-Path $InstallerPath) -and (Test-Path $altPath)) {
    $InstallerPath = $altPath
    Write-LogMessage "Using installer at: $($InstallerPath)" -Level INFO
}

if (-not (Test-Path $InstallerPath)) {
    Write-LogMessage "Installer not found: $($InstallerPath)" -Level ERROR
    exit 1
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$uninstallLog = Join-Path $ReportFolder "vcvs2022_uninstall_$($ts).log"
$installLog = Join-Path $ReportFolder "vcvs2022_reinstall_$($ts).log"

# --- Step 1: Uninstall ---
Write-LogMessage "Step 1: Uninstalling Rocket Visual COBOL for Visual Studio 2022..." -Level INFO
Write-LogMessage "Command: $($InstallerPath) /uninstall /quiet /norestart /log `"$($uninstallLog)`"" -Level INFO
$uninstallProc = Start-Process -FilePath $InstallerPath -ArgumentList '/uninstall', '/quiet', '/norestart', "/log `"$($uninstallLog)`"" -Wait -PassThru
$uninstallExit = $uninstallProc.ExitCode
$uninstallLevel = if ($uninstallExit -eq 0 -or $uninstallExit -eq 3010) { 'INFO' } else { 'WARN' }
Write-LogMessage "Uninstall finished with exit code: $($uninstallExit)" -Level $uninstallLevel

if ($uninstallExit -ne 0 -and $uninstallExit -ne 3010) {
    Write-LogMessage "Uninstall may have failed or requires reboot (3010). Check log: $($uninstallLog)" -Level WARN
}

if ($UninstallOnly) {
    Write-LogMessage "Uninstall only completed. Log: $($uninstallLog)" -Level INFO
    exit $uninstallExit
}

Start-Sleep -Seconds 5

# --- Step 2: Reinstall ---
$installArgs = @('/install', '/quiet', '/norestart', "/log `"$($installLog)`"")
if ($UseIgnoreChecksOnInstall) {
    $installArgs = @('/install', '/quiet', '/norestart', 'ignorechecks=1', "/log `"$($installLog)`"")
    Write-LogMessage "Step 2: Reinstalling with ignorechecks=1 (bypass VS2022 detection)..." -Level INFO
} else {
    Write-LogMessage "Step 2: Reinstalling Rocket Visual COBOL for Visual Studio 2022..." -Level INFO
}

Write-LogMessage "Command: $($InstallerPath) $($installArgs -join ' ')" -Level INFO
$installProc = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru
$installExit = $installProc.ExitCode
$installLevel = if ($installExit -eq 0 -or $installExit -eq 3010) { 'INFO' } else { 'WARN' }
Write-LogMessage "Reinstall finished with exit code: $($installExit)" -Level $installLevel

if ($installExit -ne 0 -and $installExit -ne 3010) {
    Write-LogMessage "Reinstall failed. If log shows VS2022ValidInstance=0, run again with -UseIgnoreChecksOnInstall" -Level WARN
    Write-LogMessage "Logs: $($uninstallLog) ; $($installLog)" -Level INFO
    exit $installExit
}

Write-LogMessage "Uninstall and reinstall completed. Logs: $($uninstallLog) ; $($installLog)" -Level INFO
exit 0
