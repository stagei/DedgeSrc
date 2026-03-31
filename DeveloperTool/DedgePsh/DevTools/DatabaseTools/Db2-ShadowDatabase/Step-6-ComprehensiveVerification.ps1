<#
.SYNOPSIS
    Comprehensive database object inventory and row count verification.

.DESCRIPTION
    Step 6 of the shadow database workflow. Queries SYSCAT views for 16+ object types
    (Tables, Views, Indexes, Primary Keys, Foreign Keys, Unique Constraints, Check
    Constraints, Triggers, Procedures, Functions, Sequences, Aliases, Nicknames,
    Table Comments, Column Comments, MQTs) and compares them between source and target.

    Row counts are loaded from pre-exported JSON files produced by Step-6-RowCountExport.ps1,
    which runs as a background process alongside other pipeline steps.

    Called twice per pipeline run: once with -Phase PreMove (after Step-2),
    once with -Phase PostMove (after Step-4).

    Defaults are loaded from config.json. Parameters override config values.

.PARAMETER SourceInstance
    DB2 instance name for the source database.

.PARAMETER SourceDatabase
    Source database name.

.PARAMETER TargetInstance
    DB2 instance name for the target/shadow database.

.PARAMETER TargetDatabase
    Target/shadow database name.

.PARAMETER Phase
    Inventory phase: "PreMove" or "PostMove".

.PARAMETER OutputPath
    Optional override for JSON output path.

.PARAMETER SourceRowCountFile
    Path to pre-exported row count JSON for the source database.

.PARAMETER TargetRowCountFile
    Path to pre-exported row count JSON for the target database.

.EXAMPLE
    .\Step-6-ComprehensiveVerification.ps1 -Phase PreMove -SourceRowCountFile C:\temp\src.json -TargetRowCountFile C:\temp\tgt.json
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceInstance,

    [Parameter(Mandatory = $false)]
    [string]$SourceDatabase,

    [Parameter(Mandatory = $false)]
    [string]$TargetInstance,

    [Parameter(Mandatory = $false)]
    [string]$TargetDatabase,

    [Parameter(Mandatory = $true)]
    [ValidateSet("PreMove", "PostMove")]
    [string]$Phase,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$SourceRowCountFile,

    [Parameter(Mandatory = $false)]
    [string]$TargetRowCountFile
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
if ([string]::IsNullOrEmpty($SourceInstance))  { throw "SourceInstance not set." }
if ([string]::IsNullOrEmpty($SourceDatabase))  { throw "SourceDatabase not set." }
if ([string]::IsNullOrEmpty($TargetInstance))   { throw "TargetInstance not set." }
if ([string]::IsNullOrEmpty($TargetDatabase))   { throw "TargetDatabase not set." }

$systemSchemas = "'SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS'"

