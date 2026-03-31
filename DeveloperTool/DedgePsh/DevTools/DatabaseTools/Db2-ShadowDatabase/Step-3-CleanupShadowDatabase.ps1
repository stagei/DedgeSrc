<#
.SYNOPSIS
    Verifies all schema objects exist in the shadow database.

.DESCRIPTION
    Step 3 of the shadow database workflow. Compares object counts between the
    source and shadow databases for: tables, views, functions, procedures,
    triggers, and sequences. Reports any missing objects.

    Defaults are loaded from config.json. Parameters override config values.

.EXAMPLE
    .\Step-3-CleanupShadowDatabase.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceInstance,

    [Parameter(Mandatory = $false)]
    [string]$SourceDatabase,

    [Parameter(Mandatory = $false)]
    [string]$TargetInstance,

    [Parameter(Mandatory = $false)]
    [string]$TargetDatabase
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrEmpty($SourceInstance))  { $SourceInstance = $cfg.SourceInstance }
if ([string]::IsNullOrEmpty($SourceDatabase))  { $SourceDatabase = $cfg.SourceDatabase }
if ([string]::IsNullOrEmpty($TargetInstance))   { $TargetInstance = $cfg.TargetInstance }
if ([string]::IsNullOrEmpty($TargetDatabase))   { $TargetDatabase = $cfg.TargetDatabase }
if ([string]::IsNullOrEmpty($SourceInstance))  { throw "SourceInstance not set. Configure in config.json or pass -SourceInstance." }
if ([string]::IsNullOrEmpty($SourceDatabase))  { throw "SourceDatabase not set. Configure in config.json or pass -SourceDatabase." }
if ([string]::IsNullOrEmpty($TargetInstance))   { throw "TargetInstance not set. Configure in config.json or pass -TargetInstance." }
if ([string]::IsNullOrEmpty($TargetDatabase))   { throw "TargetDatabase not set. Configure in config.json or pass -TargetDatabase." }

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Step-3: Verifying schema objects between $($SourceDatabase) ($($SourceInstance)) and $($TargetDatabase) ($($TargetInstance))" -Level INFO

    Test-Db2ServerAndAdmin

    $workFolder = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $workFolder

    $excludeSchemas = "'SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS'"

    $objectQueries = @{
        TABLES     = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) FROM SYSCAT.TABLES WHERE TYPE = 'T' AND TABSCHEMA NOT IN ($($excludeSchemas)) ORDER BY TABSCHEMA, TABNAME"
        VIEWS      = "SELECT RTRIM(VIEWSCHEMA) || '.' || RTRIM(VIEWNAME) FROM SYSCAT.VIEWS WHERE VIEWSCHEMA NOT IN ($($excludeSchemas)) ORDER BY VIEWSCHEMA, VIEWNAME"
        FUNCTIONS  = "SELECT DISTINCT RTRIM(FUNCSCHEMA) || '.' || RTRIM(FUNCNAME) FROM SYSCAT.FUNCTIONS WHERE FUNCSCHEMA NOT IN ($($excludeSchemas)) AND ORIGIN = 'Q' ORDER BY 1"
        PROCEDURES = "SELECT RTRIM(PROCSCHEMA) || '.' || RTRIM(PROCNAME) FROM SYSCAT.PROCEDURES WHERE PROCSCHEMA NOT IN ($($excludeSchemas)) ORDER BY PROCSCHEMA, PROCNAME"
        TRIGGERS   = "SELECT RTRIM(TRIGSCHEMA) || '.' || RTRIM(TRIGNAME) FROM SYSCAT.TRIGGERS WHERE TRIGSCHEMA NOT IN ($($excludeSchemas)) ORDER BY TRIGSCHEMA, TRIGNAME"
        SEQUENCES  = "SELECT RTRIM(SEQSCHEMA) || '.' || RTRIM(SEQNAME) FROM SYSCAT.SEQUENCES WHERE SEQSCHEMA NOT IN ($($excludeSchemas)) AND SEQTYPE = 'S' ORDER BY SEQSCHEMA, SEQNAME"
    }

    function Get-ObjectList {
        param([string]$Instance, [string]$Database, [string]$Query, [string]$Label)

        $cmds = @()
        $cmds += "set DB2INSTANCE=$($Instance)"
        $cmds += "db2 connect to $($Database)"
        $cmds += "db2 `"$($Query)`""
        $cmds += "db2 connect reset"
        $cmds += "db2 terminate"

        $output = Invoke-Db2ContentAsScript -Content $cmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "$($Label)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

        $objects = @()
        $lines = $output -split "`n"
        $inData = $false
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\d+\s+(post\(er\)\s+er\s+valgt|record\(s\)\s+selected)') { $inData = $false; continue }
            if ($trimmed -match '^[A-Z]:\\.*>') { $inData = $false; continue }
            if ($trimmed -match '^-{4,}') { $inData = $true; continue }
            if ($inData -and -not [string]::IsNullOrWhiteSpace($trimmed) -and $trimmed -notmatch '^1$') {
                $objects += $trimmed
            }
        }
        return $objects
    }

    $totalMissing = 0
    $summary = @()

    foreach ($objType in @('TABLES', 'VIEWS', 'FUNCTIONS', 'PROCEDURES', 'TRIGGERS', 'SEQUENCES')) {
        Write-LogMessage "Comparing $($objType) between $($SourceDatabase) and $($TargetDatabase)" -Level INFO

        $sourceObjects = Get-ObjectList -Instance $SourceInstance -Database $SourceDatabase `
            -Query $objectQueries[$objType] -Label "Src_$($objType)"
        $targetObjects = Get-ObjectList -Instance $TargetInstance -Database $TargetDatabase `
            -Query $objectQueries[$objType] -Label "Tgt_$($objType)"

        $srcSet = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($o in $sourceObjects) { [void]$srcSet.Add($o) }
        $tgtSet = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($o in $targetObjects) { [void]$tgtSet.Add($o) }

        $missing = $sourceObjects | Where-Object { -not $tgtSet.Contains($_) }
        $extra   = $targetObjects | Where-Object { -not $srcSet.Contains($_) }

        $missingCount = @($missing).Count
        $extraCount   = @($extra).Count

        $status = if ($missingCount -eq 0) { "OK" } else { "MISSING $($missingCount)" }
        $line = "$($objType): Source=$($sourceObjects.Count) Target=$($targetObjects.Count) Missing=$($missingCount) Extra=$($extraCount)"
        Write-LogMessage "  $($line) [$($status)]" -Level $(if ($missingCount -gt 0) { "WARN" } else { "INFO" })
        $summary += $line

        if ($missingCount -gt 0) {
            $totalMissing += $missingCount
            foreach ($obj in $missing) {
                Write-LogMessage "    MISSING in target: $($obj)" -Level WARN
            }
        }
    }

    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "SCHEMA OBJECT VERIFICATION SUMMARY" -Level INFO
    foreach ($s in $summary) { Write-LogMessage "  $($s)" -Level INFO }
    Write-LogMessage "Total missing objects: $($totalMissing)" -Level INFO
    Write-LogMessage "========================================" -Level INFO

    if ($totalMissing -gt 0) {
        Write-LogMessage "Step 3 WARNING: $($totalMissing) objects missing in shadow database" -Level WARN
    }
    else {
        Write-LogMessage "Step 3 OK: All schema objects match between source and shadow" -Level INFO
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
