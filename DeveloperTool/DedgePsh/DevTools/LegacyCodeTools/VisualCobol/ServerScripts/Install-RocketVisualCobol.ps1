#Requires -Version 7.0
<#
.SYNOPSIS
    Installs Rocket Visual COBOL packages using Install-WindowsApps.
.DESCRIPTION
    Wrapper script to install one or more Rocket Visual COBOL packages from
    C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\.

    Available packages:
    1. Rocket Visual Cobol For Visual Studio 2022 Version 11 (base install)
    2. Rocket Visual Cobol For Visual Studio 2022 Version 11 Update Patch 3
    3. Rocket Visual Cobol Server Version 11 (base server runtime)
    4. Rocket Visual Cobol Server Version 11 Update Patch 3
    5. Rocket Temp (staging area with multiple products)

    Install order matters: install base versions before patches.
.PARAMETER Package
    Which package to install. Choose from predefined names or 'All'.
.PARAMETER Force
    Force reinstallation even if already installed.
.EXAMPLE
    .\Install-RocketVisualCobol.ps1 -Package 'VS2022-Base'
.EXAMPLE
    .\Install-RocketVisualCobol.ps1 -Package 'All'
.EXAMPLE
    .\Install-RocketVisualCobol.ps1 -Package 'Server-Base' -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'VS2022-Base',
        'VS2022-Patch3',
        'Server-Base',
        'Server-Patch3',
        'Temp',
        'All-VS2022',
        'All-Server',
        'All'
    )]
    [string]$Package,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Import-Module SoftwareUtils -Force

$packageMap = [ordered]@{
    'VS2022-Base'   = 'Rocket Visual Cobol For Visual Studio 2022 Version 11'
    'VS2022-Patch3' = 'Rocket Visual Cobol For Visual Studio 2022 Version 11 Update Patch 3'
    'Server-Base'   = 'Rocket Visual Cobol Server Version 11'
    'Server-Patch3' = 'Rocket Visual Cobol Server Version 11 Update Patch 3'
    'Temp'          = 'Rocket Temp'
}

$installOrder = switch ($Package) {
    'All-VS2022' { @('VS2022-Base', 'VS2022-Patch3') }
    'All-Server' { @('Server-Base', 'Server-Patch3') }
    'All'        { @('VS2022-Base', 'VS2022-Patch3', 'Server-Base', 'Server-Patch3') }
    default      { @($Package) }
}

foreach ($pkg in $installOrder) {
    $appName = $packageMap[$pkg]
    Write-Host "=== Installing: $($appName) ===" -ForegroundColor Cyan
    if ($Force) {
        Install-WindowsApps -AppName $appName -Force
    } else {
        Install-WindowsApps -AppName $appName
    }
    Write-Host ''
}

Write-Host 'Installation sequence complete.' -ForegroundColor Green
