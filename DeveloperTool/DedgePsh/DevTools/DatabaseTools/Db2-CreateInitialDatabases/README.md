# Db2-CreateInitialDatabases

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-26  
**Technology:** PowerShell / DB2 LUW

---

## Overview

Automated provisioning of DB2 databases on any FK server. Creates complete database environments including tablespaces, bufferpools, schemas, users, grants, monitoring, and backup configuration. Replaces 4-8 hours of manual setup with a 20-minute automated run.

---

## Scripts

### Core Script

| Script | Description |
|---|---|
| `Db2-CreateInitialDatabases.ps1` | Main interactive script. Prompts for instance name, database type, backup source, and options. Creates primary and/or federated databases with full configuration. |

### Pre-configured Wrapper Scripts

These call the main script with preset parameters for common scenarios:

| Script | Instance | Type | Backup Source | Notes |
|---|---|---|---|---|
| `Db2-CreateInitialDatabasesStdAll.ps1` | DB2 | BothDatabases | PRD | Standard full setup: primary + federated, restores from production backup |
| `Db2-CreateInitialDatabasesStdAllNoBackupCopy.ps1` | DB2 | BothDatabases | (none) | Same as StdAll but skips backup copy -- uses existing staged backup |
| `Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1` | DB2 | BothDatabases | PRD | Uses new config format where XINLTST is an alias on the primary instance (no separate federated instance) |
| `Db2-CreateInitialDatabasesFkxAll.ps1` | DB2, DB2D, DB2Q | BothDatabases | (none) | Provisions all three FKX instances sequentially |
| `Db2-CreateInitialDatabasesHstAll.ps1` | DB2HST | BothDatabases | (none) | Provisions the history database instance |
| `Db2-CreateInitialDatabaseStdFed.ps1` | DB2 | FederatedDb | (prompt) | Creates only the federated database, then sets up federation nicknames |
| `Db2-CreateInitialDatabasesShadowUseNewConfig.ps1` | DB2SH | PrimaryDb | (none) | Creates a shadow database using new config. Called by the shadow pipeline. |

### Verification Scripts

| Script | Description |
|---|---|
| `Db2-VerifyServerConfiguration.ps1` | Validates server configuration against `DatabasesV2.json`. Must run from a workstation, not on the server. Defaults to BASISPRO. |
| `Db2-VerifyDbConnectivity.ps1` | Continuous connectivity test against a database. Runs SQL queries in a loop for a user-specified duration. Defaults to BASISVFT. |

## Parameters (Main Script)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-DatabaseType` | ValidateSet | (prompt) | `PrimaryDb`, `FederatedDb`, or `BothDatabases` |
| `-PrimaryInstanceName` | string | (prompt) | DB2 instance name (e.g. `DB2`, `DB2SH`, `DB2HST`) |
| `-DropExistingDatabases` | switch | (prompt) | Drop and recreate existing databases |
| `-GetBackupFromEnvironment` | string | (prompt) | Source environment for backup restore (`PRD`, or empty for staged backup) |
| `-SmsNumbers` | string[] | (prompt) | Phone numbers to notify on completion/failure |
| `-OverrideWorkFolder` | string | (auto) | Override the default work folder path |
| `-UseNewConfigurations` | switch | (prompt) | Use new config where federated DB is an alias on the primary instance |

When parameters are not provided, the script prompts interactively with timeout-based defaults.

## What It Creates

The `New-DatabaseAndConfigurations` function (from `Db2-Handler` module) performs:

1. **Database creation** with proper codepage and territory settings
2. **Tablespace setup** -- DATA, INDEX, TEMP, LARGE tablespaces
3. **Bufferpool configuration** -- optimized for the environment
4. **User and schema creation** -- DBM schema and application users
5. **Initial grants** -- permissions for application and service accounts
6. **Monitoring setup** -- DB2 monitoring configuration
7. **Backup configuration** -- automated backup schedules
8. **Federation support** (when applicable) -- nicknames for cross-database access via `Add-FederationSupportToDatabases`

## Dependencies

| Module | Purpose |
|---|---|
| `GlobalFunctions` | Logging (`Write-LogMessage`), SMS (`Send-Sms`), environment detection |
| `Db2-Handler` | Database creation, backup, federation, `DatabasesV2.json` access |
| `Infrastructure` | Server and environment utilities |
| `NetSecurity` | Firewall and network security configuration |

## Configuration

Database definitions are read from `DatabasesV2.json` on the central config share:

```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json
```

Each database entry specifies: instance name, server, access point type (PrimaryDb/FederatedDb), backup settings, and environment.

## Usage Examples

```powershell
# Interactive -- prompts for all options
.\Db2-CreateInitialDatabases.ps1

# Standard full setup on DB2 instance with production backup
.\Db2-CreateInitialDatabasesStdAll.ps1

# Shadow database for the shadow pipeline (called by Db2-ShadowDatabase Step-1)
.\Db2-CreateInitialDatabasesShadowUseNewConfig.ps1 -InstanceName "DB2SH" -OverrideWorkFolder "E:\opt\data\Db2-ShadowDatabase\FKMVFTSH"

# New config format (no separate federated instance)
.\Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1

# All FKX instances in sequence
.\Db2-CreateInitialDatabasesFkxAll.ps1

# Continuous connectivity test for 2 hours
.\Db2-VerifyDbConnectivity.ps1 -DatabaseName "BASISVFT"
```

## Deployment

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-CreateInitialDatabases\_deploy.ps1"
```

Scripts must run **on the DB2 server** as administrator (`Test-Db2ServerAndAdmin` enforces this). Deploy via `_deploy.ps1`, then run on the target server.

## SMS Notifications

- On success: sends SMS to all numbers in `-SmsNumbers`
- On failure: sends SMS to the default admin (+4797188358)
- Production environments (PRD/RAP): additionally notifies +4795762742

---

**Status:** CRITICAL -- Production infrastructure provisioning tool
