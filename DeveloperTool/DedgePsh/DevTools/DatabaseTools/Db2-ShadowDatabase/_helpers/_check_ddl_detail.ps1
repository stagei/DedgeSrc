$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$ddlFile = Get-ChildItem $dataPath -Filter 'source_ddl_*_cleaned.sql' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $ddlFile) {
    $ddlFile = Get-ChildItem $dataPath -Filter 'source_ddl_*.sql' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

if ($ddlFile) {
    $localCopy = Join-Path $env:TEMP "ddl_latest.sql"
    Copy-Item $ddlFile.FullName $localCopy -Force
    Write-Host "Reading DDL: $($ddlFile.Name) ($($ddlFile.Length) bytes)"

    $content = Get-Content $localCopy -Encoding UTF8
    Write-Host "Total lines: $($content.Count)"

    $missingTables = @('DBM.TEKSTER', 'DBM.KUNDER', 'DBM.PRINT_MASKIN', 'DBM.TILGBRUK_GRP_PROF',
        'DBM.TILGFUNK_NIVAA', 'DBM.TILGGRP_AVD', 'DBM.TILGPROF_FUNK',
        'INL.BILAGNR', 'INL.FASTE_LISTE', 'INL.FASTE_TRANS', 'INL.KONTO',
        'INL.KONTOTYPE', 'INL.KUNDEKONTO', 'INL.KUNDEKONTO_TEST',
        'INL.RENTESATSER', 'INL.TRANSREG', 'INL.TRANSTYPE')

    foreach ($table in $missingTables) {
        $parts = $table -split '\.'
        $schema = $parts[0]
        $name = $parts[1]

        for ($i = 0; $i -lt $content.Count; $i++) {
            if ($content[$i] -match "CREATE\s+TABLE\s+`"$schema" -and $content[$i] -match "$name") {
                Write-Host "`n=== CREATE TABLE for $table (line $($i+1)) ==="
                $end = [Math]::Min($content.Count - 1, $i + 30)
                for ($j = $i; $j -le $end; $j++) {
                    $line = $content[$j]
                    if ($line.Length -gt 200) { $line = $line.Substring(0, 200) + '...' }
                    Write-Host "  L$($j+1): $line"
                    if ($line -match '^\s*;' -or ($j -gt $i -and $line -match 'ORGANIZE BY')) { break }
                }
                break
            }
        }
    }
}
else {
    Write-Host "No DDL file found"
    Get-ChildItem $dataPath -Filter '*.sql' | Format-Table Name, Length, LastWriteTime
}
