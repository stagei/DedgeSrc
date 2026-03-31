<#
.SYNOPSIS
  Comprehensive COBOL dependency analysis pipeline.
  Reads a seed program list (all.json), discovers the full dependency chain
  using local source files, RAG semantic search, and DB2 catalog queries.

.DESCRIPTION
  Single reusable script that combines all analysis phases:

    Phase 1 — Load seed programs from all.json and index local source tree
    Phase 2 — Extract dependencies for seed programs (local source first, RAG fallback)
    Phase 3 — Iteratively discover new programs via CALL targets
    Phase 4 — Validate SQL tables against DB2 system catalog
    Phase 5 — Discover additional programs via shared SQL tables (RAG)
    Phase 6 — Extract dependencies for table-discovered programs
    Phase 7 — Source verification and classification
    Phase 8 — Produce all cross-reference output JSONs

  Data sources (priority order):
    1. Direct source files   — actual .CBL/.CPY/.CPB/.DCL from local repository
    2. RAG semantic search   — HTTP REST API for code snippet retrieval
    3. DB2 ODBC              — system catalog queries for table validation

  Built-in U/V fuzzy matching for OCR artefacts in program names.

.PARAMETER AllJsonPath
  Path to the seed program list JSON file.

.PARAMETER SourceRoot
  Root folder of the Visual COBOL source tree.
  Correct versions are expected in cbl/cpy subfolders; *_uncertain folders are
  treated as fallback sources where basename contains program name.

.PARAMETER OutputDir
  Directory for all output files.

.PARAMETER RagUrl
  RAG REST API endpoint URL.

.PARAMETER Db2Dsn
  ODBC DSN name for DB2 connection (table validation). Empty to skip.
  Default: BASISTST (maps to FKMTST server).

.PARAMETER DefaultFilePath
  Default path for COBOL file I/O when no ASSIGN path is specified.

.PARAMETER MaxCallIterations
  Maximum CALL-target expansion iterations.

.PARAMETER RagResults
  Number of results per RAG query.

.PARAMETER ExcludeJsonPath
  Path to an exclusion-candidate JSON file. Programs matching the rules are
  tagged as exclusion candidates in output JSONs but NOT removed from processing.
  Empty string = no candidate tagging.

.PARAMETER CobdokCsvPath
  Path to modul.csv from COBDOK DB2 export. Used to enrich programs with
  system/delsystem metadata and tag deprecated programs (system = UTGATT).
  Default looks in the AutoDocJson cache folder.

.PARAMETER OllamaUrl
  Ollama API endpoint for resolving variable-based filenames in COBOL programs.
  Default: http://localhost:11434

.PARAMETER OllamaModel
  Ollama model for variable filename resolution. Default: qwen2.5:7b

.PARAMETER SkipPhases
  Array of phase numbers to skip (e.g. 4 to skip DB2 validation).

.EXAMPLE
  pwsh.exe -File Scripts\Invoke-FullAnalysis.ps1
  pwsh.exe -File Scripts\Invoke-FullAnalysis.ps1 -AllJsonPath .\my_programs.json
  pwsh.exe -File Scripts\Invoke-FullAnalysis.ps1 -ExcludeJsonPath .\exclude.json
  pwsh.exe -File Scripts\Invoke-FullAnalysis.ps1 -Db2Dsn '' -MaxCallIterations 3
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [string]$AllJsonPath     = (Join-Path (Split-Path $PSScriptRoot -Parent) 'all.json'),
    [string]$SourceRoot      = 'C:\opt\data\VisualCobol\Sources',
    [string]$OutputDir       = (Split-Path $PSScriptRoot -Parent),
    [string]$RagUrl          = 'http://dedge-server:8486/query',
    [string]$Db2Dsn          = 'BASISTST',
    [string]$DefaultFilePath = 'N:\COBNT',
    [int]$MaxCallIterations  = 5,
    [int]$RagResults         = 8,
    [int]$RagTableResults    = 5,
    [string]$ExcludeJsonPath = '',
    [string]$CobdokCsvPath   = 'C:\opt\data\AutoDocJson\tmp\cobdok\modul.csv',
    [string]$OllamaUrl       = 'http://localhost:11434',
    [string]$OllamaModel     = 'qwen2.5:7b',
    [string]$VisualCobolRagUrl = 'http://dedge-server:8485',
    [string]$AnalysisAlias   = '',
    [string]$AnalysisDataRoot = '',
    [string]$AutoDocJsonPath = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDocJson',
    [string]$AnalysisCommonPath = '',
    [switch]$SkipClassification,
    [int[]]$SkipPhases       = @()
)

$ErrorActionPreference = 'Stop'
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$reportHelperPath = Join-Path $PSScriptRoot 'Common-JsonReport.ps1'
if (Test-Path -LiteralPath $reportHelperPath) {
    . $reportHelperPath
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RUN FOLDER — alias + timestamp output                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$allJsonRaw = Get-Content -LiteralPath $AllJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$distinctAreas = @($allJsonRaw.entries | ForEach-Object { $_.area } | Where-Object { $_ } | Sort-Object -Unique)
$areasSuffix = ($distinctAreas -join '_') -replace '[^A-Za-z0-9_]', ''
if ([string]::IsNullOrWhiteSpace($areasSuffix)) {
    $areasSuffix = 'General'
}

if ([string]::IsNullOrWhiteSpace($AnalysisAlias)) {
    $AnalysisAlias = $areasSuffix
}
$aliasSafe = (($AnalysisAlias -replace '[^A-Za-z0-9_-]', '_').Trim('_'))
if ([string]::IsNullOrWhiteSpace($aliasSafe)) {
    $aliasSafe = "Analysis_$($areasSuffix)"
}

$excludeData = $null
if ($ExcludeJsonPath -and (Test-Path -LiteralPath $ExcludeJsonPath)) {
    $excludeData = Get-Content -LiteralPath $ExcludeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$dataRoot = if ($AnalysisDataRoot) { $AnalysisDataRoot } else { $OutputDir }
New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null

$runFolderName = "$($aliasSafe)_$timestamp"
$AliasDir = Join-Path $dataRoot $aliasSafe
$HistoryDir = Join-Path $AliasDir '_History'
$RunDir = Join-Path $HistoryDir $runFolderName
$AnalysesIndexPath = Join-Path $dataRoot 'analyses.json'
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Write-Output "Run folder: $RunDir"
Write-Output "Alias folder (latest): $AliasDir"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  OUTPUT FILE PATHS                                                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
$MasterJson        = Join-Path $RunDir 'dependency_master.json'
$TotalProgsJson    = Join-Path $RunDir 'all_total_programs.json'
$SqlTablesJson     = Join-Path $RunDir 'all_sql_tables.json'
$CopyElementsJson  = Join-Path $RunDir 'all_copy_elements.json'
$CallGraphJson     = Join-Path $RunDir 'all_call_graph.json'
$FileIOJson        = Join-Path $RunDir 'all_file_io.json'
$VerifyJson        = Join-Path $RunDir 'source_verification.json'
$Db2ValidationJson = Join-Path $RunDir 'db2_table_validation.json'
$AppliedExclJson   = Join-Path $RunDir 'applied_exclusions.json'
$StdCobolJson      = Join-Path $RunDir 'standard_cobol_filtered.json'
$RunSummaryMd      = Join-Path $RunDir 'run_summary.md'

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  CANDIDATE TAGGING SETUP                                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
$candidatePrograms = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$excludeTableRules = @()
$uncertainFiles = [System.Collections.ArrayList]::new()

if ($excludeData) {
    Write-Output "Candidate config: $($excludeData.title)"

    if ($excludeData.excludePrograms) {
        foreach ($ep in $excludeData.excludePrograms) {
            if ($ep.program) { [void]$candidatePrograms.Add($ep.program.ToUpperInvariant()) }
        }
        Write-Output "  Explicit candidate programs: $($candidatePrograms.get_Count())"
    }

    if ($excludeData.excludeTables) {
        $excludeTableRules = @($excludeData.excludeTables)
        Write-Output "  Table-based candidate rules: $($excludeTableRules.Count) (resolved after extraction)"
    }

    Copy-Item -LiteralPath $ExcludeJsonPath -Destination (Join-Path $RunDir 'exclude.json') -Force
}

Copy-Item -LiteralPath $AllJsonPath -Destination (Join-Path $RunDir 'all.json') -Force

# ── Copy all.json into config/allJson_<areas>/ ──
$configDir = Join-Path $RunDir 'config'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$allJsonAreaDir = Join-Path $configDir "allJson_$($areasSuffix)"
New-Item -ItemType Directory -Path $allJsonAreaDir -Force | Out-Null
Copy-Item -LiteralPath $AllJsonPath -Destination (Join-Path $allJsonAreaDir 'all.json') -Force
Write-Output "  all.json copied to: $allJsonAreaDir"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  COBDOK ENRICHMENT — load modul.csv for system/deprecated metadata          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
$cobdokIndex = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
if ($CobdokCsvPath -and (Test-Path -LiteralPath $CobdokCsvPath)) {
    Write-Output "Loading COBDOK modul.csv: $CobdokCsvPath"
    $csvHeaders = @('cobdokSystem','delsystem','modul','tekst','modultype','benytter_sql','benytter_ds','fra_dato','fra_kl','antall_linjer','lengde','filenavn')
    $csvRows = Import-Csv -LiteralPath $CobdokCsvPath -Delimiter ';' -Header $csvHeaders
    foreach ($row in $csvRows) {
        $key = $row.modul.Trim().ToUpperInvariant()
        if (-not $cobdokIndex.ContainsKey($key)) {
            $cobdokIndex[$key] = [ordered]@{
                cobdokSystem = $row.cobdokSystem.Trim()
                delsystem    = $row.delsystem.Trim()
                description  = $row.tekst.Trim()
                modultype    = $row.modultype.Trim()
                isDeprecated = ($row.cobdokSystem.Trim() -eq 'UTGATT')
            }
        }
    }
    $deprecatedCount = @($cobdokIndex.Values | Where-Object { $_['isDeprecated'] }).Count
    Write-Output "  Loaded: $($cobdokIndex.Count) modules ($deprecatedCount deprecated/UTGATT)"
} else {
    Write-Output "COBDOK modul.csv not found — skipping enrichment"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  REGEX PATTERNS                                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

#  COPY copybook-name.
$CopyPattern = [regex]::new(
    '\bCOPY\s+[''"]?([A-Z0-9_\-\\.]+)[''"]?\s*\.?',
    'IgnoreCase'
)

# ┌─────────────────────────────────────────────────────────────────────────┐
# │  CALL 'program-name' or CALL "program-name"                           │
# │                                                                       │
# │  (?<![A-Za-z0-9\-])  — negative lookbehind: CALL must NOT be         │
# │                        preceded by a letter, digit, or hyphen.        │
# │                        Prevents matching W-CALL, I-CALL etc.          │
# │  CALL\s+             — the CALL keyword followed by whitespace       │
# │  [''"]?              — optional opening quote (single or double)     │
# │  ([A-Z0-9_\-]+)      — capture group 1: program name                │
# │  [''"]?              — optional closing quote                        │
# │  (?:\s|$)            — whitespace or end-of-string after name        │
# └─────────────────────────────────────────────────────────────────────────┘
$CallPattern = [regex]::new(
    '(?<![A-Za-z0-9\-])CALL\s+[''"]?([A-Z0-9_\-]+)[''"]?(?:\s|$)',
    'IgnoreCase'
)

#  EXEC SQL ... END-EXEC (multiline)
$SqlBlockPattern = [regex]::new(
    'EXEC\s+SQL\s+(.+?)END-EXEC',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

#  SQL table reference: keyword [schema.]table
$SqlTablePattern = [regex]::new(
    '\b(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE\s+INTO|FROM|JOIN|INTO|TABLE|INCLUDE)\s+(?:(\w+)\.)?(\w+)',
    'IgnoreCase'
)

#  SELECT [OPTIONAL] logical ASSIGN [TO] "literal"|variable
$SelectAssignPattern = [regex]::new(
    '\bSELECT\s+(?:OPTIONAL\s+)?(\w[\w-]*)\s+ASSIGN\s+(?:TO\s+)?(?:"([^"]+)"|''([^'']+)''|(\w[\w-]*))',
    'IgnoreCase'
)

# ┌─────────────────────────────────────────────────────────────────────────┐
# │  OPEN INPUT|OUTPUT|I-O|EXTEND file1 [file2 ...]                       │
# │  \b              — word boundary                                      │
# │  OPEN\s+         — keyword                                            │
# │  (INPUT|…|EXTEND)— capture group 1: access mode                       │
# │  \s+             — whitespace separator                               │
# │  (               — capture group 2: file names on same line only      │
# │    [\w][\w-]*    — first file identifier (word chars, hyphens)        │
# │    (?:           — non-capturing group for additional files            │
# │      [ \t]+      — horizontal whitespace only (no newlines)           │
# │      [\w][\w-]*  — another file identifier                            │
# │    )*            — zero or more additional files                       │
# │  )                                                                    │
# └─────────────────────────────────────────────────────────────────────────┘
$OpenPattern = [regex]::new(
    '\bOPEN\s+(INPUT|OUTPUT|I-O|EXTEND)\s+([\w][\w-]*(?:[ \t]+[\w][\w-]*)*)',
    'IgnoreCase'
)

#  RAG source metadata: (source: PROGRAM.CBL.md)
$RagSourcePattern = [regex]::new('\(source:\s*([A-Z0-9_]+)\.CBL', 'IgnoreCase')

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  EXCLUSION / NOISE SETS                                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$CallExcludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
  # COBOL verbs / reserved words
  'IF','MOVE','ADD','SUBTRACT','MULTIPLY','DIVIDE','COMPUTE','PERFORM','EXIT',
  'EVALUATE','WHEN','OTHER','END','GO','TO','GOBACK','STOP','RUN',
  'ACCEPT','DISPL','DISPL1','DISPL2','INSPECT','EXEC','END-IF','ERROR',
  'STREAM','LINEOUT','PREP_SQL','CALL','DISPLAY','PIC','PAYD','OG','TIL',
  'INS','IS','---','AVSLUTT','SLUTT','SYSFILETREE','SYSLOADFUNCS','SYSSLEEP',
  'RXFUNCADD','START_REXX','DIALOG-SYSTEM','INVOKE-MESSAGE-BOX',
  'ENABLE-OBJECT','DISABLE-OBJECT','REFRESH-OBJECT',
  'REPLACING','COPY','USING','RETURNING','GIVING','ALSO','THRU','THROUGH',
  'VARYING','UNTIL','THE','FROM','UPON','VALUE','SIZE','LENGTH','STRING',
  'UNSTRING','INITIALIZE','RELEASE','RETURN','OPEN','CLOSE','READ','WRITE',
  'REWRITE','DELETE','START','SORT','MERGE','GENERATE','SECTION','PARAGRAPH',
  'CONTINUE',
  # SQL keywords that leak through when CALL appears in SQL context
  'INTO','VALUES','LEFT','RIGHT','INNER','OUTER','CROSS','ORDER','GROUP',
  'HAVING','DISTINCT','WHERE','SELECT','INSERT','UPDATE','DELETE','TABLE',
  'BETWEEN','LIKE','EXISTS','CASE','THEN','ELSE','UNION','EXCEPT',
  'INTERSECT','FETCH','FIRST','ONLY','ROWS','NEXT','PRIOR','CURSOR',
  'DECLARE','END-EXEC','COMMIT','ROLLBACK','CONNECT','DISCONNECT',
  'SET','NULL','NOT','AND','ALL','ANY','ASC','DESC',
  # Micro Focus / Visual COBOL call conventions and runtime aliases
  'DB2API','COBAPI','NETAPI','CBLJAPI','CBLAPI','CICS','CICSAPI'
) | ForEach-Object { [void]$CallExcludeSet.Add($_) }

$SqlNotTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('SQLCA','SQLDA','SECTION','SQL','EXEC','END','WHERE','SET','VALUES','INTO','AND',
  'OR','NOT','NULL','IS','AS','ON','BY','ORDER','GROUP','HAVING','DISTINCT',
  'ALL','ANY','BETWEEN','LIKE','IN','EXISTS','CASE','WHEN','THEN','ELSE',
  'BEGIN','COMMIT','ROLLBACK','DECLARE','CURSOR','OPEN','CLOSE','FETCH','NEXT',
  'FOR','READONLY','READ','ONLY','WITH','HOLD','LOCK','ROW','ROWS','FIRST','LAST',
  'CURRENT','OF','TIMESTAMP','DATE','TIME','INTEGER','SMALLINT','CHAR','VARCHAR',
  'DECIMAL','NUMERIC','FLOAT','DOUBLE','BLOB','CLOB','DBCLOB','GRAPHIC',
  'VARGRAPHIC','BIGINT','REAL','BINARY','VARBINARY','BOOLEAN','XML',
  'GLOBAL','TEMPORARY','SEQUENCE','INDEX','VIEW','PROCEDURE','FUNCTION','TRIGGER',
  'INNER','OUTER','LEFT','RIGHT','FULL','CROSS','NATURAL','UNION','EXCEPT','INTERSECT',
  'ASC','DESC','LIMIT','OFFSET','TOP','COUNT','SUM','AVG','MIN','MAX','COALESCE',
  'CAST','TRIM','UPPER','LOWER','SUBSTRING','LENGTH','REPLACE','POSITION',
  'EXTRACT','YEAR','MONTH','DAY','HOUR','MINUTE','SECOND','MICROSECOND',
  'ISOLATION','LEVEL','REPEATABLE','SERIALIZABLE','UNCOMMITTED','COMMITTED',
  'WORK','SAVEPOINT','RELEASE','TO','DATA','EXTERNAL','INPUT','OUTPUT') |
    ForEach-Object { [void]$SqlNotTables.Add($_) }

$SkipLogicalFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('SQLCA','SQLDA','SQLENV','SQL','SECTION','DIVISION','FILLER',
  'WORKING','STORAGE','LINKAGE','FILE','DATA','PROCEDURE',
  'PROGRAM','IDENTIFICATION','CONFIGURATION','SPECIAL',
  'WRITE','READ','CLOSE','OPEN','MOVE','ADD','SUBTRACT','MULTIPLY','DIVIDE',
  'COMPUTE','PERFORM','EXIT','EVALUATE','WHEN','OTHER','END','GO','GOBACK',
  'STOP','RUN','ACCEPT','DISPLAY','INSPECT','EXEC','IF','ELSE','END-IF',
  'END-READ','END-WRITE','END-PERFORM','END-EVALUATE','END-CALL','END-STRING',
  'END-UNSTRING','END-COMPUTE','END-START','END-SEARCH','END-RETURN','END-INVOKE',
  'THEN','NOT','AND','OR','ALSO','THRU','THROUGH','GIVING','REMAINDER',
  'USING','BY','FROM','INTO','TO','ON','OF','IN','AT','WITH','UNTIL','VARYING',
  'AFTER','BEFORE','ALL','ZERO','ZEROS','ZEROES','SPACE','SPACES','QUOTE','QUOTES',
  'HIGH-VALUE','HIGH-VALUES','LOW-VALUE','LOW-VALUES','TRUE','FALSE',
  'CORRESPONDING','CORR','INITIALIZE','SET','STRING','UNSTRING','SEARCH',
  'SORT','MERGE','RETURN','RELEASE','CONTINUE','NEXT','SENTENCE','CALL',
  'UPON','ADVANCING','LINE','LINES','PAGE','COLUMN','COL','PIC','PICTURE',
  'VALUE','VALUES','REDEFINES','OCCURS','TIMES','DEPENDING','INDEXED',
  'ASCENDING','DESCENDING','KEY','RECORD','RECORDS','CONTAINS','CHARACTERS',
  'BLOCK','LABEL','STANDARD','OMITTED','STATUS','REPLACE','REPLACING',
  'LEADING','TRAILING','FIRST','INITIAL','REFERENCE','CONTENT','LENGTH',
  'DELIMITED','SIZE','DELIMITER','COUNT','POINTER','TALLYING',
  'CONVERTING','INPUT-OUTPUT','ENVIRONMENT','FILE-CONTROL','I-O-CONTROL',
  'FD','SD','COPY','INCLUDE',
  'SQLCODE','WHENEVER','SQLERROR') |
    ForEach-Object { [void]$SkipLogicalFiles.Add($_) }

$NoisePrograms = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('---','CALL','PIC','OG','CC1','PAYD','DISPLAY','DISPL1','DISPL2','SLUTT','AVSLUTT','INS','IS',
  'COB32API','DB2API','WIN32','WINAPI','WW-DS','WW-PROG',
  'SYSFILETREE','SYSLOADFUNCS','SYSSLEEP','RXFUNCADD','START_REXX',
  'INVOKE-MESSAGE-BOX','ENABLE-OBJECT','DISABLE-OBJECT','REFRESH-OBJECT','DIALOG-SYSTEM',
  'CONSTRAINTS','PRIMARY_KEY','RELASJONER','KOLONNER','HIERARKI','INDEKSER',
  'PROGRAMMET','SQLDB2','SQLDBS','SQLEXEC','HTML_HEADING','HTML_T_HEAD','HTML_TAB_HEAD',
  'KOL_COMMENT','TAB_COMMENT','ANALYSER','BEHANDLE_DEL','BEHANDLE_DIR','BEHANDLE_FILE',
  'BRUKTE_OMRADER','DANN_KOL','DANN_TAB_CRE','DEL_LOG','DRIFTLOGG','F_SKRIV',
  'FILER_FINNES','FINN_TABELL','FINN_TS_INT','HENT_PERIODE','KOPIER','LES_BUFFER',
  'LES_CBL','LES_PRM','LES_SDATO','LES_TABELL','LOGG_FELTER','M_SKRIV','OPPDATER_PRM',
  'PREP_CURSOR','READ_FILES','SCAN_FILE','SCAN_SOURCE',
  'SJEKK_FILE','SJEKK_FKSQL','SJEKK_HVILKE','SJEKK_LOG','SJEKK_PRM','SJEKK_RC',
  'SJEKK_RKFILE','SJEKK_RUT','SJEKK_RUTINER','SJEKK_SOURCE','SJEKK_STOP',
  'SKRIV_LOGG','SKRIV_SDATO','TIL_MONITOR','VENT_SEK',
  'UTL_CONVERT_DATE','UTL_GET_STRLEN','DELOPP_ANALYCEN','DELOPP_LABNETT','DELOPP_SOFTKORN',
  'INVOKESERVICE02','INVOKESERVICE06','VISMASTART1',
  'FTP_LOGOFF','FTP_LOGOFF_ALCONTROL','FTP_LOGOFF_ANALYCEN',
  'FTP_LOGON','FTP_LOGON_ALCONTROL','FTP_LOGON_BORG_SKIPT',
  'FTP_SEND_ALCONTROL','FTP_SEND_ANALYCEN','FTP_SEND_BORGSKIP','FTP_SLUTT',
  'FTPSETUSER','FTPTRACE','FTPTRACELOGOFF',
  'SEND_FILE','SEND_FILE_FTP','SENDFILE','SETUSER','LOGOFF',
  'BIND_PROG','SKRIV','SKRIV_BRYTERFILE','SKRIV_UT','MELD_RC','TEST_RC',
  'LIST_DIRECTORY','SETT_NUM_STATUS','TIL_BORG_SKIP',
  'CALL_GMLPREG','CALL_NYTTPREG','REXX','APIGUI','AVSLUTT_FEIL','AVSUTT_FEIL',
  'DSRUN','DSGRUN','D5BARTEP','D3BIBHB1','D3BOPCU1','D3BOPHB1',
  'DRHRRAP','E02REST_2012','GLAHLFR','GLBOBEK','GMBAVDP','SMETEXT',
  'S001_D3BD3TAB','S140_DRBTRAN','S150_DRBFRAK','S200_DRBVSUM',
  'S400_DRLOADV','S601_D5BDTAB','S633_D4BIIOR','S633_D5BIIOR',
  'DRBIDRSALG','DRBIDRSALG15','DRBIDRSALG16') |
    ForEach-Object { [void]$NoisePrograms.Add($_) }

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  HELPER FUNCTIONS                                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

function Write-Phase {
    param([int]$Phase, [string]$Title)
    Write-Output ''
    Write-Output ('=' * 72)
    Write-Output "  PHASE $Phase — $Title"
    Write-Output ('=' * 72)
}

function Test-ExcludeCall {
    param([string]$Name)
    if (-not $Name -or $Name.Length -lt 3) { return $true }
    if ($Name -match '-') { return $true }
    if ($CallExcludeSet.Contains($Name)) { return $true }
    if ($Name -match '^CBL_') { return $true }
    if ($Name -match '^(IEF|DFS|DFH|CEE|CEEDAY|ILBO|IGZ|__|WIN32|WINAPI|COB32API)') { return $true }
    $false
}

function Test-ValidCallTarget {
    param([string]$Name)
    if (-not $Name -or $Name.Length -lt 3) { return $false }
    if (Test-ExcludeCall -Name $Name) { return $false }

    if ($validProgramNames -and $validProgramNames.Count -gt 0) {
        $upper = $Name.ToUpperInvariant()
        if ($validProgramNames.Contains($upper)) { return $true }

        # Not in source tree — try Dedge-code RAG as last resort
        try {
            $ragResult = Invoke-Rag -Query "COBOL program $Name source file .CBL" -N 2
            if ($ragResult -and $ragResult -match "(?i)\b$([regex]::Escape($Name))\.CBL\b") {
                Write-Output "    [RAG-validated] '$Name' confirmed by Dedge-code RAG"
                [void]$validProgramNames.Add($upper)
                return $true
            }
        } catch { }

        if (-not $script:callValidationRejections.ContainsKey($upper)) {
            $script:callValidationRejections[$upper] = 0
        }
        $script:callValidationRejections[$upper]++
        return $false
    }

    # Index not yet built — fall through (accept for now, will be validated later)
    $true
}

$script:boundaryRejections = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$script:boundaryStripped   = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

function Filter-SqlByBoundary {
    param([string]$Program, [object[]]$SqlOperations)
    $valid   = [System.Collections.ArrayList]::new()
    $stripped = [System.Collections.ArrayList]::new()
    $had = ($SqlOperations -and $SqlOperations.Count -gt 0)

    if (-not $had -or $catalogQualified.Count -eq 0) {
        return [PSCustomObject]@{ validOps = $SqlOperations; strippedOps = @(); hadSqlOriginally = $had }
    }

    foreach ($op in $SqlOperations) {
        $tName = $op.tableName
        if (-not $tName) { [void]$stripped.Add($op); continue }
        $schema = $op.schema
        $isQualified = $schema -and $schema.Length -gt 1 -and $schema -ne '(UNQUALIFIED)'
        if ($isQualified -and $catalogQualified.Contains("$($schema).$($tName)")) {
            [void]$valid.Add($op)
        } else {
            [void]$stripped.Add($op)
        }
    }

    if ($stripped.Count -gt 0 -and $Program) {
        $script:boundaryStripped[$Program] = @($stripped | ForEach-Object {
            $s = $_.schema; $t = $_.tableName
            if ($s -and $s.Length -gt 1 -and $s -ne '(UNQUALIFIED)') { "$($s).$($t)" } else { $t }
        } | Sort-Object -Unique)
    }
    [PSCustomObject]@{ validOps = @($valid); strippedOps = @($stripped); hadSqlOriginally = $true }
}

function Invoke-Rag {
    param([string]$Query, [int]$N = 8)
    $body = @{ query = $Query; n_results = $N } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri $RagUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
        $r.result
    } catch {
        Write-Warning "RAG query failed: $($_.Exception.Message)"
        ''
    }
}

function Invoke-Db2Query {
    param([string]$Sql, [System.Data.Odbc.OdbcConnection]$Conn)
    if (-not $Conn -or $Conn.State -ne 'Open') { return @() }
    $cmd = $null
    $reader = $null
    try {
        $cmd = $Conn.CreateCommand()
        $cmd.CommandText = $Sql
        $cmd.CommandTimeout = 60
        $reader = $cmd.ExecuteReader()
        $results = [System.Collections.ArrayList]::new()
        while ($reader.Read()) {
            $row = [ordered]@{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = if ($reader.IsDBNull($i)) { $null } else { "$($reader.GetValue($i))".Trim() }
            }
            [void]$results.Add($row)
        }
        @($results)
    } catch {
        Write-Warning "DB2 query failed: $($_.Exception.Message)"
        @()
    } finally {
        if ($reader) { $reader.Close(); $reader.Dispose() }
        if ($cmd) { $cmd.Dispose() }
    }
}

# ── MCP HTTP DB2 fallback (JSON-RPC 2.0 via CursorDb2McpServer) ──
function Invoke-McpDb2Query {
    param([string]$Sql, [string]$DatabaseName = 'BASISMIG')
    $mcpUrl = 'http://dedge-server/CursorDb2McpServer/'
    try {
        $headers = @{ 'Accept' = 'application/json, text/event-stream' }
        $initBody = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{
            protocolVersion = '2024-11-05'; capabilities = @{}
            clientInfo = @{ name = 'SystemAnalyzer-Pipeline'; version = '1.0' }
        }} | ConvertTo-Json -Depth 5
        $initResp = Invoke-WebRequest -Uri $mcpUrl -Method Post -Body $initBody -ContentType 'application/json' -Headers $headers -TimeoutSec 30
        $sessionId = $initResp.Headers['Mcp-Session-Id'] | Select-Object -First 1
        if ($sessionId) { $headers['Mcp-Session-Id'] = $sessionId }

        $queryBody = @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{
            name = 'query_db2'
            arguments = @{ databaseName = $DatabaseName; query = $Sql }
        }} | ConvertTo-Json -Depth 5
        $queryResp = Invoke-WebRequest -Uri $mcpUrl -Method Post -Body $queryBody -ContentType 'application/json' -Headers $headers -TimeoutSec 120

        $lines = $queryResp.Content -split "`n"
        $dataLine = $lines | Where-Object { $_ -match '^data: ' } | Select-Object -First 1
        $parsed = if ($dataLine) { ($dataLine -replace '^data: ', '') | ConvertFrom-Json } else { $queryResp.Content | ConvertFrom-Json }
        $textContent = $parsed.result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
        if ($textContent) {
            $payload = $textContent.text | ConvertFrom-Json
            if ($payload.error) { Write-Warning "MCP DB2 error: $($payload.error)"; return @() }
            return @($payload.rows)
        }
        @()
    } catch {
        Write-Warning "MCP DB2 query failed: $($_.Exception.Message)"
        @()
    }
}

