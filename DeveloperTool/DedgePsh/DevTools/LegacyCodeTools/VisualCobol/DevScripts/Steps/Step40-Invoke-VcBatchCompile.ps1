#Requires -Version 7.0
<#
.SYNOPSIS
    Batch compiles all COBOL source files and reports compilation errors.
.DESCRIPTION
    Iterates over all .CBL files in VCPATH\src\cbl\, compiles each one via
    Invoke-VcCompile.ps1, parses the listing file for errors, and produces
    a structured error report with source-line context.

    Replaces: OldScripts\VisualCobolBatchCompile\VisualCobolBatchCompile.ps1
    Changes from old version:
    - Uses GlobalFunctions Write-LogMessage instead of local LogMessage
    - Removed hardcoded single-file debug filter (AAXFKTSX.CBL)
    - Added -Filter parameter for selective compilation
    - Added -SkipList parameter (replaces hardcoded exclusion list)
    - Uses Invoke-VcCompile.ps1 instead of batch file
    - Cleaner error parsing with documented regex

    Source: Rocket Visual COBOL Messages Reference Version 11 - compiler error codes
.EXAMPLE
    .\Invoke-VcBatchCompile.ps1
    .\Invoke-VcBatchCompile.ps1 -Filter 'GMSTART.CBL'
    .\Invoke-VcBatchCompile.ps1 -CobMode 64 -StopOnFirstError
