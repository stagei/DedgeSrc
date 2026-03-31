# Checklist: FederatedDb → Alias Conversion per Database

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-02  
**Technology:** DB2 / PowerShell

---

## Overview

When converting a database from the old federated setup (separate DB2FED instance with NTLM) to the new alias setup (single DB2 instance with KerberosServerEncrypt), these checks must be performed **on the database server** after the pipeline completes.

The `Run-FullShadowPipeline.ps1` script automates the entire pipeline, but the checks below should be verified manually after each database conversion.

---

## Pre-Conversion: What Changes

| Component | Old (Federated) | New (Alias) |
|---|---|---|
| XINL* AccessPointType | `FederatedDb` | `Alias` |
| XINL* InstanceName | `DB2FED` | `DB2` (same as primary) |
| XINL* NodeName | `NODEFED` | `XINL*` (= CatalogName) |
| XINL* AuthenticationType | `Ntlm` | `KerberosServerEncrypt` |
| XINL* Port | `50010` | `50010` (unchanged) |
| DB2FED instance | Required, separate instance | Not needed |
| DBM AUTHENTICATION | `KERBEROS` | `KRB_SERVER_ENCRYPT` |
| DBM SRVCON_AUTH | `KERBEROS` | `KRB_SERVER_ENCRYPT` |
| DBM ALTERNATE_AUTH_ENC | (not set) | `AES_ONLY` |

---

## Databases to Convert

| Database | Server | X-Alias | Status |
|---|---|---|---|
| INLTST | t-no1inltst-db | XINLTST | DONE |
| INLDEV | t-no1inldev-db | XINLDEV | DONE (JSON only) |
| FKMTST | t-no1fkmtst-db | XFKMTST | Pending |
| FKMDEV | t-no1fkmdev-db | XFKMDEV | Pending |
| FKMRAP | p-no1fkmrap-db | XFKMRAP | Pending |
| FKMPRD | p-no1fkmprd-db | XFKMPRD | Pending |
| FKMHST | p-no1fkmprd-db | XFKMHST | Pending |
| INLPRD | p-no1inlprd-db | XINLPRD | Pending |
| LOGTST | t-no1fkxtst-db | XLOGTST | Pending |
| DOCTST | t-no1fkxtst-db | XDOCTST | Pending |
| DBQTST | t-no1fkxtst-db | XDBQTST | Pending |
| VISPRD | p-no1visprd-db | XVISPRD | Pending |
| DOCPRD | p-no1docprd-db | XDOCPRD | Pending |
| FKMPER | t-no1fkmper-db | XFKMPER | Pending |
| FKMKAT | t-no1fkmkat-db | XFKMKAT | Pending |
| FKMVFT | t-no1fkmvft-db | XFKMVFT | Pending |
| HSTVFT | t-no1fkmvft-db | XIHSTVFT | Pending |
| FKMVFK | t-no1fkmvfk-db | XFKMVFK | Pending |
| FKMFUT | t-no1fkmfut-db | XFKMFUT | Pending |

---

## Server-Side Checks After Conversion

Run these checks **on the database server** after the pipeline completes for each database.

### 1. DatabasesV2.json Verification

```powershell
# Verify the JSON on the app server has no FederatedDb for this database
$json = Get-Content "\\<app-server>\DedgeCommon\Configfiles\DatabasesV2.json" -Raw | ConvertFrom-Json
$db = $json | Where-Object { $_.Database -eq "<DATABASE>" }
$db.AccessPoints | Format-Table AccessPointType, CatalogName, InstanceName, NodeName, Port, AuthenticationType -AutoSize
```

- [ ] No `FederatedDb` access point exists for this database
- [ ] `XINL*` entry has `AccessPointType = Alias`
- [ ] `XINL*` entry has `InstanceName = DB2` (same as PrimaryDb)
- [ ] `XINL*` entry has `AuthenticationType = KerberosServerEncrypt`
- [ ] `XINL*` entry has `Port = 50010` (unchanged)

### 2. DBM Configuration (on DB server)

```cmd
set DB2INSTANCE=DB2
db2 get dbm cfg | findstr /i "AUTHENTICATION SRVCON_AUTH ALTERNATE_AUTH_ENC"
```

- [ ] `AUTHENTICATION` = `KRB_SERVER_ENCRYPT`
- [ ] `SRVCON_AUTH` = `KRB_SERVER_ENCRYPT`
- [ ] `ALTERNATE_AUTH_ENC` = `AES_ONLY`

### 3. Database Catalog Directory

