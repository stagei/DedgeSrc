#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
    Converts PowerShell scripts to C# using AST-based conversion + Cursor Agent CLI cleanup.

.DESCRIPTION
    Pipeline:
      1. Mechanical conversion via PwshToCSharpConverter (AST-based, custom-built)
      2. AI-powered cleanup via Cursor Agent CLI (fix types, naming, patterns)
      3. Optional dotnet build verification

    Supports single file or folder of .ps1 files.

.PARAMETER InputPath
    Path to a .ps1 file or a folder containing .ps1 files.

.PARAMETER OutputPath
    Destination folder for converted .cs files. Created if missing.
    Sub-folders: raw\ (mechanical output), cleaned\ (after Agent CLI).

.PARAMETER TargetProjectPath
    Path to the target .csproj directory. When set, the Agent CLI cleanup
    runs with this as the workspace so it can edit the .cs files in place
    and verify against the project.

.PARAMETER Namespace
    C# namespace for the generated code. Default: ConvertedScripts.

.PARAMETER SkipCleanup
    Skip the Cursor Agent CLI post-conversion cleanup pass.

.PARAMETER SkipBuildVerification
    Skip the dotnet build check after conversion.

.PARAMETER CleanupModel
    Cursor Agent CLI model for the cleanup pass. Default: claude-sonnet-4-20250514.

.PARAMETER CleanupPasses
    Number of Agent CLI cleanup passes per file. Default: 2.
    Pass 1 fixes compilation errors and types. Pass 2 refactors structure.

.EXAMPLE
    pwsh.exe -NoProfile -File Convert-PwshToCSharp.ps1 -InputPath .\MyScript.ps1 -OutputPath .\Output

.EXAMPLE
    pwsh.exe -NoProfile -File Convert-PwshToCSharp.ps1 -InputPath C:\opt\src\Project\Scripts -OutputPath C:\temp\converted -Namespace MyApp -CleanupPasses 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputPath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string]$TargetProjectPath,

    [string]$Namespace = 'ConvertedScripts',

    [switch]$SkipCleanup,

    [switch]$SkipBuildVerification,

    [string]$CleanupModel = 'claude-sonnet-4-20250514',

    [int]$CleanupPasses = 2
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force
Import-Module (Join-Path $PSScriptRoot 'Converter\PwshToCSharpConverter.psm1') -Force

$scriptRoot = $PSScriptRoot
$cleanupScript = Join-Path $scriptRoot 'Invoke-PostConversionCleanup.ps1'

# Load project config
$configPath = Join-Path $scriptRoot 'Pwsh2CSharp-Config.json'
$projectConfig = @{}
if (Test-Path -LiteralPath $configPath) {
    $projectConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    Write-LogMessage "  Config loaded: $($configPath)" -Level INFO
}
if (-not $Namespace -and $projectConfig.conversion.namespace) {
    $Namespace = $projectConfig.conversion.namespace
}

if (-not (Test-Path -LiteralPath $cleanupScript)) {
    Write-LogMessage "Invoke-PostConversionCleanup.ps1 not found at: $($cleanupScript)" -Level ERROR
    exit 1
}

$rawDir     = Join-Path $OutputPath 'raw'
$cleanedDir = Join-Path $OutputPath 'cleaned'
New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
New-Item -ItemType Directory -Path $cleanedDir -Force | Out-Null

$reportPath = Join-Path $OutputPath 'conversion-report.json'

function Get-Ps1Files {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ($Path -match '\.ps1$') { return @((Resolve-Path -LiteralPath $Path).Path) }
        Write-LogMessage "Input file is not a .ps1: $($Path)" -Level ERROR
        return @()
    }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        return @(Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File |
            Sort-Object Name | ForEach-Object { $_.FullName })
    }
    Write-LogMessage "Input path not found: $($Path)" -Level ERROR
    return @()
}

