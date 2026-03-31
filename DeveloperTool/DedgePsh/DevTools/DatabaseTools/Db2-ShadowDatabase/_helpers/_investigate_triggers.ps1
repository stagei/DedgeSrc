Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$workFolder = Get-ApplicationDataPath
Set-OverrideAppDataFolder -Path $workFolder

$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

$queries = @()
$queries += "set DB2INSTANCE=$($cfg.SourceInstance)"
$queries += "db2 connect to $($cfg.SourceDatabase)"

# Check trigger validity
$queries += "db2 `"SELECT RTRIM(TRIGSCHEMA) || '.' || RTRIM(TRIGNAME) AS TRIGGER_NAME, VALID, CHAR(CREATE_TIME) AS CREATED FROM SYSCAT.TRIGGERS WHERE TRIGSCHEMA NOT LIKE 'SYS%' ORDER BY TRIGSCHEMA, TRIGNAME`""

# Column count for INL.KUNDEKONTO
$queries += "db2 `"SELECT COUNT(*) AS INL_KUNDEKONTO_COLS FROM SYSCAT.COLUMNS WHERE TABSCHEMA = 'INL' AND TABNAME = 'KUNDEKONTO'`""

# Column count for LOG.KUNDEKONTO
$queries += "db2 `"SELECT COUNT(*) AS LOG_KUNDEKONTO_COLS FROM SYSCAT.COLUMNS WHERE TABSCHEMA = 'LOG' AND TABNAME = 'KUNDEKONTO'`""

# Show LOG.KUNDEKONTO columns
$queries += "db2 `"SELECT COLNO, RTRIM(COLNAME) AS COL, RTRIM(TYPENAME) AS TYPE, LENGTH FROM SYSCAT.COLUMNS WHERE TABSCHEMA = 'LOG' AND TABNAME = 'KUNDEKONTO' ORDER BY COLNO`""

$queries += "db2 connect reset"
$queries += "db2 terminate"

$output = Invoke-Db2ContentAsScript -Content $queries -ExecutionType BAT `
    -FileName (Join-Path $workFolder "InvestigateTriggers_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

Write-Host $output
