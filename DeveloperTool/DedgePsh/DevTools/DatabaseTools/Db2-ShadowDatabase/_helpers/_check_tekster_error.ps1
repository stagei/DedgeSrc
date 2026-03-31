$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "config.json"
if (-not (Test-Path $cfgPath)) { throw "config.json not found at $($cfgPath)." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$dataPath = "\\$($cfg.ServerFqdn)\opt\data\Db2-ShadowDatabase"

$outFile = Get-ChildItem $dataPath -Filter 'ApplyDdl_*.out' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

$localOut = Join-Path $env:TEMP "ddl_tekster_check.txt"
Copy-Item $outFile.FullName $localOut -Force

$win1252 = [System.Text.Encoding]::GetEncoding(1252)
$content = [System.IO.File]::ReadAllLines($localOut, $win1252)

Write-Host "=== Full context around DBM.TEKSTER CREATE TABLE (output lines 3050-3090) ==="
for ($i = 3049; $i -lt [Math]::Min($content.Count, 3090); $i++) {
    $line = $content[$i]
    if ($line.Length -gt 250) { $line = $line.Substring(0, 250) + '...[truncated]' }
    Write-Host "  L$($i+1): $line"
}

Write-Host "`n=== Full context around DBM.KUNDER CREATE TABLE (output lines 3265-3305) ==="
for ($i = 3264; $i -lt [Math]::Min($content.Count, 3305); $i++) {
    $line = $content[$i]
    if ($line.Length -gt 250) { $line = $line.Substring(0, 250) + '...[truncated]' }
    Write-Host "  L$($i+1): $line"
}
