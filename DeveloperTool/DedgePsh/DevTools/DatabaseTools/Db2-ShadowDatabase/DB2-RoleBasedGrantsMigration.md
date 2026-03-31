# DB2 Role-Based Grants Migration

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-06  
**Technology:** DB2 LUW / PowerShell

---

## Overview

The shadow database pipeline supports two modes for applying database privileges after a restore:

- **Classic mode** (`UseNewConfigurations = $false`): Direct GRANT statements are replayed from the export JSON, one per grantee per object — identical to the source database.
- **Role-based mode** (`UseNewConfigurations = $true`): Direct grants are analyzed, grouped by identical privilege patterns, and converted into DB2 roles. Users and groups receive role membership instead of direct grants.

### Benefits of Role-Based Grants

| Classic (Direct) | Role-Based |
|---|---|
| N users × M privileges = N×M GRANT statements | K roles × M grants + N memberships |
| Adding a new user requires replicating all grants | Adding a user requires one `GRANT ROLE TO USER` |
| Auditing requires inspecting every user's grants | Auditing inspects role definitions only |
| Privilege drift between environments is hard to detect | Roles are named and comparable |

---

## End-to-End Architecture

```mermaid
flowchart LR
    subgraph export_phase ["Export Phase (Db2-GrantsExport.ps1)"]
        DBAUTH["SYSCAT.DBAUTH"]
        TABAUTH["SYSCAT.TABAUTH"]
        ROUTINEAUTH["SYSCAT.ROUTINEAUTH"]
        SCHEMAAUTH["SYSCAT.SCHEMAAUTH"]
        PACKAGEAUTH["SYSCAT.PACKAGEAUTH"]
        INDEXAUTH["SYSCAT.INDEXAUTH"]
        DBAUTH & TABAUTH & ROUTINEAUTH & SCHEMAAUTH & PACKAGEAUTH & INDEXAUTH --> ExportFn["Export-Db2GrantsViaCli"]
        ExportFn --> JSON["grants JSON file<br>(per database)"]
    end

    subgraph import_phase ["Import Phase (Import-Db2GrantsAsRoles)"]
        JSON --> P1["Phase 1:<br>Build Per-Grantee<br>Fingerprints"]
        P1 --> P2["Phase 2:<br>SHA256 Hash<br>Classification"]
        P2 --> P3["Phase 3:<br>Name Roles"]
        P3 --> P4["Phase 4:<br>Generate SQL"]
        P4 --> P5["Phase 5:<br>Execute on DB2"]
    end
```

---

## Classic vs Role-Based Comparison

### Before: Classic Direct Grants

```mermaid
graph TD
    DB[(Database)]
    U1[FKPRDADM]
    U2[FKTSTADM]
    U3[SRV_Dedge]
    U4[SRV_ERP1]

    DB -->|"GRANT DBADM"| U1
    DB -->|"GRANT CONNECT"| U1
    DB -->|"GRANT DBADM"| U2
    DB -->|"GRANT CONNECT"| U2
    DB -->|"GRANT CONNECT"| U3
    DB -->|"GRANT SELECT ON *"| U3
    DB -->|"GRANT INSERT ON *"| U3
    DB -->|"GRANT CONNECT"| U4
    DB -->|"GRANT SELECT ON *"| U4

    style DB fill:#1a1f2e,color:#e6edf3,stroke:#2d3548
    style U1 fill:#232838,color:#e6edf3,stroke:#58a6ff
    style U2 fill:#232838,color:#e6edf3,stroke:#58a6ff
    style U3 fill:#232838,color:#e6edf3,stroke:#d29922
    style U4 fill:#232838,color:#e6edf3,stroke:#d29922
```

Each user gets direct GRANT statements. With M privileges and N users, the total is N×M statements.

### After: Role-Based Grants

```mermaid
graph TD
    DB[(Database)]
    R1[FK_DBA]
    R2[FK_SVC_Dedge]
    R3[FK_READONLY]

    U1[FKPRDADM]
    U2[FKTSTADM]
    U3[SRV_Dedge]
    U4[SRV_ERP1]

    DB -->|"GRANT DBADM + CONNECT"| R1
    DB -->|"GRANT CONNECT + SELECT + INSERT"| R2
    DB -->|"GRANT CONNECT + SELECT"| R3

    R1 -->|"GRANT ROLE"| U1
    R1 -->|"GRANT ROLE"| U2
    R2 -->|"GRANT ROLE"| U3
    R3 -->|"GRANT ROLE"| U4

    style DB fill:#1a1f2e,color:#e6edf3,stroke:#2d3548
    style R1 fill:#232838,color:#3fb950,stroke:#3fb950
    style R2 fill:#232838,color:#d29922,stroke:#d29922
    style R3 fill:#232838,color:#58a6ff,stroke:#58a6ff
    style U1 fill:#232838,color:#e6edf3,stroke:#2d3548
    style U2 fill:#232838,color:#e6edf3,stroke:#2d3548
    style U3 fill:#232838,color:#e6edf3,stroke:#2d3548
    style U4 fill:#232838,color:#e6edf3,stroke:#2d3548
```

