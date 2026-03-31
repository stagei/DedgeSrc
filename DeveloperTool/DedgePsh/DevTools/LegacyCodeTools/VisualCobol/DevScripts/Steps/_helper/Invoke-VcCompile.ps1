#Requires -Version 7.0
<#
.SYNOPSIS
    Compiles a single COBOL source file using the Rocket Visual COBOL compiler.
.DESCRIPTION
    PowerShell replacement for VcComplie.bat. Sets up the COBOL compilation environment,
    generates per-file directive files, auto-detects SQL programs, and invokes cobol.exe.

    Replaces: OldScripts\VisualCobolRunScripts\VcComplie.bat
    Changes from old version:
    - Pure PowerShell (no batch file)
    - Auto-detects Rocket Software vs legacy Micro Focus install path
    - Generates per-file .dir with VCPATH-relative paths
    - Automatically adds SQL directives if source contains EXEC SQL

    Source: Rocket Visual COBOL Documentation Version 11 - Compiling COBOL Applications, Setting Directives Outside the IDE
.EXAMPLE
    .\Invoke-VcCompile.ps1 -SourceBaseName AAXFKTSX
    .\Invoke-VcCompile.ps1 -SourceBaseName GMSTART -CobMode 64
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceBaseName,

    [ValidateSet('32', '64')]
    [string]$CobMode = '32',

    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [int]$CompileTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)

# --- Auto-detect compiler path (Rocket Software first, then legacy Micro Focus) ---
$binSuffix = if ($CobMode -eq '64') { 'bin64' } else { 'bin' }
$libSuffix = if ($CobMode -eq '64') { 'lib64' } else { 'lib' }

$rocketBase = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$mfBase = 'C:\Program Files (x86)\Micro Focus\Visual COBOL'

$vcBase = if (Test-Path "$($rocketBase)\$($binSuffix)\cobol.exe") {
    $rocketBase
} elseif (Test-Path "$($mfBase)\$($binSuffix)\cobol.exe") {
    Write-LogMessage "Using legacy Micro Focus path (Rocket Software path not found)" -Level WARN
    $mfBase
} else {
    Write-LogMessage "cobol.exe not found in Rocket Software or Micro Focus paths" -Level ERROR
    exit 1
}

$cobolExe = Join-Path $vcBase "$($binSuffix)\cobol.exe"
$binFolder = Join-Path $vcBase $binSuffix
$libFolder = Join-Path $vcBase $libSuffix

$baseName = $SourceBaseName.ToUpper()
$srcFile = Join-Path $VcPath "src\cbl\$($baseName).cbl"
$intFile = Join-Path $VcPath "int\$($baseName).int"
$lstFile = Join-Path $VcPath "lst\$($baseName).lst"
$dirFile = Join-Path $VcPath "dir\$($baseName).dir"
$bndFile = Join-Path $VcPath "bnd\$($baseName).bnd"
$logFile = Join-Path $VcPath "log\$($baseName).log"

if (-not (Test-Path $srcFile)) {
    Write-LogMessage "Source file not found: $($srcFile)" -Level ERROR
    exit 1
}

# --- Set compilation environment ---
$env:COBDIR = "$($vcBase);$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl"
$env:COBPATH = "$($VcPath)\int;$($VcPath)\gs;$($VcPath)\src\cbl"
$env:COBCPY = "$($VcPath)\src\cbl\cpy;$($VcPath)\src\cbl\cpy\sys\cpy;$($VcPath)\src\cbl"
$env:COBMODE = $CobMode
$env:MFVSSW = '/c /f'
$env:LIB = $libFolder

if ($env:PATH -notlike "*$($binFolder)*") {
    $env:PATH = "$($binFolder);$($env:PATH)"
}

# --- Clean old output ---
foreach ($f in @("$($VcPath)\int\$($baseName).*", $lstFile, $bndFile, $dirFile)) {
    Remove-Item -Path $f -Force -ErrorAction SilentlyContinue
}

# --- Generate per-file directive file ---
$stdDirFile = Join-Path $VcPath 'cfg\VcCompilerDirectivesStd.dir'
$sqlDirFile = Join-Path $VcPath 'cfg\VcCompilerDirectivesSql.dir'

