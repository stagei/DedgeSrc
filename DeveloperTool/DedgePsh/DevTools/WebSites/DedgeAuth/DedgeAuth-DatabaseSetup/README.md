# DedgeAuth-DatabaseSetup

Sets up the PostgreSQL database for the DedgeAuth application. Creates the database if it doesn't exist and optionally configures `appsettings.json`.

## What It Does

1. **Detects** PostgreSQL installation on the server
2. **Creates** the `DedgeAuth` database if it doesn't exist
3. **Optionally** updates `appsettings.json` with the connection string and generates a JWT secret if empty

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PostgresHost` | `t-no1fkxtst-db` | PostgreSQL server hostname |
| `PostgresPort` | `8432` | PostgreSQL port |
| `PostgresUser` | `postgres` | PostgreSQL username |
| `PostgresPassword` | `postgres` | PostgreSQL password |
| `DatabaseName` | `DedgeAuth` | Database name to create |
| `ConfigureAppSettings` | Off | If set, updates `appsettings.json` with connection string and JWT secret |

## Usage

Run on the database server (main setup is `_DatabaseSetup.ps1`; scripts prefixed with `_` are general):

```powershell
.\_DatabaseSetup.ps1
```

Create the database and configure appsettings:

```powershell
.\_DatabaseSetup.ps1 -PostgresPassword "YourPassword" -ConfigureAppSettings
```

Use a different host or port:

```powershell
.\_DatabaseSetup.ps1 -PostgresHost "my-db-server" -PostgresPort 5433
```

## Backup and Restore

Backup and restore use **DedgeAuth-DatabaseConfig.ps1** for connection settings and the shared **PostgreSql-Handler** module (`Backup-PostgreSqlDatabase`, `Restore-PostgreSqlDatabase`).

### DedgeAuth-DatabaseConfig.ps1

Returns a hashtable of connection parameters: `PostgresHost`, `PostgresPort`, `PostgresUser`, `PostgresPassword`, `DatabaseName`. Defaults match DedgeAuth. Override by running with parameters, or by editing the defaults in the script.

### DedgeAuth-Backup-Database.ps1

Creates a backup using `pg_dump`. Default output: `.\Backups\<DatabaseName>_<yyyyMMdd-HHmmss>.backup` (Custom format) or `.sql` (Plain).

```powershell
.\DedgeAuth-Backup-Database.ps1
.\DedgeAuth-Backup-Database.ps1 -OutputPath C:\temp\DedgeAuth.backup -Format Plain
```

### DedgeAuth-Restore-Database.ps1

Restores from a `.backup` (custom) or `.sql` (plain) file. Use `-Latest` to pick the newest file in `.\Backups\`.

```powershell
.\DedgeAuth-Restore-Database.ps1 -Latest -CreateDatabaseIfNotExists
.\DedgeAuth-Restore-Database.ps1 -InputPath .\Backups\DedgeAuth_20250101-120000.backup -Clean
```

### DedgeAuth-Update-TenantCss.ps1

Updates the tenant CSS in the DedgeAuth database for a given tenant domain (`tenants.css_overrides`).

| Parameter | Description |
|-----------|-------------|
| `-InputPath` | Path to backup file (.backup or .sql) |
| `-Latest` | Use latest backup in .\Backups\ |
| `-CreateDatabaseIfNotExists` | Create the database before restore if missing |
| `-Clean` | (Custom format) Drop existing objects before restore |

## Deployment

This script is distributed to the database server automatically by `Build-And-Publish.ps1` in the DedgeAuth project via `_deploy.ps1`.

## Source Project

Maintained from `C:\opt\src\DedgeAuth`. See the DedgeAuth project for the full application source.