Roles consolidate identical privilege sets. Adding user FKTST2ADM with the same privileges as FKPRDADM requires only: `GRANT ROLE FK_DBA TO USER FKTST2ADM`.

---

## Fingerprint Algorithm

The system automatically discovers which grantees share the same privilege pattern using a deterministic fingerprint hash.

```mermaid
flowchart TD
    A["Per-Grantee Privileges<br>(6 grant types)"] --> B["Sort all privileges<br>alphabetically"]
    B --> C["Build fingerprint string<br>DB:flags|TBL:schema.table:flags|RTN:..."]
    C --> D["SHA256 hash<br>first 12 hex chars"]
    D --> E{"Same hash?"}
    E -->|Yes| F["Share a single DB2 role"]
    E -->|No| G["Get their own role"]
```

### How the Fingerprint String Is Built

For each grantee, the function collects privileges from all 6 SYSCAT auth views and builds a sorted, pipe-delimited string:

| Prefix | Source | Flags |
|---|---|---|
| `DB:` | SYSCAT.DBAUTH | CONNECTAUTH, CREATETABAUTH, DBADMAUTH, ... |
| `TBL:schema.table:` | SYSCAT.TABAUTH | SELECTAUTH, INSERTAUTH, UPDATEAUTH, ... |
| `RTN:PROC/FUNC:schema.name` | SYSCAT.ROUTINEAUTH | EXECUTEAUTH |
| `SCH:schema:` | SYSCAT.SCHEMAAUTH | CREATEINAUTH, ALTERINAUTH, DROPINAUTH |
| `PKG:schema.name:` | SYSCAT.PACKAGEAUTH | CONTROLAUTH, BINDAUTH, EXECUTEAUTH |
| `IDX:schema.name` | SYSCAT.INDEXAUTH | CONTROLAUTH |

The string is then hashed with SHA256, and the first 12 hex characters are used as the group key.

### Example

```
Grantee FKPRDADM:
  DB:CONNECTAUTH,DBADMAUTH|SCH:DBM:CREATEINAUTH,ALTERINAUTH,DROPINAUTH
  → SHA256 → "A3F7B2C91D0E"

Grantee FKTSTADM:
  DB:CONNECTAUTH,DBADMAUTH|SCH:DBM:CREATEINAUTH,ALTERINAUTH,DROPINAUTH
  → SHA256 → "A3F7B2C91D0E"  (same hash → same role)
```

---

## Role Naming Convention

The system auto-generates role names based on the dominant privilege pattern:

| Pattern Detected | Role Name | Example |
|---|---|---|
| Has `DBADMAUTH` | `FK_DBA` | Full admin users |
| All tables: SELECT only | `FK_READONLY` | Read-only reporting |
| All tables: SELECT+INSERT+UPDATE+DELETE | `FK_READWRITE` | Application accounts |
| First member starts with `SRV_` | `FK_SVC_<name>` | `FK_SVC_Dedge` |
| GranteeType is `G` (group) | `FK_GRP_<name>` | `FK_GRP_DB2ADMNS` |
| Other patterns | `FK_CUSTOM_<name>` | `FK_CUSTOM_APPUSER` |

### Collision Handling

If the same role name would be generated for two groups with different privilege fingerprints, a numeric suffix is appended: `FK_DBA_2`, `FK_DBA_3`, etc.

---

## SQL Execution Sequence

The generated SQL follows this strict order:

```mermaid
flowchart TD
    S1["1. CREATE ROLE rolename"] --> S2["2. GRANT privileges TO ROLE rolename"]
    S2 --> S3["3. GRANT ROLE rolename TO USER/GROUP"]
    S3 --> S4["4. PUBLIC grants<br>(direct, no role)"]

    style S1 fill:#232838,color:#3fb950,stroke:#3fb950
    style S2 fill:#232838,color:#58a6ff,stroke:#58a6ff
    style S3 fill:#232838,color:#d29922,stroke:#d29922
    style S4 fill:#232838,color:#e6edf3,stroke:#2d3548
```

