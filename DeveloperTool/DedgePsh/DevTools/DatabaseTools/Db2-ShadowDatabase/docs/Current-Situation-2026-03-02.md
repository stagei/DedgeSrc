# Shadow Database Pipeline — Current Situation

**Date:** 2026-03-02 23:40  
**Author:** Geir Helge Starholm / AI Agent  
**Status:** BROKEN — pipeline fails at Step-2 after refactoring

---

## What Worked at 19:00 Today

At approximately 19:00 on 2026-03-02, the full shadow database pipeline ran **successfully** on both:

- **t-no1inltst-db** (INLTST database, Application: INL)
- **t-no1inldev-db** (INLDEV database, Application: INL)

All 5 steps completed:
1. Step-1: Create shadow database (restore from PRD, create DB2SH instance + shadow DB)
2. Step-2: Copy database content (DDL export from source, import to shadow)
3. Step-3: Cleanup shadow database
4. Step-4: Move to original instance
5. Step-5: Verify row counts

## What Happened After 19:00 — The Refactoring

Starting around 18:00-21:00, a large refactoring was done across `Db2-Handler.psm1` with the goal of adding role-based access control (RBAC) and new configuration support. **The critical mistake was that many changes were NOT guarded by `UseNewConfigurations` checks**, which broke the `UseNewConfigurations = false` production code path.

### Commits since the working state

| Time | Commit | Description |
|------|--------|-------------|
| 18:05 | `be448fb0` | Refactor Db2 database creation scripts to support new configuration handling |
| 21:08 | `2ab6c618` | Refactor Db2 shadow database scripts for enhanced configuration handling and error management |
| 22:02 | `d62cbae5` | fix |
| 22:02 | `18c1e490` | fix |
| 23:19 | `55c5441c` | Fix |

### Changes made in the refactoring (973 lines changed in Db2-Handler.psm1)

1. **Add-SpecificGrants** — Changed grant targets from `User = "SRV_KPDB"` to `Role = "FK_SVC_KPDB"` etc. Originally UNGUARDED (broke production path). Now fixed with `$useRoles = ($WorkObject.UseNewConfigurations -eq $true)` branch.

2. **Set-DatabasePermissions** — Added calls to `New-Db2StandardRoles` and `Set-Db2RoleMemberships`. Originally UNGUARDED. Now wrapped in `if ($WorkObject.UseNewConfigurations -eq $true)`.

3. **New-Db2StandardRoles** (NEW function) — Creates DB2 roles (FK_DBA, FK_READONLY, FK_READWRITE, etc.). Only called when UseNewConfigurations=true.

4. **Set-Db2RoleMemberships** (NEW function) — Maps users/groups to roles. Only called when UseNewConfigurations=true.

5. **Add-DatabaseConfigurations** — KRB_SERVER_ENCRYPT auth. Properly guarded.

6. **Set-PostRestoreConfiguration** — AUTOSIZE bufferpools vs hardcoded. Properly guarded.

7. **Get-DefaultWorkObjectsCommon** — Alias/federation error handling softened from `throw` to `WARN`. Originally UNGUARDED. Now fixed: throws for UseNewConfigurations=false, warns for true.

8. **Add-ServerCatalogingForLocalDatabase** — Auth type handling. Originally hardcoded KERBEROS. Now uses `$WorkObject.AuthenticationType` for false path.

9. **Invoke-Db2OfflineActivate** — Added `-IgnoreErrors` and SQL1117N/SQL5099N handling. Originally UNGUARDED. Now guarded.

10. **Restore-DuringDatabaseCreation** — Broadened condition. Originally UNGUARDED. Now fixed: `($WorkObject.UseNewConfigurations -eq $true -or $WorkObject.InstanceName -eq "DB2")`.

11. **Restore-SingleDatabase** — BackupFilterWithDate fallback. Properly guarded.

12. **Start-Db2Restore** — Federation skip, UseNewConfigurations parameter threading. Properly guarded.

13. **Get-DefaultWorkObjects** — Added UseNewConfigurations parameter. Passed through to all Common calls.

14. **Resolve-Db2ConfigForServer / Import-Db2ConfigForServer** (NEW functions) — Auto-detect config file by COMPUTERNAME.

15. **Get-CommandsForDatabasePermissions** — Bug fix: `$user` → `$UserName` (parameter name was wrong). Safe fix.

16. **Test-DatabaseExistance** — Added SQL1060N catalog fallback. Additive/safe.

17. **Set-Db2KerberosClientConfig** — Auth type from config. Safe (only triggers for new auth types).

18. **Add-RemoteCatalogingForDatabase** — Added KerberosServerEncrypt. Additive.