function Invoke-Db2QueryAny {
    param([string]$Sql, [string]$DatabaseName = 'BASISMIG')
    if ($db2Conn -and $db2Conn.State -eq 'Open') {
        return Invoke-Db2Query -Sql $Sql -Conn $db2Conn
    }
    return Invoke-McpDb2Query -Sql $Sql -DatabaseName $DatabaseName
}

function Resolve-ProgramSource {
    param(
        [string]$Program,
        [hashtable]$CblIndex,
        [hashtable]$FullIndex,
        [System.Collections.ArrayList]$UncertainFiles
    )
    $norm = $Program.ToUpperInvariant()

    # 1. Exact CBL match
    if ($CblIndex.ContainsKey($norm)) {
        return @{ type = 'local-cbl'; path = $CblIndex[$norm]; actualName = $norm }
    }

    # 2. U→V fuzzy match
    $uvSwapped = $norm -creplace 'U','V'
    if ($uvSwapped -ne $norm -and $CblIndex.ContainsKey($uvSwapped)) {
        return @{ type = 'local-cbl-uv'; path = $CblIndex[$uvSwapped]; actualName = $uvSwapped }
    }

    # 3. Other file type
    if ($FullIndex.ContainsKey($norm)) {
        $entry = $FullIndex[$norm]
        return @{ type = "local-$($entry.ext.TrimStart('.').ToLowerInvariant())"; path = $entry.path; actualName = $norm }
    }

    # 4. Basename contains program name in *_uncertain folders
    $uncertainMatch = $null
    foreach ($uf in $UncertainFiles) {
        if ($uf.baseName.Contains($norm)) {
            if ($uf.extension -ieq '.CBL') {
                $uncertainMatch = $uf
                break
            }
            if (-not $uncertainMatch) { $uncertainMatch = $uf }
        }
    }
    if ($uncertainMatch) {
        return @{
            type       = 'local-uncertain'
            path       = $uncertainMatch.path
            actualName = $uncertainMatch.baseName
        }
    }

    # 5. Not found locally — use RAG
    return @{ type = 'rag'; path = $null; actualName = $norm }
}

function Get-ProgramText {
    param(
        [string]$Program,
        [hashtable]$CblIndex,
        [hashtable]$FullIndex,
        [System.Collections.ArrayList]$UncertainFiles
    )
    $resolution = Resolve-ProgramSource -Program $Program -CblIndex $CblIndex -FullIndex $FullIndex -UncertainFiles $UncertainFiles

    if ($resolution.type -like 'local-*' -and $resolution.path) {
        try {
            return Get-Content -LiteralPath $resolution.path -Raw -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Warning "Cannot read $($resolution.path): $($_.Exception.Message)"
        }
    }

    # RAG fallback
    $queries = @(
        "$($Program).cbl source code",
        "$($Program) COPY EXEC SQL CALL",
        "$($Program) PROCEDURE DIVISION",
        "$($Program) SELECT ASSIGN FILE-CONTROL OPEN"
    )
    $chunks = [System.Collections.Generic.List[string]]::new()
    foreach ($q in $queries) {
        $chunk = Invoke-Rag -Query $q -N $RagResults
        if ($chunk) { $chunks.Add($chunk) }
    }
    $chunks -join "`n`n"
}

# ── Extraction functions ──

function Get-CopyElements {
    param([string]$Text)
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $results = [System.Collections.ArrayList]::new()
    foreach ($m in $CopyPattern.Matches($Text)) {
        $raw = $m.Groups[1].Value.Trim()
        if (-not $raw -or $raw -match '^(SQLCA|SQLENV|SQLSTATE)$') { continue }
        if ($found.Contains($raw)) { continue }
        [void]$found.Add($raw)
        $ext = if ($raw -match '\.(\w+)$') { $Matches[1].ToUpperInvariant() } else { '' }
        $copyType = switch ($ext) {
            'CPY' { 'copybook' }
            'CPB' { 'copybook-binary' }
            'DCL' { 'sql-declare' }
            ''    { 'copybook' }
            default { $ext.ToLowerInvariant() }
        }
        [void]$results.Add([ordered]@{ name = $raw.ToUpperInvariant(); type = $copyType })
    }
    , $results
}

function Get-SqlOperations {
    param([string]$Text)
    $results = [System.Collections.ArrayList]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($blockMatch in $SqlBlockPattern.Matches($Text)) {
        $block = $blockMatch.Groups[1].Value
        foreach ($m in $SqlTablePattern.Matches($block)) {
            $rawOp = $m.Groups[1].Value.Trim() -replace '\s+', ' '
            $schema = $m.Groups[2].Value.Trim()
            $table  = $m.Groups[3].Value.Trim()
            if ($SqlNotTables.Contains($table)) { continue }
            if ($table.Length -lt 2 -or $table -match '^\d' -or $table -match '^:') { continue }
            $op = switch -regex ($rawOp) {
                '(?i)^SELECT$'  { 'SELECT' }
                '(?i)^FROM$'    { 'SELECT' }
                '(?i)^JOIN$'    { 'SELECT' }
                '(?i)^INSERT'   { 'INSERT' }
                '(?i)^INTO$'    { 'INSERT' }
                '(?i)^UPDATE$'  { 'UPDATE' }
                '(?i)^DELETE'   { 'DELETE' }
                '(?i)^MERGE'    { 'MERGE'  }
                '(?i)^TABLE$'   { 'DDL'    }
                '(?i)^INCLUDE$' { 'INCLUDE' }
                default         { $rawOp.ToUpperInvariant() }
            }
            if (-not $schema) { $schema = '(unqualified)' }
            $key = "$($schema)|$($table)|$($op)"
            if ($seen.Contains($key)) { continue }
            [void]$seen.Add($key)
            [void]$results.Add([ordered]@{
                schema    = $schema.ToUpperInvariant()
                tableName = $table.ToUpperInvariant()
                operation = $op
            })
        }
    }
    , $results
}

function Get-CallTargets {
    param([string]$Text)
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $results = [System.Collections.ArrayList]::new()
    foreach ($m in $CallPattern.Matches($Text)) {
        $raw = $m.Groups[1].Value.Trim()
        $base = $raw -replace '\.(cbl|CBL|obj|OBJ)$', ''
        if (Test-ExcludeCall -Name $base) { continue }
        $norm = $base.ToUpperInvariant()
        if ($found.Contains($norm)) { continue }
        [void]$found.Add($norm)
        [void]$results.Add($norm)
    }
    , $results
}

