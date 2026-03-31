$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$outFile = Get-ChildItem $dataPath -Filter 'ApplyDdl_*.out' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $outFile) { Write-Host "No ApplyDdl output found"; exit }

Write-Host "File: $($outFile.Name) ($($outFile.Length) bytes, Modified: $($outFile.LastWriteTime))"
$localCopy = Join-Path $env:TEMP "ddl_trigger_check.txt"
Copy-Item $outFile.FullName $localCopy -Force

$win1252 = [System.Text.Encoding]::GetEncoding(1252)
$content = [System.IO.File]::ReadAllLines($localCopy, $win1252)

Write-Host "`n=== Lines containing TRIGGER or KUNDEKONTO (trigger-related) ==="
for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match 'CREATE\s+TRIGGER|KUNDEKONTO.*TRIGGER|TRIGGER.*KUNDEKONTO|LOG\.KUNDEKONTO') {
        $start = [Math]::Max(0, $i - 1)
        $end = [Math]::Min($content.Count - 1, $i + 5)
        for ($j = $start; $j -le $end; $j++) {
            $line = $content[$j]
            if ($line.Length -gt 200) { $line = $line.Substring(0, 200) + '...' }
            Write-Host "  L$($j+1): $line"
        }
        Write-Host ""
    }
}

Write-Host "`n=== Checking DDL file for CREATE TRIGGER statements ==="
$ddlFile = Get-ChildItem $dataPath -Filter 'source_ddl_*_cleaned.sql' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($ddlFile) {
    $localDdl = Join-Path $env:TEMP "ddl_trigger_src.sql"
    Copy-Item $ddlFile.FullName $localDdl -Force
    $ddlContent = [System.IO.File]::ReadAllText($localDdl, $win1252)
    $stmts = $ddlContent -split '@'
    $triggerStmts = @()
    foreach ($stmt in $stmts) {
        if ($stmt -match 'CREATE\s+TRIGGER') {
            $firstLine = ($stmt.Trim() -split "`n")[0..2] -join "`n"
            $triggerStmts += $firstLine
        }
    }
    Write-Host "Found $($triggerStmts.Count) CREATE TRIGGER statements in cleaned DDL:"
    foreach ($t in $triggerStmts) {
        $short = if ($t.Length -gt 150) { $t.Substring(0, 150) + '...' } else { $t }
        Write-Host "  $short"
    }
}