# Use heuristic source format detection for legacy code:
# many migrated programs use fixed format with sequence numbers in cols 1-6.
$sourceLines = @(Get-Content -Path $srcFile -Encoding $ansiEncoding -ErrorAction SilentlyContinue)
$nonEmptyLines = @($sourceLines | Where-Object { $_.Trim().Length -gt 0 })
$seqNumberLines = @(
    $nonEmptyLines |
        Where-Object {
            $_.Length -ge 6 -and $_.Substring(0, 6) -match '^[0-9 ]{6}$'
        }
).Count

$sourceFormat = 'variable'
if ($nonEmptyLines.Count -gt 0) {
    $seqRatio = $seqNumberLines / $nonEmptyLines.Count
    $trailingSeqLines = @(
        $nonEmptyLines |
            Where-Object {
                $_.Length -ge 80 -and $_.Substring(72, 8) -match '^[0-9 ]{8}$'
            }
    ).Count
    $lineEndSeqLines = @(
        $nonEmptyLines |
            Where-Object {
                $_ -match '\s[0-9]{8}$'
            }
    ).Count
    $trailingSeqRatio = $trailingSeqLines / $nonEmptyLines.Count
    if ($seqRatio -ge 0.35 -or $trailingSeqRatio -ge 0.20 -or $lineEndSeqLines -ge 5) {
        $sourceFormat = 'fixed'
    }
    Write-LogMessage "Source format heuristic ratios for $($baseName): seq-prefix=$([Math]::Round($seqRatio,3)), seq-suffix=$([Math]::Round($trailingSeqRatio,3)), line-end-seq=$($lineEndSeqLines)" -Level DEBUG
}

$forceFixedPrograms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[void]$forceFixedPrograms.Add('AABFMBH')
[void]$forceFixedPrograms.Add('BDHMARK')
if ($forceFixedPrograms.Contains($baseName)) {
    $sourceFormat = 'fixed'
    Write-LogMessage "Force sourceformat 'fixed' for known legacy module: $($baseName)" -Level INFO
}
Write-LogMessage "Using sourceformat '$($sourceFormat)' for $($baseName) (sequence lines: $($seqNumberLines)/$($nonEmptyLines.Count))" -Level DEBUG

$dirContent = @(
    "int`"$($intFile)`""
    "noobj`"$($VcPath)\tmp\$($baseName).int`""
    "sourceformat`"$($sourceFormat)`""
    "DIRECTIVES`"$($stdDirFile)`""
)

# Auto-detect SQL programs by scanning source for EXEC SQL
$sourceContent = $sourceLines -join "`n"
if ($sourceContent -match 'EXEC\s+SQL') {
    $dirContent += "DIRECTIVES`"$($sqlDirFile)`""
    Write-LogMessage "SQL directives added for $($baseName) (contains EXEC SQL)" -Level DEBUG
}

Set-Content -Path $dirFile -Value ($dirContent -join "`r`n") -Encoding ASCII

# --- Invoke compiler ---
Write-LogMessage "Compiling $($baseName) ($($CobMode)-bit)..." -Level INFO
$compileArgs = @(
    "`"$($srcFile)`""
    "`"$($intFile)`""
    "`"$($lstFile)`""
    'nul'
    'DIRECTIVES'
    "`"$($dirFile)`""
)

$proc = Start-Process -FilePath $cobolExe -ArgumentList ($compileArgs -join ', ') `
    -RedirectStandardOutput $logFile -WindowStyle Hidden -PassThru

$finishedInTime = $proc.WaitForExit($CompileTimeoutSeconds * 1000)
if (-not $finishedInTime) {
    Write-LogMessage "Compilation timeout for $($baseName) after $($CompileTimeoutSeconds)s. Killing cobol.exe process." -Level ERROR
    try {
        $proc.Kill($true)
    } catch {
        Write-LogMessage "Failed to kill timed-out process for $($baseName): $($_.Exception.Message)" -Level WARN
    }
    exit 124
}

if ($proc.ExitCode -eq 0 -and (Test-Path $intFile)) {
    Write-LogMessage "Compilation successful: $($baseName).int" -Level INFO
} else {
    Write-LogMessage "Compilation failed for $($baseName) (exit code: $($proc.ExitCode))" -Level ERROR
    if (Test-Path $logFile) {
        $tail = Get-Content $logFile -Tail 20 -Encoding $ansiEncoding -ErrorAction SilentlyContinue
        $tail | ForEach-Object { Write-LogMessage "  $($_)" -Level ERROR }
    }
}

exit $proc.ExitCode