function Invoke-MechanicalConversion {
    param([string]$Ps1Path, [string]$OutputCsPath)

    $baseName = [IO.Path]::GetFileNameWithoutExtension($Ps1Path)
    Write-LogMessage "  [AST Converter] Converting $($baseName).ps1 ..." -Level INFO

    $success = $false
    $rawCs = ''

    try {
        $rawCs = ConvertTo-CSharpSource -InputFile $Ps1Path -Namespace $Namespace
        if (-not [string]::IsNullOrWhiteSpace($rawCs) -and $rawCs.Length -gt 50) {
            Set-Content -LiteralPath $OutputCsPath -Value $rawCs -Encoding UTF8
            $success = $true
            Write-LogMessage "    AST conversion produced $($rawCs.Length) chars" -Level INFO
        }
    }
    catch {
        Write-LogMessage "    AST conversion failed: $($_.Exception.Message)" -Level WARN
    }

    if (-not $success) {
        Write-LogMessage "    AST conversion failed — generating minimal scaffold" -Level WARN
        $psContent = Get-Content -LiteralPath $Ps1Path -Raw -Encoding UTF8
        $className = ($baseName -replace '[^a-zA-Z0-9]', '')

        $rawCs = @"
// AUTO-GENERATED SCAFFOLD — AST conversion could not fully process this file.
// The Cursor Agent CLI cleanup pass will refine from the embedded PowerShell source.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using NLog;

namespace $Namespace;

/// <summary>
/// Converted from $($baseName).ps1
/// </summary>
public class $className
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    // TODO: Convert the PowerShell source below into C# methods.
    // Original source: $($Ps1Path)
    // Lines: $(($psContent -split "`n").Count)
}

/*
=== ORIGINAL POWERSHELL SOURCE ===
$psContent
*/
"@
        Set-Content -LiteralPath $OutputCsPath -Value $rawCs -Encoding UTF8
        $success = $true
        Write-LogMessage "    Scaffold generated ($($rawCs.Length) chars)" -Level INFO
    }

    return [PSCustomObject]@{
        Success   = $success
        OutputCs  = $rawCs
        CharCount = $rawCs.Length
    }
}

# ── Main ──

$inputFull = (Resolve-Path -LiteralPath $InputPath -ErrorAction Stop).Path
$ps1Files = Get-Ps1Files -Path $inputFull

if ($ps1Files.Count -eq 0) {
    Write-LogMessage "No .ps1 files found at: $($inputFull)" -Level ERROR
    exit 1
}

Write-LogMessage "Pwsh2CSharp conversion starting" -Level INFO
Write-LogMessage "  Input:          $($inputFull)" -Level INFO
Write-LogMessage "  Files:          $($ps1Files.Count)" -Level INFO
Write-LogMessage "  Output:         $($OutputPath)" -Level INFO
Write-LogMessage "  Namespace:      $($Namespace)" -Level INFO
Write-LogMessage "  Cleanup model:  $($CleanupModel)" -Level INFO
Write-LogMessage "  Cleanup passes: $($CleanupPasses)" -Level INFO
Write-LogMessage "  Skip cleanup:   $($SkipCleanup)" -Level INFO

