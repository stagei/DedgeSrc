<#
.SYNOPSIS
    Installs PostgreSQL and provisions all databases configured for this server.

.DESCRIPTION
    End-to-end PostgreSQL server setup:
    1. Detects or installs PostgreSQL via Install-WindowsApps (SoftwareUtils)
    2. Ensures local config (port, listen_addresses, pg_hba, firewall) via PostgreSql-Handler
    3. Creates standard PostgreSQL folders and SMB shares via Find-PgFolders
    4. Reads DatabasesV2.json (Provider=PostgreSQL) for databases assigned to this server
    5. Creates each database that doesn't already exist
    6. Optionally installs requested PostgreSQL extensions

    Designed to run on any server. The config file determines which databases belong here.

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER PostgresUser
    PostgreSQL superuser. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL superuser password. Default: postgres

.PARAMETER SkipInstall
    Skip PostgreSQL installation (assume already installed).

.PARAMETER SkipFolders
    Skip folder and SMB share creation.

.PARAMETER SkipDatabases
    Skip database provisioning.

.EXAMPLE
    .\PostGreSql-DatabaseSetup.ps1
    Full setup: install PostgreSQL, create folders, provision databases for this server.

.EXAMPLE
    .\PostGreSql-DatabaseSetup.ps1 -SkipInstall -SkipFolders
    Only provision databases (PostgreSQL already installed and folders exist).

.EXAMPLE
    .\PostGreSql-DatabaseSetup.ps1 -PostgresPort 5432
    Full setup using port 5432 instead of default 8432.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'psql PGPASSWORD requires plain string.')]
