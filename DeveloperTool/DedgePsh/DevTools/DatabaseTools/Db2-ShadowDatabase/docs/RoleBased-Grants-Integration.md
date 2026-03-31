# Role-Based Grant Import — Design and Integration Guide

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-13  
**Technology:** DB2 / PowerShell

---

## Overview

The `Import-Db2GrantsAsRoles` function converts a standard grant export JSON (produced by `Export-Db2Grants`) into a role-based privilege model. Instead of granting privileges directly to users and groups, it:

1. Analyzes each grantee's complete privilege set
2. Groups grantees who share identical privileges
3. Creates one DB2 ROLE per unique privilege set
4. Grants all privileges to the role
5. Grants role membership to the original users/groups
6. Revokes the original direct grants

This function is **only** triggered when `Db2-GrantsImport.ps1` is called with `-UseNewConfigurations:$true`. It has no effect on any other code path.

---

## How Auto-Derive Works

### Step 1 — Build a Fingerprint Per Grantee

Every grantee in the export JSON gets a "fingerprint" — a normalized snapshot of all their privileges across all grant types (database, table, routine, schema, package, index).

```
FKGEISTA fingerprint:
  DB:  DBADM, DATAACCESS, SECADM, CONNECT, CREATETAB, ...
  TBL: ALL on DBM.*, CRM.*, ESM.*, ...
  RTN: EXECUTE on FK.CD2D, FK.D2CD, ...

FKTSTDBA fingerprint:
  DB:  DBADM, CONNECT
  TBL: ALL on DBM.*, CRM.*, ESM.*, ...
  RTN: (none)

SRV_KPDB fingerprint:
  DB:  CONNECT
  TBL: SIUD on 50 specific DBM tables
  RTN: EXECUTE on 24 FK functions
```

### Step 2 — Classify Each Fingerprint

Each fingerprint is classified by its dominant pattern:

| Classification | Rule |
|---|---|
| DBA | Has DBADM in database-level grants |
| READONLY | Only SELECT on tables, no write privileges |
| READWRITE | Has SELECT + INSERT + UPDATE + DELETE on tables |
| FULL | Has CONTROL or ALL on tables |
| CUSTOM | Mixed or specific per-table grants |

### Step 3 — Group Identical Fingerprints

Grantees with **exactly identical** fingerprints share one role. If two DBA users have different database-level privileges (e.g., one has SECADM, the other does not), they get separate roles.

### Step 4 — Create Roles and Transfer Privileges

For each unique fingerprint group, the function generates:

```sql
CREATE ROLE FK_DBA;                              -- create the role
GRANT DBADM ON DATABASE TO ROLE FK_DBA;          -- transfer privileges to role
GRANT ALL ON DBM.KUNDER TO ROLE FK_DBA;          -- ... for every table
GRANT ROLE FK_DBA TO USER FKGEISTA;              -- grant membership
GRANT ROLE FK_DBA TO USER FKSVEERI;              -- (all users with same fingerprint)
REVOKE DBADM ON DATABASE FROM USER FKGEISTA;     -- remove direct grant
REVOKE ALL ON DBM.KUNDER FROM USER FKGEISTA;     -- ... for every table
```

---

## Example: Different DBA Users with Different Access Levels

Consider a database where three users have DBADM, but with different privilege sets:

### Before (Direct Grants)

| Grantee | DB-Level Privs | Table Privs | Routine Privs |
|---|---|---|---|
| FKGEISTA | DBADM, DATAACCESS, SECADM, CONNECT, CREATETAB | ALL on 500 tables | EXECUTE on 30 routines |
| FKSVEERI | DBADM, DATAACCESS, SECADM, CONNECT, CREATETAB | ALL on 500 tables | EXECUTE on 30 routines |
| FKTSTDBA | DBADM, CONNECT | ALL on 500 tables | (none) |

FKGEISTA and FKSVEERI have identical fingerprints. FKTSTDBA has a different fingerprint (fewer DB-level privs, no routine grants).

### After (Role-Based)

| Role Created | Privileges on Role | Members |
|---|---|---|
| FK_DBA | DBADM, DATAACCESS, SECADM, CONNECT, CREATETAB + ALL on 500 tables + EXECUTE on 30 routines | FKGEISTA, FKSVEERI |
| FK_DBA_FKTSTDBA | DBADM, CONNECT + ALL on 500 tables | FKTSTDBA |