## Current Error State

### Last run on t-no1inltst-db (23:35)

Step-1 **succeeded** (PRD restore completed, ~18 minutes).

Step-2 **failed** with:
```
Federated access point not found for
```

**Root cause:** `Step-2-CopyDatabaseContent.ps1` calls `Get-DefaultWorkObjects` without passing `-UseNewConfigurations`. This causes the function to hit the `UseNewConfigurations=false` code path, which throws when no federated access point is found (INLTST no longer has federation configured in DatabasesV2.json).

### What needs to happen

All Step scripts (Step-2 through Step-5) need to pass `-UseNewConfigurations` when calling any `Db2-Handler` function. The Step scripts themselves must NOT contain any direct DB2 commands — all DB2 operations must go through `Db2-Handler.psm1` functions (see rule: `no-local-db-creation-in-steps.mdc`).

## Architecture Overview

### Remote Execution Model

The pipeline runs on remote DB2 servers via a scheduled task (`Db2-ShadowDatabase-Orchestrator`) that polls `next_command.txt` every ~10 minutes. From the developer machine:

1. **Deploy** — `_deploy.ps1` pushes scripts and modules to all target servers via UNC
2. **Trigger** — Write `RUN_ALL` to `\\<server>\opt\data\Db2-ShadowDatabase\next_command.txt`
3. **Kill** — Write `KILL` to `\\<server>\opt\data\Db2-ShadowDatabase\kill_command.txt`
4. **Monitor** — Read logs from `\\<server>\opt\data\AllPwshLog\FkLog_YYYYMMDD.log`

### Configuration

- **Central registry:** `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json`
- **Per-environment configs:** `config.inltst.json`, `config.fkmvft.json`, etc.
- **Auto-detection:** `Resolve-Db2ConfigForServer` matches `$env:COMPUTERNAME` against config files

### Key Files

| File | Purpose |
|------|---------|
| `_Modules/Db2-Handler/Db2-Handler.psm1` | ALL DB2 operations (14,410 lines) |
| `Db2-CreateInitialDatabases/Db2-CreateInitialDatabases.ps1` | Master DB creation orchestrator |
| `Db2-ShadowDatabase/Invoke-ShadowDatabaseOrchestrator.ps1` | Remote orchestrator (scheduled task) |
| `Db2-ShadowDatabase/Step-1-CreateShadowDatabase.ps1` | Restore source DB, create shadow instance |
| `Db2-ShadowDatabase/Step-2-CopyDatabaseContent.ps1` | DDL export/import source→shadow |
| `Db2-ShadowDatabase/Step-3-CleanupShadowDatabase.ps1` | Cleanup shadow DB |
| `Db2-ShadowDatabase/Step-4-MoveToOriginalInstance.ps1` | Move shadow to original instance |
| `Db2-ShadowDatabase/Step-5-VerifyRowCounts.ps1` | Verify table counts match |

### Rules (in `.cursor/rules/`)

| Rule | Purpose |
|------|---------|
| `shadow-db-fix-policy.mdc` | All fixes go in Db2-Handler.psm1 with UseNewConfigurations guards |
| `shadow-db-remote-execution.mdc` | Remote execution architecture and agent instructions |
| `no-local-db-creation-in-steps.mdc` | Step scripts must NOT contain direct DB2 commands |

## Target Servers

| Server | Database | Application | Config File | Status |
|--------|----------|-------------|-------------|--------|
| t-no1inltst-db | INLTST / INLTSTSH | INL | config.inltst.json | BROKEN (Step-2 fails) |
| t-no1fkmvft-db | FKMVFT / FKMVFTSH | FKM | config.fkmvft.json | NOT STARTED (waiting for INLTST) |
| t-no1inldev-db | INLDEV / INLDEVSH | INL | config.inldev.json | Was working at 19:00, untested since refactoring |

## Next Steps for New Agent

1. **Fix Step-2 through Step-5** to pass `-UseNewConfigurations` when calling Db2-Handler functions
2. **Do NOT add any direct DB2 commands to Step scripts** — all logic in Db2-Handler.psm1
3. **Deploy, trigger RUN_ALL on t-no1inltst-db, monitor every 60s**
4. **Fix errors** by modifying `Db2-Handler.psm1` (within `UseNewConfigurations` guards), redeploy, kill, restart
5. **Once INLTST is perfect**, trigger on t-no1fkmvft-db and repeat the monitor/fix cycle
6. **Autonomous operation** — 9 hours from ~23:00, work until morning

---

## Appendix A: _install.ps1

This script creates the scheduled task on a remote DB2 server. Run once per server.

