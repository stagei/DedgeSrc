$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$logDir = "\\$($cfg.ServerFqdn)\opt\data\AllPwshLog"
$today = (Get-Date).ToString('yyyyMMdd')
$logFile = Join-Path $logDir "FkLog_${today}.log"

$localCopy = Join-Path $env:TEMP "RemoteLog_FkLog_${today}.log"
Copy-Item -Path $logFile -Destination $localCopy -Force

$content = Get-Content $localCopy
$lines = $content | Where-Object {
    $_ -match 'Phase 2[bcdef]' -or
    $_ -match 'Found.*bufferpools' -or
    $_ -match 'Bufferpool:' -or
    $_ -match 'Tablespace:' -or
    $_ -match 'SQL0204' -or
    $_ -match 'SQL0601' -or
    $_ -match 'SQL0668' -or
    $_ -match 'SQL3304' -or
    $_ -match 'CREATE BUFFERPOOL' -or
    $_ -match 'CREATE TABLESPACE' -or
    $_ -match 'db2move.*LOAD' -or
    $_ -match 'tabellen finnes ikke' -or
    $_ -match 'table not found' -or
    $_ -match 'db2move.*output'
}

foreach ($line in $lines) {
    $shortLine = if ($line.Length -gt 250) { $line.Substring(0, 250) + '...' } else { $line }
    Write-Host $shortLine
}