$results = [System.Collections.ArrayList]::new()
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($ps1 in $ps1Files) {
    $baseName = [IO.Path]::GetFileNameWithoutExtension($ps1)
    $csName = "$($baseName).cs"
    $rawCsPath = Join-Path $rawDir $csName
    $cleanedCsPath = Join-Path $cleanedDir $csName

    Write-LogMessage "[$($results.Count + 1)/$($ps1Files.Count)] Processing: $($baseName).ps1" -Level INFO
    $fileSw = [System.Diagnostics.Stopwatch]::StartNew()

    # Step 1: Mechanical AST-based conversion
    $mechResult = Invoke-MechanicalConversion -Ps1Path $ps1 -OutputCsPath $rawCsPath

    # Step 2: Agent CLI cleanup
    if (-not $SkipCleanup -and $mechResult.Success) {
        Write-LogMessage "  [Agent CLI] Running $($CleanupPasses) cleanup pass(es)..." -Level INFO

        $currentInput = $rawCsPath
        for ($pass = 1; $pass -le $CleanupPasses; $pass++) {
            $passOutput = if ($pass -eq $CleanupPasses) {
                $cleanedCsPath
            } else {
                Join-Path $rawDir "$($baseName).pass$($pass).cs"
            }

            $cleanupArgs = @{
                RawCsPath       = $currentInput
                OriginalPs1Path = $ps1
                OutputCsPath    = $passOutput
                Model           = $CleanupModel
                PassNumber      = $pass
                TotalPasses     = $CleanupPasses
                ConfigPath      = $configPath
            }
            if ($TargetProjectPath) {
                $cleanupArgs.TargetProjectPath = $TargetProjectPath
            }

            try {
                & $cleanupScript @cleanupArgs
                if ((Test-Path -LiteralPath $passOutput) -and (Get-Item -LiteralPath $passOutput).Length -gt 0) {
                    Write-LogMessage "    Pass $($pass) complete: $(( Get-Item -LiteralPath $passOutput).Length) bytes" -Level INFO
                    $currentInput = $passOutput
                } else {
                    Write-LogMessage "    Pass $($pass) produced no output, using previous" -Level WARN
                }
            } catch {
                Write-LogMessage "    Pass $($pass) failed: $($_.Exception.Message)" -Level WARN
            }
        }
    } elseif (-not $SkipCleanup) {
        Write-LogMessage "  [Agent CLI] Skipping cleanup — mechanical conversion failed" -Level WARN
        Copy-Item -LiteralPath $rawCsPath -Destination $cleanedCsPath -Force
    } else {
        Copy-Item -LiteralPath $rawCsPath -Destination $cleanedCsPath -Force
    }

    $fileSw.Stop()

    $fileResult = [ordered]@{
        sourceFile          = $ps1
        baseName            = $baseName
        rawCsPath           = $rawCsPath
        cleanedCsPath       = $cleanedCsPath
        mechanicalSuccess   = $mechResult.Success
        mechanicalChars     = $mechResult.CharCount
        cleanupApplied      = (-not $SkipCleanup -and $mechResult.Success)
        durationMs          = $fileSw.ElapsedMilliseconds
    }
    [void]$results.Add($fileResult)
    Write-LogMessage "  Done in $($fileSw.Elapsed.ToString('mm\:ss'))" -Level INFO
}

# Step 3: Build verification
$buildSuccess = $null
if (-not $SkipBuildVerification -and $TargetProjectPath) {
    Write-LogMessage "Running dotnet build verification..." -Level INFO
    try {
        $buildOutput = & dotnet build $TargetProjectPath --nologo --verbosity quiet 2>&1
        $buildSuccess = ($LASTEXITCODE -eq 0)
        if ($buildSuccess) {
            Write-LogMessage "  Build: PASS" -Level INFO
        } else {
            Write-LogMessage "  Build: FAIL" -Level WARN
            $buildOutput | ForEach-Object { Write-LogMessage "    $($_)" -Level WARN }
        }
    } catch {
        Write-LogMessage "  Build verification error: $($_.Exception.Message)" -Level WARN
        $buildSuccess = $false
    }
}

$totalSw.Stop()

# ── Report ──
$report = [ordered]@{
    timestamp       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    inputPath       = $inputFull
    outputPath      = $OutputPath
    namespace       = $Namespace
    totalFiles      = $ps1Files.Count
    successCount    = @($results | Where-Object { $_.mechanicalSuccess }).Count
    failCount       = @($results | Where-Object { -not $_.mechanicalSuccess }).Count
    cleanupModel    = $CleanupModel
    cleanupPasses   = $CleanupPasses
    buildSuccess    = $buildSuccess
    totalDurationMs = $totalSw.ElapsedMilliseconds
    files           = @($results)
}

$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-LogMessage '' -Level INFO
Write-LogMessage "Conversion complete: $($report.successCount)/$($report.totalFiles) succeeded in $($totalSw.Elapsed.ToString('hh\:mm\:ss'))" -Level INFO
Write-LogMessage "  Raw output:     $($rawDir)" -Level INFO
Write-LogMessage "  Cleaned output: $($cleanedDir)" -Level INFO
Write-LogMessage "  Report:         $($reportPath)" -Level INFO
if ($null -ne $buildSuccess) {
    Write-LogMessage "  Build:          $(if ($buildSuccess) { 'PASS' } else { 'FAIL' })" -Level INFO
}

exit 0
