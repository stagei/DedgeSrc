$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$ddlFile = Get-ChildItem $dataPath -Filter 'source_ddl_*_cleaned.sql' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $ddlFile) {
    Write-Host "No cleaned DDL file found"
    exit
}

Write-Host "File: $($ddlFile.Name) (Modified: $($ddlFile.LastWriteTime))"
$localCopy = Join-Path $env:TEMP "cleaned_ddl_check.sql"
Copy-Item $ddlFile.FullName $localCopy -Force

$win1252 = [System.Text.Encoding]::GetEncoding(1252)
$content = [System.IO.File]::ReadAllLines($localCopy, $win1252)

Write-Host "`n=== Lines containing 'WITH DEFAULT USER' or 'WITH DEFAULT SESSION_USER' ==="
for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match 'WITH DEFAULT (SESSION_)?USER') {
        Write-Host "  L$($i+1): $($content[$i].Trim())"
    }
}

Write-Host "`n=== Lines for DBM.TEKSTER BRUKERID ==="
for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match 'CREATE\s+TABLE.*"DBM.*"TEKSTER"') {
        for ($j = $i; $j -lt [Math]::Min($content.Count, $i + 15); $j++) {
            if ($content[$j] -match 'BRUKERID|TIDSPUNKT|DEFAULT USER|SESSION_USER') {
                Write-Host "  L$($j+1): $($content[$j].Trim())"
            }
        }
        break
    }
}

Write-Host "`n=== Lines for DBM.KUNDER OPPRETTET_AV ==="
for ($i = 0; $i -lt $content.Count; $i++) {
    if ($content[$i] -match 'CREATE\s+TABLE.*"DBM.*"KUNDER"') {
        for ($j = $i; $j -lt [Math]::Min($content.Count, $i + 60); $j++) {
            if ($content[$j] -match 'OPPRETTET_AV|DEFAULT USER|SESSION_USER') {
                Write-Host "  L$($j+1): $($content[$j].Trim())"
            }
        }
        break
    }
}

Write-Host "`n=== ApplyDdl errors for TEKSTER and KUNDER ==="
$outFile = Get-ChildItem $dataPath -Filter 'ApplyDdl_*.out' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($outFile) {
    Write-Host "Output file: $($outFile.Name) (Modified: $($outFile.LastWriteTime))"
    $localOut = Join-Path $env:TEMP "ddl_out_check.txt"
    Copy-Item $outFile.FullName $localOut -Force
    $outContent = [System.IO.File]::ReadAllLines($localOut, $win1252)
    for ($i = 0; $i -lt $outContent.Count; $i++) {
        if ($outContent[$i] -match 'TEKSTER|KUNDER' -and $outContent[$i] -match 'SQL0574|SQL0204|DEFAULT') {
            $start = [Math]::Max(0, $i - 2)
            $end = [Math]::Min($outContent.Count - 1, $i + 2)
            for ($j = $start; $j -le $end; $j++) {
                Write-Host "  L$($j+1): $($outContent[$j])"
            }
            Write-Host ""
        }
    }
}