#>
[CmdletBinding()]
param(
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [ValidateSet('32', '64')]
    [string]$CobMode = '32',

    [string]$Filter = '*.cbl',

    [string]$ProgramListPath = '',

    [string[]]$SkipList = @('DOHCBLD', 'DOHCHK', 'DOHCHK2', 'DOHCHK3', 'DOHCHK4', 'DOHCHK6', 'DOHUTGAT', 'DOHSCAN'),

    [switch]$StopOnFirstError
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
$compileScript = Join-Path $PSScriptRoot '_helper\Invoke-VcCompile.ps1'
$srcFolder = Join-Path $VcPath 'src\cbl'
$lstFolder = Join-Path $VcPath 'lst'

if (-not (Test-Path $srcFolder)) {
    Write-LogMessage "Source folder not found: $($srcFolder)" -Level ERROR
    exit 1
}

$files = Get-ChildItem -Path $srcFolder -Filter $Filter -File

if (-not [string]::IsNullOrWhiteSpace($ProgramListPath)) {
    if (-not (Test-Path $ProgramListPath)) {
        Write-LogMessage "Program list file not found: $($ProgramListPath)" -Level ERROR
        exit 1
    }

    $allowedPrograms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-Content -Path $ProgramListPath -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Trim().ToUpper() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { [void]$allowedPrograms.Add($_) }

    $beforeCount = $files.Count
    $files = @($files | Where-Object { $allowedPrograms.Contains($_.BaseName.ToUpper()) })
    Write-LogMessage "Program list filter applied: $($files.Count)/$($beforeCount) selected from $($ProgramListPath)" -Level INFO
}

Write-LogMessage "Found $($files.Count) source file(s) matching '$($Filter)'" -Level INFO

$successCount = 0
$failCount = 0
$skipCount = 0

# --- Regex for error detection in LST files ---
# Matches compiler error markers in Visual COBOL listing files:
#   \*           - literal asterisk (error line prefix)
#   (?=\s{0,4}\d{0,4}-) - lookahead: up to 4 spaces, digits, then dash
#   (\s*\d{1,4}) - capture group 1: optional spaces + 1-4 digit error number
#   -([a-z])     - capture group 2: severity letter (e=error, w=warning, i=info, s=severe)
#   \*           - closing asterisk
$errorRegex = '\*(?=\s{0,4}\d{0,4}-)(\s*\d{1,4})-([a-z])\*'

# Helper functions must be defined before the compile loop
# so they are always available when the first error is parsed.
function Find-SourceLineNumber {
    param([int]$LstLineIndex, [string[]]$LstLines, [string]$VcPath)
    try {
        $checkMf = "* Micro Focus COBOL "
        $checkVc = "* $($VcPath)"
        $idx = $LstLineIndex
        $line = $LstLines[$idx]

        if ($line.StartsWith($checkVc) -and $idx -gt 0 -and $LstLines[$idx - 1].StartsWith($checkMf)) {
            $idx -= 3
            $line = $LstLines[$idx]
        }

        if ($line.StartsWith(' ')) {
            $token = $line.TrimStart().Split(' ')[0]
            $num = 0
            if ([int]::TryParse($token, [ref]$num)) { return $num }
            if ($idx -gt 0) { return Find-SourceLineNumber -LstLineIndex ($idx - 1) -LstLines $LstLines -VcPath $VcPath }
        }
    } catch { }
    return -1
}

function Get-ErrorText {
    param([int]$StartIndex, [string[]]$LstLines, [string]$VcPath)
    $checkVc = "* $($VcPath)"
    $checkMf = "* Micro Focus COBOL "
    $result = @()
    try {
        $idx = $StartIndex
        $line = $LstLines[$idx]
        $result += $line
        $idx++
        while ($idx -lt $LstLines.Count -and $LstLines[$idx].StartsWith('*')) {
            if (-not ($LstLines[$idx].StartsWith($checkVc) -or $LstLines[$idx].StartsWith($checkMf))) {
                $result += $LstLines[$idx].TrimStart('*').Trim()
            }
            if ($LstLines[$idx].StartsWith('* Last message on page')) { break }
            $idx++
        }
    } catch { }
    return $result
}

foreach ($file in $files) {
    $baseName = $file.BaseName.ToUpper()

    if ($SkipList -contains $baseName) {
        Write-LogMessage "Skipping (in skip list): $($baseName)" -Level DEBUG
        $skipCount++
        continue
    }

    # Skip files with 6-8 digit date patterns (backup/archive copies)
    if ($baseName -match '\d{6,8}' -and $baseName.Length -gt 6) {
        Write-LogMessage "Skipping (date pattern): $($baseName)" -Level DEBUG
        $skipCount++
        continue
    }

    if ($baseName -match '\s') {
        Write-LogMessage "Skipping (space in name): $($baseName)" -Level DEBUG
        $skipCount++
        continue
    }

    Write-LogMessage "Compiling: $($file.Name)" -Level INFO

    & $compileScript -SourceBaseName $baseName -CobMode $CobMode -VcPath $VcPath
    $compileExitCode = $LASTEXITCODE

    $lstFile = Join-Path $lstFolder "$($baseName).lst"
    $logFile = Join-Path $VcPath "log\$($baseName).log"

    if ($compileExitCode -eq 8) {
        Write-LogMessage "Compilation successful with warnings (exit 8): $($baseName)" -Level INFO
        Remove-Item -Path $lstFile -Force -ErrorAction SilentlyContinue
        $successCount++
        Start-Sleep -Milliseconds 200
        continue
    }

    if (Test-Path $lstFile) {
        $lstContent = Get-Content -Path $lstFile -Encoding $ansiEncoding
        $lstJoined = $lstContent -join "`n"
        if (($lstContent -join "`n") -match 'COBCH1889') {
            Write-LogMessage "License failure detected (COBCH1889). Stopping batch compile." -Level ERROR
            Write-LogMessage "Resolve Visual COBOL licensing before retrying Step4." -Level ERROR
            exit 2
        }
        if ($lstJoined -match '\* Checking complete with no serious errors') {
            Write-LogMessage "Compilation successful with warnings: $($baseName)" -Level INFO
            Remove-Item -Path $lstFile -Force -ErrorAction SilentlyContinue
            $successCount++
            Start-Sleep -Milliseconds 200
            continue
        }
        $lastMsg = $lstContent | Select-String -Pattern '^\* Last message on page:'

        if ($null -ne $lastMsg) {
            Write-LogMessage "--- Errors in $($baseName) ---" -Level WARN
            $lstLines = $lstContent -split "`r?`n"
            $errorMatches = $lstContent | Select-String -Pattern $errorRegex

            foreach ($errMatch in $errorMatches) {
                $errCode = $errMatch.Matches[0].Value.Replace('*', '').Trim()
                $errLineIdx = $errMatch.LineNumber - 1

                $srcLineNum = Find-SourceLineNumber -LstLineIndex ($errLineIdx - 1) -LstLines $lstLines -VcPath $VcPath
                $errDetails = Get-ErrorText -StartIndex ($errLineIdx - 2) -LstLines $lstLines -VcPath $VcPath

                Write-LogMessage "  Source line $($srcLineNum): $($errCode)" -Level WARN
                foreach ($detail in $errDetails) {
                    Write-LogMessage "    $($detail)" -Level WARN
                }
            }
            $failCount++

            if ($StopOnFirstError) {
                Write-LogMessage "Stopping on first error (--StopOnFirstError)" -Level ERROR
                exit 1
            }
        } else {
            Write-LogMessage "Compilation successful: $($baseName)" -Level INFO
            Remove-Item -Path $lstFile -Force -ErrorAction SilentlyContinue
            $successCount++
        }
    } elseif (Test-Path $logFile) {
        $logContent = Get-Content -Path $logFile -Encoding $ansiEncoding
        if (($logContent -join "`n") -match 'COBCH1889') {
            Write-LogMessage "License failure detected (COBCH1889). Stopping batch compile." -Level ERROR
            Write-LogMessage "Resolve Visual COBOL licensing before retrying Step4." -Level ERROR
            exit 2
        }
        $cobError = $logContent | Select-String -Pattern ': error COB.*'
        $errMsg = if ($cobError) { $cobError.Matches[0].Value.TrimStart(':').Trim() } else { 'Unknown error (no LST file)' }
        Write-LogMessage "Compilation stopped: $($baseName) - $($errMsg)" -Level ERROR
        $failCount++

        if ($StopOnFirstError) {
            Write-LogMessage "Stopping on first error (-StopOnFirstError)" -Level ERROR
            exit 1
        }
    } else {
        $intFile = Join-Path $VcPath "int\$($baseName).int"
        if (Test-Path $intFile) {
            $successCount++
        } else {
            Write-LogMessage "No output for $($baseName) (no .lst, no .log, no .int)" -Level WARN
            $failCount++
        }
    }

    Start-Sleep -Milliseconds 200
}

Write-LogMessage "Batch compile complete: $($successCount) succeeded, $($failCount) failed, $($skipCount) skipped" -Level INFO