```powershell
Import-Module ScheduledTask-Handler -Force

New-ScheduledTask -SourceFolder $PSScriptRoot `
    -TaskName "Db2-ShadowDatabase-Orchestrator" `
    -Executable "Invoke-ShadowDatabaseOrchestrator.ps1" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass" `
    -TaskFolder "DevTools" `
    -RecreateTask $true `
    -RunFrequency "EveryMinute" `
    -RunAsUser $true `
    -RunLevel "Highest" `
    -WindowStyle "Hidden"`
    -RunAtOnce $true
```

## Appendix B: _deploy.ps1

This script deploys to all target servers by reading `ServerFqdn` from every `config.*.json` file.

```powershell
Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module Deploy-Handler -Force -ErrorAction Stop

$configFiles = Get-ChildItem -Path $PSScriptRoot -Filter "config.*.json" -File -ErrorAction SilentlyContinue
$computerNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($file in $configFiles) {
    $cfg = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($cfg.ServerFqdn) {
        $hostname = $cfg.ServerFqdn.Split('.')[0]
        if (-not [string]::IsNullOrWhiteSpace($hostname)) {
            [void]$computerNames.Add($hostname)
        }
    }
}

$computerList = [string[]]$computerNames
if ($computerList.Count -eq 0) {
    throw "No computer names found in config.*.json files. Ensure each config has ServerFqdn."
}

Write-LogMessage "Deploy targets from config files: $($computerList -join ', ')" -Level INFO

Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList $computerList

$createInitialDbFolder = Join-Path (Split-Path $PSScriptRoot -Parent) "Db2-CreateInitialDatabases"
if (Test-Path $createInitialDbFolder) {
    Deploy-Files -FromFolder $createInitialDbFolder -ComputerNameList $computerList
}
```

## Appendix C: Environment Config Files

### config.inltst.json

```json
{
  "SourceInstance": "DB2",
  "SourceDatabase": "INLTST",
  "TargetInstance": "DB2SH",
  "TargetDatabase": "INLTSTSH",
  "ServerFqdn": "t-no1inltst-db.DEDGE.fk.no",
  "DataDisk": "F:",
  "DbUser": "db2nt",
  "DbPassword": "ntdb2",
  "Application": "INL"
}
```

### config.fkmvft.json

```json
{
  "SourceInstance": "DB2",
  "SourceDatabase": "FKMVFT",
  "TargetInstance": "DB2SH",
  "TargetDatabase": "FKMVFTSH",
  "ServerFqdn": "t-no1fkmvft-db.DEDGE.fk.no",
  "DataDisk": "F:",
  "DbUser": "db2nt",
  "DbPassword": "ntdb2",
  "Application": "FKM"
}
```

### config.inldev.json

```json
{
  "SourceInstance": "DB2",
  "SourceDatabase": "INLDEV",
  "TargetInstance": "DB2SH",
  "TargetDatabase": "INLDEVSH",
  "ServerFqdn": "t-no1inldev-db.DEDGE.fk.no",
  "DataDisk": "F:",
  "DbUser": "db2nt",
  "DbPassword": "ntdb2",
  "Application": "INL"
}
```

---

## Appendix D: Local Folder Rules

### Rule 1: shadow-db-fix-policy.mdc

```markdown
# Shadow Database Fix Policy — UseNewConfigurations in Db2-Handler

## Override

This rule **overrides** the "Db2-Handler Protection Rules" in `db2-shadow-database.mdc` that says "NEVER modify function logic in Db2-Handler.psm1."

Ad-hoc fixes discovered during shadow database pipeline runs **must become permanent changes** in `_Modules/Db2-Handler/Db2-Handler.psm1`, not temporary patches in step scripts or one-off workarounds.

## How to make fixes permanent

Use `$WorkObject.UseNewConfigurations -eq $true` as the branch condition inside existing functions in `Db2-Handler.psm1`. This ensures:

- **Old behavior is preserved** for production databases that don't use the new config path
- **New behavior activates automatically** for all shadow database and new-config pipelines
- **Fixes propagate everywhere** — any script that sets `UseNewConfigurations = $true` on the work object gets the fix

### Pattern

    function Some-Db2Function {
        param([psobject]$WorkObject)

        if ($WorkObject.UseNewConfigurations -eq $true) {
            # New behavior for shadow/non-federated pipeline
            # ... fixed logic here ...
        }
        else {
            # Original production behavior — unchanged
            # ... existing logic ...
        }
    }

### When a function doesn't take a WorkObject

