#Requires -Version 7.0
<#
.SYNOPSIS
    Comprehensive Visual COBOL compile, bind, and deploy pipeline.
.DESCRIPTION
    Compiles all COBOL programs locally, optionally binds .bnd files to DB2,
    and transfers compiled artifacts (.int, .gnt, .bnd) to the COBOL Server
    runtime directory on the target test server.

    Pipeline phases:
      1. Environment setup (VCPATH directory structure)
      2. Deploy sources into VCPATH layout
      3. Generate compiler directive files
      4. Batch compile all .cbl files
      5. DB2 bind (optional, can be skipped with -SkipBind)
      6. Transfer compiled output to server (optional, -SkipTransfer)
      7. Final report

    Designed to run locally on a dev machine with Visual COBOL Build Tools
    and DB2 client installed. The compiled output is then transferred to
    the COBOL Server runtime on t-no1fkmvct-app.

    SAFETY: Database defaults to BASISVCT and transfer targets t-no1fkmvct-app.
    All source files are expected in ANSI/Windows-1252 encoding.
.PARAMETER CblFolder
    Folder containing .cbl source files.
.PARAMETER CpyFolder
    Folder containing .cpy/.dcl copybook files.
.PARAMETER DatabaseAlias
    DB2 database alias to compile and bind against. Defaults to BASISVCT.
    Must match a CatalogName in DatabasesV2.json.
.PARAMETER VcPath
    Working directory for compilation output. Defaults to C:\fkavd\Dedge2.
.PARAMETER CobMode
    Compiler bit mode: 32 or 64. Defaults to 32.
.PARAMETER Collection
    DB2 package collection/schema. Defaults to DBM.
.PARAMETER SkipBind
    Skip the DB2 bind step (compile only).
.PARAMETER SkipTransfer
    Skip the server transfer step (compile and bind only, no deployment).
.PARAMETER TransferServer
    Target server for compiled output. Defaults to t-no1fkmvct-app (enforced).
.PARAMETER StopOnFirstError
    Stop on first compilation or bind error.
.PARAMETER SendNotification
    Send SMS when pipeline completes.
.EXAMPLE
    .\Invoke-VcFullPipeline.ps1 -CblFolder 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cbl' -CpyFolder 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cpy'
.EXAMPLE
    .\Invoke-VcFullPipeline.ps1 -SkipBind -SkipTransfer
.EXAMPLE
    .\Invoke-VcFullPipeline.ps1 -SkipBind
    # Compile locally, skip bind, transfer .int/.gnt to server