```cmd
set DB2INSTANCE=DB2
db2 list database directory
```

- [ ] Primary database (e.g., `INLTST`) is cataloged as `Indirect` (local)
- [ ] Primary catalog alias (e.g., `FKKTOTST`) is cataloged at its node with `KERBEROS` auth
- [ ] X-alias (e.g., `XINLTST`) is cataloged at its node with `KERBEROS` auth
- [ ] No reference to `DB2FED` instance in the catalog

### 4. Node Directory

```cmd
set DB2INSTANCE=DB2
db2 list node directory
```

- [ ] Node for X-alias (e.g., `XINLTST`) exists with correct port (`50010`)
- [ ] No `NODEFED` node remains (unless other databases still use federation)

### 5. Services File

```powershell
Get-Content "$env:SystemRoot\system32\drivers\etc\services" | Select-String "50010"
```

- [ ] Port `50010` has a service entry (e.g., `DB2FED`) mapped to the DB2 instance

### 6. Firewall Rules

```powershell
Get-NetFirewallRule -DisplayName "*DB2*" | Get-NetFirewallPortFilter | Format-Table LocalPort, Protocol -AutoSize
```

- [ ] Port `50010` is open for TCP inbound
- [ ] Port `50000` is open for TCP inbound
- [ ] Port for primary catalog alias (e.g., `3718`) is open for TCP inbound

### 7. DB2 Client Connectivity (from developer machine)

```cmd
db2 connect to <XINL-ALIAS>
db2 "SELECT CURRENT SERVER FROM SYSIBM.SYSDUMMY1"
db2 connect reset
```

- [ ] Connection succeeds using Kerberos SSO (no password prompt)
- [ ] `CURRENT SERVER` returns the correct database name

### 8. JDBC Connectivity (DBeaver or Java test)

```
JDBC URL: jdbc:db2://<server>.DEDGE.fk.no:50010/<DATABASE>
Security: securityMechanism=9 (encrypted password)
```

- [ ] JDBC connection via port `50010` succeeds with user/password
- [ ] Query returns data from the correct database

### 9. COBOL Application Connectivity

- [ ] COBOL applications using the X-alias can connect
- [ ] No `SQL30082N` errors in application logs

### 10. DB2FED Instance Cleanup (optional, after all databases converted)

Once ALL databases on a server are converted, the old DB2FED instance can be removed:

```cmd
set DB2INSTANCE=DB2FED
db2stop force
db2idrop DB2FED
```

- [ ] Verify no remaining databases in DB2FED: `db2 list database directory`
- [ ] Stop and drop instance only after all X-aliases are migrated
- [ ] Remove DB2FED Windows service if it still exists

---

## Automated Pipeline Execution

### Full pipeline (PRD restore → shadow → copy → verify → move back)

```powershell
pwsh.exe -NoProfile -File ".\Run-FullShadowPipeline.ps1"
```

### Skip PRD restore (source DB already has fresh data)

```powershell
pwsh.exe -NoProfile -File ".\Run-FullShadowPipeline.ps1" -SkipPrdRestore
```

### Only move shadow back + verify (shadow already verified)

```powershell
pwsh.exe -NoProfile -File ".\Run-FullShadowPipeline.ps1" -SkipPrdRestore -SkipShadowCreate -SkipCopy -SkipVerify
```

### Stop after verification (review before overwriting original)

```powershell
pwsh.exe -NoProfile -File ".\Run-FullShadowPipeline.ps1" -StopAfterVerify
```

---

## Rollback

If the conversion fails or causes issues:

1. **DatabasesV2.json**: Restore from the `.bak.*` backup file created by Phase 0
2. **DBM Config**: Revert authentication:
   ```cmd
   db2 update dbm cfg using AUTHENTICATION KERBEROS
   db2 update dbm cfg using SRVCON_AUTH KERBEROS
   db2stop force && db2start
   ```
3. **Database**: Restore from the pre-conversion backup (created in Step 4 Phase 1)

---

## Notes

- Phase 0 in Step 4 is **idempotent** — it skips conversion if the database already has no FederatedDb entry
- The DB2 catalog command always uses `AUTHENTICATION KERBEROS` (not `KRB_SERVER_ENCRYPT`) because `KRB_SERVER_ENCRYPT` is a server-side DBM parameter, not a catalog parameter
- `UseNewConfigurations = $true` gates all new behavior — old configs still work with `UseNewConfigurations = $false`
- The `FKMPRD ↔ FKMHST` "History" federation (nicknames) is unaffected by this conversion — it uses explicit database names and does not depend on FederatedDb access points