For functions that take individual parameters, add an optional `-UseNewConfigurations` switch parameter:

    function Some-UtilityFunction {
        param(
            [string]$InstanceName,
            [string]$DatabaseName,
            [switch]$UseNewConfigurations
        )

        if ($UseNewConfigurations) {
            # New behavior
        }
        else {
            # Original behavior
        }
    }

## What qualifies as a permanent fix

- Authentication configuration differences (KRB_SERVER_ENCRYPT vs old methods)
- Skipping federated database operations (no more federation in new config)
- Bufferpool sizing (AUTOSIZE vs hardcoded values)
- Backup/restore logic differences (SQL2532N handling, different source DB names)
- Permission/grant differences (RBAC roles vs direct grants)
- Catalog and alias handling (aliases on primary instance vs federated nodes)
- Any logic that currently fails or needs workarounds in the shadow pipeline

## Do NOT use Db2-HandlerNew

The `Db2-HandlerNew` module (`_Modules/Db2-HandlerNew/`) with `FunctionNameNew` suffixes was an interim approach. Going forward, all new-config behavior goes directly into `Db2-Handler.psm1` behind `UseNewConfigurations` branches. This keeps all DB2 logic in one module and avoids version drift between the two.

## Deploy after changes

After modifying `Db2-Handler.psm1`, the module is deployed as part of `CommonModules` by any `_deploy.ps1` script. The shadow database `_deploy.ps1` handles this automatically.
```

### Rule 2: shadow-db-remote-execution.mdc

```markdown
# Shadow Database Remote Execution

This rule overrides the general `no-remote-execution` rule for this folder. The shadow database pipeline is designed to run on remote DB2 servers via scheduled tasks -- not locally.

## The Central Database Registry: DatabasesV2.json

All DB2 servers, databases, instances, and applications are defined in one master file:

    C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json

Accessed via `Get-DatabasesV2JsonFilename` from `GlobalFunctions`. A local cache is kept at `$env:LOCALAPPDATA\Temp\DatabasesV2.json`.

Each entry has: `Database`, `Application` (FKM/INL/DOC/VIS/...), `Environment` (PRD/TST/DEV/VFT/...), `ServerName`, `InstanceName`, `AccessPoints[]`, and `IsActive`.

**This is the single source of truth for which databases exist on which servers.** There are many servers across environments (DEV, TST, VFT, VFK, KAT, PER, FUT, RAP, PRD, etc.) and this list will continue to grow as more are migrated.

## Per-Environment Config Files: config.{env}.json

Each shadow database environment has its own config file in this folder:

    config.inltst.json    →  INLTST on t-no1inltst-db
    config.inldev.json    →  INLDEV on t-no1inldev-db
    config.fkmvft.json    →  FKMVFT on t-no1fkmvft-db
    (more will be added as new environments are onboarded)

These files contain the source/target instance and database names, the server FQDN, data disk, credentials, and application type. They are derived from DatabasesV2.json entries.

The orchestrator auto-detects which config to use by matching `$env:COMPUTERNAME` against the `ServerFqdn` values across all `config.*.json` files via `Resolve-Db2ConfigForServer` in `Db2-Handler.psm1`.

## Architecture

    Local dev machine                              Remote DB2 server
    ─────────────────                              ──────────────────
    _deploy.ps1                                    \\server\opt\DedgePshApps\Db2-ShadowDatabase\
      → Reads ServerFqdn from all config.*.json      All .ps1, config.*.json, _helpers\, docs\
      → Deploy-Files copies to each server  ──────►  (plus Db2-CreateInitialDatabases)

    _install.ps1 (run once on server)              Scheduled Task: Db2-ShadowDatabase-Orchestrator
      → ScheduledTask-Handler creates task ──────►   Runs Invoke-ShadowDatabaseOrchestrator.ps1
         TaskName: Db2-ShadowDatabase-Orchestrator   every minute, polls for command file
         RunFrequency: EveryMinute
         RunLevel: Highest

    Write command file via UNC             ──────► \\server\opt\data\Db2-ShadowDatabase\next_command.txt
                                                     Orchestrator picks it up within 60 seconds

## Lifecycle

### 1. Deploy scripts to servers

    # Deploys to ALL servers found in config.*.json files (dynamic list)
    pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-ShadowDatabase\_deploy.ps1"

This deploys both `Db2-ShadowDatabase` and `Db2-CreateInitialDatabases` to every server listed in any `config.*.json`.

### 2. Install scheduled task (once per server)

The `_install.ps1` creates a scheduled task via `ScheduledTask-Handler` that runs the orchestrator every minute. This must be run directly on the server (or deployed and executed there).

### 3. Trigger execution