$objectQueries = [ordered]@{
    Tables            = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) AS OBJ_NAME FROM SYSCAT.TABLES WHERE TYPE='T' AND TABSCHEMA NOT IN ($systemSchemas) AND NOT EXISTS (SELECT 1 FROM SYSCAT.NICKNAMES N WHERE N.TABSCHEMA = SYSCAT.TABLES.TABSCHEMA AND N.TABNAME = SYSCAT.TABLES.TABNAME) ORDER BY TABSCHEMA, TABNAME"
    Views             = "SELECT RTRIM(VIEWSCHEMA) || '.' || RTRIM(VIEWNAME) AS OBJ_NAME FROM SYSCAT.VIEWS WHERE VIEWSCHEMA NOT IN ($systemSchemas) ORDER BY VIEWSCHEMA, VIEWNAME"
    Indexes           = "SELECT RTRIM(INDSCHEMA) || '.' || RTRIM(INDNAME) AS OBJ_NAME FROM SYSCAT.INDEXES WHERE INDSCHEMA NOT IN ($systemSchemas) AND INDEXTYPE NOT IN ('SBLK','XBLK') AND SYSTEM_REQUIRED = 0 ORDER BY INDSCHEMA, INDNAME"
    PrimaryKeys       = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(CONSTNAME) AS OBJ_NAME FROM SYSCAT.TABCONST WHERE TYPE='P' AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, CONSTNAME"
    ForeignKeys       = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(CONSTNAME) AS OBJ_NAME FROM SYSCAT.TABCONST WHERE TYPE='F' AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, CONSTNAME"
    UniqueConstraints = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(CONSTNAME) AS OBJ_NAME FROM SYSCAT.TABCONST WHERE TYPE='U' AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, CONSTNAME"
    CheckConstraints  = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(CONSTNAME) AS OBJ_NAME FROM SYSCAT.TABCONST WHERE TYPE='K' AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, CONSTNAME"
    Triggers          = "SELECT RTRIM(TRIGSCHEMA) || '.' || RTRIM(TRIGNAME) AS OBJ_NAME FROM SYSCAT.TRIGGERS WHERE TRIGSCHEMA NOT IN ($systemSchemas) ORDER BY TRIGSCHEMA, TRIGNAME"
    Procedures        = "SELECT RTRIM(PROCSCHEMA) || '.' || RTRIM(PROCNAME) AS OBJ_NAME FROM SYSCAT.PROCEDURES WHERE PROCSCHEMA NOT IN ($systemSchemas) ORDER BY PROCSCHEMA, PROCNAME"
    Functions         = "SELECT RTRIM(FUNCSCHEMA) || '.' || RTRIM(FUNCNAME) AS OBJ_NAME FROM SYSCAT.FUNCTIONS WHERE FUNCSCHEMA NOT IN ($systemSchemas) AND ORIGIN='Q' ORDER BY FUNCSCHEMA, FUNCNAME"
    Sequences         = "SELECT RTRIM(SEQSCHEMA) || '.' || RTRIM(SEQNAME) AS OBJ_NAME FROM SYSCAT.SEQUENCES WHERE SEQTYPE='S' AND SEQSCHEMA NOT IN ($systemSchemas) ORDER BY SEQSCHEMA, SEQNAME"
    Aliases           = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) AS OBJ_NAME FROM SYSCAT.TABLES WHERE TYPE='A' AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, TABNAME"
    Nicknames         = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) AS OBJ_NAME FROM SYSCAT.NICKNAMES WHERE TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, TABNAME"
    TableComments     = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) AS OBJ_NAME FROM SYSCAT.TABLES WHERE REMARKS IS NOT NULL AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, TABNAME"
    ColumnComments    = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) || '.' || RTRIM(COLNAME) AS OBJ_NAME FROM SYSCAT.COLUMNS WHERE REMARKS IS NOT NULL AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, TABNAME, COLNAME"
    MQTs              = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) AS OBJ_NAME FROM SYSCAT.TABLES WHERE TYPE='S' AND TABSCHEMA NOT IN ($systemSchemas) ORDER BY TABSCHEMA, TABNAME"
}

function Invoke-Db2Query {
    param(
        [string]$InstanceName,
        [string]$DatabaseName,
        [string]$Query,
        [string]$WorkFolder,
        [string]$Label
    )
    $cleanQuery = $Query -replace '[\r\n]+', ' '
    $cmds = @()
    $cmds += "set DB2INSTANCE=$($InstanceName)"
    $cmds += "db2 connect to $($DatabaseName)"
    $cmds += 'db2 "' + $cleanQuery + '"'
    $cmds += "db2 connect reset"
    $cmds += "db2 terminate"
    $output = Invoke-Db2ContentAsScript -Content $cmds -ExecutionType BAT `
        -FileName (Join-Path $WorkFolder "$($Label)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    return $output
}

function Parse-Db2ObjectList {
    param([string]$Output)
    $objects = @()
    $lines = $Output -split "`n"
    $inData = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\d+\s+(post\(er\)\s+er\s+valgt|record\(s\)\s+selected)') { $inData = $false; continue }
        if ($trimmed -match '^[A-Z]:\\.*>') { $inData = $false; continue }
        if ($trimmed -match '^-{4,}') { $inData = $true; continue }
        if ($inData -and -not [string]::IsNullOrWhiteSpace($trimmed)) {
            $parts = $trimmed -split '\s{2,}', 2
            if ($parts.Count -ge 1 -and $parts[0] -match '^\w+\.') {
                $objects += $parts[0].Trim()
            }
        }
    }
    return $objects
}

