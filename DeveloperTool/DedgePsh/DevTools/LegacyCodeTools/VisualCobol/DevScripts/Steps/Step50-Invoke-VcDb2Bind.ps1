#Requires -Version 7.0
<#
.SYNOPSIS
    Binds compiled COBOL .bnd files to a DB2 database.
.DESCRIPTION
    After batch compilation (Step4), SQL programs produce .bnd (bind) files
    in VCPATH\bnd\. This script iterates all .bnd files and executes
    db2 bind against a target database.

    If -DatabaseAlias is not provided, the script lists known databases
    and prompts the user to select one.

    The db2 bind command creates packages in the database that allow the
    COBOL programs to execute embedded SQL at runtime.

    Reference: Db2 12.1 LUW — BIND command, COLLECTION option, GRANT option
.PARAMETER DatabaseAlias
    DB2 database alias to bind against. Defaults to BASISVCT.
    SAFETY: Only BASISVCT/FKMVCT are allowed.
.PARAMETER BndFolder
    Folder containing .bnd files. Defaults to VCPATH\bnd.
.PARAMETER Collection
    DB2 package collection/schema name. Defaults to 'DBM'.
.PARAMETER BindOptions
    Additional bind options. Defaults to 'BLOCKING ALL GRANT PUBLIC'.
.PARAMETER StopOnFirstError
    Stop binding if any .bnd file fails.
.PARAMETER SendNotification
    Send SMS notification when binding completes.
.EXAMPLE
    .\Step50-Invoke-VcDb2Bind.ps1 -DatabaseAlias BASISVCT
.EXAMPLE
    .\Step50-Invoke-VcDb2Bind.ps1
#>
[CmdletBinding()]
param(
    [string]$DatabaseAlias = 'BASISVCT',

    [string]$BndFolder = $(
        if ($env:VCPATH) { Join-Path $env:VCPATH 'bnd' }
        else { 'C:\fkavd\Dedge2\bnd' }
    ),

    [string]$Collection = 'DBM',

    [string]$BindOptions = 'BLOCKING ALL GRANT PUBLIC',

    [switch]$StopOnFirstError,

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force -ErrorAction SilentlyContinue

$allowedDatabases = @('BASISVCT', 'FKMVCT')
$DatabaseAlias = $DatabaseAlias.ToUpper()
if ($DatabaseAlias -notin $allowedDatabases) {
    Write-LogMessage "SAFETY: Only BASISVCT/FKMVCT allowed for DB2 bind. Requested: $($DatabaseAlias)" -Level ERROR
    exit 1
}

Write-LogMessage "Target database: $($DatabaseAlias)" -Level INFO

$db2Exe = Get-Command db2 -ErrorAction SilentlyContinue
if (-not $db2Exe) {
    Write-LogMessage 'db2 command not found in PATH. Ensure IBM DB2 client is installed and PATH includes SQLLIB\BIN.' -Level ERROR
    exit 1
}

if (-not (Test-Path $BndFolder)) {
    Write-LogMessage "BND folder not found: $($BndFolder)" -Level ERROR
    exit 1
}

$bndFiles = Get-ChildItem -Path $BndFolder -Filter '*.bnd' -File
if ($bndFiles.Count -eq 0) {
    Write-LogMessage "No .bnd files found in $($BndFolder). Run Step4 (compile) first." -Level WARN
    exit 0
}

Write-LogMessage "Found $($bndFiles.Count) .bnd files in $($BndFolder)" -Level INFO
Write-LogMessage "Collection: $($Collection), Options: $($BindOptions)" -Level INFO

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$successCount = 0
$failCount = 0
$results = [System.Collections.Generic.List[hashtable]]::new()

Write-LogMessage "Connecting to $($DatabaseAlias) using Kerberos SSO..." -Level INFO
$connectCmd = "CONNECT TO $($DatabaseAlias)"
$connectOutput = & db2 $connectCmd 2>&1
$connectStr = ($connectOutput | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    Write-LogMessage "DB2 CONNECT failed (exit $($LASTEXITCODE)): $($connectStr)" -Level ERROR
    exit 1
}
Write-LogMessage "Connected to $($DatabaseAlias)" -Level INFO

try {
    foreach ($bnd in $bndFiles) {
        $baseName = $bnd.BaseName.ToUpper()
        Write-LogMessage "Binding: $($bnd.Name)..." -Level INFO

        $bindCmd = "BIND `"$($bnd.FullName)`" COLLECTION $($Collection) $($BindOptions)"
        $bindOutput = & db2 $bindCmd 2>&1
        $bindStr = ($bindOutput | Out-String).Trim()
        $exitCode = $LASTEXITCODE

        $record = @{
            BaseName    = $baseName
            BndFile     = $bnd.Name
            BindCommand = "db2 $($bindCmd)"
            ExitCode    = $exitCode
            Output      = $bindStr
            Status      = $null
        }

        if ($exitCode -eq 0) {
            $record.Status = 'SUCCESS'
            $successCount++
            Write-LogMessage "  OK: $($baseName)" -Level INFO
        } else {
            $record.Status = 'FAILED'
            $failCount++
            Write-LogMessage "  FAILED ($($exitCode)): $($baseName)" -Level WARN
            foreach ($line in ($bindStr -split "`r?`n")) {
                if ($line.Trim()) { Write-LogMessage "    $($line)" -Level WARN }
            }

            if ($StopOnFirstError) {
                Write-LogMessage 'Stopping on first error (-StopOnFirstError)' -Level ERROR
                $results.Add($record)
                break
            }
        }

        $results.Add($record)
    }
} finally {
    Write-LogMessage 'Disconnecting from database...' -Level INFO
    & db2 'CONNECT RESET' 2>&1 | Out-Null
}

Write-LogMessage '=== BIND SUMMARY ===' -Level INFO
Write-LogMessage "Database:    $($DatabaseAlias)" -Level INFO
Write-LogMessage "Collection:  $($Collection)" -Level INFO
Write-LogMessage "Total .bnd:  $($bndFiles.Count)" -Level INFO
Write-LogMessage "Success:     $($successCount)" -Level INFO
Write-LogMessage "Failed:      $($failCount)" -Level INFO

$parentFolder = Split-Path $BndFolder -Parent
$reportPath = Join-Path $parentFolder "BindReport-$($timestamp).json"

[ordered]@{
    GeneratedAt   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Script        = 'Step50-Invoke-VcDb2Bind.ps1'
    DatabaseAlias = $DatabaseAlias
    Collection    = $Collection
    BindOptions   = $BindOptions
    BndFolder     = $BndFolder
    TotalFiles    = $bndFiles.Count
    Success       = $successCount
    Failed        = $failCount
    Results       = @($results)
} | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportPath -Encoding utf8 -Force

Write-LogMessage "Report: $($reportPath)" -Level INFO

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $msg = "DB2 Bind ($($DatabaseAlias)): $($successCount)/$($bndFiles.Count) OK, $($failCount) failed. Collection=$($Collection)"
    Send-Sms -Receiver $smsNumber -Message $msg
}

if ($failCount -gt 0) { exit 1 }
exit 0
