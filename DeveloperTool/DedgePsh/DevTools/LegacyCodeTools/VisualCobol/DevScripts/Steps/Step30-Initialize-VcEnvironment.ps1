#Requires -Version 7.0
<#
.SYNOPSIS
    Creates the VCPATH directory structure and deploys compiler directive files.
.DESCRIPTION
    Replaces the old SetupEnv.bat and deploy.bat combination with a single PowerShell script.
    Creates the full VCPATH folder layout required for Visual COBOL compilation and
    generates compiler directive files with the correct paths.

    Replaces: OldScripts\VisualCobolRunScripts\SetupEnv.bat + deploy.bat

    Source: Rocket Visual COBOL Documentation Version 11 - Setting Directives Outside the IDE
.EXAMPLE
    .\Initialize-VcEnvironment.ps1
    .\Initialize-VcEnvironment.ps1 -VcPath 'D:\CobolWork\Dedge2' -DbAlias 'BASISVCT'
#>
[CmdletBinding()]
param(
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),
    [string]$DbAlias = 'BASISVCT',
    [string]$Collection = 'DBM',
    [string]$UdbVersion = 'V9',
    [string]$CollectedSourcesFolder = ''
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$allowedDatabases = @('BASISVCT', 'FKMVCT')
if ($DbAlias -notin $allowedDatabases) {
    Write-LogMessage "SAFETY: Only BASISVCT/FKMVCT allowed. Requested: $($DbAlias)" -Level ERROR
    exit 1
}

Write-LogMessage "Initializing Visual COBOL environment at: $($VcPath)" -Level INFO

if ([string]::IsNullOrWhiteSpace($CollectedSourcesFolder)) {
    $optPath = if ($env:OptPath) { $env:OptPath } else { 'C:\opt' }
    $CollectedSourcesFolder = Join-Path $optPath 'data\VisualCobol\Step1-Copy-VcSourceFiles\Sources'
}

$switchScript = Join-Path $PSScriptRoot '_helper\Switch-CobolEnvironment.ps1'
if (Test-Path $switchScript) {
    Write-LogMessage "Switching machine COBOL environment to VC mode..." -Level INFO
    & $switchScript -Mode VC
} else {
    Write-LogMessage "Switch script not found (skipping): $($switchScript)" -Level WARN
}

# --- Create directory structure ---
$directories = @(
    "$($VcPath)\bnd"
    "$($VcPath)\cfg"
    "$($VcPath)\dir"
    "$($VcPath)\int"
    "$($VcPath)\lst"
    "$($VcPath)\log"
    "$($VcPath)\net"
    "$($VcPath)\tmp"
    "$($VcPath)\src"
    "$($VcPath)\src\bat"
    "$($VcPath)\src\rex"
    "$($VcPath)\src\psh"
    "$($VcPath)\src\cbl"
    "$($VcPath)\src\cbl\imp"
    "$($VcPath)\src\cbl\cpy"
    "$($VcPath)\src\cbl\cpy\sys"
    "$($VcPath)\src\cbl\cpy\sys\cpy"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-LogMessage "Created: $($dir)" -Level DEBUG
    }
}

# --- Generate compiler directive files ---
$stdDirContent = @"
visualstudio"4"
anim
cobidy"$($VcPath)\int\"
sourcetabstop"4"
sourceformat"Variable"
noquery
warnings"1"
max-error"100"
"@

$sqlDirContent = @"
DB2(DB)
DB2(DB=$($DbAlias))
DB2(BINDDIR=$($VcPath)\bnd)
DB2(COPY)
DB2(NOINIT)
DB2(COLLECTION=$($Collection))
DB2(UDB-VERSION=$($UdbVersion))
DB2(BIND)
"@

