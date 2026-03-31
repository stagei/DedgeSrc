Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

$fedDb = "XFKMTST"
$fedInstance = "DB2FED"
$fedUser = "db2nt"

Write-LogMessage "=== Granting DBADM to $($fedUser) on $($fedDb) (instance $($fedInstance)) ===" -Level INFO

$workFolder = Join-Path $env:OptPath "data\Db2-FederationHandler\FixGrant"
New-Item -Path $workFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$db2Commands = @()
$db2Commands += "REM === Step 1: Connect as implicit OS user (instance owner) and grant DBADM ==="
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2start"
$db2Commands += "db2 activate database $($fedDb)"
$db2Commands += "db2 terminate"
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2 connect to $($fedDb)"
$db2Commands += "db2 `"GRANT DBADM ON DATABASE TO USER $($fedUser)`""
$db2Commands += "db2 `"GRANT CREATEIN ON SCHEMA DBM TO USER $($fedUser)`""
$db2Commands += "db2 `"GRANT CREATEIN ON SCHEMA SYSCAT TO USER $($fedUser)`""
$db2Commands += "db2 commit work"
$db2Commands += "db2 connect reset"

$db2Commands += "REM === Step 2: Verify by connecting as db2nt and creating a test nickname ==="
$db2Commands += "set DB2INSTANCE=$($fedInstance)"
$db2Commands += "db2 connect to $($fedDb) user $($fedUser) using ntdb2"
$db2Commands += "db2 `"SELECT CURRENT USER AS CONNECTED_USER FROM SYSIBM.SYSDUMMY1`""
$db2Commands += "db2 `"DROP NICKNAME DBM.PIMEKSP_VAREINFO`""
$db2Commands += "db2 `"CREATE NICKNAME DBM.PIMEKSP_VAREINFO FOR DB2LNK.DBM.PIMEKSP_VAREINFO`""
$db2Commands += "db2 `"SELECT TABSCHEMA, TABNAME, SERVERNAME FROM SYSCAT.NICKNAMES WHERE TABNAME = 'PIMEKSP_VAREINFO'`""
$db2Commands += "db2 terminate"
$db2Commands += ""

$fileName = Join-Path $workFolder "FixGrant_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
$output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors -FileName $fileName

Write-LogMessage "=== Full output ===" -Level INFO
Write-Host $output
Write-LogMessage "=== Fix script complete ===" -Level INFO