1. **CREATE ROLE**: Each unique fingerprint group gets a role
2. **GRANT TO ROLE**: All privileges from the fingerprint are granted to the role
3. **GRANT ROLE TO USER/GROUP**: Each member receives role membership
4. **PUBLIC grants**: Applied directly (DB2 limitation: PUBLIC cannot hold role membership)

### SQL Examples

```sql
-- Step 1: Create roles
CREATE ROLE FK_DBA;
CREATE ROLE FK_SVC_Dedge;
CREATE ROLE FK_READONLY;

-- Step 2: Grant privileges to roles
GRANT DBADM, CONNECT ON DATABASE TO ROLE FK_DBA;
GRANT CONNECT ON DATABASE TO ROLE FK_SVC_Dedge;
GRANT SELECT ON TABLE DBM.CUSTOMERS TO ROLE FK_SVC_Dedge;
GRANT CONNECT ON DATABASE TO ROLE FK_READONLY;
GRANT SELECT ON TABLE DBM.CUSTOMERS TO ROLE FK_READONLY;

-- Step 3: Assign users to roles
GRANT ROLE FK_DBA TO USER FKPRDADM;
GRANT ROLE FK_DBA TO USER FKTSTADM;
GRANT ROLE FK_SVC_Dedge TO USER SRV_Dedge;
GRANT ROLE FK_READONLY TO USER SRV_ERP1;

-- Step 4: PUBLIC grants (direct)
GRANT CONNECT ON DATABASE TO PUBLIC;
GRANT EXECUTE ON PROCEDURE DBM.MY_PROC TO PUBLIC;
```

---

## Special Cases

### PUBLIC Grants

DB2 does not allow `GRANT ROLE TO PUBLIC`. All grants where the grantee is `PUBLIC` are preserved as direct GRANT statements, bypassing the role system entirely.

### System Accounts

Grantees `SYSIBM` and `SYSIBMINTERNAL` are internal DB2 system accounts. Their grants are always skipped during import — they are managed by DB2 itself.

### UseNewConfigurations Gate

The entire role-based conversion is gated by the `UseNewConfigurations` flag:

```mermaid
flowchart TD
    Import["Db2-GrantsImport.ps1"] --> Check{"UseNewConfigurations?"}
    Check -->|"$true"| RoleBased["Import-Db2GrantsAsRoles<br>(role-based)"]
    Check -->|"$false"| Classic["Import-Db2Grants<br>(direct grants)"]

    style Import fill:#1a1f2e,color:#e6edf3,stroke:#2d3548
    style Check fill:#232838,color:#d29922,stroke:#d29922
    style RoleBased fill:#232838,color:#3fb950,stroke:#3fb950
    style Classic fill:#232838,color:#58a6ff,stroke:#58a6ff
```

This ensures existing production workflows are unaffected until the flag is explicitly enabled.

---

## Integration with Shadow Pipeline

The role-based grants import is invoked during the shadow pipeline through `Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1`, which sets `UseNewConfigurations = $true`.

```mermaid
sequenceDiagram
    participant Pipeline as Run-FullShadowPipeline
    participant Step1 as Step-1 (Create Shadow)
    participant CreateDB as Db2-CreateInitialDatabases<br>StdAllUseNewConfig
    participant Handler as Db2-Handler.psm1
    participant Step4 as Step-4 (Move Back)

    Pipeline->>Step1: Create shadow instance + DB
    Step1->>CreateDB: UseNewConfigurations = $true
    CreateDB->>Handler: Import-Db2GrantsAsRoles
    Handler-->>CreateDB: Roles created + assigned

    Pipeline->>Step4: Move shadow back
    Step4->>CreateDB: Recreate on original instance
    CreateDB->>Handler: Import-Db2GrantsAsRoles
    Handler-->>CreateDB: Roles created + assigned
```

---

## Source Code References

| Component | Location |
|---|---|
| Grant Export (CLI) | `Db2-Handler.psm1` → `Export-Db2GrantsViaCli` (line ~14432) |
| Grant Export Script | `DevTools/DatabaseTools/Db2-GrantsExport/Db2-GrantsExport.ps1` |
| Grant Import (classic) | `Db2-Handler.psm1` → `Import-Db2Grants` (line ~14800) |
| Grant Import (roles) | `Db2-Handler.psm1` → `Import-Db2GrantsAsRoles` (line ~14904) |
| Import Router | `DevTools/DatabaseTools/Db2-GrantsImport/Db2-GrantsImport.ps1` |
| Grantee Clause Helper | `Db2-Handler.psm1` → `Get-GranteeClause` (line ~15471) |
| Pipeline Integration | `DevTools/DatabaseTools/Db2-CreateInitialDatabases/Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1` |
