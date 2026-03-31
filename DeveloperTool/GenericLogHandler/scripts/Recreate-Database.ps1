<#
.SYNOPSIS
    Drops all app tables and recreates the database schema from EF Core migrations.
.DESCRIPTION
    Uses Postgres connection from appsettings.json (repo root). Either runs
    PostgreSQL_RecreateTables.sql via psql then starts the Web API so Migrate()
    runs, or calls POST /api/maintenance/recreate-schema if the API is already running.
.EXAMPLE
    .\Recreate-Database.ps1
#>
$ErrorActionPreference = 'Stop'
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

# Try API first (if Web API is already running)
$baseUrl = 'http://localhost:8110'
try {
    $r = Invoke-WebRequest -Uri "$baseUrl/api/maintenance/recreate-schema" -Method Post -UseDefaultCredentials -UseBasicParsing -TimeoutSec 30 -AllowUnencryptedAuthentication -ErrorAction Stop
    if ($r.StatusCode -eq 200) {
        Write-Output "Database recreated via API (recreate-schema)."
        exit 0
    }
} catch {
    # API not available or failed; fall back to psql + dotnet run
}

# Find psql
$psqlExe = $null
if (Get-Command psql -ErrorAction SilentlyContinue) {
    $psqlExe = (Get-Command psql).Source
} else {
    $pgBins = Get-ChildItem -Path 'C:\Program Files\PostgreSQL' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($ver in $pgBins) {
        $exe = Join-Path $ver.FullName "bin\psql.exe"
        if (Test-Path $exe) {
            $psqlExe = $exe
            break
        }
    }
}

if (-not $psqlExe) {
    Write-Error "psql not found. Install PostgreSQL client or start the Web API and run: Invoke-WebRequest -Uri http://localhost:8110/api/maintenance/recreate-schema -Method Post -UseDefaultCredentials -AllowUnencryptedAuthentication"
}

$recreateSql = Join-Path $repoRoot "DatabaseSchemas\PostgreSQL_RecreateTables.sql"
if (-not (Test-Path $recreateSql)) {
    Write-Error "Schema script not found: $recreateSql"
}

$env:PGPASSWORD = $dbPass
try {
    & $psqlExe -h $dbHost -p $dbPort -U $dbUser -d $dbName -f $recreateSql
    if ($LASTEXITCODE -ne 0) { throw "psql exited with $LASTEXITCODE" }
    Write-Output "Dropped app tables. Starting Web API to run migrations..."
} finally {
    $env:PGPASSWORD = $null
}

$webApiProj = Join-Path $repoRoot "src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj"
if (-not (Test-Path $webApiProj)) {
    Write-Output "Web API project not found. Start it manually so Migrate() runs: dotnet run --project $webApiProj"
    exit 0
}

$proc = Start-Process -FilePath "dotnet" -ArgumentList "run", "--no-build", "--project", $webApiProj -PassThru -NoNewWindow
try {
    Start-Sleep -Seconds 15
    Write-Output "Database recreated (tables dropped, migrations applied via Web API startup)."
} finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
