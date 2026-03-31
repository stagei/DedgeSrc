<#
.SYNOPSIS
    Copies DDL and data from source database to shadow database.

.DESCRIPTION
    Step 2 of the shadow database workflow. Auto-discovers user schemas from the source,
    then copies schema objects and data to the target shadow database.

    Supports two modes:
    - Same instance: uses db2move COPY with MODE DDL_AND_LOAD and TABLESPACE_MAP SYS_ANY
    - Cross instance: uses db2look for DDL extraction, strips tablespace references
      so all objects go to default USERSPACE1 (AUTOMATIC STORAGE), then db2move EXPORT + LOAD

    All DB2 connections use OS authentication (implicit SYSADM) — the service
    account running the script is the instance owner and needs no explicit user/password.

    Defaults are loaded from config.json. Parameters override config values.

.PARAMETER DataDisk
    Drive letter for export staging files (e.g. "F:"). Splits I/O so the
    source DB reads from one disk while export writes go to another controller.

.EXAMPLE
    .\Step-2-CopyDatabaseContent.ps1
    .\Step-2-CopyDatabaseContent.ps1
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

    [Parameter(Mandatory = $false)]
    [string]$Schemas = "",

    [Parameter(Mandatory = $false)]
    [string]$DataDisk,

    [Parameter(Mandatory = $false)]
    [switch]$SkipExport
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
if ([string]::IsNullOrEmpty($DataDisk))         { $DataDisk = $cfg.DataDisk }
if ([string]::IsNullOrEmpty($SourceInstance))  { throw "SourceInstance not set. Configure in config.json or pass -SourceInstance." }
if ([string]::IsNullOrEmpty($SourceDatabase))  { throw "SourceDatabase not set. Configure in config.json or pass -SourceDatabase." }
if ([string]::IsNullOrEmpty($TargetInstance))   { throw "TargetInstance not set. Configure in config.json or pass -TargetInstance." }
if ([string]::IsNullOrEmpty($TargetDatabase))   { throw "TargetDatabase not set. Configure in config.json or pass -TargetDatabase." }

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Source: $($SourceDatabase) on $($SourceInstance) -> Target: $($TargetDatabase) on $($TargetInstance)" -Level INFO

    Test-Db2ServerAndAdmin

    $workFolder = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $workFolder
    Write-LogMessage "Work folder: $($workFolder)" -Level INFO

    $crossInstance = ($SourceInstance -ne $TargetInstance)
    if ($crossInstance) {
        Write-LogMessage "Cross-instance mode: will use db2look + db2move EXPORT/LOAD" -Level INFO
    }
    else {
        Write-LogMessage "Same-instance mode: will use db2move COPY" -Level INFO
    }

    #########################################################
    # Phase 1: Auto-discover user schemas from source
    #########################################################
    if ([string]::IsNullOrEmpty($Schemas)) {
        Write-LogMessage "Phase 1: Auto-discovering user schemas from $($SourceDatabase)" -Level INFO

        $schemaQuery = "SELECT DISTINCT RTRIM(TABSCHEMA) FROM SYSCAT.TABLES WHERE TABSCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC', 'SYSTOOLS')"

        $discoverCommands = @()
        $discoverCommands += "set DB2INSTANCE=$($SourceInstance)"
        $discoverCommands += "db2 connect to $($SourceDatabase)"
        $discoverCommands += "db2 `"$($schemaQuery)`""
        $discoverCommands += "db2 connect reset"
        $discoverCommands += "db2 terminate"

        $output = Invoke-Db2ContentAsScript -Content $discoverCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "DiscoverSchemas_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "Schema discovery output: $($output)" -Level INFO

        # Parse schema names from db2 output (supports Norwegian and English locales)
        $systemSchemas = @('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC', 'SYSTOOLS', '1', 'RTRIM', 'TABSCHEMA')
        $schemaList = @()
        $outputLines = $output -split "`n"
        $inData = $false
        foreach ($line in $outputLines) {
            $trimmed = $line.Trim()
            # Regex: record count footer
            #   ^\d+\s+post\(er\)\s+er\s+valgt  -- Norwegian
            #   ^\d+\s+record\(s\)\s+selected   -- English
            if ($trimmed -match '^\d+\s+(post\(er\)\s+er\s+valgt|record\(s\)\s+selected)') {
                $inData = $false
                continue
            }
            # Stop at db2 prompt lines (e.g. "E:\opt\DedgePshApps>db2 ...")
            if ($trimmed -match '^[A-Z]:\\.*>') {
                $inData = $false
                continue
            }
            if ($trimmed -match '^-{4,}$') {
                $inData = $true
                continue
            }
            if ($inData -and -not [string]::IsNullOrWhiteSpace($trimmed) -and $trimmed -notmatch '^1$' -and $trimmed -notmatch '^RTRIM') {
                $schemaList += $trimmed
            }
        }
        # Fallback: db2 may not output dashes, or may put column and value on one line.
        # DB2 schema names from SYSCAT.TABLES are always UPPERCASE, so only accept
        # fully uppercase tokens to avoid picking up Norwegian connection output
        # words (e.g. "Databasetjener", "Kommandoen", "Tilkoblingsopplysninger").
        if ($schemaList.Count -eq 0) {
            $db2NoisePrefixes = @('DB2', 'SQL', 'TERMINATE', 'CONNECT', 'RESET', 'SET')
            foreach ($line in $outputLines) {
                $trimmed = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                # Skip prompts, record count, db2 message codes, and connection info
                if ($trimmed -match '^[A-Z]:\\.*>') { continue }
                if ($trimmed -match '^\d+\s+(post\(er\)|record\(s\))') { continue }
                if ($trimmed -match 'DB2\d{4}[A-Z]') { continue }
                if ($trimmed -match '(?i)(databasetjener|databasealias|tilkoblings|Kommandoen|autorisasjons|connect|server\s*=)') { continue }
                foreach ($token in ($trimmed -split '\s+')) {
                    # Regex: Only accept fully UPPERCASE identifiers (DB2 schema convention)
                    #   ^[A-Z][A-Z0-9_]*$  -- starts with uppercase letter, rest uppercase/digits/underscore
                    if ($token -match '^[A-Z][A-Z0-9_]*$' -and $token -notin $systemSchemas -and $token -notin $db2NoisePrefixes -and $token.Length -ge 2) {
                        $schemaList += $token
                    }
                }
            }
            $schemaList = $schemaList | Sort-Object -Unique
        }

        if ($schemaList.Count -eq 0) {
            throw "No user schemas found in $($SourceDatabase). Check database connectivity."
        }

        $Schemas = $schemaList -join ","
        Write-LogMessage "Discovered schemas: $($Schemas)" -Level INFO
    }

    $schemaCount = ($Schemas -split ",").Count
    Write-LogMessage "Will copy $($schemaCount) schema(s): $($Schemas)" -Level INFO

    if ($crossInstance) {
        #########################################################
        # Cross-instance: Phase 2a0 - Reset buffer pools + enable STMM on source
        #
        # After PRD restore, FKMVFT carries production buffer pool definitions
        # (potentially hundreds of named pools, multi-GB each). These exceed test
        # server RAM and cause SQL1218N during db2look and package bind.
        #
        # DB2 STMM 3-step pattern (db2_perf_tune_1212.md):
        #   1. ALTER BUFFERPOOL ... SIZE <fixed> — clears SYSCAT.BUFFERPOOLDBPARTITIONS
        #      exception entries that block STMM
        #   2. ALTER BUFFERPOOL ... SIZE AUTOMATIC — hands control to STMM
        #   3. deactivate/activate — STMM allocates pages based on available RAM
        #
        # Also resets legacy PRD memory config params (LOCKLIST, SORTHEAP, etc.)
        # to AUTOMATIC so DB2 manages them for the test environment.
        #########################################################
        Write-LogMessage "Phase 2a0: Resetting buffer pools + enabling STMM on $($SourceDatabase)" -Level INFO
        $resetBpCommands = @()
        $resetBpCommands += "set DB2INSTANCE=$($SourceInstance)"
        $resetBpCommands += "db2 force application all"
        $resetBpCommands += "db2 connect to $($SourceDatabase)"
        # Step 1: Set all buffer pools to fixed 1000 pages to clear partition exception entries
        $resetBpCommands += "db2 -x `"SELECT 'ALTER BUFFERPOOL ' || RTRIM(BPNAME) || ' SIZE 1000 ;' FROM SYSCAT.BUFFERPOOLS`" | db2 +p -"
        # Step 2: Hand all buffer pools to STMM (AUTOMATIC)
        $resetBpCommands += "db2 -x `"SELECT 'ALTER BUFFERPOOL ' || RTRIM(BPNAME) || ' SIZE AUTOMATIC ;' FROM SYSCAT.BUFFERPOOLS`" | db2 +p -"
        # Reset legacy PRD memory config params to AUTOMATIC for test environment.
        # DATABASE_MEMORY must be reset first — PRD may carry a large fixed value (e.g. 818832 pages = ~3.2 GB).
        # Setting it to AUTOMATIC lets DB2 size the shared database memory pool for available test-server RAM.
        # SHEAPTHRES (instance-level) is already 0 on this instance, which is required for SORTHEAP AUTOMATIC.
        $resetBpCommands += "db2 update db cfg for $($SourceDatabase) using SELF_TUNING_MEM ON"
        $resetBpCommands += "db2 update db cfg for $($SourceDatabase) using DATABASE_MEMORY AUTOMATIC"
        $resetBpCommands += "db2 update db cfg for $($SourceDatabase) using LOCKLIST AUTOMATIC"
        $resetBpCommands += "db2 update db cfg for $($SourceDatabase) using SHEAPTHRES_SHR AUTOMATIC"
        $resetBpCommands += "db2 update db cfg for $($SourceDatabase) using PCKCACHESZ AUTOMATIC"
        $resetBpCommands += "db2 update db cfg for $($SourceDatabase) using SORTHEAP AUTOMATIC"
        $resetBpCommands += "db2 connect reset"
        $resetBpCommands += "db2 deactivate db $($SourceDatabase)"
        $resetBpCommands += "db2 activate db $($SourceDatabase)"
        Invoke-Db2ContentAsScript -Content $resetBpCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "ResetBufferPools_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors | Out-Null
        Write-LogMessage "Phase 2a0: Buffer pool reset + STMM enabled on $($SourceDatabase)" -Level INFO

        #########################################################
        # Cross-instance: Phase 2a1 - Rebind DB2 packages
        # After PRD restore, db2look packages (DB2LKFUN.BND etc.)
        # may be incompatible with the local DB2 installation,
        # causing SQL0001N bind errors and empty DDL output.
        #########################################################
        Write-LogMessage "Phase 2a1: Rebinding DB2 packages on $($SourceDatabase)" -Level INFO
        $bindCommands = @()
        $bindCommands += "set DB2INSTANCE=$($SourceInstance)"
        $bindCommands += "db2 connect to $($SourceDatabase)"
        $bindCommands += "db2 bind `"C:\DbInst\BND\@db2ubind.lst`" blocking all grant public sqlerror continue"
        $bindCommands += "db2 bind `"C:\DbInst\BND\@db2cli.lst`" blocking all grant public sqlerror continue"
        $bindCommands += "db2 bind `"C:\DbInst\BND\DB2LKFUN.BND`" blocking all grant public sqlerror continue"
        $bindCommands += "db2 connect reset"
        $bindOutput = Invoke-Db2ContentAsScript -Content $bindCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "RebindPackages_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors -UseNewConfigurations
        Write-LogMessage "Phase 2a1: Package rebind completed. Output: $($bindOutput)" -Level INFO

        #########################################################
        # Cross-instance: Phase 2a - Extract DDL with db2look
        #########################################################
        Write-LogMessage "Phase 2a: Extracting DDL from $($SourceDatabase) with db2look" -Level INFO
        $ddlFile = Join-Path $workFolder "source_ddl_$(Get-Date -Format 'yyyyMMddHHmmssfff').sql"

        $ddlCommands = @()
        $ddlCommands += "set DB2INSTANCE=$($SourceInstance)"
        $ddlCommands += "db2look -d $($SourceDatabase) -e -a -l -td @ -o `"$($ddlFile)`""

        $output = Invoke-Db2ContentAsScript -Content $ddlCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "Db2look_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "db2look output: $($output)" -Level INFO

        if (-not (Test-Path $ddlFile)) {
            throw "DDL file not found: $($ddlFile)"
        }

        $ddlSizeKB = [math]::Round((Get-Item $ddlFile).Length / 1KB, 2)
        Write-LogMessage "Phase 2a: DDL file size: $($ddlSizeKB) KB" -Level INFO
        if ($ddlSizeKB -lt 100) {
            $errFile = (Get-ChildItem $workFolder -Filter "Db2look_*.err" | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            $errContent = if ($errFile) { Get-Content $errFile.FullName -Raw -ErrorAction SilentlyContinue } else { "no error file" }
            throw "Phase 2a: DDL file critically small ($($ddlSizeKB) KB). Expected >1 MB for $($SourceDatabase). db2look error: $($errContent)"
        }

        #########################################################
        # Cross-instance: Phase 2b - Clean and apply DDL to target
        #########################################################
        Write-LogMessage "Phase 2b: Cleaning DDL file for shadow database (statement-level)" -Level INFO

        $win1252 = [System.Text.Encoding]::GetEncoding(1252)
        $rawDdl = [System.IO.File]::ReadAllText($ddlFile, $win1252)

        # Split by @ terminator into individual statements
        $statements = $rawDdl -split '@'
        $keptCount = 0
        $droppedCount = 0
        $cleanedStatements = @()

        foreach ($stmt in $statements) {
            $trimmed = $stmt.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

            # Skip patterns:
            #   CONNECT/TERMINATE/COMMIT  - session commands from db2look header
            #   BUFFERPOOL/TABLESPACE     - storage objects (shadow uses defaults)
            #   WRAPPER/SERVER/NICKNAME   - federation objects (not needed on shadow)
            #   USER MAPPING              - federated user mappings
            #   GRANT/REVOKE              - user permissions (added later via role-based config)
            $skip = ($trimmed -match '(?mi)^\s*CONNECT\s+(TO|RESET)\b') -or
                    ($trimmed -match '(?mi)^\s*TERMINATE\s*$') -or
                    ($trimmed -match '(?mi)^\s*COMMIT\s+WORK\s*$') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+BUFFERPOOL\s+') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+(REGULAR\s+|LARGE\s+|SYSTEM\s+TEMPORARY\s+)?TABLESPACE\s+') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+WRAPPER\s+') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+SERVER\s+') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+NICKNAME\s+') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+ALIAS\s+') -or
                    ($trimmed -match '(?mi)^\s*CREATE\s+USER\s+MAPPING\s+') -or
                    ($trimmed -match '(?mi)^\s*ALTER\s+NICKNAME\s+') -or
                    ($trimmed -match '(?mi)^\s*GRANT\s+') -or
                    ($trimmed -match '(?mi)^\s*REVOKE\s+')

            if ($skip) {
                $droppedCount++
                continue
            }

            # Strip tablespace IN clauses -- all tables go to default USERSPACE1 (automatic storage)
            $cleaned = $trimmed -replace '\b(INDEX\s+|LONG\s+)?IN\s+"[^"]+"\s*', ' '

            # SQL0574N fix: USER/SESSION_USER return VARCHAR(128), incompatible with CHAR(8)
            $cleaned = $cleaned -replace 'WITH DEFAULT USER\b', "WITH DEFAULT ' '"
            $cleaned = $cleaned -replace 'WITH DEFAULT SESSION_USER\b', "WITH DEFAULT ' '"

            $cleanedStatements += $cleaned
            $keptCount++
        }

        $cleanedDdlFile = $ddlFile -replace '\.sql$', '_cleaned.sql'
        $cleanedText = ($cleanedStatements -join "`n@`n") + "`n@`n"
        [System.IO.File]::WriteAllText($cleanedDdlFile, $cleanedText, $win1252)
        Write-LogMessage "Cleaned DDL: kept $($keptCount) statements, dropped $($droppedCount) (Windows-1252 encoding)" -Level INFO

        Write-LogMessage "Phase 2b: Applying DDL to $($TargetDatabase) on $($TargetInstance) (OS auth, terminator @)" -Level INFO

        $applyDdlCommands = @()
        $applyDdlCommands += "set DB2INSTANCE=$($TargetInstance)"
        $applyDdlCommands += "db2start"
        $applyDdlCommands += "db2 connect to $($TargetDatabase)"
        $applyDdlCommands += "db2 -td@ -vf `"$($cleanedDdlFile)`""
        $applyDdlCommands += "db2 connect reset"
        $applyDdlCommands += "db2 terminate"

        $output = Invoke-Db2ContentAsScript -Content $applyDdlCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "ApplyDdl_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors -UseNewConfigurations
        $ddlOutputLines = ($output -split "`n").Count
        Write-LogMessage "Apply DDL completed: $($ddlOutputLines) output lines processed" -Level INFO

        #########################################################
        # Cross-instance: Phase 2b1 - Enable STMM on shadow database
        #
        # The shadow DB (FKMVFTSH) was created fresh so it has DB2 defaults.
        # CREATE BUFFERPOOL/TABLESPACE statements were stripped from DDL (Phase 2b),
        # so the shadow uses IBMDEFAULTBP only — correct for test environment.
        # Explicitly enable STMM so DB2 auto-manages buffer pool and memory params.
        # Per db2_perf_tune_1212.md: SELF_TUNING_MEM ON + 2+ consumers = AUTOMATIC.
        #########################################################
        Write-LogMessage "Phase 2b1: Enabling STMM on $($TargetDatabase) (shadow database)" -Level INFO
        $stmmCommands = @()
        $stmmCommands += "set DB2INSTANCE=$($TargetInstance)"
        $stmmCommands += "db2 connect to $($TargetDatabase)"
        $stmmCommands += "db2 update db cfg for $($TargetDatabase) using SELF_TUNING_MEM ON"
        $stmmCommands += "db2 update db cfg for $($TargetDatabase) using DATABASE_MEMORY AUTOMATIC"
        $stmmCommands += "db2 update db cfg for $($TargetDatabase) using LOCKLIST AUTOMATIC"
        $stmmCommands += "db2 update db cfg for $($TargetDatabase) using SHEAPTHRES_SHR AUTOMATIC"
        $stmmCommands += "db2 update db cfg for $($TargetDatabase) using PCKCACHESZ AUTOMATIC"
        $stmmCommands += "db2 update db cfg for $($TargetDatabase) using SORTHEAP AUTOMATIC"
        $stmmCommands += "db2 alter bufferpool IBMDEFAULTBP size automatic"
        $stmmCommands += "db2 connect reset"
        Invoke-Db2ContentAsScript -Content $stmmCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "EnableStmm_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors | Out-Null
        Write-LogMessage "Phase 2b1: STMM enabled on $($TargetDatabase) — DB2 auto-manages buffer pools and memory" -Level INFO

        #########################################################
        # Cross-instance: Phase 2b2 - Trigger handling note
        # DB2 LUW does NOT support ALTER TRIGGER ... DISABLE/ENABLE (z/OS only).
        # db2move LOAD bypasses triggers entirely (uses LOAD utility, not INSERT),
        # so disabling triggers before LOAD is unnecessary.
        #########################################################
        Write-LogMessage "Phase 2b2: Skipped trigger disable — db2move LOAD bypasses triggers (DB2 LUW has no ALTER TRIGGER DISABLE)" -Level INFO

        #########################################################
        # Cross-instance: Phase 2c - Export data from source
        #########################################################
        $norwegianTableEntries = @()
        $norwegianMap = @()

        $exportDir = Join-Path $workFolder "db2move_export"
        if (-not (Test-Path $exportDir)) { New-Item -Path $exportDir -ItemType Directory -Force | Out-Null }

        if ($SkipExport) {
            $ixfCount = (Get-ChildItem -Path $exportDir -Filter "*.ixf" -ErrorAction SilentlyContinue).Count
            Write-LogMessage "Phase 2c: SKIPPED (-SkipExport). Using existing export data ($($ixfCount) IXF files in $($exportDir))" -Level INFO
            $exportStart = $null
            $exportEnd = $null

            $mapFile = Join-Path $workFolder "norwegian_table_rename_map.txt"
            if (Test-Path $mapFile) {
                $mapContent = [System.IO.File]::ReadAllLines($mapFile, [System.Text.Encoding]::GetEncoding(1252))
                foreach ($mapLine in $mapContent) {
                    if ($mapLine.StartsWith('#') -or [string]::IsNullOrWhiteSpace($mapLine)) { continue }
                    $parts = $mapLine -split '\|'
                    if ($parts.Count -ge 4) {
                        $norwegianMap += [PSCustomObject]@{
                            OriginalQuoted = "`"$($parts[0])`".`"$($parts[1])`""
                            Schema         = $parts[0]
                            OriginalTable  = $parts[1]
                            AsciiSafeTable = $parts[2]
                            AsciiSafeFile  = $parts[3]
                        }
                    }
                }
                if ($norwegianMap.Count -gt 0) {
                    Write-LogMessage "Phase 2c: Read existing Norwegian table mapping ($($norwegianMap.Count) entries)" -Level INFO
                }
            }
        }
        else {
            $oldFiles = Get-ChildItem -Path $exportDir -File -ErrorAction SilentlyContinue
            if ($oldFiles.Count -gt 0) {
                $oldSizeMB = [math]::Round(($oldFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 0)
                Write-LogMessage "Phase 2c: Cleaning old export data ($($oldFiles.Count) files, $($oldSizeMB) MB)" -Level INFO
                $oldFiles | Remove-Item -Force -ErrorAction SilentlyContinue
            }

            Write-LogMessage "Phase 2c: Exporting data from $($SourceDatabase)" -Level INFO
            Write-LogMessage "Export dir: $($exportDir)" -Level INFO

            # Build table list excluding:
            #   TYPE='N' (nicknames) — hang db2move when remote federated server is unreachable
            #   Known problematic tables — cause db2move to hang indefinitely (lock contention, LOBs, etc.)
            $skipTables = @(
                'DBM.D365_BUNTER',
                'DBM.VISMA_TRANSER_BCK25'
            )
            $schemaIn = ($Schemas -split ',' | ForEach-Object { "'$($_)'" }) -join ','
            $skipCondition = if ($skipTables.Count -gt 0) {
                $skipPairs = $skipTables | ForEach-Object { $s, $t = $_ -split '\.'; "('$($s)','$($t)')" }
                " AND (TABSCHEMA, TABNAME) NOT IN (VALUES $($skipPairs -join ','))"
            } else { "" }
            $tableListQuery = "SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) FROM SYSCAT.TABLES WHERE TABSCHEMA IN ($($schemaIn)) AND TYPE = 'T'$($skipCondition) ORDER BY TABSCHEMA, TABNAME"
            $tableListFile = Join-Path $workFolder "db2move_tablelist.txt"

            $listCommands = @()
            $listCommands += "set DB2INSTANCE=$($SourceInstance)"
            $listCommands += "db2 connect to $($SourceDatabase)"
            $listCommands += "db2 `"$($tableListQuery)`""
            $listCommands += "db2 connect reset"
            $listCommands += "db2 terminate"

            $listOutput = Invoke-Db2ContentAsScript -Content $listCommands -ExecutionType BAT `
                -FileName (Join-Path $workFolder "ListTables_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

            $tableNames = @()
            foreach ($line in ($listOutput -split "`n")) {
                $t = $line.Trim()
                # Regex: ^([A-Za-z][A-Za-z0-9_]*)\.([\w]+)$
                #   Match SCHEMA.TABLE format from query output
                if ($t -match '^([A-Za-z][A-Za-z0-9_]*)\.([\w]+)$') {
                    # db2move -tf requires "SCHEMA"."TABLE" format (quoted identifiers)
                    $tableNames += "`"$($matches[1])`".`"$($matches[2])`""
                }
            }

            #########################################################
            # Separate tables with Norwegian special characters (æ,ø,å,Æ,Ø,Å).
            # db2move EXPORT/LOAD fails with ERROR -3022 on these names.
            # They are handled individually via db2 EXPORT/IMPORT
            # with ANSI-1252 encoded BAT files and ASCII-safe IXF filenames.
            #########################################################
            # Regex: [æøåÆØÅ]  — match any single Norwegian special character
            $norwegianPattern = '[æøåÆØÅ]'
            $normalTableEntries = @()
            foreach ($tbl in $tableNames) {
                if ($tbl -match $norwegianPattern) {
                    $norwegianTableEntries += $tbl
                } else {
                    $normalTableEntries += $tbl
                }
            }

            if ($norwegianTableEntries.Count -gt 0) {
                Write-LogMessage "Phase 2c: Detected $($norwegianTableEntries.Count) tables with Norwegian characters — will be handled individually (not via db2move)" -Level INFO

                foreach ($entry in $norwegianTableEntries) {
                    # Regex: ^"([^"]+)"\."([^"]+)"$
                    #   Matches the "SCHEMA"."TABLE" quoted-identifier format used in db2move table lists
                    if ($entry -match '^"([^"]+)"\."([^"]+)"$') {
                        $origSchema = $matches[1]
                        $origTable = $matches[2]
                        # Case-sensitive replace: lowercase and uppercase Norwegian chars separately
                        $safeTable = $origTable -creplace 'æ', 'ae' -creplace 'ø', 'oe' -creplace 'å', 'aa' -creplace 'Æ', 'AE' -creplace 'Ø', 'OE' -creplace 'Å', 'AA'
                        $norwegianMap += [PSCustomObject]@{
                            OriginalQuoted = $entry
                            Schema         = $origSchema
                            OriginalTable  = $origTable
                            AsciiSafeTable = $safeTable
                            AsciiSafeFile  = "$($origSchema)_$($safeTable)"
                        }
                        Write-LogMessage "  Norwegian table: $($origSchema).$($origTable) -> file: $($origSchema)_$($safeTable).ixf" -Level INFO
                    }
                }

                $mapFile = Join-Path $workFolder "norwegian_table_rename_map.txt"
                $mapLines = @("# Norwegian Character Table Name Mapping (ANSI-1252)")
                $mapLines += "# Format: SCHEMA|ORIGINAL_TABLE|ASCII_SAFE_TABLE|ASCII_SAFE_FILE"
                $mapLines += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $mapLines += ""
                foreach ($m in $norwegianMap) {
                    $mapLines += "$($m.Schema)|$($m.OriginalTable)|$($m.AsciiSafeTable)|$($m.AsciiSafeFile)"
                }
                [System.IO.File]::WriteAllText($mapFile, ($mapLines -join "`r`n"), [System.Text.Encoding]::GetEncoding(1252))
                Write-LogMessage "Phase 2c: Norwegian table mapping file written: $($mapFile) ($($norwegianMap.Count) entries)" -Level INFO
            }
            else {
                Write-LogMessage "Phase 2c: No tables with Norwegian characters detected" -Level INFO
            }

            if ($normalTableEntries.Count -gt 0) {
                $normalTableEntries | Set-Content -Path $tableListFile -Encoding ASCII
                Write-LogMessage "Phase 2c: Table list created with $($normalTableEntries.Count) tables for db2move (nicknames excluded, $($norwegianTableEntries.Count) Norwegian-char tables separated, $($skipTables.Count) known problematic tables skipped: $($skipTables -join ', '))" -Level INFO

                $exportCommands = @()
                $exportCommands += "set DB2INSTANCE=$($SourceInstance)"
                $exportCommands += "cd /d `"$($exportDir)`""
                $exportCommands += "db2move $($SourceDatabase) EXPORT -tf `"$($tableListFile)`""
            }
            else {
                Write-LogMessage "Phase 2c: WARNING — Could not build table list, falling back to schema-based export" -Level WARN
                $exportCommands = @()
                $exportCommands += "set DB2INSTANCE=$($SourceInstance)"
                $exportCommands += "cd /d `"$($exportDir)`""
                $exportCommands += "db2move $($SourceDatabase) EXPORT -sn $($Schemas)"
            }

            $exportStart = Get-Date
            $output = Invoke-Db2ContentAsScript -Content $exportCommands -ExecutionType BAT `
                -FileName (Join-Path $workFolder "Db2moveExport_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors -UseNewConfigurations
            $exportEnd = Get-Date
            $outputLines = ($output -split "`n").Count
            Write-LogMessage "db2move EXPORT completed: $($outputLines) output lines, $([math]::Round(($exportEnd - $exportStart).TotalSeconds, 1))s" -Level INFO

            #########################################################
            # Cross-instance: Phase 2c-nor - Export Norwegian tables individually
            # Tables with æ,ø,å in their names cause db2move ERROR -3022.
            # These are exported individually using db2 EXPORT with
            # ANSI-1252 encoded BAT files and ASCII-safe IXF filenames.
            #########################################################
            if ($norwegianMap.Count -gt 0) {
                Write-LogMessage "Phase 2c-nor: Exporting $($norwegianMap.Count) Norwegian-character tables individually" -Level INFO

                $norExportCmds = @()
                $norExportCmds += "set DB2INSTANCE=$($SourceInstance)"
                $norExportCmds += "db2 connect to $($SourceDatabase)"
                foreach ($m in $norwegianMap) {
                    $ixfPath = Join-Path $exportDir "$($m.AsciiSafeFile).ixf"
                    $msgPath = Join-Path $exportDir "$($m.AsciiSafeFile).msg"
                    $norExportCmds += "db2 `"EXPORT TO '$($ixfPath)' OF IXF MESSAGES '$($msgPath)' SELECT * FROM $($m.Schema).$($m.OriginalTable)`""
                }
                $norExportCmds += "db2 connect reset"
                $norExportCmds += "db2 terminate"

                $norExportStart = Get-Date
                $norExportOutput = Invoke-Db2ContentAsScript -Content $norExportCmds -ExecutionType BAT `
                    -FileName (Join-Path $workFolder "NorwegianExport_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors -UseNewConfigurations
                $norExportEnd = Get-Date
                Write-LogMessage "Phase 2c-nor: Norwegian table export completed in $([math]::Round(($norExportEnd - $norExportStart).TotalSeconds, 1))s" -Level INFO
                Write-LogMessage "Phase 2c-nor output: $($norExportOutput)" -Level INFO
            }
        }

        # Parse per-table export stats from db2move output
        $tableStats = [ordered]@{}
        foreach ($line in ($output -split "`n")) {
            $t = $line.Trim()
            # Regex: EXPORT:\s+(\d+)\s+rows\s+from\s+table\s+"(\w+\s*)"\."(\w+\s*)"
            #   EXPORT:     - literal prefix from db2move
            #   (\d+)       - row count
            #   "(\w+\s*)"  - schema name (may have trailing spaces)
            #   "(\w+\s*)"  - table name (may have trailing spaces)
            if ($t -match 'EXPORT:\s+(\d+)\s+rows\s+from\s+table\s+"([^"]+)"\s*\.\s*"([^"]+)"') {
                $rows = [int]$matches[1]
                $schema = $matches[2].Trim()
                $table = $matches[3].Trim()
                $key = "$($schema).$($table)"
                $tableStats[$key] = [PSCustomObject]@{
                    Schema     = $schema
                    Table      = $table
                    ExportRows = $rows
                    ExportSec  = $null
                    LoadRows   = $null
                    LoadSec    = $null
                }
            }
        }

        # Get per-table export timing from IXF file timestamps (skip when -SkipExport)
        $ixfFiles = Get-ChildItem -Path $exportDir -Filter "*.ixf" -ErrorAction SilentlyContinue | Sort-Object CreationTime
        if ($ixfFiles.Count -gt 0 -and $null -ne $exportEnd) {
            $db2moveLst = Join-Path $exportDir "db2move.lst"
            $ixfToTable = @{}
            if (Test-Path $db2moveLst) {
                foreach ($lstLine in (Get-Content $db2moveLst)) {
                    $parts = $lstLine -split '!\s*'
                    if ($parts.Count -ge 3) {
                        $ixfName = $parts[0].Trim()
                        $tblSchema = $parts[1].Trim()
                        $tblName = $parts[2].Trim()
                        $ixfToTable[$ixfName] = "$($tblSchema).$($tblName)"
                    }
                }
            }

            for ($i = 0; $i -lt $ixfFiles.Count; $i++) {
                $fileStart = $ixfFiles[$i].CreationTime
                $fileEnd = if ($i -lt $ixfFiles.Count - 1) { $ixfFiles[$i + 1].CreationTime } else { $exportEnd }
                $durationSec = [math]::Round(($fileEnd - $fileStart).TotalSeconds, 1)

                $tblKey = $ixfToTable[$ixfFiles[$i].Name]
                if ($tblKey -and $tableStats.Contains($tblKey)) {
                    $tableStats[$tblKey].ExportSec = $durationSec
                }
            }
        }

        #########################################################
        # Cross-instance: Phase 2d - Load data into target
        #########################################################
        Write-LogMessage "Phase 2d: Loading data into $($TargetDatabase) on $($TargetInstance) (OS auth)" -Level INFO

        $loadCommands = @()
        $loadCommands += "set DB2INSTANCE=$($TargetInstance)"
        $loadCommands += "cd /d `"$($exportDir)`""
        $loadCommands += "db2move $($TargetDatabase) LOAD"

        $loadStart = Get-Date
        $output = Invoke-Db2ContentAsScript -Content $loadCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "Db2moveLoad_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors -UseNewConfigurations
        $loadEnd = Get-Date
        $loadOutputLines = ($output -split "`n").Count
        Write-LogMessage "db2move LOAD completed: $($loadOutputLines) output lines, $([math]::Round(($loadEnd - $loadStart).TotalSeconds, 1))s" -Level INFO

        # Parse per-table load stats from db2move output
        foreach ($line in ($output -split "`n")) {
            $t = $line.Trim()
            # Regex: LOAD:\s+(\d+)\s+rows\s+from\s+table\s+"(\w+\s*)"\."(\w+\s*)"
            if ($t -match 'LOAD:\s+(\d+)\s+rows\s+(from|into)\s+table\s+"([^"]+)"\s*\.\s*"([^"]+)"') {
                $rows = [int]$matches[1]
                $schema = $matches[3].Trim()
                $table = $matches[4].Trim()
                $key = "$($schema).$($table)"
                if ($tableStats.Contains($key)) {
                    $tableStats[$key].LoadRows = $rows
                }
                else {
                    $tableStats[$key] = [PSCustomObject]@{
                        Schema     = $schema
                        Table      = $table
                        ExportRows = $null
                        ExportSec  = $null
                        LoadRows   = $rows
                        LoadSec    = $null
                    }
                }
            }
        }

        #########################################################
        # Cross-instance: Phase 2d-nor - Import Norwegian tables individually
        # Uses db2 IMPORT (not LOAD) to avoid IXF codepage conversion
        # issues with Norwegian characters in table names.
        # IMPORT handles codepage more gracefully and does not
        # put tables into LOAD PENDING state.
        #########################################################
        if ($norwegianMap.Count -gt 0) {
            Write-LogMessage "Phase 2d-nor: Importing $($norwegianMap.Count) Norwegian-character tables individually" -Level INFO

            $norImportCmds = @()
            $norImportCmds += "set DB2INSTANCE=$($TargetInstance)"
            $norImportCmds += "db2 connect to $($TargetDatabase)"
            foreach ($m in $norwegianMap) {
                $ixfPath = Join-Path $exportDir "$($m.AsciiSafeFile).ixf"
                $msgPath = Join-Path $exportDir "$($m.AsciiSafeFile)_imp.msg"
                $norImportCmds += "db2 `"IMPORT FROM '$($ixfPath)' OF IXF MESSAGES '$($msgPath)' INSERT INTO $($m.Schema).$($m.OriginalTable)`""
            }
            $norImportCmds += "db2 connect reset"
            $norImportCmds += "db2 terminate"

            $norImportStart = Get-Date
            $norImportOutput = Invoke-Db2ContentAsScript -Content $norImportCmds -ExecutionType BAT `
                -FileName (Join-Path $workFolder "NorwegianImport_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors -UseNewConfigurations
            $norImportEnd = Get-Date
            Write-LogMessage "Phase 2d-nor: Norwegian table import completed in $([math]::Round(($norImportEnd - $norImportStart).TotalSeconds, 1))s" -Level INFO
            Write-LogMessage "Phase 2d-nor output: $($norImportOutput)" -Level INFO

            foreach ($m in $norwegianMap) {
                $key = "$($m.Schema).$($m.OriginalTable)"
                $msgPath = Join-Path $exportDir "$($m.AsciiSafeFile).msg"
                $impMsgPath = Join-Path $exportDir "$($m.AsciiSafeFile)_imp.msg"

                $exportedRows = 0
                if (Test-Path $msgPath) {
                    $msgContent = Get-Content $msgPath -Raw -ErrorAction SilentlyContinue
                    # Regex: Number of rows exported:\s*(\d+)
                    #   Standard db2 EXPORT completion message
                    if ($msgContent -match 'Number of rows exported:\s*(\d+)') {
                        $exportedRows = [int]$matches[1]
                    }
                }

                $importedRows = 0
                if (Test-Path $impMsgPath) {
                    $impContent = Get-Content $impMsgPath -Raw -ErrorAction SilentlyContinue
                    # Regex: Number of rows (committed|inserted):\s*(\d+)
                    #   db2 IMPORT completion message (may say "committed" or "inserted")
                    if ($impContent -match 'Number of rows (committed|inserted):\s*(\d+)') {
                        $importedRows = [int]$matches[2]
                    }
                }

                $tableStats[$key] = [PSCustomObject]@{
                    Schema     = $m.Schema
                    Table      = $m.OriginalTable
                    ExportRows = $exportedRows
                    ExportSec  = $null
                    LoadRows   = $importedRows
                    LoadSec    = $null
                }
                Write-LogMessage "  Norwegian table $($key): exported=$($exportedRows), imported=$($importedRows)" -Level INFO

                # Surface any SQL warning/error codes from the import msg file
                if (Test-Path $impMsgPath) {
                    $impContent = Get-Content $impMsgPath -Raw -ErrorAction SilentlyContinue
                    # Regex: SQL\d{4,5}[NW]  — matches DB2 SQL error/warning codes
                    $sqlMsgMatches = [regex]::Matches($impContent, 'SQL\d{4,5}[NW]')
                    foreach ($sqlMsg in $sqlMsgMatches) {
                        Write-LogMessage "  Norwegian import msg for $($key): $($sqlMsg.Value)" -Level INFO
                    }
                }
            }

            #########################################################
            # Generate ANSI-1252 encoded RENAME TABLE script
            # This script is NOT executed automatically. It serves as
            # documentation and a fallback mechanism: if direct IMPORT
            # into Norwegian-named tables fails, load into ASCII-safe
            # named tables and run this script to rename them back.
            #########################################################
            $renameScriptPath = Join-Path $workFolder "norwegian_table_rename.bat"
            $renameCmds = @()
            $renameCmds += "REM Norwegian Table Rename Script (ANSI-1252)"
            $renameCmds += "REM Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $renameCmds += "REM Renames ASCII-safe table names back to Norwegian originals."
            $renameCmds += "REM Use this if direct IMPORT into Norwegian-named tables fails."
            $renameCmds += ""
            $renameCmds += "set DB2INSTANCE=$($TargetInstance)"
            $renameCmds += "db2 connect to $($TargetDatabase)"
            foreach ($m in $norwegianMap) {
                $renameCmds += "db2 `"RENAME TABLE $($m.Schema).$($m.AsciiSafeTable) TO $($m.OriginalTable)`""
            }
            $renameCmds += "db2 connect reset"
            $renameCmds += "db2 terminate"
            [System.IO.File]::WriteAllText($renameScriptPath, ($renameCmds -join "`r`n"), [System.Text.Encoding]::GetEncoding(1252))
            Write-LogMessage "Phase 2d-nor: RENAME TABLE script generated (not executed): $($renameScriptPath)" -Level INFO
        }

        #########################################################
        # Log per-table statistics
        #########################################################
        $exportTotalSec = if ($null -ne $exportStart -and $null -ne $exportEnd) { [math]::Round(($exportEnd - $exportStart).TotalSeconds, 1) } else { 0 }
        $loadTotalSec = [math]::Round(($loadEnd - $loadStart).TotalSeconds, 1)
        $totalRows = ($tableStats.Values | Measure-Object -Property ExportRows -Sum).Sum

        Write-LogMessage "========== EXPORT/LOAD STATISTICS ==========" -Level INFO
        Write-LogMessage ("  {0,-30} {1,10} {2,10} {3,10}" -f "TABLE", "ROWS", "EXP(s)", "LOAD(s)") -Level INFO
        Write-LogMessage ("  {0,-30} {1,10} {2,10} {3,10}" -f ("-" * 30), ("-" * 10), ("-" * 10), ("-" * 10)) -Level INFO

        foreach ($key in $tableStats.Keys) {
            $s = $tableStats[$key]
            $expSec = if ($null -ne $s.ExportSec) { $s.ExportSec.ToString("F1") } else { "-" }
            $ldSec = if ($null -ne $s.LoadSec) { $s.LoadSec.ToString("F1") } else { "-" }
            $rowStr = if ($null -ne $s.ExportRows) { $s.ExportRows.ToString() } else { "-" }
            Write-LogMessage ("  {0,-30} {1,10} {2,10} {3,10}" -f $key, $rowStr, $expSec, $ldSec) -Level INFO
        }

        Write-LogMessage ("  {0,-30} {1,10} {2,10} {3,10}" -f ("-" * 30), ("-" * 10), ("-" * 10), ("-" * 10)) -Level INFO
        Write-LogMessage ("  {0,-30} {1,10} {2,10} {3,10}" -f "TOTAL", $totalRows, $exportTotalSec, $loadTotalSec) -Level INFO
        if ($norwegianMap.Count -gt 0) {
            $norExportTotal = ($tableStats.Values | Where-Object { $norwegianMap.AsciiSafeTable -contains $_.Table -or $norwegianMap.OriginalTable -contains $_.Table } | Measure-Object -Property ExportRows -Sum).Sum
            Write-LogMessage ("  Norwegian tables handled separately: {0} tables, {1} rows" -f $norwegianMap.Count, $norExportTotal) -Level INFO
        }
        Write-LogMessage "============================================" -Level INFO

        #########################################################
        # Cross-instance: Phase 2e - Clear LOAD PENDING state
        #########################################################
        Write-LogMessage "Phase 2e: Clearing LOAD PENDING / CHECK PENDING state for all user tables" -Level INFO

        $pendingQuery = "SELECT 'SET INTEGRITY FOR ' || RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) || ' IMMEDIATE CHECKED;' FROM SYSCAT.TABLES WHERE STATUS <> 'N' AND TYPE = 'T' AND TABSCHEMA NOT IN ('SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS')"

        $pendingCmds = @()
        $pendingCmds += "set DB2INSTANCE=$($TargetInstance)"
        $pendingCmds += "db2 connect to $($TargetDatabase)"
        $pendingCmds += "db2 `"$($pendingQuery)`""
        $pendingCmds += "db2 connect reset"
        $pendingCmds += "db2 terminate"

        $pendingOutput = Invoke-Db2ContentAsScript -Content $pendingCmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "FindPending_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "Pending tables query output: $($pendingOutput)" -Level INFO

        $setIntegrityStmts = @()
        $pendingLines = $pendingOutput -split "`n"
        foreach ($line in $pendingLines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^SET INTEGRITY FOR\s+') {
                $setIntegrityStmts += $trimmed
            }
        }

        if ($setIntegrityStmts.Count -gt 0) {
            Write-LogMessage "Found $($setIntegrityStmts.Count) tables in pending state, running SET INTEGRITY" -Level INFO

            $integrityCmds = @()
            $integrityCmds += "set DB2INSTANCE=$($TargetInstance)"
            $integrityCmds += "db2 connect to $($TargetDatabase)"
            foreach ($stmt in $setIntegrityStmts) {
                $cleanStmt = $stmt.TrimEnd(';')
                $integrityCmds += "db2 `"$($cleanStmt)`""
            }
            $integrityCmds += "db2 commit work"
            $integrityCmds += "db2 connect reset"
            $integrityCmds += "db2 terminate"

            $output = Invoke-Db2ContentAsScript -Content $integrityCmds -ExecutionType BAT `
                -FileName (Join-Path $workFolder "SetIntegrity_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
            Write-LogMessage "SET INTEGRITY output: $($output)" -Level INFO
        }
        else {
            Write-LogMessage "No tables in pending state" -Level INFO
        }

        #########################################################
        # Cross-instance: Phase 2f - Fix triggers with alias.*
        #   column expansion mismatches (SQL0117N)
        #   When a table gains columns after a trigger was created,
        #   the compiled trigger still uses the old expansion, but
        #   db2look outputs the raw text with alias.* which expands
        #   to the CURRENT column count causing SQL0117N on recreate.
        #########################################################
        Write-LogMessage "Phase 2f: Checking for missing triggers and fixing column expansion" -Level INFO

        $excludeSch = "'SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS'"
        $trigQuery = "SELECT RTRIM(TRIGSCHEMA) || '.' || RTRIM(TRIGNAME) FROM SYSCAT.TRIGGERS WHERE TRIGSCHEMA NOT IN ($($excludeSch)) ORDER BY TRIGSCHEMA, TRIGNAME"

        $srcTrigCmds = @("set DB2INSTANCE=$($SourceInstance)", "db2 connect to $($SourceDatabase)", "db2 `"$($trigQuery)`"", "db2 connect reset", "db2 terminate")
        $srcTrigOut = Invoke-Db2ContentAsScript -Content $srcTrigCmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "SrcTrigList_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

        $tgtTrigCmds = @("set DB2INSTANCE=$($TargetInstance)", "db2 connect to $($TargetDatabase)", "db2 `"$($trigQuery)`"", "db2 connect reset", "db2 terminate")
        $tgtTrigOut = Invoke-Db2ContentAsScript -Content $tgtTrigCmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "TgtTrigList_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

        function Parse-DbList {
            param([string]$Output)
            $items = @()
            $inData = $false
            foreach ($line in ($Output -split "`n")) {
                $t = $line.Trim()
                if ($t -match '^\d+\s+(post|record)') { $inData = $false; continue }
                if ($t -match '^[A-Z]:\\.*>') { $inData = $false; continue }
                if ($t -match '^-{4,}') { $inData = $true; continue }
                if ($inData -and -not [string]::IsNullOrWhiteSpace($t)) { $items += $t }
            }
            return $items
        }

        $srcTrigs = Parse-DbList -Output $srcTrigOut
        $tgtTrigs = Parse-DbList -Output $tgtTrigOut
        $tgtSet = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($t in $tgtTrigs) { [void]$tgtSet.Add($t) }
        $missingTrigs = @($srcTrigs | Where-Object { -not $tgtSet.Contains($_) })

        if ($missingTrigs.Count -gt 0) {
            Write-LogMessage "Found $($missingTrigs.Count) missing triggers, attempting to fix" -Level INFO

            # Extract trigger DDL from the cleaned DDL file we already created
            $ddlContent = [System.IO.File]::ReadAllText($cleanedDdlFile, $win1252)
            $ddlStatements = $ddlContent -split '@'

            foreach ($trigName in $missingTrigs) {
                Write-LogMessage "  Fixing trigger: $($trigName)" -Level INFO
                $parts = $trigName -split '\.'
                $trigSchema = $parts[0]
                $trigNameOnly = $parts[1]

                # Find this trigger's CREATE statement in the cleaned DDL
                $trigStmt = $null
                foreach ($stmt in $ddlStatements) {
                    $trimStmt = $stmt.Trim()
                    # Regex: match CREATE TRIGGER with schema.name
                    #  (?si)             - case-insensitive, dot-matches-newline
                    #  CREATE\s+TRIGGER  - literal CREATE TRIGGER
                    #  \s+               - whitespace
                    #  <schema>\.<name>  - qualified trigger name
                    if ($trimStmt -match "(?si)CREATE\s+TRIGGER\s+$($trigSchema)\.$($trigNameOnly)\b") {
                        $trigStmt = $trimStmt
                        break
                    }
                }

                if ([string]::IsNullOrWhiteSpace($trigStmt)) {
                    Write-LogMessage "    Trigger DDL not found in cleaned DDL file, skipping" -Level WARN
                    continue
                }

                # Find the INSERT INTO target table
                if ($trigStmt -notmatch 'INSERT\s+INTO\s+(\w+)\.(\w+)') {
                    Write-LogMessage "    No INSERT INTO pattern in trigger body, skipping" -Level WARN
                    continue
                }
                $insertSchema = $matches[1]
                $insertTable = $matches[2]
                Write-LogMessage "    INSERT target: $($insertSchema).$($insertTable)" -Level INFO

                # Find the alias.* pattern (e.g. G.*, K.*, N.*)
                # Regex: (\w)\.\* matches single-char alias followed by literal .*
                if ($trigStmt -notmatch '(\w)\.\*') {
                    Write-LogMessage "    No alias.* pattern found, skipping" -Level WARN
                    continue
                }
                $alias = $matches[1]

                # Get INSERT target table column names (skip first 2 log columns: COLNO 0,1)
                $colQuery = "SELECT RTRIM(COLNAME) FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '$($insertSchema)' AND TABNAME = '$($insertTable)' AND COLNO >= 2 ORDER BY COLNO"
                $colCmds = @("set DB2INSTANCE=$($TargetInstance)", "db2 connect to $($TargetDatabase)", "db2 `"$($colQuery)`"", "db2 connect reset", "db2 terminate")
                $colOut = Invoke-Db2ContentAsScript -Content $colCmds -ExecutionType BAT `
                    -FileName (Join-Path $workFolder "TrigCols_$($trigNameOnly)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

                $dataCols = Parse-DbList -Output $colOut
                if ($dataCols.Count -eq 0) {
                    Write-LogMessage "    Could not get target table columns, skipping" -Level WARN
                    continue
                }

                Write-LogMessage "    Target data columns ($($dataCols.Count)): $($dataCols -join ', ')" -Level INFO
                $explicitCols = ($dataCols | ForEach-Object { "$($alias).$_" }) -join ', '
                $pattern = [regex]::Escape("$($alias).*")
                $fixedStmt = $trigStmt -replace $pattern, $explicitCols
                Write-LogMessage "    Replaced $($alias).* with $($dataCols.Count) explicit columns" -Level INFO

                # Write fixed DDL and apply to target
                $trigDdlFile = Join-Path $workFolder "FixTrigger_$($trigNameOnly)_$(Get-Date -Format 'yyyyMMddHHmmssfff').sql"
                [System.IO.File]::WriteAllText($trigDdlFile, $fixedStmt + "`n@`n", $win1252)

                $createCmds = @("set DB2INSTANCE=$($TargetInstance)", "db2 connect to $($TargetDatabase)")
                $createCmds += "db2 -td@ -vf `"$($trigDdlFile)`""
                $createCmds += "db2 connect reset"
                $createCmds += "db2 terminate"

                $createOut = Invoke-Db2ContentAsScript -Content $createCmds -ExecutionType BAT `
                    -FileName (Join-Path $workFolder "CreateFixedTrig_$($trigNameOnly)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
                Write-LogMessage "    Create fixed trigger result: $($createOut)" -Level INFO
            }
        }
        else {
            Write-LogMessage "All triggers present, no fixup needed" -Level INFO
        }
    }
    else {
        #########################################################
        # Same-instance: Phase 2 - db2move COPY
        #########################################################
        Write-LogMessage "Phase 2: Running db2move COPY" -Level INFO

        $db2moveCommand = "db2move $($SourceDatabase) COPY -sn $($Schemas) -co TARGET_DB $($TargetDatabase) MODE DDL_AND_LOAD TABLESPACE_MAP `"(SYS_ANY)`""

        $copyCommands = @()
        $copyCommands += "set DB2INSTANCE=$($SourceInstance)"
        $copyCommands += $db2moveCommand

        $output = Invoke-Db2ContentAsScript -Content $copyCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "Db2moveCopy_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "db2move COPY output: $($output)" -Level INFO
    }

    #########################################################
    # Phase 3: Validate by comparing table counts
    #########################################################
    Write-LogMessage "Phase 3: Validating table counts" -Level INFO

    $validateCommands = @()
    $validateCommands += "set DB2INSTANCE=$($SourceInstance)"
    $validateCommands += "db2 connect to $($SourceDatabase)"
    $validateCommands += "db2 `"SELECT COUNT(*) AS SOURCE_TABLES FROM SYSCAT.TABLES WHERE TYPE = 'T' AND TABSCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC', 'SYSTOOLS')`""
    $validateCommands += "db2 connect reset"
    $validateCommands += "db2 terminate"
    $validateCommands += "set DB2INSTANCE=$($TargetInstance)"
    $validateCommands += "db2 connect to $($TargetDatabase)"
    $validateCommands += "db2 `"SELECT COUNT(*) AS TARGET_TABLES FROM SYSCAT.TABLES WHERE TYPE = 'T' AND TABSCHEMA NOT IN ('SYSIBM', 'SYSCAT', 'SYSFUN', 'SYSSTAT', 'NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSIBMTS', 'SYSPUBLIC', 'SYSTOOLS')`""
    $validateCommands += "db2 connect reset"
    $validateCommands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $validateCommands -ExecutionType BAT `
        -FileName (Join-Path $workFolder "ValidateCopy_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Validation output: $($output)" -Level INFO

    #########################################################
    # Phase 4: Trigger state note
    # DB2 LUW does NOT support ALTER TRIGGER ... ENABLE (z/OS only).
    # Triggers created via DDL in Phase 2b are already active.
    # LOAD (Phase 2d) does not fire triggers, so no state change needed.
    #########################################################
    Write-LogMessage "Phase 4: Skipped trigger enable — triggers are already active from DDL creation (DB2 LUW has no ALTER TRIGGER ENABLE)" -Level INFO

    #########################################################
    # Phase 5: Control SQL verification
    #########################################################
    $ctlWorkObj = Get-DefaultWorkObjects -DatabaseType PrimaryDb -DatabaseName $SourceDatabase -QuickMode -SkipDb2StateInfo
    if ($ctlWorkObj -is [array]) { $ctlWorkObj = $ctlWorkObj[-1] }
    $ctlWorkObj = Get-ControlSqlStatement -WorkObject $ctlWorkObj -SelectCount -ForceGetControlSqlStatement
    if ($ctlWorkObj -is [array]) { $ctlWorkObj = $ctlWorkObj[-1] }
    $controlTable = $ctlWorkObj.TableToCheck

    if (-not [string]::IsNullOrEmpty($controlTable)) {
        Write-LogMessage "Phase 5: Running control SQL on $($TargetDatabase) - SELECT COUNT(*) FROM $($controlTable)" -Level INFO

        $controlCmds = @("set DB2INSTANCE=$($TargetInstance)", "db2 connect to $($TargetDatabase)")
        $controlCmds += "db2 `"SELECT COUNT(*) FROM $($controlTable)`""
        $controlCmds += "db2 connect reset"
        $controlCmds += "db2 terminate"

        $controlOut = Invoke-Db2ContentAsScript -Content $controlCmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "ControlSql_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "Control SQL output: $($controlOut)" -Level INFO

        # Regex: match row count from Norwegian DB2 output "N post(er) er valgt."
        #   (\d+)           - capture the count
        #   \s+post         - literal " post"
        #   (\(er\))?       - optional "(er)" for plural
        #   \s+er\s+valgt   - literal " er valgt"
        if ($controlOut -match '(\d+)\s+post(\(er\))?\s+er\s+valgt') {
            $rowCount = [int]$matches[1]
            Write-LogMessage "Control SQL: $($rowCount) rows returned from $($controlTable)" -Level INFO
            if ($rowCount -eq 0) {
                throw "Control SQL FAILED: 0 rows returned from $($controlTable) on $($TargetDatabase). Data conversion may have failed."
            }
        }
        else {
            Write-LogMessage "Control SQL: Could not parse row count from output - verify manually" -Level WARN
        }
    }
    else {
        Write-LogMessage "Phase 5: No control table from Get-ControlSqlStatement, skipping control SQL" -Level WARN
    }

    Write-LogMessage "Step 2 COMPLETED: $($schemaCount) schemas copied from $($SourceDatabase) to $($TargetDatabase)" -Level INFO
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