#>
[CmdletBinding()]
param(
    [string]$CblFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cbl',

    [string]$CpyFolder = 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\cpy',

    [string]$DatabaseAlias = 'BASISVCT',

    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [ValidateSet('32', '64')]
    [string]$CobMode = '32',

    [string]$Collection = 'DBM',

    [string]$UdbVersion = 'V9',

    [string]$BindOptions = 'BLOCKING ALL GRANT PUBLIC',

    [string[]]$SkipList = @('DOHCBLD', 'DOHCHK', 'DOHCHK2', 'DOHCHK3', 'DOHCHK4', 'DOHCHK6', 'DOHUTGAT', 'DOHSCAN'),

    [switch]$SkipBind,

    [switch]$SkipTransfer,

    [string]$TransferServer = 't-no1fkmvct-app',

    [switch]$StopOnFirstError,

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$allowedDatabases = @('BASISVCT', 'FKMVCT')
if ($DatabaseAlias -notin $allowedDatabases) {
    Write-LogMessage "SAFETY: Only BASISVCT/FKMVCT allowed. Requested: $($DatabaseAlias)" -Level ERROR
    exit 1
}

. (Join-Path $PSScriptRoot 'Steps\_helper\VcEnvironmentSwitch.ps1')
$vcSwitched = Switch-ToVisualCobol
if (-not $vcSwitched) {
    Write-LogMessage 'Failed to switch to Visual COBOL environment' -Level ERROR
    exit 1
}

try {

$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
$pipelineStart = Get-Date
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "Visual COBOL Full Pipeline - $($timestamp)" -Level INFO
Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "CBL source:   $($CblFolder)" -Level INFO
Write-LogMessage "CPY source:   $($CpyFolder)" -Level INFO
Write-LogMessage "DB alias:     $($DatabaseAlias)" -Level INFO
Write-LogMessage "VCPATH:       $($VcPath)" -Level INFO
Write-LogMessage "Collection:   $($Collection)" -Level INFO
Write-LogMessage "Compiler:     $($CobMode)-bit" -Level INFO
Write-LogMessage "Skip bind:    $($SkipBind)" -Level INFO
Write-LogMessage "Skip xfer:    $($SkipTransfer)" -Level INFO
Write-LogMessage "Target srv:   $($TransferServer)" -Level INFO
Write-LogMessage '======================================================' -Level INFO

# ============================================================
# PHASE 0: Validate inputs
# ============================================================

if (-not (Test-Path $CblFolder)) {
    Write-LogMessage "CBL folder not found: $($CblFolder)" -Level ERROR
    exit 1
}

$cblFiles = @(Get-ChildItem -Path $CblFolder -Filter '*.cbl' -File)
if ($cblFiles.Count -eq 0) {
    Write-LogMessage "No .cbl files found in $($CblFolder)" -Level ERROR
    exit 1
}
Write-LogMessage "Found $($cblFiles.Count) CBL source files" -Level INFO

$dbConfigPath = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json'
if (Test-Path $dbConfigPath) {
    $dbConfig = Get-Content -Path $dbConfigPath -Raw -Encoding $ansiEncoding | ConvertFrom-Json
    $matchingDb = $dbConfig | Where-Object {
        $_.AccessPoints | Where-Object { $_.CatalogName -eq $DatabaseAlias }
    }
    if ($matchingDb) {
        $dbInfo = $matchingDb | Select-Object -First 1
        Write-LogMessage "Database validated: $($DatabaseAlias) -> $($dbInfo.ServerName) ($($dbInfo.Environment))" -Level INFO
    } else {
        Write-LogMessage "WARNING: $($DatabaseAlias) not found in DatabasesV2.json. Proceeding anyway." -Level WARN
    }
} else {
    Write-LogMessage "DatabasesV2.json not accessible. Skipping validation." -Level WARN
}

# ============================================================
# PHASE 1: Set up VCPATH directory structure
# ============================================================

Write-LogMessage '--- PHASE 1: Environment Setup ---' -Level INFO

$directories = @(
    "$($VcPath)\bnd", "$($VcPath)\cfg", "$($VcPath)\dir",
    "$($VcPath)\int", "$($VcPath)\lst", "$($VcPath)\log",
    "$($VcPath)\net", "$($VcPath)\tmp", "$($VcPath)\gs",
    "$($VcPath)\src", "$($VcPath)\src\cbl",
    "$($VcPath)\src\cbl\imp",
    "$($VcPath)\src\cbl\cpy",
    "$($VcPath)\src\cbl\cpy\sys",
    "$($VcPath)\src\cbl\cpy\sys\cpy"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ============================================================
# PHASE 2: Copy sources into VCPATH layout
# ============================================================

Write-LogMessage '--- PHASE 2: Deploying Sources ---' -Level INFO

$dstCbl = Join-Path $VcPath 'src\cbl'
$dstCpy = Join-Path $VcPath 'src\cbl\cpy'
$dstSys = Join-Path $VcPath 'src\cbl\cpy\sys\cpy'

Write-LogMessage "Copying $($cblFiles.Count) CBL files to $($dstCbl)..." -Level INFO
$cblFiles | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $dstCbl -Force
}

if (Test-Path $CpyFolder) {
    $cpyFiles = @(Get-ChildItem -Path $CpyFolder -File)
    Write-LogMessage "Copying $($cpyFiles.Count) copybook files from $($CpyFolder)..." -Level INFO
    foreach ($f in $cpyFiles) {
        $ext = $f.Extension.ToUpper()
        $dest = switch ($ext) {
            '.DCL' { $dstSys }
            '.CPX' { $dstSys }
            default { $dstCpy }
        }
        Copy-Item -Path $f.FullName -Destination $dest -Force
    }
}

$cpyUncertain = Join-Path (Split-Path $CpyFolder -Parent) 'cpy_uncertain'
if (Test-Path $cpyUncertain) {
    $uncertainFiles = @(Get-ChildItem -Path $cpyUncertain -File)
    Write-LogMessage "Copying $($uncertainFiles.Count) uncertain copybooks..." -Level INFO
    foreach ($f in $uncertainFiles) {
        $ext = $f.Extension.ToUpper()
        $dest = switch ($ext) {
            '.DCL' { $dstSys }
            '.CPX' { $dstSys }
            '.IMP' { Join-Path $VcPath 'src\cbl\imp' }
            default { $dstCpy }
        }
        Copy-Item -Path $f.FullName -Destination $dest -Force
    }
}

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
}

$deployedCbl = @(Get-ChildItem -Path $dstCbl -Filter '*.cbl' -File).Count
$deployedCpy = @(Get-ChildItem -Path $dstCpy -File).Count
$deployedSys = @(Get-ChildItem -Path $dstSys -File).Count
Write-LogMessage "Deployed: CBL=$($deployedCbl), CPY=$($deployedCpy), SYS=$($deployedSys)" -Level INFO

# ============================================================
# PHASE 3: Generate compiler directive files
# ============================================================

Write-LogMessage '--- PHASE 3: Compiler Directives ---' -Level INFO

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
DB2(DB=$($DatabaseAlias))
DB2(BINDDIR=$($VcPath)\bnd)
DB2(COPY)
DB2(NOINIT)
DB2(COLLECTION=$($Collection))
DB2(UDB-VERSION=$($UdbVersion))
DB2(BIND)
"@

Set-Content -Path (Join-Path $VcPath 'cfg\VcCompilerDirectivesStd.dir') -Value $stdDirContent -Encoding ASCII
Set-Content -Path (Join-Path $VcPath 'cfg\VcCompilerDirectivesSql.dir') -Value $sqlDirContent -Encoding ASCII

Write-LogMessage "Directives written (DB=$($DatabaseAlias), Collection=$($Collection))" -Level INFO

if (-not $env:VCPATH) {
    $env:VCPATH = $VcPath
}

# ============================================================
# PHASE 4: Batch compile
# ============================================================

Write-LogMessage '--- PHASE 4: Batch Compilation ---' -Level INFO

$binSuffix = if ($CobMode -eq '64') { 'bin64' } else { 'bin' }

$rocketBase = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$mfBase = 'C:\Program Files (x86)\Micro Focus\Visual COBOL'
$vcBase = if (Test-Path "$($rocketBase)\$($binSuffix)\cobol.exe") {
    $rocketBase
} elseif (Test-Path "$($mfBase)\$($binSuffix)\cobol.exe") {
    $mfBase
} else {
    Write-LogMessage "cobol.exe not found in Rocket Software or Micro Focus paths" -Level ERROR
    exit 1
}
Write-LogMessage "Compiler: $($vcBase)\$($binSuffix)\cobol.exe" -Level INFO

$compileScript = Join-Path $PSScriptRoot 'Steps\_helper\Invoke-VcCompile.ps1'
if (-not (Test-Path $compileScript)) {
    Write-LogMessage "Invoke-VcCompile.ps1 not found at: $($compileScript)" -Level ERROR
    exit 1
}

$srcCblFolder = Join-Path $VcPath 'src\cbl'
$allCbl = @(Get-ChildItem -Path $srcCblFolder -Filter '*.cbl' -File)
Write-LogMessage "Compiling $($allCbl.Count) programs..." -Level INFO

$successCount = 0
$failCount = 0
$skipCount = 0
$failedPrograms = [System.Collections.Generic.List[string]]::new()

$compileStart = Get-Date
$progressInterval = 100

foreach ($file in $allCbl) {
    $baseName = $file.BaseName.ToUpper()

    if ($SkipList -contains $baseName) {
        $skipCount++
        continue
    }
    if ($baseName -match '\d{6,8}' -and $baseName.Length -gt 6) {
        $skipCount++
        continue
    }
    if ($baseName -match '\s') {
        $skipCount++
        continue
    }

    & $compileScript -SourceBaseName $baseName -CobMode $CobMode -VcPath $VcPath
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0 -or $exitCode -eq 8) {
        $successCount++
    } else {
        $failCount++
        $failedPrograms.Add($baseName)

        if ($StopOnFirstError) {
            Write-LogMessage "Stopping on first error: $($baseName)" -Level ERROR
            break
        }
    }

    $totalProcessed = $successCount + $failCount + $skipCount
    if ($totalProcessed % $progressInterval -eq 0) {
        $elapsed = (Get-Date) - $compileStart
        $rate = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($totalProcessed / $elapsed.TotalSeconds, 1) } else { 0 }
        Write-LogMessage "Progress: $($totalProcessed)/$($allCbl.Count) ($($successCount) ok, $($failCount) fail) [$($rate)/s]" -Level INFO
    }
}

