# Plan: DB2 Role-Based Access Control (RBAC)

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-02  
**Technology:** DB2 LUW / PowerShell  

---

## Overview

The current `Db2-Handler.psm1` permission model grants privileges **directly to individual users and groups** (DB2ADMNS, DB2USERS, SRV_KPDB, ISYS, FORIT, etc.). DB2 roles are not used. This document proposes migrating to a role-based model.

---

## Current State — Problems

### 1. Hardcoded user lists
`Get-DefaultDb2AdminUsers` returns a fixed array:
```powershell
@("FKGEISTA", "FKSVEERI", "DB2NT", "SRV_SFKSS07", "SRV_DB2", $env:USERNAME, "FKPRDADM", "FKTSTADM", "FKDEVADM")
```
Adding/removing a person requires a code change, deploy, and re-run of permissions.

### 2. Per-user table grants
`Add-SpecificGrants` issues `GRANT ... TO USER <name>` for every table × every user. For FKM alone this is 50+ tables × 6+ users = 300+ individual GRANT statements. On restore, all must be re-applied.

### 3. No separation of concerns
Every admin user gets the same full set of privileges (`DBADM`, `DATAACCESS`, `ACCESSCTRL`, `SECADM`, etc.). There's no distinction between a DBA, a read-only analyst, a service account, or an application user.

### 4. Environment duplication
The same grant logic appears in:
- `Set-DatabasePermissions` (post-restore admin grants)
- `Add-SpecificGrants` (application-specific table grants)
- `Set-StandardConfigurations` (DBADM to current user)
- `Step-Fix-ApplyPermissions.ps1` (shadow pipeline fix script)

---

## Proposed Role Model

### Suggested DB2 Roles

| Role | Purpose | Key Privileges |
|------|---------|---------------|
| `FK_DBA` | Database administrators | DBADM, DATAACCESS, ACCESSCTRL, SECADM, LOAD, all db-level |
| `FK_READONLY` | Read-only analysts, data warehouse | SELECT on all application schemas |
| `FK_READWRITE` | Standard application users | SELECT, INSERT, UPDATE, DELETE on application schemas |
| `FK_SVC_KPDB` | Service account: KP database integration | Specific table grants (current SRV_KPDB grants) |
| `FK_SVC_BIZTALK` | Service account: BizTalk integration | Specific table grants (current SRV_BIZTALKHIA grants) |
| `FK_SVC_ISYS` | Service account: ISYS EDI integration | Specific table grants (current ISYS grants) |
| `FK_SVC_FORIT` | Service account: Forit production system | Specific table grants (current FORIT grants) |
| `FK_SVC_CRM` | Service account: CRM integration | Specific table grants (current SRV_CRM grants) |
| `FK_EXECUTE` | Execute privileges on FK.* functions | EXECUTE on all FK schema functions |

### Schema Coverage

All roles with table access cover these schemas (matching current `AllTablesSchemaFilter`):

```
CRM, DBM, ESM, DV, TV, HST, INL, TMS, LOG
```

---

## Migration Plan

### Phase 1: Create roles (non-breaking)

Add a new function `New-Db2StandardRoles` to `Db2-Handler.psm1`:

```powershell
function New-Db2StandardRoles {
    param([PSCustomObject]$WorkObject)

    $db2Commands = @()
    $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $db2Commands += Get-ConnectCommand -WorkObject $WorkObject

    $roles = @("FK_DBA", "FK_READONLY", "FK_READWRITE",
               "FK_SVC_KPDB", "FK_SVC_BIZTALK", "FK_SVC_ISYS",
               "FK_SVC_FORIT", "FK_SVC_CRM", "FK_EXECUTE")

    foreach ($role in $roles) {
        # CREATE ROLE is idempotent-safe with IF NOT EXISTS in DB2 11.5+
        $db2Commands += "db2 `"CREATE ROLE $role`""
    }

    $db2Commands += "db2 terminate"
    return $db2Commands
}
```

### Phase 2: Grant privileges to roles

Replace the per-user grant arrays in `Add-SpecificGrants` with role-based grants:

```powershell
# Instead of granting to USER SRV_KPDB directly:
$db2Commands += "db2 grant SELECT,INSERT,UPDATE,DELETE on table DBM.VK_VARE_KATEGORI to role FK_SVC_KPDB"

