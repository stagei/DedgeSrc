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

# Get full trigger text for the 3 problematic triggers
$queries += "db2 `"SELECT RTRIM(TEXT) FROM SYSCAT.TRIGGERS WHERE RTRIM(TRIGSCHEMA) = 'LOG' AND RTRIM(TRIGNAME) = 'KUNDEKONTO_D'`""
$queries += "db2 `"SELECT RTRIM(TEXT) FROM SYSCAT.TRIGGERS WHERE RTRIM(TRIGSCHEMA) = 'LOG' AND RTRIM(TRIGNAME) = 'KUNDEKONTO_I'`""
$queries += "db2 `"SELECT RTRIM(TEXT) FROM SYSCAT.TRIGGERS WHERE RTRIM(TRIGSCHEMA) = 'LOG' AND RTRIM(TRIGNAME) = 'KUNDEKONTO_U2'`""

# Also check VALID column
$queries += "db2 `"SELECT RTRIM(TRIGSCHEMA) || '.' || RTRIM(TRIGNAME) AS T, VALID FROM SYSCAT.TRIGGERS WHERE TRIGSCHEMA = 'LOG' ORDER BY TRIGNAME`""

$queries += "db2 connect reset"
$queries += "db2 terminate"

$output = Invoke-Db2ContentAsScript -Content $queries -ExecutionType BAT `
    -FileName (Join-Path $workFolder "TrigText_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

Write-Host $output
