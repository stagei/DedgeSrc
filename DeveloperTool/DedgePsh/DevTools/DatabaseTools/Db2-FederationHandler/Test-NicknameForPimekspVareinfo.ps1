Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$tableName = "PIMEKSP_VAREINFO"
$schema = "DBM"
$fedDb = "XFKMTST"
$fedInstance = "DB2FED"
$primaryDb = "FKMTST"
$primaryInstance = "DB2"
$serverLink = "DB2LNK"

Write-LogMessage "=== Diagnosing nickname for $($schema).$($tableName) ===" -Level INFO

$workFolder = Join-Path $env:OptPath "data\Db2-FederationHandler\DiagNickname"
New-Item -Path $workFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$db2Commands = @()
$db2Commands += "REM === Phase 1: Check if nickname exists in $($fedDb) ==="
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2 connect to $($fedDb) user db2nt using ntdb2"
$db2Commands += "db2 `"SELECT TABSCHEMA, TABNAME, SERVERNAME, CHAR(CREATE_TIME) AS CREATED FROM SYSCAT.NICKNAMES WHERE TABNAME = '$($tableName)'`""
$db2Commands += "db2 `"SELECT COUNT(*) AS TOTAL_NICKNAMES FROM SYSCAT.NICKNAMES`""
$db2Commands += "db2 terminate"

$db2Commands += "REM === Phase 2: Confirm source table exists in $($primaryDb) ==="
$db2Commands += "set DB2INSTANCE=$($primaryInstance)"
$db2Commands += "db2 connect to $($primaryDb) user db2nt using ntdb2"
$db2Commands += "db2 `"SELECT TABSCHEMA, TABNAME, TYPE, CHAR(ALTER_TIME) AS ALTERED FROM SYSCAT.TABLES WHERE TABNAME = '$($tableName)'`""
$db2Commands += "db2 terminate"

$db2Commands += "REM === Phase 3: Drop existing nickname (ignore error if not exists) ==="
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2 connect to $($fedDb) user db2nt using ntdb2"
$db2Commands += "db2 `"DROP NICKNAME $($schema).$($tableName)`""
$db2Commands += "db2 terminate"

$db2Commands += "REM === Phase 4: Re-create nickname and capture full output ==="
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2 connect to $($fedDb) user db2nt using ntdb2"
$db2Commands += "db2 `"CREATE NICKNAME $($schema).$($tableName) FOR $($serverLink).$($schema).$($tableName)`""
$db2Commands += "db2 terminate"

$db2Commands += "REM === Phase 5: Verify nickname after creation ==="
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2 connect to $($fedDb) user db2nt using ntdb2"
$db2Commands += "db2 `"SELECT TABSCHEMA, TABNAME, SERVERNAME, CHAR(CREATE_TIME) AS CREATED FROM SYSCAT.NICKNAMES WHERE TABNAME = '$($tableName)'`""
$db2Commands += "db2 terminate"

$db2Commands += ""

$fileName = Join-Path $workFolder "DiagNickname_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
$output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName $fileName

Write-LogMessage "=== Full DB2 output ===" -Level INFO
Write-Host $output
Write-LogMessage "=== Diagnosis complete ===" -Level INFO