# Instead of per-user schema-wide SELECT:
$db2Commands += "db2 grant SELECT on table $schema.$table to role FK_READONLY"
$db2Commands += "db2 grant SELECT,INSERT,UPDATE,DELETE on table $schema.$table to role FK_READWRITE"
```

### Phase 3: Assign users to roles

Replace `Get-DefaultDb2AdminUsers` with role membership:

```powershell
function Set-Db2RoleMemberships {
    param([PSCustomObject]$WorkObject)

    $db2Commands = @()
    $db2Commands += Get-ConnectCommand -WorkObject $WorkObject

    # DBA role members
    $dbaUsers = @("FKGEISTA", "FKSVEERI", "DB2NT", $env:USERNAME,
                  "FKPRDADM", "FKTSTADM", "FKDEVADM")
    foreach ($user in $dbaUsers) {
        $db2Commands += "db2 `"GRANT ROLE FK_DBA TO USER $user`""
    }

    # Service accounts → their specific roles
    $db2Commands += "db2 `"GRANT ROLE FK_SVC_KPDB TO USER SRV_KPDB`""
    $db2Commands += "db2 `"GRANT ROLE FK_SVC_BIZTALK TO USER SRV_BIZTALKHIA`""
    $db2Commands += "db2 `"GRANT ROLE FK_SVC_ISYS TO USER ISYS`""
    $db2Commands += "db2 `"GRANT ROLE FK_SVC_FORIT TO USER FORIT`""
    $db2Commands += "db2 `"GRANT ROLE FK_SVC_CRM TO USER SRV_CRM`""

    # Read-only
    $db2Commands += "db2 `"GRANT ROLE FK_READONLY TO USER SRV_DATAVAREHUS`""
    $db2Commands += "db2 `"GRANT ROLE FK_READONLY TO GROUP DB2USERS`""

    # Read/write standard user
    $stdUser = switch ($WorkObject.Environment) {
        "PRD" { "FKPRDUSR" }
        "DEV" { "FKDEVUSR" }
        default { "FKTSTSTD" }
    }
    $db2Commands += "db2 `"GRANT ROLE FK_READWRITE TO USER $stdUser`""

    $db2Commands += "db2 terminate"
    return $db2Commands
}
```

### Phase 4: Update Set-DatabasePermissions

```powershell
# Current: loops through AdminUsers and grants 15 privileges each
# New: grant FK_DBA role, which already has all those privileges
$db2Commands += "db2 `"GRANT ROLE FK_DBA TO USER $($env:USERNAME)`""
$db2Commands += "db2 `"GRANT ROLE FK_DBA TO GROUP DB2ADMNS`""
```

### Phase 5: Update shadow pipeline

The shadow pipeline's `Step-Fix-ApplyPermissions.ps1` and control verification should call:

```powershell
New-Db2StandardRoles -WorkObject $workObj
Set-Db2RoleMemberships -WorkObject $workObj
Add-SpecificGrants -WorkObject $workObj  # now grants to roles, not users
```

---

## Benefits

| Aspect | Current | With Roles |
|--------|---------|-----------|
| Add a new DBA | Code change + deploy + re-run grants | `GRANT ROLE FK_DBA TO USER newuser` |
| Add a new service account | Add to grant array + deploy | `GRANT ROLE FK_SVC_xxx TO USER newsvc` |
| Post-restore permissions | 300+ individual GRANTs | Create roles + assign members (faster) |
| Audit who has access | Query SYSCAT.DBAUTH per user | `SELECT * FROM SYSCAT.ROLEAUTH` |
| Revoke access | Find and revoke individual grants | `REVOKE ROLE FK_DBA FROM USER olduser` |
| Grant count (FKM example) | ~300+ statements | ~50 role grants + ~15 membership grants |

---

## Risks and Considerations

1. **DB2 version**: `CREATE ROLE` requires DB2 9.5+. All environments are 12.1 LUW — no issue.
2. **Windows group interaction**: `DB2ADMNS` and `DB2USERS` are Windows local groups used for instance-level auth. Roles complement these, they don't replace them. Keep `SYSADM_GROUP = DB2ADMNS`.
3. **DBADM cannot be granted to a role**: DB2 does not allow `GRANT DBADM TO ROLE`. DBADM must remain a per-user/group grant. The `FK_DBA` role covers everything *except* DBADM — that stays as `GRANT DBADM ON DATABASE TO GROUP DB2ADMNS`.
4. **Backward compatibility**: During migration, keep both direct grants and role grants active. Remove direct grants only after verifying role-based access works.
5. **Federation removed**: With the move away from DB2FED instances, the `DB2FED`-specific grants in the current code can be dropped.

---

## Implementation Priority

1. **Start with FK_READONLY and FK_READWRITE** — highest volume of duplicate grants, biggest cleanup win
2. **Then FK_SVC_* service roles** — cleanest separation, easiest to test per-application
3. **FK_DBA last** — most sensitive, needs careful testing with DBADM limitation
4. **Externalize role membership to JSON** — move the user→role mapping out of code into a config file (e.g. `db2-role-memberships.json` in DatabasesV2 or Db2-Handler config)

---

## Open Questions

- Should `FK_EXECUTE` be a separate role or folded into `FK_READWRITE`?
- Should environment-specific service accounts (e.g. `SRV_TST_BIZTALKHIA` vs `SRV_BIZTALKHIA`) map to the same role or separate roles?
- Should the role membership config live in `DatabasesV2.json` alongside access points, or in a separate file?