FKGEISTA and FKSVEERI share `FK_DBA` because their fingerprints match exactly. FKTSTDBA gets a dedicated role because his privilege set is different.

---

## Role Naming Convention

| Pattern | Role Name | Shared? |
|---|---|---|
| DBA (identical privs) | `FK_DBA` | Yes — all DBA users with same fingerprint |
| DBA (unique privs) | `FK_DBA_<GRANTEE>` | No — one role per user |
| Read-only | `FK_READONLY` | Yes |
| Read-write | `FK_READWRITE` | Yes |
| Service account | `FK_SVC_<NAME>` | No — one role per service account |
| Group | `FK_GRP_<GROUP>` | No — one role per group |
| Other | `FK_CUSTOM_<GRANTEE>` | No |

---

## PUBLIC Grants

Grants to `PUBLIC` are **not** converted to roles. PUBLIC is a DB2 pseudo-entity that cannot receive role membership. PUBLIC grants remain as direct grants.

---

## Isolation from Other Code Paths

This function is completely isolated from all existing grant and permission code.

| Code Path | Trigger | Affected? |
|---|---|---|
| `Add-SpecificGrants` | Called during DB creation pipeline via WorkObject | NOT affected |
| `Set-DatabasePermissions` | Called during DB creation pipeline via WorkObject | NOT affected |
| `Import-Db2Grants` | Called from `Db2-GrantsImport.ps1` when UseNewConfigurations is false (default) | NOT affected |
| `$WorkObject.UseNewConfigurations` | Set by shadow DB pipeline, restore, federation | NOT connected — separate property on a separate object |
| **`Import-Db2GrantsAsRoles`** | **Called from `Db2-GrantsImport.ps1` ONLY when `-UseNewConfigurations:$true`** | **This is the new function** |

The `[bool]$UseNewConfigurations` on the import launcher and the `$WorkObject.UseNewConfigurations` on the shadow DB pipeline are **completely separate parameters on completely separate functions**. One cannot trigger the other.

---

## Shadow Database Pipeline Integration

The shadow pipeline (`Run-FullShadowPipeline.ps1`) calls the grant import **after Step 4** restores the database on the original instance. At that point `DatabasesV2.json` lookups resolve correctly — no instance override is needed.

### Parameter

`[bool]$UseRoleBasedGrants = $true` on `Run-FullShadowPipeline.ps1`:

| Value | Behavior |
|---|---|
| `$true` (default) | Calls `Db2-GrantsImport.ps1 -UseNewConfigurations $true` → `Import-Db2GrantsAsRoles` creates roles, revokes redundant direct grants |
| `$false` | Calls `Db2-GrantsImport.ps1` (no `-UseNewConfigurations`) → `Import-Db2Grants` re-applies production grants as classic direct grants |

### Sequence

1. Step 4 restores the database and runs the standard pipeline (`Set-DatabasePermissions` + `Add-SpecificGrants` apply direct grants)
2. Grant Import step calls `$env:OptPath\DedgePshApps\Db2-GrantsImport\Db2-GrantsImport.ps1 -DatabaseName <SourceDatabase>`
3. The import function auto-finds the latest weekly grant export JSON from `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants\`
4. When role-based: `Import-Db2GrantsAsRoles` revokes the direct grants from step 1 and replaces them with DB2 roles
5. Step 6b (PostMove verification) runs on the final state

### Federated Grants

The federated database does not exist after Step 4 restore. The weekly export JSON covers only the primary database (`SYSCAT.*` for the connected DB). Nickname-table grants (HST schema) may appear in the JSON but are harmlessly skipped — the tables don't exist and `Invoke-Db2ContentAsScript -IgnoreErrors` handles this.

### No Core Module Changes

`Set-DatabasePermissions`, `Add-SpecificGrants`, `Import-Db2GrantsAsRoles`, and `Db2-GrantsImport.ps1` are all used as-is. The pipeline only adds the call.

---

## System Accounts Excluded

The following grantees are **always skipped** (their grants are DB2-internal and cannot/should not be revoked):

- SYSIBM
- SYSIBMINTERNAL
- IBM internal accounts

---

## Running the Conversion

```powershell
# Standard import (direct grants, unchanged behavior)
pwsh.exe -NoProfile -File "Db2-GrantsImport.ps1" -DatabaseName "FKMTST"

# Role-based import (new behavior, explicit opt-in)
pwsh.exe -NoProfile -File "Db2-GrantsImport.ps1" -DatabaseName "FKMTST" -UseNewConfigurations:$true
```
