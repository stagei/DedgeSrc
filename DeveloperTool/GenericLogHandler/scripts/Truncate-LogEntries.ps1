<#
.SYNOPSIS
    Truncates log_entries and optional "files" table. Keeps import_status and saved_filters.
.DESCRIPTION
    Uses connection from appsettings (Postgres). Run from repo root or set $env:PGPASSWORD.
#>
$ErrorActionPreference = 'Stop'
# Repo root = parent of scripts folder (contains appsettings.json)
$repoRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location | Select-Object -ExpandProperty Path }

$appsettingsPath = Join-Path $repoRoot 'appsettings.json'
if (-not (Test-Path $appsettingsPath)) {
    Write-Error "appsettings.json not found at: $appsettingsPath"
}
$json = Get-Content $appsettingsPath -Raw | ConvertFrom-Json
$conn = $json.ConnectionStrings.Postgres ?? $json.ConnectionStrings.DefaultConnection
if (-not $conn) {
    Write-Error 'No Postgres connection string in appsettings.json'
}

# Parse Host=...;Port=...;Database=...;Username=...;Password=...
$parts = @{}
foreach ($pair in $conn -split ';') {
    if ($pair -match '^([^=]+)=(.*)$') {
        $parts[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
$dbHost = $parts['Host'] ?? 'localhost'
$dbPort = $parts['Port'] ?? '5432'
$dbName = $parts['Database'] ?? 'loghandler'
$dbUser = $parts['Username'] ?? 'postgres'
$dbPass = $parts['Password'] ?? 'postgres'

$env:PGPASSWORD = $dbPass
$sql = @"
TRUNCATE TABLE log_entries RESTART IDENTITY CASCADE;
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'files') THEN
    EXECUTE 'TRUNCATE TABLE files RESTART IDENTITY CASCADE';
  END IF;
END \$\$;
"@
$sqlFile = [System.IO.Path]::GetTempFileName()
$sql | Set-Content $sqlFile -Encoding UTF8
try {
    & psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -f $sqlFile
    if ($LASTEXITCODE -ne 0) { throw "psql exited with $LASTEXITCODE" }
    Write-Output "Truncated log_entries (and files if present). Kept import_status and saved_filters."
}
finally {
    Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
    $env:PGPASSWORD = $null
}