$proxyDirContent = "DIRECTIVES`"$($VcPath)\cfg\VcCompilerDirectivesStd.dir`""

$stdDirPath = Join-Path $VcPath 'cfg\VcCompilerDirectivesStd.dir'
$sqlDirPath = Join-Path $VcPath 'cfg\VcCompilerDirectivesSql.dir'
$proxyDirPath = Join-Path $VcPath 'cfg\VcCompilerDirectivesStdProxy.dir'

Set-Content -Path $stdDirPath -Value $stdDirContent -Encoding ASCII
Set-Content -Path $sqlDirPath -Value $sqlDirContent -Encoding ASCII
Set-Content -Path $proxyDirPath -Value $proxyDirContent -Encoding ASCII

Write-LogMessage "Generated directive files in $($VcPath)\cfg\" -Level INFO

# --- Copy compile/run scripts from Config to VCPATH\cfg if they exist ---
$configDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Config'
if (Test-Path $configDir) {
    Get-ChildItem -Path $configDir -Filter '*.dir' | ForEach-Object {
        $destFile = Join-Path $VcPath "cfg\$($_.Name)"
        if (-not (Test-Path $destFile)) {
            Copy-Item -Path $_.FullName -Destination $destFile -Force
            Write-LogMessage "Deployed template: $($_.Name) -> $($destFile)" -Level DEBUG
        }
    }
}

Write-LogMessage "Visual COBOL environment initialized at: $($VcPath)" -Level INFO

# --- Set VCPATH environment variable if not already set ---
if (-not $env:VCPATH) {
    [System.Environment]::SetEnvironmentVariable('VCPATH', $VcPath, [System.EnvironmentVariableTarget]::Machine)
    $env:VCPATH = $VcPath
    Write-LogMessage "Set VCPATH environment variable to: $($VcPath)" -Level INFO
}

# --- Copy Step1 collected sources into VCPATH layout ---
if (Test-Path $CollectedSourcesFolder) {
    $srcCbl = Join-Path $CollectedSourcesFolder 'cbl'
    $srcCpy = Join-Path $CollectedSourcesFolder 'cpy'
    $srcUncertain = Join-Path $CollectedSourcesFolder 'cpy_uncertain'

    $dstCbl = Join-Path $VcPath 'src\cbl'
    $dstCpy = Join-Path $VcPath 'src\cbl\cpy'
    $dstSys = Join-Path $VcPath 'src\cbl\cpy\sys\cpy'
    $dstImp = Join-Path $VcPath 'src\cbl\imp'

    Write-LogMessage "Copying collected sources from $($CollectedSourcesFolder) into VCPATH..." -Level INFO

    if (Test-Path $srcCbl) {
        Get-ChildItem -Path $srcCbl -File -Filter '*.cbl' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstCbl -Force
    }
    if (Test-Path $srcCpy) {
        Get-ChildItem -Path $srcCpy -File -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstCpy -Force
    }
    if (Test-Path $srcUncertain) {
        # Promote uncertain copybooks into active include paths by extension.
        Get-ChildItem -Path $srcUncertain -File -Filter '*.cpy' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstCpy -Force
        Get-ChildItem -Path $srcUncertain -File -Filter '*.cpb' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstCpy -Force
        Get-ChildItem -Path $srcUncertain -File -Filter '*.dcl' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstSys -Force
        Get-ChildItem -Path $srcUncertain -File -Filter '*.cpx' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstSys -Force
        Get-ChildItem -Path $srcUncertain -File -Filter '*.imp' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dstImp -Force
    }

    $copiedCbl = @(Get-ChildItem -Path $dstCbl -Filter '*.cbl' -File -ErrorAction SilentlyContinue).Count
    $copiedCpy = @(Get-ChildItem -Path $dstCpy -File -ErrorAction SilentlyContinue).Count
    $copiedSys = @(Get-ChildItem -Path $dstSys -File -ErrorAction SilentlyContinue).Count
    Write-LogMessage "VCPATH source counts: CBL=$($copiedCbl), CPY=$($copiedCpy), SYS=$($copiedSys)" -Level INFO

    # Ensure DB2 baseline SQL include copybooks exist for legacy COPY "SQL"/"SQLENV"/"SQLCA".
    $db2Include = 'C:\Program Files\IBM\SQLLIB\include\cobol_mf'
    if (Test-Path $db2Include) {
        $sqlSeedMap = @{
            'sql.cbl'    = 'SQL.CPY'
            'sqlenv.cbl' = 'SQLENV.CPY'
            'sqlca.cbl'  = 'SQLCA.CPY'
        }
        foreach ($srcName in $sqlSeedMap.Keys) {
            $srcPath = Join-Path $db2Include $srcName
            $dstPath = Join-Path $dstCpy $sqlSeedMap[$srcName]
            if (Test-Path $srcPath) {
                Copy-Item -Path $srcPath -Destination $dstPath -Force
                Write-LogMessage "Seeded DB2 copybook: $($sqlSeedMap[$srcName])" -Level DEBUG
            }
        }
    } else {
        Write-LogMessage "DB2 include folder not found for SQL copybook seeding: $($db2Include)" -Level WARN
    }
} else {
    Write-LogMessage "Collected sources folder not found: $($CollectedSourcesFolder)" -Level WARN
}