param(
    [int]$PostgresPort        = 8432,
    [string]$PostgresUser     = "postgres",
    [string]$PostgresPassword = "postgres",
    [switch]$SkipInstall,
    [switch]$SkipFolders,
    [switch]$SkipDatabases
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force
Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\PostGreSql-DatabaseSetup")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PostgreSQL — Server Setup" -ForegroundColor Cyan
Write-Host "  Server: $($env:COMPUTERNAME)    Port: $($PostgresPort)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: INSTALL POSTGRESQL
# ═══════════════════════════════════════════════════════════════════════════════

if (-not $SkipInstall) {
    Write-LogMessage "Step 1: Detecting / installing PostgreSQL..." -Level INFO

    $psqlBinDir = Get-PostgreSqlPsqlPath
    if ($psqlBinDir) {
        Write-LogMessage "PostgreSQL already installed at: $($psqlBinDir)" -Level INFO
    } else {
        Write-LogMessage "PostgreSQL not found — installing via SoftwareUtils..." -Level INFO
        Import-Module SoftwareUtils -Force
        Install-WindowsApps -AppName "PostgreSQL.18"

        $psqlBinDir = Get-PostgreSqlPsqlPath
        if (-not $psqlBinDir) {
            Write-LogMessage "PostgreSQL installation failed — psql not found after install." -Level ERROR
            exit 1
        }
        Write-LogMessage "PostgreSQL installed successfully at: $($psqlBinDir)" -Level INFO
    }
} else {
    Write-LogMessage "Step 1: Skipping PostgreSQL installation (--SkipInstall)." -Level INFO
    $psqlBinDir = Get-PostgreSqlPsqlPath
    if (-not $psqlBinDir) {
        Write-LogMessage "PostgreSQL not found on this machine." -Level ERROR
        exit 1
    }
}

$psqlExe = Join-Path $psqlBinDir "psql.exe"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: LOCAL CONFIG (port, listen_addresses, pg_hba, firewall, service restart)
# ═══════════════════════════════════════════════════════════════════════════════

Write-LogMessage "Step 2: Ensuring local PostgreSQL configuration..." -Level INFO

try {
    Invoke-PostgreSqlEnsureLocalReady -Host "localhost" -Port $PostgresPort `
        -User $PostgresUser -Password $PostgresPassword `
        -PsqlExe $psqlExe -PgHbaComment "PostGreSql-DatabaseSetup"
} catch {
    Write-LogMessage "Local PostgreSQL configuration failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}

$connected = $false
$maxRetries = 5
for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    $connected = Test-PostgreSqlConnection -Host "localhost" -Port $PostgresPort `
        -User $PostgresUser -Password $PostgresPassword -PsqlExe $psqlExe
    if ($connected) { break }
    if ($attempt -lt $maxRetries) {
        Write-LogMessage "Connection attempt $($attempt)/$($maxRetries) failed, retrying in 3s..." -Level WARN
        Start-Sleep -Seconds 3
    }
}
if (-not $connected) {
    Write-LogMessage "Cannot connect to PostgreSQL on localhost:$($PostgresPort) after $($maxRetries) attempts." -Level ERROR
    exit 1
}
Write-LogMessage "PostgreSQL responding on localhost:$($PostgresPort)." -Level INFO

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: CREATE FOLDERS AND SMB SHARES
# ═══════════════════════════════════════════════════════════════════════════════

if (-not $SkipFolders) {
    Write-LogMessage "Step 3: Creating PostgreSQL folders and SMB shares..." -Level INFO
    $pgFolders = Find-PgFolders
    Write-LogMessage "DataFolder:       $($pgFolders.DataFolder)" -Level INFO
    Write-LogMessage "BackupFolder:     $($pgFolders.BackupFolder)" -Level INFO
    Write-LogMessage "WalArchiveFolder: $($pgFolders.WalArchiveFolder)" -Level INFO
    Write-LogMessage "RestoreFolder:    $($pgFolders.RestoreFolder)" -Level INFO
} else {
    Write-LogMessage "Step 3: Skipping folder creation (--SkipFolders)." -Level INFO
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: PROVISION DATABASES FROM CONFIG
# ═══════════════════════════════════════════════════════════════════════════════

if (-not $SkipDatabases) {
    Write-LogMessage "Step 4: Provisioning databases for $($env:COMPUTERNAME)..." -Level INFO

    $databases = Get-PostgreSqlDatabases

    if ($databases.Count -eq 0) {
        Write-LogMessage "No PostgreSQL databases configured for this server in DatabasesV2.json." -Level INFO
    } else {
        Write-LogMessage "Found $($databases.Count) database(s) to provision." -Level INFO

        $created  = 0
        $existed  = 0
        $failedDb = 0

        foreach ($dbEntry in $databases) {
            $dbName = $dbEntry.Database
            Write-LogMessage "Checking database '$($dbName)' ($($dbEntry.Application) / $($dbEntry.Environment))..." -Level INFO

            try {
                $existsQuery = "SELECT 1 FROM pg_database WHERE datname = '$($dbName)'"
                $result = Invoke-PostgreSqlQuery -Host "localhost" -Port $PostgresPort `
                    -User $PostgresUser -Password $PostgresPassword `
                    -Database "postgres" -Query $existsQuery -PsqlExe $psqlExe -Unattended

                if ($result -and $result.Trim() -eq '1') {
                    Write-LogMessage "Database '$($dbName)' already exists." -Level INFO
                    $existed++
                } else {
                    New-PostgreSqlDatabaseIfNotExists -Host "localhost" -Port $PostgresPort `
                        -User $PostgresUser -Password $PostgresPassword `
                        -DatabaseName $dbName -PsqlExe $psqlExe
                    Write-LogMessage "Database '$($dbName)' created." -Level INFO
                    $created++
                }

                if ($dbEntry.Extensions -and $dbEntry.Extensions.Count -gt 0) {
                    foreach ($ext in $dbEntry.Extensions) {
                        $extCheck = Invoke-PostgreSqlQuery -Host "localhost" -Port $PostgresPort `
                            -User $PostgresUser -Password $PostgresPassword `
                            -Database $dbName -Query "SELECT 1 FROM pg_extension WHERE extname = '$($ext)'" `
                            -PsqlExe $psqlExe -Unattended
                        if (-not $extCheck -or $extCheck.Trim() -ne '1') {
                            Invoke-PostgreSqlQuery -Host "localhost" -Port $PostgresPort `
                                -User $PostgresUser -Password $PostgresPassword `
                                -Database $dbName -Query "CREATE EXTENSION IF NOT EXISTS `"$($ext)`"" `
                                -PsqlExe $psqlExe
                            Write-LogMessage "Extension '$($ext)' enabled in '$($dbName)'." -Level INFO
                        }
                    }
                }
            } catch {
                Write-LogMessage "Failed to provision '$($dbName)': $($_.Exception.Message)" -Level ERROR
                $failedDb++
            }
        }

        Write-LogMessage "Database provisioning complete — created: $($created), existed: $($existed), failed: $($failedDb)" -Level INFO
    }
} else {
    Write-LogMessage "Step 4: Skipping database provisioning (--SkipDatabases)." -Level INFO
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PostgreSQL Server Setup Complete" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Server:     $($env:COMPUTERNAME)" -ForegroundColor Gray
Write-Host "  Port:       $($PostgresPort)" -ForegroundColor Gray
Write-Host "  PostgreSQL: $($psqlBinDir)" -ForegroundColor Gray
Write-Host ""

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
exit 0
