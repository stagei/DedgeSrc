$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$outFile = Get-ChildItem $dataPath -Filter 'ApplyDdl_*.out' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $outFile) {
    Write-Host "No ApplyDdl output file found"
    Get-ChildItem $dataPath -Filter '*.out' | Format-Table Name, Length, LastWriteTime
    exit
}

$localCopy = Join-Path $env:TEMP "ddl_output_latest.txt"
Copy-Item $outFile.FullName $localCopy -Force
Write-Host "Reading: $($outFile.Name) ($($outFile.Length) bytes)"

$content = Get-Content $localCopy -Encoding ([System.Text.Encoding]::GetEncoding(1252))
Write-Host "Total lines: $($content.Count)"

$missingTables = @('DBM.PRINT_MASKIN', 'DBM.TILGBRUK_GRP_PROF', 'DBM.TILGFUNK_NIVAA',
    'DBM.TILGGRP_AVD', 'DBM.TILGPROF_FUNK', 'DBM.TEKSTER', 'DBM.KUNDER',
    'INL.BILAGNR', 'INL.FASTE_LISTE', 'INL.FASTE_TRANS', 'INL.KONTO',
    'INL.KONTOTYPE', 'INL.KUNDEKONTO', 'INL.KUNDEKONTO_TEST',
    'INL.RENTESATSER', 'INL.TRANSREG', 'INL.TRANSTYPE')

foreach ($table in $missingTables) {
    $parts = $table -split '\.'
    $schema = $parts[0]
    $name = $parts[1]

    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match "CREATE\s+TABLE" -and $content[$i] -match "`"$schema" -and $content[$i] -match "$name") {
            $startIdx = [Math]::Max(0, $i - 1)
            $errorFound = $false
            for ($j = $i; $j -lt [Math]::Min($content.Count, $i + 50); $j++) {
                if ($content[$j] -match 'SQL\d{4,5}') {
                    Write-Host "`n=== $table (DDL at line $($i+1), Error at line $($j+1)) ==="
                    $errStart = [Math]::Max(0, $j - 2)
                    $errEnd = [Math]::Min($content.Count - 1, $j + 3)
                    for ($k = $errStart; $k -le $errEnd; $k++) {
                        Write-Host "  L$($k+1): $($content[$k])"
                    }
                    $errorFound = $true
                    break
                }
                if ($content[$j] -match '^\s*$' -and $j -gt $i + 5) { break }
            }
            if (-not $errorFound) {
                Write-Host "`n=== $table (DDL at line $($i+1)) - No SQL error found within 50 lines (likely OK) ==="
            }
            break
        }
    }
}