function Import-RowCountFile {
    param([string]$FilePath)
    $counts = [ordered]@{}
    if ([string]::IsNullOrEmpty($FilePath) -or -not (Test-Path $FilePath)) { return $counts }
    $json = Get-Content $FilePath -Raw | ConvertFrom-Json
    foreach ($prop in $json.RowCounts.PSObject.Properties) {
        $counts[$prop.Name] = [long]$prop.Value
    }
    return $counts
}

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Step 6: Comprehensive Verification ($($Phase)) - $($SourceDatabase)/$($TargetDatabase)" -Level INFO

    Test-Db2ServerAndAdmin

    $workFolder = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $workFolder
    Write-LogMessage "Work folder: $($workFolder)" -Level INFO

    if ($Phase -eq "PreMove") {
        $dbA = @{ Instance = $SourceInstance; Database = $SourceDatabase; Label = "Source" }
        $dbB = @{ Instance = $TargetInstance; Database = $TargetDatabase; Label = "Target" }
    } else {
        $dbA = @{ Instance = $SourceInstance; Database = $SourceDatabase; Label = "Original" }
        $dbB = $null
    }

    $inventory = [ordered]@{
        Timestamp    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Phase        = $Phase
        SourceDb     = $SourceDatabase
        TargetDb     = $TargetDatabase
        SourceInst   = $SourceInstance
        TargetInst   = $TargetInstance
        ObjectCounts = [ordered]@{}
        RowCounts    = [ordered]@{}
        Summary      = [ordered]@{}
    }

    $totalMismatches = 0

    #########################################################
    # Object Inventory (always live SYSCAT queries)
    #########################################################
    foreach ($objectType in $objectQueries.Keys) {
        Write-LogMessage "Collecting $($objectType) from $($dbA.Label) ($($dbA.Database))..." -Level INFO
        $outputA = Invoke-Db2Query -InstanceName $dbA.Instance -DatabaseName $dbA.Database `
            -Query $objectQueries[$objectType] -WorkFolder $workFolder -Label "$($objectType)_$($dbA.Label)"
        $objectsA = @(Parse-Db2ObjectList -Output $outputA)

        if ($null -ne $dbB) {
            Write-LogMessage "Collecting $($objectType) from $($dbB.Label) ($($dbB.Database))..." -Level INFO
            $outputB = Invoke-Db2Query -InstanceName $dbB.Instance -DatabaseName $dbB.Database `
                -Query $objectQueries[$objectType] -WorkFolder $workFolder -Label "$($objectType)_$($dbB.Label)"
            $objectsB = @(Parse-Db2ObjectList -Output $outputB)

            $missing = @($objectsA | Where-Object { $_ -notin $objectsB })
            $extra = @($objectsB | Where-Object { $_ -notin $objectsA })
            $match = ($missing.Count -eq 0 -and $extra.Count -eq 0)
            if (-not $match) { $totalMismatches++ }

            $inventory.ObjectCounts[$objectType] = [ordered]@{
                SourceCount = $objectsA.Count
                TargetCount = $objectsB.Count
                Match       = $match
                Missing     = $missing
                Extra       = $extra
            }

            if (-not $match) {
                Write-LogMessage "$($objectType): MISMATCH - Source=$($objectsA.Count), Target=$($objectsB.Count), Missing=$($missing.Count), Extra=$($extra.Count)" -Level WARN
            } else {
                Write-LogMessage "$($objectType): MATCH - $($objectsA.Count) objects" -Level INFO
            }
        } else {
            $inventory.ObjectCounts[$objectType] = [ordered]@{
                SourceCount = $objectsA.Count
                TargetCount = $null
                Match       = $null
                Missing     = @()
                Extra       = @()
            }
            Write-LogMessage "$($objectType): $($objectsA.Count) objects" -Level INFO
        }
    }

    #########################################################
    # Row Counts (from pre-exported JSON files only)
    #########################################################
    $rowCountMismatches = 0
    $tableCount = 0
    $hasSourceCounts = (-not [string]::IsNullOrEmpty($SourceRowCountFile) -and (Test-Path $SourceRowCountFile))
    $hasTargetCounts = (-not [string]::IsNullOrEmpty($TargetRowCountFile) -and (Test-Path $TargetRowCountFile))

    if ($hasSourceCounts) {
        Write-LogMessage "Loading source row counts from: $($SourceRowCountFile)" -Level INFO
        $sourceCounts = Import-RowCountFile -FilePath $SourceRowCountFile
        $tableCount = $sourceCounts.Count
        Write-LogMessage "Loaded $($tableCount) source row counts" -Level INFO

        if ($hasTargetCounts) {
            Write-LogMessage "Loading target row counts from: $($TargetRowCountFile)" -Level INFO
            $targetCounts = Import-RowCountFile -FilePath $TargetRowCountFile
            Write-LogMessage "Loaded $($targetCounts.Count) target row counts" -Level INFO

            foreach ($tbl in $sourceCounts.Keys) {
                $srcCount = $sourceCounts[$tbl]
                $tgtCount = if ($targetCounts.Contains($tbl)) { $targetCounts[$tbl] } else { -1 }
                $match = ($srcCount -eq $tgtCount)
                if (-not $match) { $rowCountMismatches++ }
                $inventory.RowCounts[$tbl] = [ordered]@{
                    Source = $srcCount
                    Target = $tgtCount
                    Match  = $match
                }
            }
            foreach ($tbl in $targetCounts.Keys) {
                if (-not $sourceCounts.Contains($tbl)) {
                    $rowCountMismatches++
                    $inventory.RowCounts[$tbl] = [ordered]@{
                        Source = -1
                        Target = $targetCounts[$tbl]
                        Match  = $false
                    }
                }
            }
        } else {
            Write-LogMessage "No target row count file provided — recording source counts only" -Level INFO
            foreach ($tbl in $sourceCounts.Keys) {
                $inventory.RowCounts[$tbl] = [ordered]@{
                    Source = $sourceCounts[$tbl]
                    Target = $null
                    Match  = $null
                }
            }
        }
    } else {
        Write-LogMessage "No row count files provided — skipping row count comparison" -Level WARN
    }

    $inventory.Summary = [ordered]@{
        TotalObjectTypes   = $objectQueries.Keys.Count
        TotalTables        = $tableCount
        ObjectMismatches   = $totalMismatches
        RowCountMismatches = $rowCountMismatches
        AllMatch           = ($totalMismatches -eq 0 -and $rowCountMismatches -eq 0)
        SourceRowCountFile = if ($hasSourceCounts) { $SourceRowCountFile } else { $null }
        TargetRowCountFile = if ($hasTargetCounts) { $TargetRowCountFile } else { $null }
    }

    if ([string]::IsNullOrEmpty($OutputPath)) {
        $execLogsDir = Join-Path $PSScriptRoot "ExecLogs"
        if (-not (Test-Path $execLogsDir -PathType Container)) {
            New-Item -Path $execLogsDir -ItemType Directory -Force | Out-Null
        }
        $OutputPath = Join-Path $execLogsDir "$($env:COMPUTERNAME)_$($Phase)_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    }

    $inventory | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
    Write-LogMessage "Inventory written to: $($OutputPath)" -Level INFO

    Write-LogMessage "===============================================================" -Level INFO
    Write-LogMessage "Step 6 Summary ($($Phase)):" -Level INFO
    Write-LogMessage "  Object types checked: $($objectQueries.Keys.Count)" -Level INFO
    Write-LogMessage "  Object mismatches: $($totalMismatches)" -Level INFO
    Write-LogMessage "  Tables with row counts: $($tableCount)" -Level INFO
    Write-LogMessage "  Row count mismatches: $($rowCountMismatches)" -Level INFO
    Write-LogMessage "  Overall: $(if ($inventory.Summary.AllMatch) { 'ALL MATCH' } else { 'MISMATCHES FOUND' })" -Level INFO
    Write-LogMessage "===============================================================" -Level INFO

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Step 6 ($($Phase)) FAILED: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