function Get-FileIO {
    param([string]$Text)
    $fileMap = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

    # Pass 1: SELECT...ASSIGN declarations — the only source of truth for file names
    foreach ($m in $SelectAssignPattern.Matches($Text)) {
        $logName = $m.Groups[1].Value.Trim().ToUpperInvariant()
        if ($SkipLogicalFiles.Contains($logName)) { continue }
        $literal  = $m.Groups[2].Value.Trim()
        if (-not $literal) { $literal = $m.Groups[3].Value.Trim() }
        $variable = $m.Groups[4].Value.Trim()
        $physName = $null; $physPath = $DefaultFilePath; $aType = 'variable'
        if ($literal) {
            $aType = 'literal'
            if ($literal -match '[\\\/:]') {
                $physPath = Split-Path $literal -Parent
                $physName = Split-Path $literal -Leaf
                if (-not $physPath) { $physPath = $DefaultFilePath }
            } else { $physName = $literal }
        } elseif ($variable) {
            $physName = $variable
            if ($variable -match '^(DYNAMIC|SELECT)$') { $aType = 'dynamic' }
        }

        $fullP = $null
        if ($aType -eq 'literal' -and $literal -match '[\\\/:]') { $fullP = $literal }
        elseif ($aType -eq 'literal' -and $physName) {
            $fullP = try { Join-Path $physPath $physName } catch { "$physPath\$physName" }
        }

        if (-not $fileMap.ContainsKey($logName)) {
            $fileMap[$logName] = [ordered]@{
                logicalName  = $logName
                physicalName = $physName
                path         = $physPath
                fullPath     = $fullP
                assignType   = $aType
                operations   = [System.Collections.Generic.List[string]]::new()
            }
        }
    }

    # Pass 2: OPEN statements — only add operations to files already declared above
    foreach ($m in $OpenPattern.Matches($Text)) {
        $mode = switch ($m.Groups[1].Value.Trim().ToUpperInvariant()) {
            'INPUT'  { 'READ' }
            'OUTPUT' { 'WRITE' }
            'EXTEND' { 'WRITE' }
            'I-O'    { 'READ-WRITE' }
            default  { $_ }
        }
        $names = $m.Groups[2].Value.Trim() -split '[ \t]+'
        foreach ($fn in $names) {
            $fn = $fn.Trim().ToUpperInvariant()
            if (-not $fn -or $fn.Length -lt 2) { continue }
            if ($fileMap.ContainsKey($fn)) {
                if ($fileMap[$fn].operations -notcontains $mode) {
                    $fileMap[$fn].operations.Add($mode)
                }
            }
        }
    }

    $results = [System.Collections.ArrayList]::new()
    foreach ($entry in $fileMap.Values) {
        $ops = @($entry.operations)
        if ($ops.Count -eq 0) { $ops = @('UNKNOWN') }
        [void]$results.Add([ordered]@{
            logicalName  = $entry.logicalName
            physicalName = $entry.physicalName
            path         = $entry.path
            fullPath     = $entry.fullPath
            assignType   = $entry.assignType
            operations   = $ops
        })
    }
    , $results
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  OLLAMA — resolve variable-based filenames using local LLM                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
function Invoke-Ollama {
    param([string]$Prompt)
    $body = @{
        model  = $OllamaModel
        prompt = $Prompt
        stream = $false
    } | ConvertTo-Json -Depth 5
    try {
        $r = Invoke-RestMethod -Uri "$OllamaUrl/api/generate" `
            -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 120
        $r.response
    } catch {
        Write-Warning "Ollama error: $($_.Exception.Message)"
        $null
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  ANALYSISCOMMON CACHE — shared AI knowledge base                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$script:analysisCommonEnabled = $false
$script:analysisCommonObjectsDir = ''

function Initialize-AnalysisCommonCache {
    if (-not $AnalysisCommonPath -or -not (Test-Path -LiteralPath $AnalysisCommonPath)) {
        Write-Output "  AnalysisCommon cache: disabled (path not set or not found)"
        return
    }
    $script:analysisCommonObjectsDir = Join-Path $AnalysisCommonPath 'Objects'
    New-Item -ItemType Directory -Path $script:analysisCommonObjectsDir -Force | Out-Null
    $script:analysisCommonEnabled = $true
    $count = @(Get-ChildItem -LiteralPath $script:analysisCommonObjectsDir -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    $cblCount = @(Get-ChildItem -LiteralPath $script:analysisCommonObjectsDir -Filter '*.cbl.json' -File -ErrorAction SilentlyContinue).Count
    Write-Output "  AnalysisCommon cache: enabled ($count cached elements, $cblCount programs) at $($AnalysisCommonPath)"
}

function Get-CachedFact {
    param([string]$ProgramName, [string]$FactKey, [string]$ElementType = 'cbl')
    if (-not $script:analysisCommonEnabled) { return $null }
    $path = Join-Path $script:analysisCommonObjectsDir "$($ProgramName.ToUpperInvariant()).$($ElementType).json"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $pj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pj.PSObject.Properties.Name -contains $FactKey) { return $pj.$FactKey }
    } catch { }
    return $null
}

function Save-CachedFact {
    param([string]$ProgramName, [string]$FactKey, [object]$FactValue, [string]$ElementType = 'cbl')
    if (-not $script:analysisCommonEnabled) { return }
    $name = $ProgramName.ToUpperInvariant()
    $path = Join-Path $script:analysisCommonObjectsDir "$($name).$($ElementType).json"
    try {
        if (Test-Path -LiteralPath $path) {
            $pj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        } else {
            $pj = [PSCustomObject]@{ program = $name; elementType = $ElementType; lastUpdated = $null }
        }
        if (-not ($pj.PSObject.Properties.Name -contains 'elementType')) {
            $pj | Add-Member -NotePropertyName 'elementType' -NotePropertyValue $ElementType -Force
        }
        if ($pj.PSObject.Properties.Name -contains $FactKey) {
            $pj.$FactKey = $FactValue
        } else {
            $pj | Add-Member -NotePropertyName $FactKey -NotePropertyValue $FactValue -Force
        }
        $pj.lastUpdated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $pj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        Write-Warning "  Cache write failed for $($name).$($ElementType)/$($FactKey): $($_.Exception.Message)"
    }
}

function Get-SourceHash {
    param([string]$Text)
    if (-not $Text) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return 'sha256:' + [System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$script:extractionCacheHits = 0
$script:extractionCacheMisses = 0

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  TABLE METADATA CACHE — DB2 catalog info in Objects/*.sqltable.json        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$script:db2MetadataMap = @{}
$script:db2ForeignKeyMap = @{}
$script:tableMetadataCacheHits = 0
$script:tableMetadataCacheMisses = 0

function Invoke-BulkTableMetadataFetch {
    param([string]$DatabaseName = 'BASISMIG')
    if ($script:db2MetadataMap.Count -gt 0) { return }

    $colSql = @"
SELECT TRIM(T.TABSCHEMA) AS TABSCHEMA, TRIM(T.TABNAME) AS TABNAME,
       T.TYPE, TRIM(T.REMARKS) AS TABLE_REMARKS,
       C.COLNO, TRIM(C.COLNAME) AS COLNAME, TRIM(C.TYPENAME) AS TYPENAME,
       C.LENGTH, C.SCALE, C.NULLS, TRIM(C.REMARKS) AS COL_REMARKS
FROM SYSCAT.TABLES T
JOIN SYSCAT.COLUMNS C ON T.TABSCHEMA = C.TABSCHEMA AND T.TABNAME = C.TABNAME
WHERE T.TABSCHEMA NOT LIKE 'SYS%' AND T.TYPE IN ('T','V')
ORDER BY T.TABNAME, C.COLNO
FETCH FIRST 100000 ROWS ONLY
"@
    Write-Output '  Fetching table + column metadata from DB2 catalog...'
    $colRows = Invoke-Db2QueryAny -Sql $colSql -DatabaseName $DatabaseName
    foreach ($row in $colRows) {
        $tName = "$($row.TABNAME)"
        if (-not $script:db2MetadataMap.ContainsKey($tName)) {
            $script:db2MetadataMap[$tName] = @{
                schemas = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                type = "$($row.TYPE)".Trim()
                tableRemarks = "$($row.TABLE_REMARKS)"
                columns = [System.Collections.ArrayList]::new()
            }
        }
        [void]$script:db2MetadataMap[$tName].schemas.Add("$($row.TABSCHEMA)")
        [void]$script:db2MetadataMap[$tName].columns.Add([ordered]@{
            colNo    = [int]"$($row.COLNO)"
            name     = "$($row.COLNAME)"
            typeName = "$($row.TYPENAME)"
            length   = [int]"$($row.LENGTH)"
            scale    = [int]"$($row.SCALE)"
            nullable = ("$($row.NULLS)" -eq 'Y')
            remarks  = "$($row.COL_REMARKS)"
        })
    }
    Write-Output "    Loaded metadata for $($script:db2MetadataMap.Count) tables ($($colRows.Count) column rows)"

    $fkSql = @"
SELECT TRIM(R.TABSCHEMA) AS CHILD_SCHEMA, TRIM(R.TABNAME) AS CHILD_TABLE,
       TRIM(R.CONSTNAME) AS CONSTRAINT_NAME,
       TRIM(R.REFTABSCHEMA) AS PARENT_SCHEMA, TRIM(R.REFTABNAME) AS PARENT_TABLE,
       TRIM(FK.COLNAME) AS CHILD_COLUMN, FK.COLSEQ,
       TRIM(PK.COLNAME) AS PARENT_COLUMN
FROM SYSCAT.REFERENCES R
JOIN SYSCAT.KEYCOLUSE FK ON R.CONSTNAME = FK.CONSTNAME AND R.TABSCHEMA = FK.TABSCHEMA AND R.TABNAME = FK.TABNAME
JOIN SYSCAT.KEYCOLUSE PK ON R.REFKEYNAME = PK.CONSTNAME AND R.REFTABSCHEMA = PK.TABSCHEMA AND R.REFTABNAME = PK.TABNAME AND FK.COLSEQ = PK.COLSEQ
WHERE R.TABSCHEMA NOT LIKE 'SYS%'
FETCH FIRST 50000 ROWS ONLY
"@
    Write-Output '  Fetching FK references from DB2 catalog...'
    $fkRows = Invoke-Db2QueryAny -Sql $fkSql -DatabaseName $DatabaseName
    foreach ($row in $fkRows) {
        $childTable = "$($row.CHILD_TABLE)"
        if (-not $script:db2ForeignKeyMap.ContainsKey($childTable)) {
            $script:db2ForeignKeyMap[$childTable] = [System.Collections.ArrayList]::new()
        }
        [void]$script:db2ForeignKeyMap[$childTable].Add([ordered]@{
            constraintName = "$($row.CONSTRAINT_NAME)"
            childColumn    = "$($row.CHILD_COLUMN)"
            parentTable    = "$($row.PARENT_TABLE)"
            parentSchema   = "$($row.PARENT_SCHEMA)"
            parentColumn   = "$($row.PARENT_COLUMN)"
        })
    }
    Write-Output "    Loaded FK references for $($script:db2ForeignKeyMap.Count) tables ($($fkRows.Count) FK rows)"
}

function Ensure-TableMetadataCached {
    param([string[]]$TableNames)
    if (-not $script:analysisCommonEnabled) { return }
    $newCount = 0
    foreach ($tbl in $TableNames) {
        $tName = $tbl.ToUpperInvariant()
        $cachePath = Join-Path $script:analysisCommonObjectsDir "$($tName).sqltable.json"
        if (Test-Path -LiteralPath $cachePath) {
            $script:tableMetadataCacheHits++
            continue
        }
        $meta = $script:db2MetadataMap[$tName]
        if (-not $meta) { continue }

        $fks = @()
        if ($script:db2ForeignKeyMap.ContainsKey($tName)) {
            $fks = @($script:db2ForeignKeyMap[$tName])
        }

        $obj = [ordered]@{
            tableName   = $tName
            elementType = 'sqltable'
            lastUpdated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            db2Metadata = [ordered]@{
                schemas            = @($meta.schemas | Sort-Object)
                type               = $meta.type
                tableRemarks       = $meta.tableRemarks
                fetchedFrom        = $Db2Dsn
                fetchedAt          = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                fetchMethod        = if ($db2Conn -and $db2Conn.State -eq 'Open') { 'odbc' } else { 'mcp-http' }
                columns            = @($meta.columns)
                explicitForeignKeys = $fks
            }
        }
        $obj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cachePath -Encoding UTF8
        $script:tableMetadataCacheMisses++
        $newCount++
    }
    if ($newCount -gt 0) {
        Write-Output "    Cached metadata for $newCount new tables ($($script:tableMetadataCacheHits) already cached)"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  NAMING CACHE — modern CamelCase names in Naming/ subfolders              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$script:namingEnabled = $false
$script:namingTableDir = ''
$script:namingColumnDir = ''
$script:namingProgramDir = ''

function Initialize-NamingCache {
    if (-not $AnalysisCommonPath -or -not (Test-Path -LiteralPath $AnalysisCommonPath)) { return }
    $namingRoot = Join-Path $AnalysisCommonPath 'Naming'
    $script:namingTableDir   = Join-Path $namingRoot 'TableNames'
    $script:namingColumnDir  = Join-Path $namingRoot 'ColumnNames'
    $script:namingProgramDir = Join-Path $namingRoot 'ProgramNames'
    New-Item -ItemType Directory -Path $script:namingTableDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:namingColumnDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:namingProgramDir -Force | Out-Null
    $script:namingEnabled = $true
    $tCount = @(Get-ChildItem -LiteralPath $script:namingTableDir -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    $cCount = @(Get-ChildItem -LiteralPath $script:namingColumnDir -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    $pCount = @(Get-ChildItem -LiteralPath $script:namingProgramDir -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    Write-Output "  Naming cache: $tCount tables (with columns), $cCount column registry entries, $pCount programs"
}

function Get-CachedNaming {
    param([string]$Name, [string]$SubFolder)
    if (-not $script:namingEnabled) { return $null }
    $dir = switch ($SubFolder) {
        'TableNames'   { $script:namingTableDir }
        'ColumnNames'  { $script:namingColumnDir }
        'ProgramNames' { $script:namingProgramDir }
        default { return $null }
    }
    $path = Join-Path $dir "$($Name.ToUpperInvariant()).json"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch { return $null }
}

function Save-CachedNaming {
    param([string]$Name, [string]$SubFolder, [object]$Data)
    if (-not $script:namingEnabled) { return }
    $dir = switch ($SubFolder) {
        'TableNames'   { $script:namingTableDir }
        'ColumnNames'  { $script:namingColumnDir }
        'ProgramNames' { $script:namingProgramDir }
        default { return }
    }
    $path = Join-Path $dir "$($Name.ToUpperInvariant()).json"
    try {
        $Data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        Write-Warning "  Naming cache write failed for $($SubFolder)/$($Name): $($_.Exception.Message)"
    }
}

$script:columnRegistryStats = @{ created = 0; updated = 0; conflicts = 0; resolved = 0 }

function Update-ColumnRegistry {
    param(
        [string]$ColumnName,
        [string]$FutureName,
        [string]$Description,
        [string]$TableName,
        [string]$AnalysisAlias
    )
    if (-not $script:namingEnabled -or -not $ColumnName) { return }
    $colKey = $ColumnName.ToUpperInvariant()
    $existing = Get-CachedNaming -Name $colKey -SubFolder 'ColumnNames'

    if (-not $existing) {
        $newEntry = [ordered]@{
            originalName       = $colKey
            futureName         = $FutureName
            finalContext        = $Description
            contexts           = @(
                [ordered]@{
                    analysis    = $AnalysisAlias
                    description = $Description
                    analyzedAt  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                }
            )
            usedInTables       = @($TableName)
            isTypicalForeignKey = $false
            typicalTarget      = $null
            model              = $OllamaModel
            lastResolvedAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        }
        Save-CachedNaming -Name $colKey -SubFolder 'ColumnNames' -Data ([PSCustomObject]$newEntry)
        $script:columnRegistryStats.created++
        return
    }

    # Ensure usedInTables includes this table
    $tables = [System.Collections.ArrayList]::new()
    if ($existing.usedInTables) {
        foreach ($t in $existing.usedInTables) { [void]$tables.Add($t) }
    }
    if ($TableName -and $tables -notcontains $TableName) { [void]$tables.Add($TableName) }

    # Check if this analysis already has a context entry
    $contexts = [System.Collections.ArrayList]::new()
    if ($existing.contexts) {
        foreach ($c in $existing.contexts) { [void]$contexts.Add($c) }
    }
    $existingForAnalysis = $contexts | Where-Object { $_.analysis -eq $AnalysisAlias } | Select-Object -First 1
    if ($existingForAnalysis) {
        $existing.usedInTables = @($tables)
        Save-CachedNaming -Name $colKey -SubFolder 'ColumnNames' -Data $existing
        return
    }

    # New analysis context — check if description differs from finalContext
    $currentFinal = if ($existing.finalContext) { $existing.finalContext } else { '' }
    $descNorm = ($Description ?? '').Trim().ToLowerInvariant()
    $finalNorm = $currentFinal.Trim().ToLowerInvariant()

    $isSimilar = $false
    if ($descNorm -and $finalNorm) {
        # Quick similarity: if new description is a substring of existing or vice versa, or Levenshtein-like ratio
        $isSimilar = $finalNorm.Contains($descNorm) -or $descNorm.Contains($finalNorm)
        if (-not $isSimilar) {
            $words1 = [System.Collections.Generic.HashSet[string]]::new(($finalNorm -split '\s+'), [StringComparer]::OrdinalIgnoreCase)
            $words2 = [System.Collections.Generic.HashSet[string]]::new(($descNorm -split '\s+'), [StringComparer]::OrdinalIgnoreCase)
            $intersection = [System.Collections.Generic.HashSet[string]]::new($words1, [StringComparer]::OrdinalIgnoreCase)
            $intersection.IntersectWith($words2)
            $union = [System.Collections.Generic.HashSet[string]]::new($words1, [StringComparer]::OrdinalIgnoreCase)
            $union.UnionWith($words2)
            $jaccard = if ($union.Count -gt 0) { $intersection.Count / $union.Count } else { 0 }
            $isSimilar = $jaccard -gt 0.5
        }
    }

    [void]$contexts.Add([ordered]@{
        analysis    = $AnalysisAlias
        description = $Description
        analyzedAt  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    })

    if ($isSimilar) {
        $existing.contexts = @($contexts)
        $existing.usedInTables = @($tables)
        Save-CachedNaming -Name $colKey -SubFolder 'ColumnNames' -Data $existing
        $script:columnRegistryStats.updated++
        return
    }

    # Conflict detected — invoke Ollama to resolve
    $script:columnRegistryStats.conflicts++
    $existingContextList = ($contexts | ForEach-Object {
        "- [$($_.analysis)] $($_.description)"
    }) -join "`n"

    $conflictPrompt = @"
You are resolving a naming conflict for a legacy DB2 column used across multiple analysis domains.

COLUMN: $colKey
CURRENT FUTURE NAME: $($existing.futureName)
CURRENT FINAL CONTEXT: $currentFinal

ALL ANALYSIS CONTEXTS:
$existingContextList

NEW CONTEXT FROM [$AnalysisAlias]: $Description

Your task:
1. Determine if the new context adds valid information or contradicts existing context
2. Produce a unified finalContext that covers all valid perspectives
3. If the new analysis reveals the previous context was wrong, say so
4. If the new context is wrong (e.g. misidentified column purpose), say so

Respond with EXACTLY one JSON object:
{"verdict":"keep-both","futureName":"DepartmentNumber","finalContext":"Unified description covering all valid perspectives"}

Verdicts: "keep-both" (both valid, merge), "replace-old" (old was wrong), "keep-old" (new is wrong)

JSON:
{"verdict":
"@
    try {
        $conflictResp = Invoke-Ollama -Prompt $conflictPrompt
        if ($conflictResp) {
            $conflictResp = $conflictResp.Trim()
            if ($conflictResp -notmatch '^\{') { $conflictResp = '{"verdict":' + $conflictResp }
            if ($conflictResp -match '\{[^}]+\}') {
                $resolution = $Matches[0] | ConvertFrom-Json
                if ($resolution.verdict -eq 'replace-old') {
                    foreach ($ctx in $contexts) {
                        if ($ctx.analysis -ne $AnalysisAlias -and -not $ctx.superseded) {
                            $ctx.superseded = $true
                            $ctx.supersededBy = $AnalysisAlias
                        }
                    }
                }
                $existing.futureName = if ($resolution.futureName) { $resolution.futureName } else { $existing.futureName }
                $existing.finalContext = if ($resolution.finalContext) { $resolution.finalContext } else { $currentFinal }
                $existing.contexts = @($contexts)
                $existing.usedInTables = @($tables)
                $existing.lastResolvedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                Save-CachedNaming -Name $colKey -SubFolder 'ColumnNames' -Data $existing
                $script:columnRegistryStats.resolved++
                return
            }
        }
    } catch { }

    # Fallback: save without resolution
    $existing.contexts = @($contexts)
    $existing.usedInTables = @($tables)
    Save-CachedNaming -Name $colKey -SubFolder 'ColumnNames' -Data $existing
    $script:columnRegistryStats.updated++
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  AUTODOCJSON — pre-parsed program data from AutoDocJson batch output       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
$script:autoDocIndexLoaded = $false
$script:autoDocIndex = @{}

function Initialize-AutoDocIndex {
    if ($script:autoDocIndexLoaded) { return }
    $script:autoDocIndexLoaded = $true

    if (-not $AutoDocJsonPath -or -not (Test-Path -LiteralPath $AutoDocJsonPath)) {
        Write-Output "  AutoDocJson path not accessible: $($AutoDocJsonPath)"
        return
    }
    $indexPath = Join-Path $AutoDocJsonPath '_json\CblParseResult.json'
    if (-not (Test-Path -LiteralPath $indexPath)) {
        Write-Output "  AutoDocJson CblParseResult.json not found"
        return
    }
    try {
        $entries = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($e in $entries) {
            $name = ($e.programName -replace '\.cbl$', '').ToUpperInvariant()
            $script:autoDocIndex[$name] = $true
        }
        Write-Output "  AutoDocJson index loaded: $($script:autoDocIndex.Count) COBOL programs"
    } catch {
        Write-Warning "  Failed to load AutoDocJson index: $($_.Exception.Message)"
    }
}

function Get-AutoDocData {
    param([string]$ProgramName)
    if (-not $AutoDocJsonPath -or -not (Test-Path -LiteralPath $AutoDocJsonPath)) { return $null }

    $jsonFile = Join-Path $AutoDocJsonPath "$($ProgramName).CBL.json"
    if (-not (Test-Path -LiteralPath $jsonFile)) {
        $jsonFile = Join-Path $AutoDocJsonPath "$($ProgramName.ToLowerInvariant()).cbl.json"
        if (-not (Test-Path -LiteralPath $jsonFile)) { return $null }
    }
    try {
        $data = Get-Content -LiteralPath $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return $data
    } catch {
        return $null
    }
}

function Test-ProgramInAutoDocIndex {
    param([string]$ProgramName)
    Initialize-AutoDocIndex
    return $script:autoDocIndex.ContainsKey($ProgramName.ToUpperInvariant())
}

function Invoke-VisualCobolRag {
    param([string]$Query, [int]$N = 4)
    $body = @{ query = $Query; n_results = $N } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri "$VisualCobolRagUrl/query" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
        $r.result
    } catch {
        Write-Warning "Visual COBOL RAG query failed: $($_.Exception.Message)"
        ''
    }
}

function Test-StandardCobolProgram {
    param([string]$ProgramName)

    $cached = Get-CachedFact -ProgramName $ProgramName -FactKey 'isStandardCobol'
    if ($cached -and $cached.answer) {
        $isYes = $cached.answer -eq 'YES'
        Write-Output "      (cache hit: isStandardCobol=$($cached.answer))"
        return @{ isStandard = $isYes; evidence = $cached.ragEvidence; verdict = $cached.answer }
    }

    $ragResult = Invoke-VisualCobolRag -Query "$ProgramName COBOL standard keyword function runtime" -N 4
    if (-not $ragResult) {
        return @{ isStandard = $false; evidence = ''; verdict = 'RAG_UNAVAILABLE' }
    }
    $prompt = @"
Based on the following Visual COBOL / Micro Focus documentation excerpts, determine if '$ProgramName' is a standard COBOL keyword, built-in function, runtime routine, reserved word, or standard library program that ships with Visual COBOL or the COBOL standard.

Answer ONLY with a JSON object: {"answer":"YES"} or {"answer":"NO"}
- YES = it is a standard COBOL/Visual COBOL keyword, statement, function, or runtime routine
- NO  = it is an application-specific program name (custom business logic, not part of COBOL standard or Visual COBOL runtime)

Documentation excerpts:
$ragResult
"@
    $ollamaResult = Invoke-Ollama -Prompt $prompt
    if (-not $ollamaResult) {
        return @{ isStandard = $false; evidence = $ragResult; verdict = 'OLLAMA_UNAVAILABLE' }
    }
    $isYes = $ollamaResult -match '"answer"\s*:\s*"YES"' -or ($ollamaResult.Trim() -match '(?i)^YES$')
    $verdictText = $isYes ? 'YES' : 'NO'
    $truncatedEvidence = $ragResult.Substring(0, [math]::Min($ragResult.Length, 500))

    Save-CachedFact -ProgramName $ProgramName -FactKey 'isStandardCobol' -FactValue ([PSCustomObject]@{
        answer     = $verdictText
        ragEvidence = $truncatedEvidence
        model      = $OllamaModel
        protocol   = 'Cbl-StandardProgramFilter'
        analyzedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    })

    return @{
        isStandard = $isYes
        evidence   = $truncatedEvidence
        verdict    = $verdictText
    }
}

function Classify-ProgramByRules {
    param(
        [string]$ProgramName,
        [object]$MasterEntry
    )
    $copies = @($MasterEntry.copyElements | ForEach-Object { $_.name.ToUpperInvariant() })
    $thirdChar = if ($ProgramName.Length -ge 3) { $ProgramName.Substring(2, 1).ToUpperInvariant() } else { '?' }

    $hasDsrunner  = $copies -contains 'DSRUNNER.CPY'
    $hasDssysinf  = $copies -contains 'DSSYSINF.CPY'
    $hasDsCntrl   = $copies -contains 'DS-CNTRL.MF'
    $hasDsUsrVal  = $copies -contains 'DSUSRVAL.CPY'
    $hasGmadbba   = $copies -contains 'GMADBBA.CPY'
    $hasGmasoal   = $copies -contains 'GMASOAL.CPY'
    $hasDialogSys = $hasDsrunner -or $hasDssysinf -or $hasDsCntrl

    switch ($thirdChar) {
        'H' {
            $conf = $hasDialogSys ? 'high' : 'medium'
            $ev = "3rd-letter=H"
            if ($hasDialogSys) { $ev += ', has Dialog System copybooks' }
            return @{ classification = 'main-ui'; classificationConfidence = $conf; classificationEvidence = $ev }
        }
        'V' {
            $conf = $hasDsUsrVal ? 'high' : 'medium'
            $ev = "3rd-letter=V"
            if ($hasDsUsrVal) { $ev += ', has DSUSRVAL.CPY' }
            return @{ classification = 'validation-ui'; classificationConfidence = $conf; classificationEvidence = $ev }
        }
        'F' {
            $conf = $hasDialogSys ? 'high' : 'medium'
            $ev = "3rd-letter=F"
            if ($hasDialogSys) { $ev += ', has Dialog System copybooks' }
            return @{ classification = 'secondary-ui'; classificationConfidence = $conf; classificationEvidence = $ev }
        }
        'B' {
            $conf = (-not $hasDialogSys) ? 'high' : 'low'
            $ev = "3rd-letter=B"
            if (-not $hasDialogSys) { $ev += ', no Dialog System copybooks' }
            return @{ classification = 'batch-processing'; classificationConfidence = $conf; classificationEvidence = $ev }
        }
        'S' {
            if ($hasGmadbba -or $hasGmasoal) {
                return @{ classification = 'webservice'; classificationConfidence = 'high'; classificationEvidence = "3rd-letter=S, has GMADBBA/GMASOAL" }
            }
            if ($hasDialogSys) {
                return @{ classification = 'main-ui'; classificationConfidence = 'medium'; classificationEvidence = "3rd-letter=S but has Dialog System copybooks" }
            }
            return @{ classification = 'webservice'; classificationConfidence = 'medium'; classificationEvidence = "3rd-letter=S" }
        }
        'A' {
            $conf = (-not $hasDialogSys) ? 'high' : 'medium'
            $ev = "3rd-letter=A"
            if (-not $hasDialogSys) { $ev += ', no Dialog System copybooks' }
            return @{ classification = 'common-utility'; classificationConfidence = $conf; classificationEvidence = $ev }
        }
        default {
            if ($hasDialogSys) {
                $cls = $hasDsUsrVal ? 'validation-ui' : 'main-ui'
                return @{ classification = $cls; classificationConfidence = 'medium'; classificationEvidence = "copybook-fallback: has Dialog System copybooks" }
            }
            if ($hasDsUsrVal) {
                return @{ classification = 'validation-ui'; classificationConfidence = 'medium'; classificationEvidence = "copybook-fallback: has DSUSRVAL.CPY" }
            }
            if ($hasGmadbba -or $hasGmasoal) {
                return @{ classification = 'webservice'; classificationConfidence = 'medium'; classificationEvidence = "copybook-fallback: has GMADBBA/GMASOAL" }
            }
            return @{ classification = 'unknown'; classificationConfidence = 'low'; classificationEvidence = "no matching 3rd-letter rule or copybook pattern" }
        }
    }
}

function Resolve-VariableFilenames {
    param(
        [System.Collections.ArrayList]$FileIOEntries,
        [string]$SourceText,
        [string]$ProgramName
    )
    $varEntries = @($FileIOEntries | Where-Object {
        $_.assignType -eq 'variable' -and $_.physicalName -and
        $_.physicalName -notin @('DYNAMIC','SELECT')
    })
    if ($varEntries.Count -eq 0) { return }

    $src = if ($SourceText.Length -gt 12000) { $SourceText.Substring(0, 12000) } else { $SourceText }

    $cachedVf = Get-CachedFact -ProgramName $ProgramName -FactKey 'variableFilenames'

    foreach ($ve in $varEntries) {
        $logicalKey = $ve.logicalName
        if (-not $logicalKey) { $logicalKey = $ve.physicalName }

        if ($cachedVf -and $cachedVf.PSObject.Properties.Name -contains $logicalKey) {
            $hit = $cachedVf.$logicalKey
            if ($hit.resolvedPath)    { $ve['resolvedPath']        = $hit.resolvedPath }
            if ($hit.filenamePattern) { $ve['filenamePattern']     = $hit.filenamePattern }
            if ($hit.description)     { $ve['filenameDescription'] = $hit.description }
            if ($hit.basePath -and (-not $ve['path'] -or $ve['path'] -eq $DefaultFilePath)) {
                $ve['path'] = $hit.basePath
            }
            Write-Output "    File $($logicalKey): cache hit"
            continue
        }

        $prompt = @"
Analyze this COBOL program ($ProgramName). Find how the filename variable $($ve.physicalName) (for file $($ve.logicalName)) is constructed.

Look for:
- MOVE statements that set $($ve.physicalName) or parts of it
- STRING operations building $($ve.physicalName)
- VALUE clauses in WORKING-STORAGE for $($ve.physicalName)
- Any UNC path (\\server\share\), drive letter (N:\), or folder prefix
- File extension (.CSV, .DAT, .TXT, .FNK, .RPT, etc.)

IMPORTANT: Use FORWARD SLASHES (/) for all paths in JSON. Never use backslashes.

Respond with EXACTLY one JSON object (no markdown, no explanation, no text before or after):
{"basePath":"//SERVER/SHARE/","filenamePattern":"<userid>-<date>.CSV","resolvedPath":"//SERVER/SHARE/<dynamic>.CSV","description":"short description"}

Use null for fields you cannot determine. If the variable is a printer (WW-PRINTER), set description to "Printer output spool".

JSON:
{"basePath":
"@
        $fullPrompt = $prompt + "`n`nCOBOL SOURCE:`n$src"

        $response = Invoke-Ollama -Prompt $fullPrompt
        if (-not $response) { continue }

        try {
            $cleaned = $response.Trim()
            if ($cleaned -match '```(?:json)?\s*([\s\S]*?)```') { $cleaned = $Matches[1].Trim() }
            if ($cleaned -match '(\{[\s\S]*\})') { $cleaned = $Matches[1] }
            if ($cleaned -notmatch '^\s*\{') { $cleaned = '{"basePath":' + $cleaned }

            $r = $cleaned | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "  Ollama JSON parse failed for $($ProgramName)/$($ve.logicalName): $($_.Exception.Message)"
            continue
        }

        if ($r.resolvedPath)    { $ve['resolvedPath']        = $r.resolvedPath -replace '/', '\' }
        if ($r.filenamePattern) { $ve['filenamePattern']     = $r.filenamePattern }
        if ($r.description)     { $ve['filenameDescription'] = $r.description }
        if ($r.basePath -and (-not $ve['path'] -or $ve['path'] -eq $DefaultFilePath)) {
            $ve['path'] = $r.basePath -replace '/', '\'
        }

        Save-CachedFact -ProgramName $ProgramName -FactKey 'variableFilenames' -FactValue (
            & {
                $existing = Get-CachedFact -ProgramName $ProgramName -FactKey 'variableFilenames'
                if (-not $existing) { $existing = [PSCustomObject]@{} }
                $existing | Add-Member -NotePropertyName $logicalKey -NotePropertyValue ([PSCustomObject]@{
                    logicalName      = $ve.logicalName
                    physicalVariable = $ve.physicalName
                    basePath         = if ($r.basePath) { $r.basePath -replace '/', '\' } else { $null }
                    filenamePattern  = $r.filenamePattern
                    resolvedPath     = if ($r.resolvedPath) { $r.resolvedPath -replace '/', '\' } else { $null }
                    description      = $r.description
                    model            = $OllamaModel
                    protocol         = 'Cbl-VariableFilenames'
                    analyzedAt       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                }) -Force
                $existing
            }
        )
    }
}

function Extract-ProgramDependencies {
    param(
        [string]$Program,
        [hashtable]$CblIndex,
        [hashtable]$FullIndex,
        [System.Collections.ArrayList]$UncertainFiles
    )
    $resolution = Resolve-ProgramSource -Program $Program -CblIndex $CblIndex -FullIndex $FullIndex -UncertainFiles $UncertainFiles
    $isLocal = $resolution.type -like 'local-*' -and $resolution.path

    # For local sources, compute hash before reading full text (fast path)
    $sourceHash = $null
    $localText = $null
    if ($isLocal) {
        try {
            $localText = Get-Content -LiteralPath $resolution.path -Raw -Encoding UTF8 -ErrorAction Stop
            $sourceHash = Get-SourceHash -Text $localText
        } catch {
            Write-Warning "Cannot read $($resolution.path): $($_.Exception.Message)"
        }
    }

    # Check extraction cache
    $cachedExtraction = Get-CachedFact -ProgramName $Program -FactKey 'extraction'
    if ($cachedExtraction) {
        $cachedHash = $cachedExtraction.sourceHash
        # Cache hit: local source with matching hash, or RAG source (null hash = always accept)
        if (($sourceHash -and $cachedHash -eq $sourceHash) -or (-not $isLocal -and -not $cachedHash)) {
            $script:extractionCacheHits++
            return [ordered]@{
                program       = $cachedExtraction.program ?? $Program.ToUpperInvariant()
                sourceType    = $cachedExtraction.sourceType ?? $resolution.type
                sourcePath    = $cachedExtraction.sourcePath ?? $resolution.path
                actualName    = $cachedExtraction.actualName ?? $resolution.actualName
                copyElements  = @($cachedExtraction.copyElements)
                sqlOperations = @($cachedExtraction.sqlOperations)
                callTargets   = @($cachedExtraction.callTargets)
                fileIO        = @($cachedExtraction.fileIO)
            }
        }
    }
    $script:extractionCacheMisses++

    # Cache miss — perform full extraction
    $text = if ($localText) { $localText } else {
        Get-ProgramText -Program $Program -CblIndex $CblIndex -FullIndex $FullIndex -UncertainFiles $UncertainFiles
    }
    if (-not $sourceHash -and -not $isLocal) {
        $sourceHash = $null
    }

    $copies = Get-CopyElements  -Text $text
    $sqlOps = Get-SqlOperations -Text $text
    $calls  = Get-CallTargets   -Text $text
    $fileIO = Get-FileIO        -Text $text

    # Resolve variable-based filenames: try AutoDocJson first, fall back to Ollama
    $hasVarFiles = @($fileIO | Where-Object {
        $_.assignType -eq 'variable' -and $_.physicalName -and
        $_.physicalName -notin @('DYNAMIC','SELECT')
    })
    if ($hasVarFiles.Count -gt 0 -and $text -and $text.Length -gt 100) {
        $autoDoc = Get-AutoDocData -ProgramName $Program
        $resolvedFromAutoDoc = $false
        if ($autoDoc -and $autoDoc.diagrams.flowMmd) {
            foreach ($ve in $hasVarFiles) {
                $flowText = $autoDoc.diagrams.flowMmd
                if ($flowText -match [regex]::Escape($ve.logicalName)) {
                    $resolvedFromAutoDoc = $true
                }
            }
        }
        if (-not $resolvedFromAutoDoc) {
            Resolve-VariableFilenames -FileIOEntries $fileIO -SourceText $text -ProgramName $Program
        }
    }

    $result = [ordered]@{
        program       = $Program.ToUpperInvariant()
        sourceType    = $resolution.type
        sourcePath    = $resolution.path
        actualName    = $resolution.actualName
        copyElements  = @($copies)
        sqlOperations = @($sqlOps)
        callTargets   = @($calls)
        fileIO        = @($fileIO)
    }

    # Save extraction to cache
    Save-CachedFact -ProgramName $Program -FactKey 'extraction' -FactValue ([PSCustomObject]@{
        sourceHash    = $sourceHash
        sourceType    = $resolution.type
        sourcePath    = $resolution.path
        actualName    = $resolution.actualName
        program       = $Program.ToUpperInvariant()
        copyElements  = @($copies)
        sqlOperations = @($sqlOps)
        callTargets   = @($calls)
        fileIO        = @($fileIO)
        extractedAt   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    })

    $result
}

function Save-Master {
    param(
        [System.Collections.Generic.Dictionary[string, object]]$Master,
        [string]$Path
    )
    $programs = [System.Collections.ArrayList]::new()
    $fpnCheck = 0
    foreach ($key in ($Master.Keys | Sort-Object)) {
        $item = $Master[$key]
        if ($item.futureProjectName) { $fpnCheck++ }
        [void]$programs.Add($item)
    }
    if ($fpnCheck -gt 0) { Write-Output "    [Save-Master] $fpnCheck programs with futureProjectName" }
    $output = [ordered]@{
        title         = 'COBOL Dependency Master'
        generated     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        totalPrograms = $programs.Count
        programs      = @($programs)
    }
    if ($profileDatabase) {
        $output.database = $profileDatabase
        $output.db2Alias = $catalogDb2Alias
    }
    if ($catalogQualified.Count -gt 0) {
        $output.boundaryStats = [ordered]@{
            database            = $profileDatabase
            catalogQualified    = $catalogQualified.Count
            programsRejected    = $script:boundaryRejections.Count
            sqlOpsStripped       = $script:boundaryStripped.Count
        }
    }
    if ($script:tableNamingSection -and $script:tableNamingSection.Count -gt 0) {
        $output.tableNaming = $script:tableNamingSection
    }
    $jsonText = $output | ConvertTo-Json -Depth 10
    
    $maxAttempts = 6
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $jsonText | Set-Content -LiteralPath $Path -Encoding UTF8
            return
        } catch {
            if ($attempt -eq $maxAttempts) {
                throw
            }
            Start-Sleep -Milliseconds (200 * $attempt)
        }
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 1 — Load seed programs & index local source tree                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

Write-Phase -Phase 1 -Title 'Load seed programs and index local source tree'

Initialize-AnalysisCommonCache
Initialize-NamingCache

$allJson = Get-Content -LiteralPath $AllJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$seedPrograms = @($allJson.entries | ForEach-Object { $_.program } |
    Where-Object { $_ -and $_.Length -ge 2 } | Sort-Object -Unique)
Write-Output "  Seed programs from all.json: $($seedPrograms.Count)"

# ── Database boundary catalog ──
$profileDatabase = $allJson.database
$catalogQualified  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$catalogPackages   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$catalogDb2Alias   = ''

$AnalysisStaticPath = if ($AnalysisCommonPath) {
    Join-Path (Split-Path $AnalysisCommonPath -Parent) 'AnalysisStatic'
} else { '' }

if ($profileDatabase -and $AnalysisStaticPath -and (Test-Path -LiteralPath $AnalysisStaticPath)) {
    $catalogPath = Join-Path $AnalysisStaticPath "Databases\$profileDatabase\syscat_tables.json"
    if (Test-Path -LiteralPath $catalogPath) {
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $catalogDb2Alias = if ($catalog.db2Alias) { $catalog.db2Alias } else { '' }
        foreach ($t in $catalog.tables) {
            if ($t.qualifiedName) { [void]$catalogQualified.Add($t.qualifiedName) }
        }
        Write-Output "  Database boundary (tables): $($profileDatabase) (alias=$($catalogDb2Alias)) — $($catalogQualified.Count) qualifiedNames"
    } else {
        Write-Warning "Database catalog not found: $($catalogPath) — table boundary filtering disabled"
    }

    $packagePath = Join-Path $AnalysisStaticPath "Databases\$profileDatabase\syscat_packages.json"
    if (Test-Path -LiteralPath $packagePath) {
        $pkgCatalog = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pkg in $pkgCatalog.packages) {
            if ($pkg.qualifiedName) { [void]$catalogPackages.Add($pkg.qualifiedName.ToUpperInvariant()) }
        }
        Write-Output "  Database boundary (packages): $($catalogPackages.Count) bound programs (strict — non-seed programs must be bound)"
    } else {
        Write-Warning "Package catalog not found: $($packagePath) — package boundary filtering disabled"
    }
} else {
    Write-Output "  Database boundary: disabled (no 'database' field in all.json or AnalysisStatic not found)"
}

$script:packageRejections = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)

$db2TableSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($qn in $catalogQualified) {
    $parts = $qn.Split('.')
    if ($parts.Length -eq 2) { [void]$db2TableSet.Add($parts[1]) }
}
$seedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($sp in $seedPrograms) { [void]$seedSet.Add($sp.ToUpperInvariant()) }

# Index local source tree
Write-Output '  Indexing local source tree...'
$cblIndex  = @{}  # basename (upper) -> full path (CBL only)
$fullIndex = @{}  # basename (upper) -> @{ext; path} (first match of any type)
$copyIndex = @{}  # name (upper) -> full path (CPY/CPB/DCL)

$allLocalFiles = Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -ErrorAction SilentlyContinue
foreach ($f in $allLocalFiles) {
    $baseName = $f.BaseName.ToUpperInvariant()
    $directory = $f.DirectoryName
    $isCblFolder = $directory -imatch '[\\/]cbl([\\/]|$)'
    $isCpyFolder = $directory -imatch '[\\/]cpy([\\/]|$)'
    $isUncertain = $directory -imatch '[\\/][^\\/]*_uncertain([\\/]|$)'

    if ($isUncertain) {
        [void]$uncertainFiles.Add([ordered]@{
            baseName  = $baseName
            extension = $f.Extension
            path      = $f.FullName
        })
        continue
    }

    if ($isCblFolder -and $f.Extension -ieq '.CBL' -and -not $cblIndex.ContainsKey($baseName)) {
        $cblIndex[$baseName] = $f.FullName
    }
    if (($isCblFolder -or $isCpyFolder) -and -not $fullIndex.ContainsKey($baseName)) {
        $fullIndex[$baseName] = @{ ext = $f.Extension; path = $f.FullName }
    }
    if ($isCpyFolder -and $f.Extension -imatch '^\.(cpy|cpb|dcl)$') {
        $nameKey = $f.Name.ToUpperInvariant()
        $baseKey = $baseName
        if (-not $copyIndex.ContainsKey($nameKey)) { $copyIndex[$nameKey] = $f.FullName }
        if (-not $copyIndex.ContainsKey($baseKey)) { $copyIndex[$baseKey] = $f.FullName }
    }
}
Write-Output "  Total files: $($allLocalFiles.Count)  |  CBL (cbl\): $($cblIndex.Count)  |  Copy elements (cpy\): $($copyIndex.Count)"
Write-Output "  Uncertain files (*_uncertain): $($uncertainFiles.Count)"

# ┌─────────────────────────────────────────────────────────────────────────┐
# │  VALID PROGRAM NAME INDEX                                              │
# │  Used to validate CALL targets — a name must exist as an actual        │
# │  source file (.CBL or .INT) to be accepted as a real program call.     │
# └─────────────────────────────────────────────────────────────────────────┘
$validProgramNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($k in $cblIndex.Keys) { [void]$validProgramNames.Add($k) }
foreach ($k in $fullIndex.Keys) { [void]$validProgramNames.Add($k) }
$intOnlyFiles = Get-ChildItem -LiteralPath $SourceRoot -Filter '*.INT' -Recurse -File -ErrorAction SilentlyContinue
foreach ($intFile in $intOnlyFiles) {
    [void]$validProgramNames.Add($intFile.BaseName.ToUpperInvariant())
}
Write-Output "  Valid program name index: $($validProgramNames.Count) unique names (CBL + INT + full index)"
$script:callValidationRejections = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)

# Track discovery layers
$programLayers = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($p in $seedPrograms) { $programLayers[$p.ToUpperInvariant()] = 'original' }

# Master dependency dictionary
$master = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 2 — Extract seed program dependencies                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if ($SkipPhases -notcontains 2) {
    Write-Phase -Phase 2 -Title "Extract seed program dependencies ($($seedPrograms.Count) programs)"

    $localCount = 0; $ragCount = 0; $seedStripped = 0
    $hitsBefore = $script:extractionCacheHits
    $idx = 0; $total = $seedPrograms.Count
    foreach ($prog in $seedPrograms) {
        $idx++
        if ($idx % 25 -eq 0 -or $idx -eq 1 -or $idx -eq $total) {
            Write-Output "  [$idx/$total] $prog"
        }
        $entry = Extract-ProgramDependencies -Program $prog -CblIndex $cblIndex -FullIndex $fullIndex -UncertainFiles $uncertainFiles
        $boundary = Filter-SqlByBoundary -Program $prog -SqlOperations $entry.sqlOperations
        if ($boundary.strippedOps.Count -gt 0) {
            $seedStripped += $boundary.strippedOps.Count
        }
        $entry.sqlOperations = $boundary.validOps
        $master[$prog.ToUpperInvariant()] = $entry
        if ($entry.sourceType -like 'local-*') { $localCount++ } else { $ragCount++ }
    }
    $phaseHits = $script:extractionCacheHits - $hitsBefore
    Write-Output "  Done: $localCount local  |  $ragCount RAG  |  $phaseHits cache hits"
    if ($seedStripped -gt 0) {
        Write-Output "  Boundary filter: stripped $seedStripped non-matching SQL ops from seed programs"
    }
    Save-Master -Master $master -Path $MasterJson
    Write-Output "  Saved: $MasterJson"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  POST-PHASE 2 — Validate & clean callTargets against source index          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
if ($validProgramNames.Count -gt 0) {
    Write-Output ''
    Write-Output '  Cleaning call targets against valid program name index...'
    $cleanedTotal = 0; $removedTotal = 0
    foreach ($mk in @($master.Keys)) {
        $p = $master[$mk]
        $ct = @($p.callTargets)
        if ($ct.Count -eq 0) { continue }
        $validTargets = [System.Collections.ArrayList]::new()
        $removedTargets = [System.Collections.ArrayList]::new()
        foreach ($c in $ct) {
            $cn = if ($c -is [string]) { $c } else { "$c" }
            if ($cn -and (Test-ValidCallTarget -Name $cn)) {
                [void]$validTargets.Add($cn)
            } else {
                [void]$removedTargets.Add($cn)
                $removedTotal++
            }
        }
        if ($removedTargets.Count -gt 0) {
            $cleanedTotal++
            if ($p -is [System.Collections.IDictionary]) {
                $p['callTargets'] = @($validTargets)
            } elseif ($p.PSObject.Properties.Match('callTargets').Count) {
                $p.callTargets = @($validTargets)
            }
        }
    }
    Write-Output "  Cleaned $removedTotal invalid call targets from $cleanedTotal programs"
    if ($removedTotal -gt 0) {
        Save-Master -Master $master -Path $MasterJson
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 3 — Iterative CALL target expansion                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if ($SkipPhases -notcontains 3) {
    Write-Phase -Phase 3 -Title "Discover programs via CALL targets (max $MaxCallIterations iterations)"

    $iter = 0
    while ($iter -lt $MaxCallIterations) {
        $iter++
        Write-Output "  --- Iteration $iter of $MaxCallIterations ---"

        $allCalls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($mk in $master.Keys) {
            $p = $master[$mk]
            foreach ($c in $p.callTargets) {
                $cn = if ($c -is [string]) { $c } else { "$c" }
                if ($cn -and (Test-ValidCallTarget -Name $cn)) {
                    [void]$allCalls.Add($cn.ToUpperInvariant())
                }
            }
        }

        $newProgs = @($allCalls | Where-Object {
            -not $master.ContainsKey($_)
        } | Sort-Object -Unique)
        if ($newProgs.Count -eq 0) {
            Write-Output "  No new programs. Stopping."
            break
        }
        Write-Output "  Found $($newProgs.Count) new programs via CALL (validated against source index)."

        $localCount = 0; $ragCount = 0; $boundaryRejected = 0; $packageFiltered = 0
        $hitsBefore = $script:extractionCacheHits
        $idx = 0; $total = $newProgs.Count
        foreach ($prog in $newProgs) {
            $idx++
            if ($idx % 25 -eq 0 -or $idx -eq 1 -or $idx -eq $total) {
                Write-Output "    [$idx/$total] $prog"
            }
            if ($catalogPackages.Count -gt 0 -and -not $seedSet.Contains($prog) -and -not $catalogPackages.Contains($prog)) {
                $script:packageRejections[$prog] = 'call-expansion'
                $packageFiltered++
                continue
            }
            if (-not $programLayers.ContainsKey($prog)) { $programLayers[$prog] = 'call-expansion' }
            $entry = Extract-ProgramDependencies -Program $prog -CblIndex $cblIndex -FullIndex $fullIndex -UncertainFiles $uncertainFiles
            $boundary = Filter-SqlByBoundary -Program $prog -SqlOperations $entry.sqlOperations
            $entry.sqlOperations = $boundary.validOps
            if ($boundary.hadSqlOriginally -and $boundary.validOps.Count -eq 0) {
                $script:boundaryRejections[$prog] = @($boundary.strippedOps | ForEach-Object { $_.tableName } | Sort-Object -Unique)
                $boundaryRejected++
                continue
            }
            $master[$prog] = $entry
            if ($entry.sourceType -like 'local-*') { $localCount++ } else { $ragCount++ }
        }
        $phaseHits = $script:extractionCacheHits - $hitsBefore
        Write-Output "  Iteration $($iter): $localCount local  |  $ragCount RAG  |  $phaseHits cache hits  |  $boundaryRejected boundary-rejected  |  $packageFiltered package-rejected"
        Save-Master -Master $master -Path $MasterJson
    }

    if ($script:callValidationRejections.Count -gt 0) {
        Write-Output ''
        Write-Output "  Call target validation rejections (not found in source tree):"
        $script:callValidationRejections.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 30 | ForEach-Object {
            Write-Output "    $($_.Key): rejected $($_.Value) time(s)"
        }
    }

    if ($script:boundaryRejections.Count -gt 0) {
        Write-Output ''
        Write-Output "  Database boundary rejections ($($script:boundaryRejections.Count) programs excluded — tables outside $($profileDatabase)):"
        $script:boundaryRejections.GetEnumerator() | Sort-Object Key | Select-Object -First 50 | ForEach-Object {
            $foreignList = ($_.Value | Select-Object -First 5) -join ', '
            $more = if ($_.Value.Count -gt 5) { " (+$($_.Value.Count - 5) more)" } else { '' }
            Write-Output "    $($_.Key): $($foreignList)$($more)"
        }
        if ($script:boundaryRejections.Count -gt 50) {
            Write-Output "    ... and $($script:boundaryRejections.Count - 50) more"
        }
    }

    if ($script:packageRejections.Count -gt 0) {
        Write-Output ''
        Write-Output "  Package boundary rejections ($($script:packageRejections.Count) programs not bound in $($profileDatabase)):"
        $script:packageRejections.GetEnumerator() | Sort-Object Key | Select-Object -First 50 | ForEach-Object {
            Write-Output "    $($_.Key) (via $($_.Value))"
        }
        if ($script:packageRejections.Count -gt 50) {
            Write-Output "    ... and $($script:packageRejections.Count - 50) more"
        }
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 4 — DB2 table validation                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$db2Conn = $null

if ($SkipPhases -notcontains 4) {
    $effectiveDsn = if ($catalogDb2Alias) { $catalogDb2Alias } else { $Db2Dsn }

    if ($catalogQualified.Count -gt 0) {
        Write-Phase -Phase 4 -Title "Validate SQL tables against database catalog ($($profileDatabase), $($catalogQualified.Count) qualifiedNames)"

        $uniqueQualified = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($mk in $master.Keys) {
            foreach ($s in $master[$mk].sqlOperations) {
                if ($s.tableName -and $s.schema -and $s.schema.Length -gt 1 -and $s.schema -ne '(UNQUALIFIED)') {
                    [void]$uniqueQualified.Add("$($s.schema).$($s.tableName)")
                }
            }
        }
        Write-Output "  Unique qualified table refs in COBOL: $($uniqueQualified.get_Count())"
        Write-Output "  Validating against catalog: $($profileDatabase) ($($catalogQualified.Count) qualifiedNames)"

        $validated = 0; $notFound = 0
        $validationResults = [System.Collections.ArrayList]::new()
        foreach ($qn in $uniqueQualified) {
            $exists = $catalogQualified.Contains($qn)
            if ($exists) { $validated++ } else { $notFound++ }
            $parts = $qn.Split('.')
            [void]$validationResults.Add([ordered]@{
                qualifiedName = $qn
                tableName     = $parts[1]
                schema        = $parts[0]
                existsInDb2   = $exists
            })
        }
        Write-Output "  Validated: $validated  |  Not in catalog: $notFound"

        [ordered]@{
            title            = 'DB2 Table Validation'
            generated        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            database         = $profileDatabase
            db2Alias         = $catalogDb2Alias
            source           = 'catalog-file'
            totalQualified   = $uniqueQualified.get_Count()
            validated        = $validated
            notFound         = $notFound
            tables           = @($validationResults | Sort-Object { $_['qualifiedName'] })
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Db2ValidationJson -Encoding UTF8
        Write-Output "  Report: $Db2ValidationJson"

        # Cache table metadata using the profile's DB2 alias
        if ($script:analysisCommonEnabled -and $effectiveDsn) {
            try {
                $db2Conn = New-Object System.Data.Odbc.OdbcConnection("DSN=$effectiveDsn")
                $db2Conn.Open()
                Write-Output "  Connected via ODBC DSN=$($effectiveDsn) for metadata caching"
                Invoke-BulkTableMetadataFetch -DatabaseName $effectiveDsn
                $validatedTableNames = @($validationResults | Where-Object { $_.existsInDb2 } | ForEach-Object { $_.tableName })
                Ensure-TableMetadataCached -TableNames $validatedTableNames
            } catch {
                Write-Warning "ODBC metadata fetch failed (DSN=$($effectiveDsn)): $($_.Exception.Message)"
            } finally {
                if ($db2Conn -and $db2Conn.State -eq 'Open') { $db2Conn.Close() }
                if ($db2Conn) { $db2Conn.Dispose(); $db2Conn = $null }
            }
        }

    } else {
        Write-Output ''
        Write-Output '  Phase 4 skipped (no catalog file in AnalysisStatic/Databases).'
    }
} else {
    Write-Output ''
    Write-Output '  Phase 4 skipped (phase excluded).'
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 5 — Discover programs via shared SQL tables (RAG)                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if ($SkipPhases -notcontains 5) {
    Write-Phase -Phase 5 -Title 'Discover new programs via shared SQL tables'

    # Only expand from tables found in SEED programs (Level 0).
    # Tables from CALL-expanded infrastructure programs (GMFTRAP, GMAFELL, etc.)
    # are shared across the entire codebase and would cause massive fan-out.
    $seedTableSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($sp in $seedPrograms) {
        $spKey = $sp.ToUpperInvariant()
        if ($master.ContainsKey($spKey)) {
            foreach ($s in $master[$spKey].sqlOperations) {
                if ($s.tableName) { [void]$seedTableSet.Add($s.tableName) }
            }
        }
    }

    $allTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($mk in $master.Keys) {
        foreach ($s in $master[$mk].sqlOperations) {
            if ($s.tableName) { [void]$allTables.Add($s.tableName) }
        }
    }

    $tableList = @($seedTableSet) | Sort-Object
    Write-Output "  Seed tables: $($seedTableSet.Count) (from $($seedPrograms.Count) seeds)"
    Write-Output "  Total tables across all programs: $($allTables.Count) (infrastructure tables excluded from RAG expansion)"
    Write-Output "  Querying RAG for $($tableList.Count) seed tables..."

    $tableDiscoveries = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $tIdx = 0; $tTotal = $tableList.Count
    foreach ($table in $tableList) {
        $tIdx++
        if ($tIdx % 50 -eq 0 -or $tIdx -eq 1 -or $tIdx -eq $tTotal) {
            Write-Output "    [$tIdx/$tTotal] $table"
        }
        $result = Invoke-Rag -Query "EXEC SQL SELECT FROM $table" -N $RagTableResults
        if (-not $result) { continue }

        foreach ($m in $RagSourcePattern.Matches($result)) {
            $pName = $m.Groups[1].Value.ToUpperInvariant()
            if ($master.ContainsKey($pName) -or $pName.Length -lt 3) { continue }
            if (Test-ExcludeCall -Name $pName) { continue }
            if ($validProgramNames.Count -gt 0 -and -not $validProgramNames.Contains($pName)) { continue }
            if ($catalogPackages.Count -gt 0 -and -not $seedSet.Contains($pName) -and -not $catalogPackages.Contains($pName)) {
                if (-not $script:packageRejections.ContainsKey($pName)) {
                    $script:packageRejections[$pName] = 'table-reference'
                }
                continue
            }
            if (-not $tableDiscoveries.ContainsKey($pName)) {
                $tableDiscoveries[$pName] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            }
            [void]$tableDiscoveries[$pName].Add($table)
        }
    }

    $tableNewProgs = @($tableDiscoveries.Keys | Sort-Object)
    Write-Output "  Discovered $($tableNewProgs.Count) new programs via seed table references (validated against source index)."

    foreach ($np in $tableNewProgs) {
        if (-not $programLayers.ContainsKey($np)) { $programLayers[$np] = 'table-reference' }
    }

    # ╔══════════════════════════════════════════════════════════════════════════╗
    # ║  PHASE 6 — Extract table-discovered programs                            ║
    # ╚══════════════════════════════════════════════════════════════════════════╝

    if ($tableNewProgs.Count -gt 0) {
        Write-Phase -Phase 6 -Title "Extract $($tableNewProgs.Count) table-discovered programs"

        $localCount = 0; $ragCount = 0; $boundaryRejected = 0
        $hitsBefore = $script:extractionCacheHits
        $idx = 0; $total = $tableNewProgs.Count
        foreach ($prog in $tableNewProgs) {
            $idx++
            if ($idx % 25 -eq 0 -or $idx -eq 1 -or $idx -eq $total) {
                Write-Output "  [$idx/$total] $prog"
            }
            $entry = Extract-ProgramDependencies -Program $prog -CblIndex $cblIndex -FullIndex $fullIndex -UncertainFiles $uncertainFiles
            $boundary = Filter-SqlByBoundary -Program $prog -SqlOperations $entry.sqlOperations
            $entry.sqlOperations = $boundary.validOps
            if ($boundary.hadSqlOriginally -and $boundary.validOps.Count -eq 0) {
                $script:boundaryRejections[$prog] = @($boundary.strippedOps | ForEach-Object { $_.tableName } | Sort-Object -Unique)
                $boundaryRejected++
                continue
            }
            $master[$prog] = $entry
            if ($entry.sourceType -like 'local-*') { $localCount++ } else { $ragCount++ }
        }
        $phaseHits = $script:extractionCacheHits - $hitsBefore
        Write-Output "  Done: $localCount local  |  $ragCount RAG  |  $phaseHits cache hits  |  $boundaryRejected boundary-rejected"
        Save-Master -Master $master -Path $MasterJson
    }

    # ── Cache metadata for newly discovered tables from Phase 5/6 ──
    if ($script:analysisCommonEnabled -and $script:db2MetadataMap.Count -gt 0) {
        $newTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($mk in $master.Keys) {
            foreach ($s in $master[$mk].sqlOperations) {
                if ($s.tableName -and $db2TableSet.Contains($s.tableName)) {
                    [void]$newTables.Add($s.tableName)
                }
            }
        }
        Write-Output "  Checking table metadata cache for $($newTables.Count) tables after Phase 5-6..."
        Ensure-TableMetadataCached -TableNames @($newTables)
    }
} else {
    Write-Output ''
    Write-Output '  Phase 5-6 skipped.'
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DATABASE BOUNDARY SWEEP — re-verify all programs with qualifiedName filter║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if ($catalogQualified.Count -gt 0 -or $catalogPackages.Count -gt 0) {
    $boundaryRemoved = 0
    $packageRemoved  = 0

    # Package boundary: remove non-seed programs not bound in the target DB
    if ($catalogPackages.Count -gt 0) {
        foreach ($key in @($master.Keys)) {
            if ($seedSet.Contains($key)) { continue }
            if (-not $catalogPackages.Contains($key)) {
                $master.Remove($key)
                $packageRemoved++
                if (-not $script:packageRejections.ContainsKey($key)) {
                    $script:packageRejections[$key] = 'final-sweep'
                }
            }
        }
        if ($packageRemoved -gt 0) {
            Write-Output ''
            Write-Output "  Package boundary sweep: removed $packageRemoved programs not bound in $($profileDatabase)"
            Save-Master -Master $master -Path $MasterJson
        }
    }

    # Table boundary: remove non-seed programs whose SQL all falls outside the catalog
    foreach ($key in @($master.Keys)) {
        if ($seedSet.Contains($key)) { continue }
        $entry = $master[$key]
        $boundary = Filter-SqlByBoundary -Program $key -SqlOperations $entry.sqlOperations
        $entry.sqlOperations = $boundary.validOps
        if ($boundary.hadSqlOriginally -and $boundary.validOps.Count -eq 0) {
            $master.Remove($key)
            $boundaryRemoved++
        }
    }
    if ($boundaryRemoved -gt 0) {
        Write-Output ''
        Write-Output "  Table boundary sweep: removed $boundaryRemoved programs with all SQL outside $($profileDatabase)"
        Save-Master -Master $master -Path $MasterJson
    }

    # Prune call edges to removed programs, then remove orphans via reverse-call index
    $orphanedRemoved = 0
    $changed = $true
    while ($changed) {
        $changed = $false

        foreach ($key in @($master.Keys)) {
            $entry = $master[$key]
            if (-not $entry.callTargets -or $entry.callTargets.Count -eq 0) { continue }
            $entry.callTargets = @($entry.callTargets | Where-Object {
                $cn = if ($_ -is [string]) { $_ } else { "$_" }
                $master.ContainsKey($cn.ToUpperInvariant())
            })
        }

        $calledBy = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($mk in $master.Keys) {
            $ct = $master[$mk].callTargets
            if (-not $ct) { continue }
            foreach ($c in $ct) {
                $cn = if ($c -is [string]) { $c } else { "$c" }
                $upper = $cn.ToUpperInvariant()
                if (-not $calledBy.ContainsKey($upper)) {
                    $calledBy[$upper] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                }
                [void]$calledBy[$upper].Add($mk)
            }
        }

        foreach ($key in @($master.Keys)) {
            if ($seedSet.Contains($key)) { continue }
            $isCalledByAnyone = $calledBy.ContainsKey($key) -and $calledBy[$key].Count -gt 0
            $hasSqlInCatalog = $false
            if ($master[$key].sqlOperations -and $master[$key].sqlOperations.Count -gt 0) {
                $hasSqlInCatalog = $true
            }
            if (-not $isCalledByAnyone -and -not $hasSqlInCatalog) {
                $master.Remove($key)
                $orphanedRemoved++
                $changed = $true
            }
        }
    }
    if ($orphanedRemoved -gt 0) {
        Write-Output "  Orphan cleanup: removed $orphanedRemoved programs no longer reachable from seeds"
        Save-Master -Master $master -Path $MasterJson
    }

    Write-Output "  Programs after boundary filter: $($master.Count)"
    Write-Output ''
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 7 — Source verification & classification                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if ($SkipPhases -notcontains 7) {
    Write-Phase -Phase 7 -Title 'Source verification and classification'

    $programList = @($master.Keys | Sort-Object)
    $cblFound       = [System.Collections.ArrayList]::new()
    $uncertainFound = [System.Collections.ArrayList]::new()
    $uvMatchFound   = [System.Collections.ArrayList]::new()
    $otherTypeFound = [System.Collections.ArrayList]::new()
    $noiseFiltered  = [System.Collections.ArrayList]::new()
    $trulyMissing   = [System.Collections.ArrayList]::new()

    foreach ($prog in $programList) {
        $progNorm = $prog.ToUpperInvariant()
        if ($cblIndex.ContainsKey($progNorm)) {
            [void]$cblFound.Add([ordered]@{ program = $progNorm; fileType = 'CBL'; path = $cblIndex[$progNorm] })
        } else {
            $uvSwapped = $progNorm -creplace 'U','V'
            if ($uvSwapped -ne $progNorm -and $cblIndex.ContainsKey($uvSwapped)) {
                [void]$uvMatchFound.Add([ordered]@{
                    program = $progNorm; actualName = $uvSwapped
                    fileType = 'CBL'; path = $cblIndex[$uvSwapped]; matchType = 'U_to_V'
                })
            } else {
                $uncertainMatch = $null
                foreach ($uf in $uncertainFiles) {
                    if ($uf.baseName.Contains($progNorm)) {
                        if ($uf.extension -ieq '.CBL') {
                            $uncertainMatch = $uf
                            break
                        }
                        if (-not $uncertainMatch) { $uncertainMatch = $uf }
                    }
                }
                if ($uncertainMatch) {
                    [void]$uncertainFound.Add([ordered]@{
                        program = $progNorm
                        fileType = $uncertainMatch.extension.TrimStart('.').ToUpperInvariant()
                        path = $uncertainMatch.path
                        matchType = 'basename-contains-program'
                    })
                } elseif ($fullIndex.ContainsKey($progNorm)) {
                    $entry = $fullIndex[$progNorm]
                    [void]$otherTypeFound.Add([ordered]@{
                        program = $progNorm; fileType = $entry.ext.TrimStart('.').ToUpperInvariant(); path = $entry.path
                    })
                } elseif ($NoisePrograms.Contains($progNorm)) {
                    [void]$noiseFiltered.Add([ordered]@{ program = $progNorm; reason = 'noise' })
                } else {
                    [void]$trulyMissing.Add($progNorm)
                }
            }
        }
    }

    $totalFound = $cblFound.Count + $uncertainFound.Count + $uvMatchFound.Count + $otherTypeFound.Count
    $realPrograms = $programList.Count - $noiseFiltered.Count
    $pctFound = if ($realPrograms -gt 0) { [math]::Round(100 * $totalFound / $realPrograms, 1) } else { 0 }

    # Copy element verification
    $copyFound = [System.Collections.ArrayList]::new()
    $copyMissing = [System.Collections.ArrayList]::new()
    $allCopyNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($mk in $master.Keys) {
        foreach ($c in $master[$mk].copyElements) {
            [void]$allCopyNames.Add($c.name)
        }
    }
    foreach ($ceName in $allCopyNames) {
        $ceNorm = $ceName.ToUpperInvariant()
        $ceFound = $false
        if ($copyIndex.ContainsKey($ceNorm)) { $ceFound = $true }
        else {
            $nameNoExt = $ceNorm -replace '\.\w+$', ''
            if ($copyIndex.ContainsKey($nameNoExt)) { $ceFound = $true }
        }
        if ($ceFound) { [void]$copyFound.Add($ceNorm) }
        else { [void]$copyMissing.Add($ceNorm) }
    }
    $pctCopy = if ($allCopyNames.get_Count() -gt 0) { [math]::Round(100 * $copyFound.Count / $allCopyNames.get_Count(), 1) } else { 0 }

    Write-Output "  Programs: $totalFound / $realPrograms real ($($pctFound)%)"
    Write-Output "    CBL exact: $($cblFound.Count) | Uncertain: $($uncertainFound.Count) | U/V fuzzy: $($uvMatchFound.Count) | Other: $($otherTypeFound.Count)"
    Write-Output "    Noise: $($noiseFiltered.Count) | Truly missing: $($trulyMissing.Count)"
    Write-Output "  Copy elements: $($copyFound.Count) / $($allCopyNames.get_Count()) ($($pctCopy)%)"

    # On-disk-only CBLs
    $knownSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $programList) { [void]$knownSet.Add($p.ToUpperInvariant()) }
    foreach ($uv in $uvMatchFound) { [void]$knownSet.Add($uv.actualName) }
    $onDiskOnly = @($cblIndex.Keys | Where-Object { -not $knownSet.Contains($_) } | Sort-Object)

    [ordered]@{
        title = 'Source Availability Verification'
        generated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        sourceRoot = $SourceRoot
        summary = [ordered]@{
            totalFilesOnDisk     = $allLocalFiles.Count
            cblOnDisk            = $cblIndex.Count
            programsInMaster     = $programList.Count
            programsCblFound     = $cblFound.Count
            programsUncertainFound = $uncertainFound.Count
            programsUvFuzzyMatch = $uvMatchFound.Count
            programsOtherType    = $otherTypeFound.Count
            programsTotalFound   = $totalFound
            programsNoise        = $noiseFiltered.Count
            programsTrulyMissing = $trulyMissing.Count
            programFoundPct      = $pctFound
            copyTotal            = $allCopyNames.get_Count()
            copyFound            = $copyFound.Count
            copyMissing          = $copyMissing.Count
            copyFoundPct         = $pctCopy
            onDiskNotInMaster    = $onDiskOnly.Count
        }
        programsCblFound      = @($cblFound)
        programsUncertainFound = @($uncertainFound)
        programsUvFuzzyMatch  = @($uvMatchFound)
        programsOtherType     = @($otherTypeFound)
        programsNoiseFiltered = @($noiseFiltered)
        programsTrulyMissing  = @($trulyMissing | Sort-Object)
        copyMissing           = @($copyMissing | Sort-Object)
        onDiskNotInMaster     = @($onDiskOnly)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $VerifyJson -Encoding UTF8
    Write-Output "  Report: $VerifyJson"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  FILTER STANDARD COBOL PROGRAMS (RAG + Ollama)                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$nullSourceProgs = @($master.Keys | Where-Object { $null -eq $master[$_].sourcePath } | Sort-Object)
if ($nullSourceProgs.Count -gt 0) {
    Write-Output ''
    Write-Output ('=' * 72)
    Write-Output '  FILTER — Standard COBOL program detection (RAG + Ollama)'
    Write-Output ('=' * 72)
    Write-Output "  Programs with null sourcePath: $($nullSourceProgs.Count)"

    $removed  = [System.Collections.ArrayList]::new()
    $retained = [System.Collections.ArrayList]::new()
    $ollamaReachable = $true

    Initialize-AutoDocIndex
    $autoDocSkipCount = 0

    foreach ($prog in $nullSourceProgs) {
        Write-Output "    Checking: $prog"

        if (Test-ProgramInAutoDocIndex -ProgramName $prog) {
            Write-Output "      -> Application program (AutoDocJson index hit, skipping Ollama)"
            $null = $retained.Add([PSCustomObject]@{ program = $prog; ragEvidence = 'AutoDocJson index'; ollamaVerdict = 'AUTODOC_KNOWN' })
            $autoDocSkipCount++
            continue
        }

        $result = Test-StandardCobolProgram -ProgramName $prog
        if ($result.verdict -eq 'OLLAMA_UNAVAILABLE') {
            Write-Warning "  Ollama unreachable — skipping remaining standard COBOL checks"
            $ollamaReachable = $false
            $null = $retained.Add([PSCustomObject]@{ program = $prog; ragEvidence = $result.evidence; ollamaVerdict = $result.verdict })
            break
        }
        if ($result.isStandard) {
            Write-Output "      -> STANDARD COBOL (removing)"
            $null = $removed.Add([PSCustomObject]@{ program = $prog; ragEvidence = $result.evidence; ollamaVerdict = $result.verdict })
        } else {
            Write-Output "      -> Application-specific (keeping)"
            $null = $retained.Add([PSCustomObject]@{ program = $prog; ragEvidence = $result.evidence; ollamaVerdict = $result.verdict })
        }
    }

    if ($autoDocSkipCount -gt 0) {
        Write-Output "  AutoDocJson shortcut: $($autoDocSkipCount) programs identified without Ollama"
    }

    if (-not $ollamaReachable) {
        foreach ($remaining in ($nullSourceProgs | Where-Object { $_ -ne $prog -and ($removed.program + $retained.program) -notcontains $_ })) {
            $null = $retained.Add([PSCustomObject]@{ program = $remaining; ragEvidence = ''; ollamaVerdict = 'SKIPPED' })
        }
    }

    if ($removed.Count -gt 0) {
        Write-Output "  Removing $($removed.Count) standard COBOL program(s) from master..."
        foreach ($entry in $removed) {
            $master.Remove($entry.program)
        }
        foreach ($mk in @($master.Keys)) {
            $m = $master[$mk]
            if ($m.callTargets) {
                $m.callTargets = @($m.callTargets | Where-Object { $removed.program -notcontains $_ })
            }
        }
        Save-Master -Master $master -Path $MasterJson
        Write-Output "  Saved updated master: $MasterJson"
    }

    [PSCustomObject]@{
        title        = 'Standard COBOL Program Filter'
        generated    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        totalChecked = $nullSourceProgs.Count
        totalRemoved = $removed.Count
        totalRetained = $retained.Count
        removed      = @($removed)
        retained     = @($retained)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StdCobolJson -Encoding UTF8
    Write-Output "  Filter report: $StdCobolJson"
} else {
    Write-Output ''
    Write-Output '  No programs with null sourcePath — skipping standard COBOL filter'
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RULE-BASED PROGRAM CLASSIFICATION                                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if (-not $SkipClassification) {
    Write-Output ''
    Write-Output '  Classifying programs by naming rules and copybook evidence ...'
    $classResults = [System.Collections.ArrayList]::new()
    foreach ($key in @($master.Keys)) {
        $entry = $master[$key]
        $result = Classify-ProgramByRules -ProgramName $entry.program -MasterEntry $entry
        $master[$key].classification           = $result.classification
        $master[$key].classificationConfidence = $result.classificationConfidence
        $master[$key].classificationEvidence   = $result.classificationEvidence

        [void]$classResults.Add([ordered]@{
            program    = $entry.program
            classification = $result.classification
            confidence = $result.classificationConfidence
            evidence   = $result.classificationEvidence
        })
    }

    $classCounts = $classResults | Group-Object -Property { $_.classification } | Sort-Object Name
    foreach ($cg in $classCounts) {
        Write-Output "    $($cg.Name): $($cg.Count)"
    }

    $classifiedJsonName = "classified_$($areasSuffix).json"
    $classifiedJsonPath = Join-Path $configDir $classifiedJsonName
    [ordered]@{
        title    = "Rule-Based Program Classification"
        areas    = @($distinctAreas)
        total    = $classResults.Count
        programs = @($classResults)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $classifiedJsonPath -Encoding UTF8
    Write-Output "  Classification output: $classifiedJsonPath"

    Save-Master -Master $master -Path $MasterJson
} else {
    Write-Output ''
    Write-Output '  Skipping rule-based classification (SkipClassification flag set)'
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RESOLVE EXCLUSION CANDIDATES (tag-only, no filtering)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$candidateReasons = [System.Collections.Generic.Dictionary[string, System.Collections.ArrayList]]::new([StringComparer]::OrdinalIgnoreCase)

if ($excludeTableRules.Count -gt 0) {
    Write-Output ''
    Write-Output '  Resolving table-based exclusion candidates...'

    foreach ($rule in $excludeTableRules) {
        $ruleSchema = $rule.schema.ToUpperInvariant()
        $ruleTable  = $rule.tableName.ToUpperInvariant()
        $ruleOps    = @($rule.operations | ForEach-Object { $_.ToUpperInvariant() })

        foreach ($mk in @($master.Keys)) {
            $p = $master[$mk]
            foreach ($s in $p.sqlOperations) {
                $sSchema = $s.schema.ToUpperInvariant()
                $sTable  = $s.tableName.ToUpperInvariant()
                $sOp     = $s.operation.ToUpperInvariant()

                $schemaMatch = ($ruleSchema -eq '*' -or $sSchema -eq $ruleSchema)
                $tableMatch  = ($sTable -eq $ruleTable)
                $opMatch     = ($ruleOps -contains '*' -or $ruleOps -contains $sOp)

                if ($schemaMatch -and $tableMatch -and $opMatch) {
                    $progKey = $p.program.ToUpperInvariant()
                    [void]$candidatePrograms.Add($progKey)
                    if (-not $candidateReasons.ContainsKey($progKey)) {
                        $candidateReasons[$progKey] = [System.Collections.ArrayList]::new()
                    }
                    $ruleStr = "$($ruleSchema).$($ruleTable) $($ruleOps -join ',')"
                    $alreadyHasRule = $false
                    foreach ($existing in $candidateReasons[$progKey]) {
                        if ($existing['rule'] -eq $ruleStr) { $alreadyHasRule = $true; break }
                    }
                    if (-not $alreadyHasRule) {
                        [void]$candidateReasons[$progKey].Add([ordered]@{
                            reason = 'table-rule'
                            rule   = $ruleStr
                            detail = $rule.reason
                        })
                        Write-Output "    Candidate: $($p.program) ($($ruleSchema).$($ruleTable) $($sOp))"
                    }
                }
            }
        }
    }
}

if ($excludeData -and $excludeData.excludePrograms) {
    foreach ($ep in $excludeData.excludePrograms) {
        if ($ep.program) {
            $progKey = $ep.program.ToUpperInvariant()
            [void]$candidatePrograms.Add($progKey)
            if (-not $candidateReasons.ContainsKey($progKey)) {
                $candidateReasons[$progKey] = [System.Collections.ArrayList]::new()
            }
            [void]$candidateReasons[$progKey].Add([ordered]@{
                reason = 'explicit'
                rule   = 'excludePrograms'
                detail = $ep.reason
            })
        }
    }
}

if ($candidatePrograms.get_Count() -gt 0) {
    Write-Output "  Exclusion candidates tagged: $($candidatePrograms.get_Count())"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PHASE 8 — Produce cross-reference output JSONs                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

Write-Phase -Phase 8 -Title 'Produce cross-reference output JSONs'

$generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Write applied_exclusions.json (candidate tagging results)
if ($excludeData) {
    $candidateList = [System.Collections.ArrayList]::new()
    foreach ($progKey in ($candidatePrograms | Sort-Object)) {
        $reasons = [System.Collections.ArrayList]::new()
        if ($candidateReasons.ContainsKey($progKey)) {
            foreach ($r in $candidateReasons[$progKey]) { [void]$reasons.Add($r) }
        }
        [void]$candidateList.Add([ordered]@{
            program = $progKey
            reasons = @($reasons)
        })
    }
    [ordered]@{
        title                    = 'Exclusion Candidates'
        generated                = $generated
        description              = 'Programs tagged as potential exclusion candidates — NOT removed from outputs'
        exclusionConfig          = $excludeData.title
        totalCandidates          = $candidatePrograms.get_Count()
        candidateProgramSet      = @($candidatePrograms | Sort-Object)
        candidates               = @($candidateList)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $AppliedExclJson -Encoding UTF8
    Write-Output "  applied_exclusions.json: $($candidatePrograms.get_Count()) programs tagged as candidates"
}

# ── 8a. all_total_programs.json ──
Write-Output '  Building all_total_programs.json ...'
$progEntries = [System.Collections.ArrayList]::new()
$sortedKeys = @($master.Keys | Sort-Object)
foreach ($pKey in $sortedKeys) {
    $p = $master[$pKey]
    $layer = if ($programLayers.ContainsKey($p.program)) { $programLayers[$p.program] } else { 'unknown' }
    $origEntry = $allJson.entries | Where-Object { $_.program -eq $p.program } | Select-Object -First 1
    $isCandidate = $candidatePrograms.Contains($pKey)
    $reasons = [System.Collections.ArrayList]::new()
    if ($isCandidate -and $candidateReasons.ContainsKey($pKey)) {
        foreach ($r in $candidateReasons[$pKey]) { [void]$reasons.Add($r) }
    }
    $cobdok = if ($cobdokIndex.ContainsKey($pKey)) { $cobdokIndex[$pKey] } else { $null }
    $isInfra = $p.program -match '^(GMA|GMF|GMD|GMV)'
    [void]$progEntries.Add([ordered]@{
        program                  = $p.program
        filetype                 = 'cbl'
        source                   = $layer
        sourceType               = $p.sourceType
        isSharedInfrastructure   = $isInfra
        type                     = if ($origEntry) { $origEntry.type } else { $null }
        menuChoice               = if ($origEntry) { $origEntry.menuChoice } else { $null }
        area                     = if ($origEntry) { $origEntry.area } else { $null }
        description              = if ($origEntry) { $origEntry.description } else { $null }
        descriptionNorwegian     = if ($origEntry) { $origEntry.descriptionNorwegian } else { $null }
        cobdokSystem             = if ($cobdok) { $cobdok['cobdokSystem'] } else { $null }
        cobdokDelsystem          = if ($cobdok) { $cobdok['delsystem'] } else { $null }
        cobdokDescription        = if ($cobdok) { $cobdok['description'] } else { $null }
        isDeprecated             = if ($cobdok) { $cobdok['isDeprecated'] } else { $false }
        copyCount                = @($p.copyElements).Count
        sqlOpCount               = @($p.sqlOperations).Count
        callCount                = @($p.callTargets).Count
        fileIOCount              = @($p.fileIO).Count
        classification           = $p.classification
        classificationConfidence = $p.classificationConfidence
        classificationEvidence   = $p.classificationEvidence
        isExclusionCandidate     = $isCandidate
        exclusionCandidateReasons = @($reasons)
    })
}
$countOrig  = @($progEntries | Where-Object { $_['source'] -eq 'original' }).Count
$countCall  = @($progEntries | Where-Object { $_['source'] -eq 'call-expansion' }).Count
$countTable = @($progEntries | Where-Object { $_['source'] -eq 'table-reference' }).Count
$countLocal      = @($progEntries | Where-Object { $_['sourceType'] -like 'local-*' }).Count
$countRag        = @($progEntries | Where-Object { $_['sourceType'] -eq 'rag' }).Count
$countDeprecated = @($progEntries | Where-Object { $_['isDeprecated'] -eq $true }).Count
$countInfra      = @($progEntries | Where-Object { $_['isSharedInfrastructure'] -eq $true }).Count

[ordered]@{
    title         = 'All Programs (Total)'
    generated     = $generated
    totalPrograms = $progEntries.Count
    breakdown     = [ordered]@{
        original       = $countOrig
        callExpansion  = $countCall
        tableReference = $countTable
    }
    dataSources       = [ordered]@{ localSource = $countLocal; rag = $countRag }
    deprecatedCount          = $countDeprecated
    sharedInfrastructureCount = $countInfra
    programs                  = @($progEntries)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $TotalProgsJson -Encoding UTF8
Write-Output "    -> $($progEntries.Count) programs ($countDeprecated deprecated, $countInfra shared infrastructure)"

# ── 8b. all_sql_tables.json ──
Write-Output '  Building all_sql_tables.json ...'
$sqlEntries = [System.Collections.ArrayList]::new()
$sqlUnique = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($mk in $master.Keys) {
    $p = $master[$mk]
    foreach ($s in $p.sqlOperations) {
        $key = "$($p.program)|$($s.schema)|$($s.tableName)|$($s.operation)"
        if ($sqlUnique.Contains($key)) { continue }
        [void]$sqlUnique.Add($key)
        $qnCheck = if ($s.schema -and $s.schema.Length -gt 1 -and $s.schema -ne '(UNQUALIFIED)') {
            "$($s.schema).$($s.tableName)"
        } else { $null }
        [void]$sqlEntries.Add([ordered]@{
            program              = $p.program
            schema               = $s.schema
            tableName            = $s.tableName
            qualifiedName        = $qnCheck
            operation            = $s.operation
            existsInDb2          = if ($catalogQualified.Count -gt 0 -and $qnCheck) { $catalogQualified.Contains($qnCheck) } else { $null }
            isExclusionCandidate = $candidatePrograms.Contains($mk)
        })
    }
}
$uTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($se in $sqlEntries) {
    $tk = if ($se['schema'] -eq '(unqualified)') { $se['tableName'] } else { "$($se['schema']).$($se['tableName'])" }
    [void]$uTables.Add($tk)
}
[ordered]@{
    title           = 'All SQL Table References'
    generated       = $generated
    totalReferences = $sqlEntries.Count
    uniqueTables    = $uTables.get_Count()
    db2Validated    = if ($catalogQualified.Count -gt 0) { $true } else { $false }
    tableReferences = @($sqlEntries | Sort-Object { $_['tableName'] }, { $_['program'] })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SqlTablesJson -Encoding UTF8
Write-Output "    -> $($sqlEntries.Count) refs, $($uTables.get_Count()) unique tables"

# ── 8c. all_copy_elements.json ──
Write-Output '  Building all_copy_elements.json ...'
$copyMap = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($mk in $master.Keys) {
    $p = $master[$mk]
    foreach ($c in $p.copyElements) {
        if (-not $copyMap.ContainsKey($c.name)) {
            $localPath = $null
            if ($copyIndex.ContainsKey($c.name)) { $localPath = $copyIndex[$c.name] }
            else {
                $nameNoExt = $c.name -replace '\.\w+$', ''
                if ($copyIndex.ContainsKey($nameNoExt)) { $localPath = $copyIndex[$nameNoExt] }
            }
            $copyMap[$c.name] = [ordered]@{
                name                = $c.name
                type                = $c.type
                localPath           = $localPath
                usedBy              = [System.Collections.Generic.List[string]]::new()
                usedByCandidateList = [System.Collections.Generic.List[string]]::new()
            }
        }
        $copyMap[$c.name].usedBy.Add($p.program)
        if ($candidatePrograms.Contains($mk)) {
            $copyMap[$c.name].usedByCandidateList.Add($p.program)
        }
    }
}
$copyList = [System.Collections.ArrayList]::new()
foreach ($ck in ($copyMap.Keys | Sort-Object)) {
    $ce = $copyMap[$ck]
    $ce.usedBy = @($ce.usedBy | Sort-Object -Unique)
    $ce['usedByCandidateCount'] = @($ce.usedByCandidateList | Sort-Object -Unique).Count
    $ce.Remove('usedByCandidateList')
    [void]$copyList.Add($ce)
}
[ordered]@{
    title             = 'All COPY Elements'
    generated         = $generated
    totalCopyElements = $copyList.Count
    copyElements      = @($copyList)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $CopyElementsJson -Encoding UTF8
Write-Output "    -> $($copyList.Count) unique copy elements"

# ── 8d. all_call_graph.json ──
Write-Output '  Building all_call_graph.json ...'
$callEdges = [System.Collections.ArrayList]::new()
$callUnique = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($mk in $master.Keys) {
    $p = $master[$mk]
    foreach ($c in $p.callTargets) {
        $cn = if ($c -is [string]) { $c } else { "$c" }
        $key = "$($p.program)->$cn"
        if ($callUnique.Contains($key)) { continue }
        [void]$callUnique.Add($key)
        [void]$callEdges.Add([ordered]@{
            caller               = $p.program
            callee               = $cn.ToUpperInvariant()
            isExclusionCandidate = $candidatePrograms.Contains($mk)
        })
    }
}
[ordered]@{
    title      = 'COBOL Call Graph'
    generated  = $generated
    totalEdges = $callEdges.Count
    edges      = @($callEdges | Sort-Object { $_['caller'] }, { $_['callee'] })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $CallGraphJson -Encoding UTF8
Write-Output "    -> $($callEdges.Count) edges"

# ── 8e. all_file_io.json ──
Write-Output '  Building all_file_io.json ...'
$fioEntries = [System.Collections.ArrayList]::new()
$fioUnique = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($mk in $master.Keys) {
    $p = $master[$mk]
    foreach ($f in $p.fileIO) {
        $key = "$($p.program)|$($f.logicalName)"
        if ($fioUnique.Contains($key)) { continue }
        [void]$fioUnique.Add($key)
        [void]$fioEntries.Add([ordered]@{
            program              = $p.program
            logicalName          = $f.logicalName
            physicalName         = $f.physicalName
            path                 = $f.path
            fullPath             = $f.fullPath
            assignType           = $f.assignType
            operations           = @($f.operations)
            resolvedPath         = $f.resolvedPath
            filenamePattern      = $f.filenamePattern
            filenameDescription  = $f.filenameDescription
            isExclusionCandidate = $candidatePrograms.Contains($mk)
        })
    }
}
$fioUniqueFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($f in $fioEntries) {
    $fn = if ($f['fullPath']) { $f['fullPath'] } else { $f['physicalName'] }
    if ($fn) { [void]$fioUniqueFiles.Add($fn) }
}
[ordered]@{
    title               = 'COBOL File I/O Map'
    generated           = $generated
    defaultPath         = $DefaultFilePath
    totalFileReferences = $fioEntries.Count
    uniqueFiles         = $fioUniqueFiles.get_Count()
    fileReferences      = @($fioEntries | Sort-Object { $_['program'] }, { $_['logicalName'] })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $FileIOJson -Encoding UTF8
Write-Output "    -> $($fioEntries.Count) refs, $($fioUniqueFiles.get_Count()) unique files"

# ── 8f. Modern CamelCase Naming (tables, columns, programs) ──
if ($script:namingEnabled -and $script:analysisCommonEnabled) {
    Write-Output ''
    Write-Output '  ╔═══════════════════════════════════════════════════════════════╗'
    Write-Output '  ║  Phase 8f — Modern CamelCase Naming + FK Inference           ║'
    Write-Output '  ╚═══════════════════════════════════════════════════════════════╝'

    # ── Build cross-table context ──
    Write-Output '  Building cross-table context...'

    $script:columnIndex = @{}
    $script:tableUsageMap = @{}
    $script:calledByMap = @{}

    $sqltableFiles = @(Get-ChildItem -LiteralPath $script:analysisCommonObjectsDir -Filter '*.sqltable.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $sqltableFiles) {
        try {
            $tData = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $tName = $tData.tableName
            if ($tData.db2Metadata -and $tData.db2Metadata.columns) {
                foreach ($col in $tData.db2Metadata.columns) {
                    $cName = "$($col.name)"
                    if (-not $script:columnIndex.ContainsKey($cName)) {
                        $script:columnIndex[$cName] = [System.Collections.ArrayList]::new()
                    }
                    [void]$script:columnIndex[$cName].Add($tName)
                }
            }
        } catch { }
    }
    Write-Output "    Column index: $($script:columnIndex.Count) unique column names across $($sqltableFiles.Count) tables"

    foreach ($mk in $master.Keys) {
        $p = $master[$mk]
        foreach ($s in $p.sqlOperations) {
            $tKey = $s.tableName.ToUpperInvariant()
            if (-not $script:tableUsageMap.ContainsKey($tKey)) {
                $script:tableUsageMap[$tKey] = [System.Collections.ArrayList]::new()
            }
            [void]$script:tableUsageMap[$tKey].Add([ordered]@{ program = $p.program; operation = $s.operation })
        }
        foreach ($ct in $p.callTargets) {
            $ctKey = $ct.ToUpperInvariant()
            if (-not $script:calledByMap.ContainsKey($ctKey)) {
                $script:calledByMap[$ctKey] = [System.Collections.ArrayList]::new()
            }
            [void]$script:calledByMap[$ctKey].Add($p.program)
        }
    }
    Write-Output "    Table usage map: $($script:tableUsageMap.Count) tables | CalledBy map: $($script:calledByMap.Count) programs"

    # ── Table + Column Naming ──
    $tableNamingHits = 0; $tableNamingNew = 0; $tableNamingErrors = 0

    foreach ($f in $sqltableFiles) {
        try {
            $tData = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $tName = $tData.tableName

            $existingTableNaming = Get-CachedNaming -Name $tName -SubFolder 'TableNames'

            $tableNamingWasCached = $false
            if ($existingTableNaming -and $existingTableNaming.columns -and $existingTableNaming.columns.Count -gt 0) {
                $tableNamingHits++
                $tableNamingWasCached = $true
                continue
            }

            if (-not $tData.db2Metadata -or -not $tData.db2Metadata.columns -or $tData.db2Metadata.columns.Count -eq 0) {
                continue
            }

            $meta = $tData.db2Metadata
            $schemas = ($meta.schemas -join ', ')
            $tableRemarks = if ($meta.tableRemarks) { $meta.tableRemarks } else { 'No comment' }

            $colGrid = "| # | Name | Type | Length | Nullable | Comment |`n"
            foreach ($col in $meta.columns) {
                $colGrid += "| $($col.colNo) | $($col.name) | $($col.typeName) | $($col.length) | $(if ($col.nullable) { 'Yes' } else { 'No' }) | $(if ($col.remarks) { $col.remarks } else { '-' }) |`n"
            }

            $explicitFks = 'None'
            if ($meta.explicitForeignKeys -and $meta.explicitForeignKeys.Count -gt 0) {
                $explicitFks = ($meta.explicitForeignKeys | ForEach-Object {
                    "$($_.childColumn) -> $($_.parentSchema).$($_.parentTable).$($_.parentColumn) ($($_.constraintName))"
                }) -join "`n"
            }

            $colMatches = ''
            foreach ($col in $meta.columns) {
                $cName = "$($col.name)"
                if ($script:columnIndex.ContainsKey($cName) -and $script:columnIndex[$cName].Count -gt 1) {
                    $others = @($script:columnIndex[$cName] | Where-Object { $_ -ne $tName }) | Select-Object -First 10
                    if ($others.Count -gt 0) {
                        $colMatches += "$cName -> also in: $($others -join ', ')`n"
                    }
                }
            }
            if (-not $colMatches) { $colMatches = 'No cross-table column matches' }

            $usageCount = 0; $usageList = ''
            if ($script:tableUsageMap.ContainsKey($tName)) {
                $grouped = @{}
                foreach ($u in $script:tableUsageMap[$tName]) {
                    if (-not $grouped.ContainsKey($u.program)) { $grouped[$u.program] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
                    [void]$grouped[$u.program].Add($u.operation)
                }
                $usageCount = $grouped.Count
                $usageList = ($grouped.GetEnumerator() | Select-Object -First 20 | ForEach-Object {
                    "$($_.Key) ($($_.Value -join ', '))"
                }) -join ', '
            }
            if (-not $usageList) { $usageList = 'None' }

            $ragSnippets = 'No RAG data'
            if ($RagUrl) {
                try {
                    $ragResult = Invoke-Rag -Query "EXEC SQL JOIN $tName" -N 3
                    if ($ragResult) { $ragSnippets = $ragResult.Substring(0, [Math]::Min($ragResult.Length, 2000)) }
                } catch { }
            }

            # ── Table name via Ollama ──
            if (-not $existingTableNaming) {
                $tablePrompt = @"
You are analyzing a legacy DB2 table for modernization to C#.
Your task is to suggest a modern CamelCase class name and logical namespace.

TABLE: $tName
SCHEMAS: $schemas
TABLE COMMENT (Norwegian): $tableRemarks
TYPE: $($meta.type)

COLUMNS ($($meta.columns.Count)):
$colGrid

PROGRAMS USING THIS TABLE ($($usageCount)):
$usageList

COBOL USAGE (from source code):
$ragSnippets

Based on ALL the context above, suggest a CamelCase C# class name and namespace.
Respond with EXACTLY one JSON object (no markdown, no explanation):
{"futureName":"OrderHeader","namespace":"Orders"}

JSON:
{"futureName":
"@
                $tableResp = Invoke-Ollama -Prompt $tablePrompt
                if ($tableResp) {
                    $tableResp = $tableResp.Trim()
                    if ($tableResp -notmatch '^\{') { $tableResp = '{"futureName":' + $tableResp }
                    if ($tableResp -match '\{[^}]+\}') {
                        try {
                            $tn = $Matches[0] | ConvertFrom-Json
                            $tableNaming = [ordered]@{
                                tableName  = $tName
                                futureName = $tn.futureName
                                namespace  = $tn.namespace
                                columns    = @()
                                model      = $OllamaModel
                                protocol   = 'Naming-TableNames'
                                analyzedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                            }
                            $existingTableNaming = [PSCustomObject]$tableNaming
                        } catch { $tableNamingErrors++ }
                    }
                }
            }

            # ── Column names + FK inference via Ollama ──
            # Only attempt column naming when table naming was just generated (not from cache)
            if (-not $tableNamingWasCached -and $existingTableNaming -and (-not $existingTableNaming.columns -or $existingTableNaming.columns.Count -eq 0)) {
                $futureTableName = if ($existingTableNaming -and $existingTableNaming.futureName) { $existingTableNaming.futureName } else { 'unknown' }
                $colPrompt = @"
You are analyzing columns of a legacy DB2 table for modernization to C#.
Generate a CamelCase property name and English description for EACH column.
Also identify foreign key relationships (explicit or inferred).

TABLE: $tName (Future C# name: $futureTableName)
TABLE COMMENT (Norwegian): $tableRemarks

COLUMNS:
$colGrid

EXPLICIT FOREIGN KEYS (from DB2 catalog):
$explicitFks

COLUMN NAME MATCHES (same column name in other tables):
$colMatches

COBOL USAGE (from source code):
$ragSnippets

For EACH column provide: CamelCase property name, English description, FK if applicable.
Norwegian hints: NR=number, DATO=date, BELOP=amount, KODE=code, NAVN=name, ADR=address.
Confidence: high=DB2 FK or name+usage, medium=name+type match, low=name-only.

Respond with EXACTLY one JSON object:
{"columns":[{"name":"ORDRNR","futureName":"OrderNumber","description":"Unique order identifier","foreignKey":null}]}

JSON:
{"columns":[
"@
                $colResp = Invoke-Ollama -Prompt $colPrompt
                if ($colResp) {
                    $colResp = $colResp.Trim()
                    $colParsed = $false

                    if ($colResp -notmatch '^\{') { $colResp = '{"columns":[' + $colResp }

                    # Strategy 1: Find last } and try progressive substrings
                    $lastBrace = $colResp.LastIndexOf('}')
                    while ($lastBrace -gt 0 -and -not $colParsed) {
                        try {
                            $candidate = $colResp.Substring(0, $lastBrace + 1)
                            $cn = $candidate | ConvertFrom-Json
                            if ($cn.columns -and $cn.columns.Count -gt 0) {
                                $colParsed = $true
                                if ($existingTableNaming.PSObject.Properties.Match('columns').Count) {
                                    $existingTableNaming.columns = @($cn.columns)
                                } else {
                                    $existingTableNaming | Add-Member -NotePropertyName 'columns' -NotePropertyValue @($cn.columns) -Force
                                }
                            }
                        } catch { }
                        if (-not $colParsed) { $lastBrace = $colResp.LastIndexOf('}', $lastBrace - 1) }
                    }

                    # Strategy 2: Extract individual column objects via regex
                    if (-not $colParsed) {
                        # Regex: match objects like {"name":"X","futureName":"Y",...}
                        $colObjPattern = '\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"futureName"\s*:\s*"[^"]+"[^}]*\}'
                        $colMatches2 = [regex]::Matches($colResp, $colObjPattern)
                        if ($colMatches2.Count -gt 0) {
                            $extractedCols = [System.Collections.ArrayList]::new()
                            foreach ($cm in $colMatches2) {
                                try {
                                    $colObj = $cm.Value | ConvertFrom-Json
                                    [void]$extractedCols.Add($colObj)
                                } catch { }
                            }
                            if ($extractedCols.Count -gt 0) {
                                $colParsed = $true
                                if ($existingTableNaming.PSObject.Properties.Match('columns').Count) {
                                    $existingTableNaming.columns = @($extractedCols)
                                } else {
                                    $existingTableNaming | Add-Member -NotePropertyName 'columns' -NotePropertyValue @($extractedCols) -Force
                                }
                            }
                        }
                    }

                    if (-not $colParsed) { $tableNamingErrors++ }
                }
            }

            # Save the merged TableNames file (table name + columns in one file)
            if ($existingTableNaming) {
                Save-CachedNaming -Name $tName -SubFolder 'TableNames' -Data ([PSCustomObject]$existingTableNaming)

                # Upsert each column into the cross-analysis column registry
                if ($existingTableNaming.columns -and $existingTableNaming.columns.Count -gt 0) {
                    foreach ($col in $existingTableNaming.columns) {
                        if ($col.name) {
                            Update-ColumnRegistry -ColumnName $col.name `
                                -FutureName $col.futureName `
                                -Description $col.description `
                                -TableName $tName `
                                -AnalysisAlias $AnalysisAlias
                        }
                    }
                }
            }

            $tableNamingNew++
            if ($tableNamingNew % 25 -eq 0) {
                Write-Output "    Tables named: $tableNamingNew new, $tableNamingHits cached..."
            }
        } catch {
            Write-Warning "  Naming error for table in $($f.Name): $($_.Exception.Message)"
            $tableNamingErrors++
        }
    }
    Write-Output "  Table naming: $tableNamingNew new | $tableNamingHits cached | $tableNamingErrors errors"
    Write-Output "  Column registry: $($script:columnRegistryStats.created) created | $($script:columnRegistryStats.updated) updated | $($script:columnRegistryStats.conflicts) conflicts | $($script:columnRegistryStats.resolved) resolved"

    # ── Program Naming ──
    $progNamingHits = 0; $progNamingNew = 0; $progNamingErrors = 0

    $progCount = $master.Keys.Count
    $progIdx = 0
    foreach ($mk in $master.Keys) {
        $progIdx++
        $prog = $master[$mk]
        $progName = $prog.program.ToUpperInvariant()

        $existingProgNaming = Get-CachedNaming -Name $progName -SubFolder 'ProgramNames'
        if ($existingProgNaming) {
            $progNamingHits++
            continue
        }

        $cached = Get-CachedFact -ProgramName $progName -FactKey 'classification'
        $classification = if ($cached -and $cached.value) { $cached.value } else { $prog.classification }
        $confidence = if ($cached -and $cached.confidence) { $cached.confidence } else { $prog.classificationConfidence }
        if (-not $classification) { $classification = 'unknown' }
        if (-not $confidence) { $confidence = 'unknown' }

        $cobdokSystem = if ($prog.cobdokSystem) { $prog.cobdokSystem } else { 'Unknown' }
        $cobdokDelsystem = if ($prog.cobdokDelsystem) { $prog.cobdokDelsystem } else { 'Unknown' }
        $cobdokDesc = if ($prog.cobdokDescription) { $prog.cobdokDescription } else { 'No description' }
        $isDeprecated = if ($prog.isDeprecated) { 'true' } else { 'false' }

        $tableList = ''
        if ($prog.sqlOperations -and $prog.sqlOperations.Count -gt 0) {
            $tblGrouped = @{}
            foreach ($s in $prog.sqlOperations) {
                $tk = $s.tableName
                if (-not $tblGrouped.ContainsKey($tk)) { $tblGrouped[$tk] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
                [void]$tblGrouped[$tk].Add($s.operation)
            }
            $tableList = ($tblGrouped.GetEnumerator() | Select-Object -First 15 | ForEach-Object {
                $tn = Get-CachedNaming -Name $_.Key -SubFolder 'TableNames'
                $futName = if ($tn -and $tn.futureName) { " ($($tn.futureName))" } else { '' }
                "$($_.Key)$futName [$($_.Value -join ', ')]"
            }) -join "`n"
        }
        if (-not $tableList) { $tableList = 'None' }

        $callTargets = if ($prog.callTargets -and $prog.callTargets.Count -gt 0) { ($prog.callTargets | Select-Object -First 20) -join ', ' } else { 'None' }
        $callers = if ($script:calledByMap.ContainsKey($progName)) { ($script:calledByMap[$progName] | Select-Object -First 10) -join ', ' } else { 'None' }

        $ragSnippet = 'No source available'
        if ($RagUrl) {
            try {
                $rr = Invoke-Rag -Query "$progName COBOL program purpose" -N 2
                if ($rr) { $ragSnippet = $rr.Substring(0, [Math]::Min($rr.Length, 1500)) }
            } catch { }
        }

        $progPrompt = @"
You are analyzing a legacy COBOL program for modernization to C#.
Suggest a descriptive PascalCase C# project/class name and namespace.

PROGRAM: $progName
CLASSIFICATION: $classification (confidence: $confidence)
COBDOK SYSTEM: $cobdokSystem
COBDOK SUBSYSTEM: $cobdokDelsystem
COBDOK DESCRIPTION (Norwegian): $cobdokDesc
IS DEPRECATED: $isDeprecated

TABLES USED ($($prog.sqlOperations.Count) operations):
$tableList

CALL TARGETS: $callTargets
CALLED BY: $callers

COBOL SOURCE SUMMARY:
$ragSnippet

Respond with EXACTLY one JSON object:
{"futureProjectName":"GrainStockMaintenance","futureNamespace":"Agriculture.Grain","description":"Manages grain stock levels"}

JSON:
{"futureProjectName":
"@
        $progResp = Invoke-Ollama -Prompt $progPrompt
        if ($progResp) {
            $progResp = $progResp.Trim()
            if ($progResp -notmatch '^\{') { $progResp = '{"futureProjectName":' + $progResp }
            if ($progResp -match '\{[^}]+\}') {
                try {
                    $pn = $Matches[0] | ConvertFrom-Json
                    $progNamingData = [ordered]@{
                        program            = $progName
                        futureProjectName  = $pn.futureProjectName
                        futureNamespace    = $pn.futureNamespace
                        description        = $pn.description
                        model              = $OllamaModel
                        protocol           = 'Naming-ProgramNames'
                        analyzedAt         = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                    }
                    Save-CachedNaming -Name $progName -SubFolder 'ProgramNames' -Data ([PSCustomObject]$progNamingData)
                    $progNamingNew++
                } catch { $progNamingErrors++ }
            }
        }

        if ($progNamingNew % 25 -eq 0 -and $progNamingNew -gt 0) {
            Write-Output "    Programs named: $progNamingNew new, $progNamingHits cached ($progIdx/$progCount)..."
        }
    }
    Write-Output "  Program naming: $progNamingNew new | $progNamingHits cached | $progNamingErrors errors"

    # ── Inject future names into $master and build tableNaming section ──
    Write-Output '  Injecting future names into master data...'
    $script:tableNamingSection = [ordered]@{}

    foreach ($f in $sqltableFiles) {
        try {
            $tData = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $tName = $tData.tableName
            $tn = Get-CachedNaming -Name $tName -SubFolder 'TableNames'
            if ($tn) {
                $entry = [ordered]@{
                    futureName = $tn.futureName
                    namespace  = $tn.namespace
                }
                if ($tData.db2Metadata -and $tData.db2Metadata.tableRemarks) {
                    $entry.tableRemarks = $tData.db2Metadata.tableRemarks
                }
                if ($tn.columns -and $tn.columns.Count -gt 0) {
                    $entry.columns = @($tn.columns)
                }
                $script:tableNamingSection[$tName] = $entry
            }
        } catch { }
    }

    Write-Output "  Injecting future names into master data..."
    $injectedProgs = 0; $injectedOps = 0
    foreach ($mk in $master.Keys) {
        $p = $master[$mk]
        $pn = Get-CachedNaming -Name $p.program -SubFolder 'ProgramNames'
        if ($pn -and $pn.futureProjectName) {
            $p['futureProjectName'] = $pn.futureProjectName
            $injectedProgs++
        }
        foreach ($s in $p.sqlOperations) {
            $tn = Get-CachedNaming -Name $s.tableName -SubFolder 'TableNames'
            if ($tn -and $tn.futureName) {
                if ($s -is [System.Collections.IDictionary]) {
                    $s['futureTableName'] = $tn.futureName
                } elseif (-not ($s.PSObject.Properties.Match('futureTableName')).Count) {
                    $s | Add-Member -NotePropertyName 'futureTableName' -NotePropertyValue $tn.futureName
                } else {
                    $s.futureTableName = $tn.futureName
                }
                $injectedOps++
            }
        }
    }
    Write-Output "    Injected $injectedProgs futureProjectName, $injectedOps futureTableName"

    Save-Master -Master $master -Path $MasterJson
    Write-Output "  Naming complete. tableNaming section: $($script:tableNamingSection.Count) tables"
}

if (Get-Command -Name Write-RunSummaryMarkdown -ErrorAction SilentlyContinue) {
    try {
        $reportPath = Write-RunSummaryMarkdown -RunDir $RunDir -OutputPath $RunSummaryMd
        Write-Output "  Markdown report: $reportPath"
    } catch {
        Write-Warning "Could not generate run summary markdown: $($_.Exception.Message)"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  PUBLISH LATEST ALIAS + analyses.json                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
try {
    New-Item -ItemType Directory -Path $AliasDir -Force | Out-Null
    Get-ChildItem -LiteralPath $AliasDir -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_History' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $RunDir '*') -Destination $AliasDir -Recurse -Force
    Write-Output "  Latest alias snapshot updated: $AliasDir"
} catch {
    Write-Warning "Could not update alias folder '$($AliasDir)': $($_.Exception.Message)"
}

try {
    if (Test-Path -LiteralPath $AnalysesIndexPath) {
        $analysesIndex = Get-Content -LiteralPath $AnalysesIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $analysesIndex = [ordered]@{ analyses = @() }
    }

    if (-not $analysesIndex.analyses) {
        $analysesIndex.analyses = @()
    }

    $nowIso = (Get-Date).ToString('s')
    $runRecord = [ordered]@{
        folder    = $runFolderName
        timestamp = $nowIso
    }

    $existing = $analysesIndex.analyses | Where-Object { $_.alias -eq $aliasSafe } | Select-Object -First 1
    if (-not $existing) {
        $existing = [ordered]@{
            alias             = $aliasSafe
            areas             = @($distinctAreas)
            created           = $nowIso
            lastRun           = $nowIso
            latestFolder      = $aliasSafe
            runs              = @($runRecord)
            allJsonSourcePath = $AllJsonPath
            parameters        = [ordered]@{
                db2Dsn            = $Db2Dsn
                maxCallIterations = $MaxCallIterations
                ragResults        = $RagResults
                ragTableResults   = $RagTableResults
            }
        }
        $analysesIndex.analyses += $existing
    } else {
        if ($existing -is [System.Collections.IDictionary]) {
            $existing['areas'] = @($distinctAreas)
            $existing['lastRun'] = $nowIso
            $existing['latestFolder'] = $aliasSafe
            $existing['allJsonSourcePath'] = $AllJsonPath
            if (-not $existing['runs']) { $existing['runs'] = @() }
            $existing['runs'] += $runRecord
            if (-not $existing['parameters']) { $existing['parameters'] = [ordered]@{} }
            $existing['parameters']['db2Dsn'] = $Db2Dsn
            $existing['parameters']['maxCallIterations'] = $MaxCallIterations
            $existing['parameters']['ragResults'] = $RagResults
            $existing['parameters']['ragTableResults'] = $RagTableResults
        } else {
            foreach ($propName in @('areas','lastRun','latestFolder','allJsonSourcePath')) {
                if (-not ($existing.PSObject.Properties.Match($propName)).Count) {
                    $existing | Add-Member -NotePropertyName $propName -NotePropertyValue $null
                }
            }
            $existing.areas = @($distinctAreas)
            $existing.lastRun = $nowIso
            $existing.latestFolder = $aliasSafe
            $existing.allJsonSourcePath = $AllJsonPath
            if (-not $existing.runs) { $existing | Add-Member -NotePropertyName 'runs' -NotePropertyValue @() }
            $existing.runs += $runRecord
            if (-not $existing.parameters) { $existing | Add-Member -NotePropertyName 'parameters' -NotePropertyValue ([ordered]@{}) }
            foreach ($paramName in @('db2Dsn','maxCallIterations','ragResults','ragTableResults')) {
                if (-not ($existing.parameters.PSObject.Properties.Match($paramName)).Count) {
                    $existing.parameters | Add-Member -NotePropertyName $paramName -NotePropertyValue $null
                }
            }
            $existing.parameters.db2Dsn = $Db2Dsn
            $existing.parameters.maxCallIterations = $MaxCallIterations
            $existing.parameters.ragResults = $RagResults
            $existing.parameters.ragTableResults = $RagTableResults
        }
    }

    $analysesIndex.analyses = @($analysesIndex.analyses | Sort-Object alias)
    $analysesIndex | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $AnalysesIndexPath -Encoding UTF8
    Write-Output "  Analysis index updated: $AnalysesIndexPath"
} catch {
    Write-Warning "Could not update analyses index '$($AnalysesIndexPath)': $($_.Exception.Message)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Phase 8g — Business Area Classification (Ollama)                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

$BusinessAreasJson = Join-Path $RunDir 'business_areas.json'
$baCachePath = if ($AnalysisCommonPath) { Join-Path $AnalysisCommonPath "BusinessAreas\$($AnalysisAlias)_business_areas.json" } else { $null }

$skipBA = $false
if ($baCachePath -and (Test-Path -LiteralPath $baCachePath)) {
    try {
        $cached = Get-Content -LiteralPath $baCachePath -Raw | ConvertFrom-Json
        $cachedProgs = @($cached.programAreaMap.PSObject.Properties.Name | Sort-Object)
        $currentProgs = @($master.Keys | Sort-Object)
        if ($cachedProgs.Count -eq $currentProgs.Count -and ($cachedProgs -join ',') -eq ($currentProgs -join ',')) {
            Write-Output '  Business area classification: using cache (program set unchanged)'
            Copy-Item -LiteralPath $baCachePath -Destination $BusinessAreasJson -Force
            $skipBA = $true
        }
    } catch {
        Write-Warning "Could not read BA cache: $($_.Exception.Message)"
    }
}

if (-not $skipBA) {
    Write-Output ''
    Write-Output '  ╔═══════════════════════════════════════════════════════════════╗'
    Write-Output '  ║  Phase 8g — Business Area Classification                      ║'
    Write-Output '  ╚═══════════════════════════════════════════════════════════════╝'

    $baProgList = [System.Text.StringBuilder]::new()
    $baTableList = [System.Text.StringBuilder]::new()
    $allTables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($key in ($master.Keys | Sort-Object)) {
        $item = $master[$key]
        $cls = $item.classification
        $fpn = $item.futureProjectName
        $tables = @($item.sqlOperations | ForEach-Object { $_.tableName } | Sort-Object -Unique) -join ', '
        $calls = @($item.callTargets) -join ', '
        $origEntry = $allJson.entries | Where-Object { $_.program -eq $key } | Select-Object -First 1
        $area = if ($origEntry) { $origEntry.area } else { '' }
        [void]$baProgList.AppendLine("  $($key): cls=$($cls) fpn=$($fpn) area=$($area) tables=[$($tables)] calls=[$($calls)]")
        $item.sqlOperations | ForEach-Object { [void]$allTables.Add($_.tableName) }
    }
    foreach ($t in ($allTables | Sort-Object)) {
        $fn = if ($script:tableNamingSection -and $script:tableNamingSection[$t]) { $script:tableNamingSection[$t].futureName } else { '' }
        [void]$baTableList.AppendLine("  $($t) -> $($fn)")
    }

    $baPrompt = @"
You are a business domain analyst for a legacy COBOL ERP system (Dedge - Norwegian agricultural cooperative).
Analyze the following programs and classify them into detailed business areas.

ANALYSIS: $AnalysisAlias
PROGRAMS ($($master.Count)):
$($baProgList.ToString())

TABLES ($($allTables.Count)):
$($baTableList.ToString())

RULES:
1. Create 3-15 business areas depending on analysis complexity.
2. Each area must have: id (kebab-case), name (English), description (1-2 sentences).
3. Assign every program to exactly one primary area.
4. Programs calling each other often belong to the same area.
5. Programs sharing the same tables often belong to the same area.
6. Common utility programs (GM* prefix) should be in "common-infrastructure".
7. Use domain-specific names like "grain-quality-control", not "module-1".

Return ONLY valid JSON:
{"areas":[{"id":"...","name":"...","description":"..."}],"programAreaMap":{"PROGRAM":"area-id"}}
"@

    $baResponse = Invoke-Ollama -Prompt $baPrompt
    $baResult = $null
    if ($baResponse) {
        $baClean = $baResponse -replace '(?s)^[^{]*', '' -replace '(?s)[^}]*$', ''
        try {
            $baResult = $baClean | ConvertFrom-Json
        } catch {
            Write-Warning "  Business area Ollama JSON parse failed, using fallback"
        }
    }

    if (-not $baResult -or -not $baResult.areas) {
        Write-Output '  Ollama failed or invalid — using fallback area grouping'
        $fallbackAreas = @{}
        $fallbackMap = [ordered]@{}
        foreach ($key in ($master.Keys | Sort-Object)) {
            $origEntry = $allJson.entries | Where-Object { $_.program -eq $key } | Select-Object -First 1
            $areaId = if ($origEntry -and $origEntry.area) { $origEntry.area.ToLower() -replace '\s+', '-' } else { 'unclassified' }
            if (-not $fallbackAreas.ContainsKey($areaId)) {
                $fallbackAreas[$areaId] = [ordered]@{ id = $areaId; name = $areaId; description = "Programs in the $($areaId) area" }
            }
            $fallbackMap[$key] = $areaId
        }
        $baResult = [ordered]@{
            areas = @($fallbackAreas.Values)
            programAreaMap = $fallbackMap
        }
    }

    $baOutput = [ordered]@{
        title = 'Business Area Classification'
        generated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        analysisAlias = $AnalysisAlias
        totalAreas = $baResult.areas.Count
        areas = @($baResult.areas)
        programAreaMap = $baResult.programAreaMap
    }

    $baOutput | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BusinessAreasJson -Encoding UTF8
    Write-Output "  Business areas: $($baResult.areas.Count) areas, $($master.Count) programs classified"

    if ($baCachePath) {
        $baCacheDir = Split-Path $baCachePath -Parent
        if (-not (Test-Path -LiteralPath $baCacheDir)) { New-Item -ItemType Directory -Path $baCacheDir -Force | Out-Null }
        Copy-Item -LiteralPath $BusinessAreasJson -Destination $baCachePath -Force
        Write-Output "  Cached at: $($baCachePath)"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  CLEANUP & SUMMARY                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if ($db2Conn -and $db2Conn.State -eq 'Open') {
    $db2Conn.Close()
    $db2Conn.Dispose()
}

$stopwatch.Stop()
Write-Output ''
Write-Output ('=' * 72)
Write-Output '  FULL ANALYSIS COMPLETE'
Write-Output ('=' * 72)
Write-Output "  Elapsed: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))"
Write-Output ''
Write-Output '  Programs:'
Write-Output "    Original (all.json):     $countOrig"
Write-Output "    CALL expansion:          $countCall"
Write-Output "    Table-reference:         $countTable"
Write-Output "    TOTAL:                   $($progEntries.Count)"
Write-Output "    Data sources:            $countLocal local / $countRag RAG"
if ($countDeprecated -gt 0) {
    Write-Output "    Deprecated (UTGATT):     $countDeprecated"
}
if ($script:extractionCacheHits -gt 0 -or $script:extractionCacheMisses -gt 0) {
    Write-Output ''
    Write-Output '  Extraction Cache:'
    Write-Output "    Cache hits (unchanged):  $($script:extractionCacheHits)"
    Write-Output "    Cache misses (new/changed): $($script:extractionCacheMisses)"
}
Write-Output ''
Write-Output '  Cross-references:'
Write-Output "    SQL table refs:          $($sqlEntries.Count) ($($uTables.get_Count()) unique)"
Write-Output "    COPY elements:           $($copyList.Count) unique"
Write-Output "    Call graph edges:        $($callEdges.Count)"
Write-Output "    File I/O refs:           $($fioEntries.Count) ($($fioUniqueFiles.get_Count()) unique files)"
if ($db2TableSet.get_Count() -gt 0) {
    Write-Output "    DB2 validated tables:    $($db2TableSet.get_Count()) in catalog"
}
if ($candidatePrograms.get_Count() -gt 0) {
    Write-Output ''
    Write-Output '  Exclusion Candidates (tagged, not removed):'
    Write-Output "    Candidate programs:      $($candidatePrograms.get_Count())"
}
Write-Output ''
Write-Output '  Output files:'
Write-Output "    dependency_master.json      — per-program full dependency data"
Write-Output "    all_total_programs.json     — all programs with metadata"
Write-Output "    all_sql_tables.json         — table references (with DB2 validation)"
Write-Output "    all_copy_elements.json      — copybook cross-reference"
Write-Output "    all_call_graph.json         — caller/callee edges"
Write-Output "    all_file_io.json            — file I/O mappings"
Write-Output "    source_verification.json    — local source availability"
Write-Output "    standard_cobol_filtered.json — standard COBOL program filter results"
Write-Output "    business_areas.json         — business domain classification"
Write-Output "    run_summary.md              — markdown run statistics"
if ($Db2Dsn) {
    Write-Output "    db2_table_validation.json   — DB2 catalog validation"
}
if ($excludeData) {
    Write-Output "    applied_exclusions.json    — exclusion candidate details"
    Write-Output "    exclude.json               — copy of candidate config"
}
Write-Output "    all.json                   — copy of input seed file"
Write-Output ''
Write-Output "  Run folder: $RunDir"
Write-Output "  Latest alias folder: $AliasDir"
Write-Output "  Analysis alias: $aliasSafe"
Write-Output "  analyses.json: $AnalysesIndexPath"
