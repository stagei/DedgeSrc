#Requires -Version 7.0
<#
.SYNOPSIS
    Switches machine-level PATH and COBOL environment variables between environments.
.DESCRIPTION
    Toggles between legacy Micro Focus Net Express and modern Rocket Visual COBOL
    environments by updating machine-level environment variables and PATH entries.

    Replaces: OldScripts\switchMF\switchMF.ps1
    Changes from old version:
    - Updated paths from "Micro Focus\Visual COBOL" to "Rocket Software\Visual COBOL"
    - Uses GlobalFunctions Write-LogMessage instead of Write-Host
    - Implemented VCL (64-bit Visual COBOL) mode
    - Removed VCX (unused placeholder)
    - Cleaned up duplicate PATH entries and double-backslash handling

    Source: Rocket Visual COBOL Documentation Version 11 - To start a Visual COBOL command prompt
.EXAMPLE
    .\Switch-CobolEnvironment.ps1 -Mode VC
    .\Switch-CobolEnvironment.ps1 -Mode MF
    .\Switch-CobolEnvironment.ps1 -Mode VCL
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('MF', 'VC', 'VCL')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$VcBasePath = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$MfBasePath = 'C:\Program Files (x86)\Micro Focus\Net Express 5.1'
$VcPath = if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }
$GitPath = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\mingw64\bin'

function Set-MachineEnvVar {
    param([string]$Name, [string]$Value)
    [System.Environment]::SetEnvironmentVariable($Name, $Value, [System.EnvironmentVariableTarget]::Machine)
    $action = if ([string]::IsNullOrEmpty($Value)) { 'Removed' } else { 'Set' }
    Write-LogMessage "$($action) env var $($Name)" -Level INFO
}

function Update-MachinePath {
    param(
        [string[]]$RemovePatterns,
        [string[]]$AddPaths
    )
    $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine)
    $entries = $currentPath.Split(';') |
        Where-Object { $_.Trim().Length -gt 0 } |
        Select-Object -Unique

    $filtered = @()
    $allPatterns = $RemovePatterns + @('%PATH%')
    foreach ($entry in $entries) {
        $shouldRemove = $false
        foreach ($pattern in $allPatterns) {
            if ($entry -like "*$($pattern)*") {
                Write-LogMessage "Removing from PATH: $($entry)" -Level DEBUG
                $shouldRemove = $true
                break
            }
        }
        if (-not $shouldRemove) { $filtered += $entry }
    }

    foreach ($addPath in $AddPaths) {
        if ($filtered -notcontains $addPath) {
            $filtered += $addPath
            Write-LogMessage "Adding to PATH: $($addPath)" -Level DEBUG
        }
    }

    $newPath = ($filtered | Select-Object -Unique) -join ';'
    Set-MachineEnvVar -Name 'PATH' -Value $newPath
}

switch ($Mode) {
    'MF' {
        $removePatterns = @($GitPath, 'Rocket Software', 'Micro Focus', 'IBM\SQLLIB')
        $addPaths = @(
            "$($MfBasePath)\base\bin"
            "$($MfBasePath)\dialogsystem\bin"
            'C:\Program Files\IBM\SQLLIB\BIN'
            $GitPath
        )
        Update-MachinePath -RemovePatterns $removePatterns -AddPaths $addPaths
        Write-LogMessage "Switched to Micro Focus Net Express mode" -Level INFO
    }

    'VC' {
        if (-not (Test-Path $VcPath)) { New-Item -ItemType Directory -Path $VcPath -Force | Out-Null }
        Set-MachineEnvVar -Name 'VCPATH' -Value $VcPath
        Set-MachineEnvVar -Name 'COBCPY' -Value "$($VcPath)\src\cbl\cpy;$($VcPath)\src\cbl\cpy\sys\cpy;$($VcPath)\src\cbl;"
        Set-MachineEnvVar -Name 'COBPATH' -Value "$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl;"
        Set-MachineEnvVar -Name 'COBDIR' -Value "$($VcBasePath);$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl;"
        Set-MachineEnvVar -Name 'MFVSSW' -Value '/c /f'
        Set-MachineEnvVar -Name 'COBMODE' -Value '32'
        Set-MachineEnvVar -Name 'LIB' -Value "$($VcBasePath)\lib"

        $removePatterns = @($GitPath, 'Rocket Software', 'Micro Focus', 'IBM\SQLLIB')
        $addPaths = @(
            "$($VcBasePath)\bin"
            "$($VcBasePath)\lib"
            'C:\Program Files\IBM\SQLLIB\BIN'
            "$($VcPath)\cfg"
            $GitPath
        )
        Update-MachinePath -RemovePatterns $removePatterns -AddPaths $addPaths
        Write-LogMessage "Switched to Rocket Visual COBOL 32-bit mode (VCPATH=$($VcPath))" -Level INFO
    }

    'VCL' {
        if (-not (Test-Path $VcPath)) { New-Item -ItemType Directory -Path $VcPath -Force | Out-Null }
        Set-MachineEnvVar -Name 'VCPATH' -Value $VcPath
        Set-MachineEnvVar -Name 'COBCPY' -Value "$($VcPath)\src\cbl\cpy;$($VcPath)\src\cbl\cpy\sys\cpy;$($VcPath)\src\cbl;"
        Set-MachineEnvVar -Name 'COBPATH' -Value "$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl;"
        Set-MachineEnvVar -Name 'COBDIR' -Value "$($VcBasePath);$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl;"
        Set-MachineEnvVar -Name 'MFVSSW' -Value '/c /f'
        Set-MachineEnvVar -Name 'COBMODE' -Value '64'
        Set-MachineEnvVar -Name 'LIB' -Value "$($VcBasePath)\lib64"

        $removePatterns = @($GitPath, 'Rocket Software', 'Micro Focus', 'IBM\SQLLIB')
        $addPaths = @(
            "$($VcBasePath)\bin64"
            "$($VcBasePath)\lib64"
            'C:\Program Files\IBM\SQLLIB\BIN'
            "$($VcPath)\cfg"
            $GitPath
        )
        Update-MachinePath -RemovePatterns $removePatterns -AddPaths $addPaths
        Write-LogMessage "Switched to Rocket Visual COBOL 64-bit mode (VCPATH=$($VcPath))" -Level INFO
    }
}
