#Requires -Version 7.0
<#
.SYNOPSIS
    Quick test: compile a single COBOL program and report the result.
.DESCRIPTION
    Sets up the VCPATH environment (Phase 1-3 of the full pipeline) for a
    single program, compiles it, and shows whether the .int file was produced.

    Use this to verify that the local Visual COBOL compiler is working before
    running the full 3400+ program batch.
.PARAMETER ProgramName
    Base name of the CBL program to compile (without extension). Defaults to AABELMA.
.PARAMETER DatabaseAlias
    DB2 alias for SQL directive generation. Defaults to BASISVCT (enforced).
.EXAMPLE
    .\Test-VcSingleCompile.ps1
.EXAMPLE
    .\Test-VcSingleCompile.ps1 -ProgramName GMSTART
#>
[CmdletBinding()]
param(
    [string]$ProgramName = 'AABELMA',

    [string]$DatabaseAlias = 'BASISVCT',

    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [string]$CblFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cbl',

    [string]$CpyFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cpy',

    [ValidateSet('32', '64')]
    [string]$CobMode = '32'
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$allowedDatabases = @('BASISVCT', 'FKMVCT')
if ($DatabaseAlias -notin $allowedDatabases) {
    Write-LogMessage "SAFETY: Only BASISVCT/FKMVCT allowed. Requested: $($DatabaseAlias)" -Level ERROR
    exit 1
}

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Steps\_helper\VcEnvironmentSwitch.ps1')
$vcSwitched = Switch-ToVisualCobol
if (-not $vcSwitched) {
    Write-LogMessage 'Failed to switch to Visual COBOL environment' -Level ERROR
    exit 1
}

$_exitCode = 1
try {

$baseName = $ProgramName.ToUpper()
$startTime = Get-Date

Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "Test Single Compile: $($baseName)" -Level INFO
Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "VCPATH:    $($VcPath)" -Level INFO
Write-LogMessage "DB alias:  $($DatabaseAlias)" -Level INFO
Write-LogMessage "Mode:      $($CobMode)-bit" -Level INFO

# --- Step 1: Initialize VCPATH structure ---
Write-LogMessage '--- Setting up VCPATH ---' -Level INFO
$initScript = Join-Path $PSScriptRoot 'Steps\Step30-Initialize-VcEnvironment.ps1'
if (-not (Test-Path $initScript)) {
    Write-LogMessage "Step30-Initialize-VcEnvironment.ps1 not found" -Level ERROR
    exit 1
}
& $initScript -VcPath $VcPath -DbAlias $DatabaseAlias -CollectedSourcesFolder $CblFolder
if ($LASTEXITCODE -ne 0) {
    Write-LogMessage "Environment init failed (exit $($LASTEXITCODE))" -Level ERROR
    exit 1
}

# --- Step 2: Ensure the specific source file is in VCPATH ---
$srcFile = Join-Path $CblFolder "$($baseName).cbl"
if (-not (Test-Path $srcFile)) {
    Write-LogMessage "Source not found: $($srcFile)" -Level ERROR
    exit 1
}

$dstCbl = Join-Path $VcPath 'src\cbl'
Copy-Item -Path $srcFile -Destination $dstCbl -Force
Write-LogMessage "Copied $($baseName).cbl to VCPATH" -Level INFO

# --- Step 3: Compile ---
Write-LogMessage '--- Compiling ---' -Level INFO
$compileScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Steps\_helper\Invoke-VcCompile.ps1'
& $compileScript -SourceBaseName $baseName -CobMode $CobMode -VcPath $VcPath
$exitCode = $LASTEXITCODE

# --- Step 4: Report ---
$intFile = Join-Path $VcPath "int\$($baseName).int"
$lstFile = Join-Path $VcPath "lst\$($baseName).lst"
$logFile = Join-Path $VcPath "log\$($baseName).log"
$bndFile = Join-Path $VcPath "bnd\$($baseName).bnd"
$elapsed = (Get-Date) - $startTime

Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "Result for $($baseName):" -Level INFO
Write-LogMessage "  Exit code:  $($exitCode)" -Level INFO
Write-LogMessage "  .int file:  $(if (Test-Path $intFile) { 'YES (' + (Get-Item $intFile).Length + ' bytes)' } else { 'NO' })" -Level INFO
Write-LogMessage "  .bnd file:  $(if (Test-Path $bndFile) { 'YES (SQL program)' } else { 'No (not SQL or compile failed)' })" -Level INFO
Write-LogMessage "  Duration:   $($elapsed.TotalSeconds.ToString('F1'))s" -Level INFO

if (Test-Path $logFile) {
    $ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
    $logContent = Get-Content $logFile -Encoding $ansiEncoding -ErrorAction SilentlyContinue
    if ($logContent) {
        Write-LogMessage '--- Compiler output ---' -Level INFO
        $logContent | ForEach-Object { Write-LogMessage "  $($_)" -Level INFO }
    }
}

if (Test-Path $lstFile) {
    Write-LogMessage "  Listing:    $($lstFile)" -Level INFO
}

Write-LogMessage '======================================================' -Level INFO
if ($exitCode -eq 0 -and (Test-Path $intFile)) {
    Write-LogMessage "PASS: $($baseName) compiled successfully" -Level INFO
} else {
    Write-LogMessage "FAIL: $($baseName) compilation failed" -Level ERROR
}

$_exitCode = $exitCode

} finally {
    Switch-ToMicroFocus
}

exit $_exitCode