Write a command to the server's command file via UNC:

    # Full pipeline (all steps)
    "RUN_ALL" | Out-File -FilePath "\\<server>\opt\data\Db2-ShadowDatabase\next_command.txt" -Encoding utf8 -Force

    # Single step
    "Step-Fix-ApplyPermissions.ps1" | Out-File -FilePath "\\<server>\opt\data\Db2-ShadowDatabase\next_command.txt" -Encoding utf8 -Force

### 4. Kill a running pipeline

    "STOP" | Out-File -FilePath "\\<server>\opt\data\Db2-ShadowDatabase\kill_command.txt" -Encoding utf8 -Force

### 5. Monitor progress

Follow the remote-log-reading rule: copy the log file locally, then read it.

    $server = "<server>"
    $logDir = "\\$($server)\opt\data\AllPwshLog"
    $logFile = "FkLog_$(Get-Date -Format 'yyyyMMdd').log"
    $localCopy = Join-Path $env:TEMP "RemoteLog_$($logFile)"
    Copy-Item -Path (Join-Path $logDir $logFile) -Destination $localCopy -Force
    # Then search/read the local copy

The orchestrator also sends SMS at each milestone (start, step complete, failure, pipeline done).

## Agent instructions

**Never try to run DB2 commands or pipeline scripts locally.** They require the DB2 instance on the target server.

When the user asks to "run the pipeline" or "test on <environment>":

1. **Deploy** -- run `_deploy.ps1` locally (it auto-discovers target servers from `config.*.json`)
2. **Identify the server** -- look up the environment in the matching `config.*.json` for the `ServerFqdn`
3. **Trigger** -- write `RUN_ALL` (or a specific step) to `\\<server>\opt\data\Db2-ShadowDatabase\next_command.txt`
4. **Monitor** -- copy remote log locally every 60 seconds and report progress
5. **Never** attempt `db2 connect`, `Invoke-Command`, or SSH to the server -- all execution is handled by the scheduled task

When the user asks to "run on multiple environments":
- Write the command file on each server
- Monitor each server's log in parallel

When adding a new environment:
- Create a new `config.<env>.json` with the correct `ServerFqdn`, source/target instances, database names, and `Application` type
- The values should align with the corresponding entry in `DatabasesV2.json`
- Deploy and install once on the new server
```

### Rule 3: no-local-db-creation-in-steps.mdc

```markdown
# No Local Database Creation or Configuration in Step Scripts

## Rule

**NEVER add database creation, restore, configuration, grants, or permissions logic directly in any Step script** (`Step-1-*.ps1`, `Step-2-*.ps1`, `Step-3-*.ps1`, `Step-4-*.ps1`, `Step-5-*.ps1`) or any other script in the `Db2-ShadowDatabase` folder.

All database creation and configuration is handled by:
- `Db2-CreateInitialDatabases/Db2-CreateInitialDatabases.ps1` — the master orchestrator for DB creation
- `_Modules/Db2-Handler/Db2-Handler.psm1` — all DB2 operations (create, restore, configure, grant, catalog)

## What Step scripts are allowed to do

- **Call** `Db2-CreateInitialDatabases.ps1` with the correct parameters (via `pwsh.exe`)
- **Call** functions from `Db2-Handler` module (e.g. `Get-DefaultWorkObjects`, `New-DatabaseAndConfigurations`)
- **Orchestrate** the pipeline flow (decide which steps to run, check exit codes)
- **Log** progress and results
- **Read** config files (`config.*.json`)

## What Step scripts are NOT allowed to do

- Create databases directly (`db2 create database ...`)
- Run `db2 restore` commands directly
- Run `db2 grant` commands directly
- Run `db2 update dbm cfg` or `db2 update db cfg` directly
- Build ad-hoc `$db2Commands` arrays and call `Invoke-Db2ContentAsScript`
- Implement bufferpool sizing, authentication config, or permission logic
- Duplicate or rewrite any logic that already exists in `Db2-Handler.psm1`

## Where to put new functionality

If the pipeline needs new DB2 behavior for `UseNewConfigurations = $true`:

1. Add it to an **existing function** in `_Modules/Db2-Handler/Db2-Handler.psm1`
2. Guard it with `if ($WorkObject.UseNewConfigurations -eq $true)`
3. Keep the original behavior in the `else` branch unchanged
4. Deploy via `_deploy.ps1` (deploys `CommonModules` automatically)

See `shadow-db-fix-policy.mdc` for the full pattern.

## Why

- One source of truth for all DB2 operations
- Prevents drift between step scripts and the module
- Ensures `UseNewConfigurations = $false` path is never broken
- Makes fixes available to ALL callers, not just the shadow pipeline
```