$compileElapsed = (Get-Date) - $compileStart
Write-LogMessage '=== COMPILATION SUMMARY ===' -Level INFO
Write-LogMessage "Total:    $($allCbl.Count)" -Level INFO
Write-LogMessage "Success:  $($successCount)" -Level INFO
Write-LogMessage "Failed:   $($failCount)" -Level INFO
Write-LogMessage "Skipped:  $($skipCount)" -Level INFO
Write-LogMessage "Duration: $($compileElapsed.ToString('hh\:mm\:ss'))" -Level INFO

if ($failedPrograms.Count -gt 0) {
    $failedListPath = Join-Path $VcPath "FailedCompilations-$($timestamp).txt"
    $failedPrograms | Out-File -FilePath $failedListPath -Encoding utf8 -Force
    Write-LogMessage "Failed program list: $($failedListPath)" -Level WARN
}

# ============================================================
# PHASE 5: DB2 Bind
# ============================================================

if (-not $SkipBind) {
    Write-LogMessage '--- PHASE 5: DB2 Bind ---' -Level INFO

    $bndFolder = Join-Path $VcPath 'bnd'
    $bndFiles = @(Get-ChildItem -Path $bndFolder -Filter '*.bnd' -File)

    if ($bndFiles.Count -eq 0) {
        Write-LogMessage "No .bnd files found. Skipping bind." -Level WARN
    } else {
        Write-LogMessage "Found $($bndFiles.Count) .bnd files to bind against $($DatabaseAlias)" -Level INFO

        $db2Exe = Get-Command db2 -ErrorAction SilentlyContinue
        if (-not $db2Exe) {
            Write-LogMessage 'db2 command not found. Ensure DB2 client is in PATH.' -Level ERROR
        } else {
            Write-LogMessage "Connecting to $($DatabaseAlias) using Kerberos SSO..." -Level INFO
            $connectOutput = & db2 "CONNECT TO $($DatabaseAlias)" 2>&1
            $connectStr = ($connectOutput | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "DB2 CONNECT failed: $($connectStr)" -Level ERROR
            } else {
                Write-LogMessage "Connected to $($DatabaseAlias)" -Level INFO

                $bindSuccess = 0
                $bindFail = 0
                $bindResults = [System.Collections.Generic.List[hashtable]]::new()

                try {
                    foreach ($bnd in $bndFiles) {
                        $bName = $bnd.BaseName.ToUpper()
                        $bindCmd = "BIND `"$($bnd.FullName)`" COLLECTION $($Collection) $($BindOptions)"
                        $bindOutput = & db2 $bindCmd 2>&1
                        $bindStr = ($bindOutput | Out-String).Trim()
                        $bExitCode = $LASTEXITCODE

                        $record = @{
                            BaseName = $bName
                            ExitCode = $bExitCode
                            Status   = if ($bExitCode -eq 0) { 'SUCCESS' } else { 'FAILED' }
                            Output   = $bindStr
                        }
                        $bindResults.Add($record)

                        if ($bExitCode -eq 0) {
                            $bindSuccess++
                        } else {
                            $bindFail++
                            Write-LogMessage "  BIND FAILED: $($bName) - $($bindStr)" -Level WARN
                            if ($StopOnFirstError) { break }
                        }
                    }
                } finally {
                    & db2 'CONNECT RESET' 2>&1 | Out-Null
                }

                Write-LogMessage '=== BIND SUMMARY ===' -Level INFO
                Write-LogMessage "Total .bnd: $($bndFiles.Count)" -Level INFO
                Write-LogMessage "Bound OK:   $($bindSuccess)" -Level INFO
                Write-LogMessage "Bind fail:  $($bindFail)" -Level INFO

                $bindReportPath = Join-Path $VcPath "BindReport-$($timestamp).json"
                [ordered]@{
                    GeneratedAt   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    DatabaseAlias = $DatabaseAlias
                    Collection    = $Collection
                    TotalFiles    = $bndFiles.Count
                    Success       = $bindSuccess
                    Failed        = $bindFail
                    Results       = @($bindResults)
                } | ConvertTo-Json -Depth 4 | Out-File -FilePath $bindReportPath -Encoding utf8 -Force
                Write-LogMessage "Bind report: $($bindReportPath)" -Level INFO
            }
        }
    }
} else {
    Write-LogMessage '--- PHASE 5: DB2 Bind (SKIPPED) ---' -Level INFO
}

# ============================================================
# PHASE 6: Transfer compiled output to server
# ============================================================

if (-not $SkipTransfer) {
    Write-LogMessage '--- PHASE 6: Transfer to Server ---' -Level INFO
    $transferScript = Join-Path $PSScriptRoot 'Steps\Step70-Deploy-VcCompiledToServer.ps1'
    if (-not (Test-Path $transferScript)) {
        Write-LogMessage "Step70-Deploy-VcCompiledToServer.ps1 not found at: $($transferScript)" -Level ERROR
    } else {
        $transferArgs = @{
            VcPath          = $VcPath
            CblSourceFolder = $CblFolder
            CpySourceFolder = $CpyFolder
            ServerName      = $TransferServer
        }
        if (-not $SkipBind) {
            $transferArgs['IncludeBnd'] = $true
        }
        & $transferScript @transferArgs
        $transferExit = $LASTEXITCODE
        if ($transferExit -ne 0) {
            Write-LogMessage "Transfer to $($TransferServer) failed with exit code $($transferExit)" -Level ERROR
        } else {
            Write-LogMessage "Transfer to $($TransferServer) completed successfully" -Level INFO
        }
    }
} else {
    Write-LogMessage '--- PHASE 6: Transfer to Server (SKIPPED) ---' -Level INFO
}

# ============================================================
# PHASE 7: Final report
# ============================================================

$pipelineElapsed = (Get-Date) - $pipelineStart
Write-LogMessage '======================================================' -Level INFO
Write-LogMessage "Pipeline complete in $($pipelineElapsed.ToString('hh\:mm\:ss'))" -Level INFO
Write-LogMessage '======================================================' -Level INFO

$reportPath = Join-Path $VcPath "PipelineReport-$($timestamp).json"
[ordered]@{
    GeneratedAt      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Script           = 'Invoke-VcFullPipeline.ps1'
    DatabaseAlias    = $DatabaseAlias
    Collection       = $Collection
    CobMode          = $CobMode
    CblFolder        = $CblFolder
    CpyFolder        = $CpyFolder
    VcPath           = $VcPath
    TotalCblFiles    = $allCbl.Count
    CompileSuccess   = $successCount
    CompileFailed    = $failCount
    CompileSkipped   = $skipCount
    CompileDuration  = $compileElapsed.ToString('hh\:mm\:ss')
    BindSkipped      = [bool]$SkipBind
    TransferSkipped  = [bool]$SkipTransfer
    TransferServer   = $TransferServer
    PipelineDuration = $pipelineElapsed.ToString('hh\:mm\:ss')
    FailedPrograms   = @($failedPrograms)
} | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportPath -Encoding utf8 -Force
Write-LogMessage "Pipeline report: $($reportPath)" -Level INFO

. (Join-Path $PSScriptRoot 'Steps\_helper\CollectReports.ps1')
Copy-VcReportsToArchive -ScriptName 'Invoke-VcFullPipeline' -Timestamp $timestamp -VcPath $VcPath

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $msg = "VC Pipeline ($($DatabaseAlias)): $($successCount)/$($allCbl.Count) compiled OK, $($failCount) failed. Duration: $($pipelineElapsed.ToString('hh\:mm\:ss'))"
    Import-Module GlobalFunctions -Force
    Send-Sms -Receiver $smsNumber -Message $msg
}

} finally {
    Switch-ToMicroFocus
}

if ($failCount -gt 0) { exit 1 }
exit 0
