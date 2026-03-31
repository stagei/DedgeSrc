$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$applyDdlFiles = Get-ChildItem $dataPath -Filter 'ApplyDdl_*.out' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($applyDdlFiles) {
    $localCopy = Join-Path $env:TEMP "ApplyDdl_latest.out"
    Copy-Item $applyDdlFiles.FullName $localCopy -Force
    Write-Host "Reading: $($applyDdlFiles.Name) ($($applyDdlFiles.Length) bytes)"

    $content = Get-Content $localCopy
    $errorLines = @()
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match 'SQL0204|SQL0668|SQL0601|SQL0205|SQLSTATE|Feil|error' -and $content[$i] -notmatch 'SQL0601N') {
            $start = [Math]::Max(0, $i - 3)
            $end = [Math]::Min($content.Count - 1, $i + 1)
            for ($j = $start; $j -le $end; $j++) {
                $prefix = if ($j -eq $i) { ">>> " } else { "    " }
                $line = $content[$j]
                if ($line.Length -gt 200) { $line = $line.Substring(0, 200) + '...' }
                $errorLines += "${prefix}L${j}: $line"
            }
            $errorLines += "---"
        }
    }
    if ($errorLines.Count -gt 0) {
        Write-Host "`n=== DDL Application Errors ==="
        $errorLines | Select-Object -First 100 | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-Host "No errors found in DDL output"
    }
}
else {
    Write-Host "No ApplyDdl output file found"
    Get-ChildItem $dataPath -Filter '*.out' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Format-Table Name, Length, LastWriteTime
}
