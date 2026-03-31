<#
.SYNOPSIS
    Backs up DedgeAuth and GenericLogHandler from TST PostgreSQL and restores to PRD.

.DESCRIPTION
    Uses DedgeAuth-DatabaseSetup and GenericLogHandler-DatabaseSetup backup/restore scripts
    with PostgreSql-Handler. Default TST host: t-no1fkxtst-db. Default PRD host: p-no1fkxprd-db.
    Port 8432, user postgres (override via parameters).

    Run from a machine with PostgreSQL client tools (pg_dump/pg_restore) and network access
    to both database servers.

.PARAMETER TstHost
    Source PostgreSQL host (default t-no1fkxtst-db)

.PARAMETER PrdHost
    Target PostgreSQL host (default p-no1fkxprd-db)

.PARAMETER PostgresPassword
    Plain postgres superuser password (default: postgres per project conventions)
#>
param(
    [string]$TstHost = 't-no1fkxtst-db',
    [string]$PrdHost = 'p-no1fkxprd-db',
    [int]$PostgresPort = 8432,
    [string]$PostgresUser = 'postgres',
    [string]$PostgresPassword = 'postgres',
    [string]$StagingFolder = ''
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force

$script:HadError = $false

# PSScriptRoot = ...\DedgePsh\DevTools\WebSites\IIS-DeployApp — repo root is three levels up
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$DedgeAuthSetup = Join-Path $repoRoot 'DevTools\WebSites\DedgeAuth\DedgeAuth-DatabaseSetup'
$glhSetup = Join-Path $repoRoot 'DevTools\WebSites\GenericLogHandler\GenericLogHandler-DatabaseSetup'

if (-not (Test-Path $DedgeAuthSetup)) {
    Write-LogMessage "DedgeAuth-DatabaseSetup not found: $($DedgeAuthSetup)" -Level ERROR
    exit 1
}
if (-not (Test-Path $glhSetup)) {
    Write-LogMessage "GenericLogHandler-DatabaseSetup not found: $($glhSetup)" -Level ERROR
    exit 1
}

if ([string]::IsNullOrWhiteSpace($StagingFolder)) {
    $StagingFolder = Join-Path $env:TEMP "PgPrdRestore_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
New-Item -ItemType Directory -Path $StagingFolder -Force | Out-Null
Write-LogMessage "Staging backup folder: $($StagingFolder)" -Level INFO

function Invoke-DedgeAuthBackup {
    $out = Join-Path $StagingFolder "DedgeAuth_$(Get-Date -Format 'yyyyMMdd-HHmmss').backup"
    & (Join-Path $DedgeAuthSetup 'DedgeAuth-Backup-Database.ps1') `
        -PostgresHost $TstHost -PostgresPort $PostgresPort -PostgresUser $PostgresUser `
        -PostgresPassword $PostgresPassword -DatabaseName 'DedgeAuth' -OutputPath $out -Format Custom
    return $out
}

function Invoke-GlhBackup {
    $out = Join-Path $StagingFolder "GenericLogHandler_$(Get-Date -Format 'yyyyMMdd-HHmmss').backup"
    & (Join-Path $glhSetup 'GenericLogHandler-Backup-Database.ps1') `
        -PostgresHost $TstHost -PostgresPort $PostgresPort -PostgresUser $PostgresUser `
        -PostgresPassword $PostgresPassword -DatabaseName 'GenericLogHandler' -OutputPath $out -Format Custom
    return $out
}

function Invoke-DedgeAuthRestore {
    param([string]$BackupPath)
    & (Join-Path $DedgeAuthSetup 'DedgeAuth-Restore-Database.ps1') `
        -InputPath $BackupPath -PostgresHost $PrdHost -PostgresPort $PostgresPort `
        -PostgresUser $PostgresUser -PostgresPassword $PostgresPassword -DatabaseName 'DedgeAuth' `
        -CreateDatabaseIfNotExists -Clean
}

function Invoke-GlhRestore {
    param([string]$BackupPath)
    & (Join-Path $glhSetup 'GenericLogHandler-Restore-Database.ps1') `
        -InputPath $BackupPath -PostgresHost $PrdHost -PostgresPort $PostgresPort `
        -PostgresUser $PostgresUser -PostgresPassword $PostgresPassword -DatabaseName 'GenericLogHandler' `
        -CreateDatabaseIfNotExists -Clean
}

Write-LogMessage "Backing up DedgeAuth from $($TstHost)..." -Level INFO
try {
    $fkBackup = Invoke-DedgeAuthBackup
    Write-LogMessage "DedgeAuth backup: $($fkBackup)" -Level INFO
}
catch {
    throw
}

Write-LogMessage "Backing up GenericLogHandler from $($TstHost)..." -Level INFO
try {
    $glhBackup = Invoke-GlhBackup
    Write-LogMessage "GenericLogHandler backup: $($glhBackup)" -Level INFO
}
catch {
    $script:HadError = $true
    throw
}

Write-LogMessage "Restoring DedgeAuth to $($PrdHost)..." -Level INFO
try {
    Invoke-DedgeAuthRestore -BackupPath $fkBackup
}
catch {
    Write-LogMessage "DedgeAuth restore to $($PrdHost) failed — copy .backup to PRD DB server and run DedgeAuth-Restore-Database.ps1 with -PostgresHost localhost." -Level WARN
    $script:HadError = $true
}

Write-LogMessage "Restoring GenericLogHandler to $($PrdHost)..." -Level INFO
try {
    Invoke-GlhRestore -BackupPath $glhBackup
}
catch {
    Write-LogMessage "GenericLogHandler restore to $($PrdHost) failed — copy .backup to PRD DB server and run GenericLogHandler-Restore-Database.ps1 with -PostgresHost localhost." -Level WARN
    $script:HadError = $true
}

if ($script:HadError) {
    Write-LogMessage "TST→PRD PostgreSQL backup/restore finished with errors." -Level ERROR
    exit 1
}
Write-LogMessage "TST→PRD PostgreSQL backup/restore completed." -Level INFO
Write-Host "Staging folder (retain for audit): $($StagingFolder)"
