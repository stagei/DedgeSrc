$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$outFile = Get-ChildItem $dataPath -Filter 'ApplyDdl_*.out' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

$localCopy = Join-Path $env:TEMP "ddl_trigger_detail.txt"
Copy-Item $outFile.FullName $localCopy -Force

$win1252 = [System.Text.Encoding]::GetEncoding(1252)
$content = [System.IO.File]::ReadAllLines($localCopy, $win1252)

Write-Host "=== Lines 5340-5400 (LOG.KUNDEKONTO_D trigger and error) ==="
for ($i = 5339; $i -lt [Math]::Min($content.Count, 5400); $i++) {
    $line = $content[$i]
    if ($line.Length -gt 250) { $line = $line.Substring(0, 250) + '...' }
    Write-Host "  L$($i+1): $line"
}

Write-Host "`n=== Lines 5375-5445 (LOG.KUNDEKONTO_I and LOG.KUNDEKONTO_U2 triggers) ==="
for ($i = 5374; $i -lt [Math]::Min($content.Count, 5445); $i++) {
    $line = $content[$i]
    if ($line.Length -gt 250) { $line = $line.Substring(0, 250) + '...' }
    Write-Host "  L$($i+1): $line"
}
