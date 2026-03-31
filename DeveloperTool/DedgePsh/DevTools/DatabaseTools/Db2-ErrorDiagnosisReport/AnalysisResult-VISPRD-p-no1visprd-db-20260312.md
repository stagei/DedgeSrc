# DB2 Diagnosis Report — VISPRD (p-no1visprd-db)

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-12  
**Source report:** `\\p-no1visprd-db\opt\data\Db2-ErrorDiagnosisReport\Db2-ErrorDiagnosisReport_p-no1visprd-db_20260312_062612.txt`  
**DB2 Version:** 12.1.1000.77 Fix Pack 0  
**Instance:** DB2 | **Database:** VISPRD  
**OS:** Windows Server 2025 Datacenter  
**Service account:** `DEDGE\p1_srv_visprd_db`

---

## Summary

| Priority | Count |
|---|---|
| 🔴 High | 2 |
| 🟡 Medium | 3 |
| 🟢 Low | 1 |

---

## 🔴 REC-01 — Community Edition on Production Server

**Category:** Licensing  
**Status:** Open

### Observation
The installed DB2 edition is **Developer Community Edition**:

```
INSTALLED_PROD: DEC = DB2_DEVELOPER_C_EDITION
LICENSE_TYPE:   COMMUNITY
```

The server has **16 GB physical RAM**, but the Community Edition enforces an **8 GB memory cap**. Running Community Edition on a production server is outside IBM licensing terms and imposes hard resource limits that cannot be bypassed.

### Recommendation
- Verify the intended license tier for `p-no1visprd-db`
- Install **DB2 Standard** or **Enterprise Edition** if this is a production workload
- Until the license is upgraded, the instance is capped at 8 GB usable memory regardless of available hardware

### DB2 Commands to Verify
```sql
SELECT INSTALLED_PROD, INSTALLED_PROD_FULLNAME, LICENSE_TYPE
FROM SYSIBMADM.ENV_PROD_INFO
WHERE LICENSE_INSTALLED = 'Y'
```

---

## 🔴 REC-02 — DATABASE_MEMORY Fixed — STMM Cannot Self-Tune Memory Pool

**Category:** Memory / Performance  
**Status:** Open

### Observation
`SELF_TUNING_MEM = ON` is set, but `DATABASE_MEMORY` and all major memory consumers are **fixed values**, not `AUTOMATIC`. This means STMM can rebalance components *within* the fixed pool but cannot resize the pool to match workload demand.

Current values:

| Parameter | Current Value | Recommended |
|---|---|---|
| `DATABASE_MEMORY` | `1048576` (4 GB fixed) | `AUTOMATIC` |
| `LOCKLIST` | `2000` (fixed) | `AUTOMATIC` |
| `SHEAPTHRES_SHR` | `10000` (fixed) | `AUTOMATIC` |
| `SORTHEAP` | `10000` (fixed) | `AUTOMATIC` |
| `PCKCACHESZ` | `2560` (fixed) | `AUTOMATIC` |

### Recommendation
Set all STMM-tunable parameters to `AUTOMATIC` so DB2 can manage the full memory pool dynamically. This is especially important given the 8 GB Community Edition cap.

### DB2 Commands to Apply
```sql
-- Connect as instance owner or SYSADM
db2 connect to VISPRD
db2 "UPDATE DB CFG FOR VISPRD USING SELF_TUNING_MEM ON"
db2 "UPDATE DB CFG FOR VISPRD USING DATABASE_MEMORY AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING LOCKLIST AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING SHEAPTHRES_SHR AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING SORTHEAP AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING PCKCACHESZ AUTOMATIC"
db2 connect reset
```

> **Note:** `DATABASE_MEMORY AUTOMATIC` takes effect after a database deactivate/activate cycle.

---

## 🟡 REC-03 — DB2FED Service Running as LocalSystem Instead of Service Account

**Category:** Security / Federation  
**Status:** Open

### Observation
The `DB2FED` instance service runs as `LocalSystem`, while the main `DB2` instance correctly runs as the domain service account:

| Service | StartName | Expected |
|---|---|---|
| `DB2-0` (DB2 instance) | `DEDGE\p1_srv_visprd_db` | ✅ Correct |
| `DB2FED` (federated instance) | `LocalSystem` | ❌ Inconsistent |

`LocalSystem` cannot obtain Kerberos tickets, which means that if federation is ever activated on VISPRD, cross-server queries will fail with Kerberos/authentication errors.

Additionally, no federated servers or nicknames are currently configured (`SYSCAT.SERVERS = 0 rows`, `SYSCAT.NICKNAMES = 0 rows`), so this is not currently causing issues.

### Recommendation
- If `DB2FED` is not in use on VISPRD, consider leaving it as-is or disabling the service
- If federation will be used, change the `DB2FED` service logon to `DEDGE\p1_srv_visprd_db` (same as DB2-0) to ensure Kerberos delegation works

### How to Change Service Account
```powershell
# Run on p-no1visprd-db as administrator
$svc = Get-WmiObject Win32_Service -Filter "Name='DB2FED'"
$svc.Change($null, $null, $null, $null, $null, $null, "DEDGE\p1_srv_visprd_db", "<password>")
Restart-Service DB2FED
```

---

## 🟡 REC-04 — CUR_COMMIT Disabled (Currently Committed Semantics Off)

**Category:** Concurrency / Performance  
**Status:** Open

### Observation
```
CUR_COMMIT = DISABLED
```

Currently Committed (CC) is a DB2 locking optimization that allows readers to see the last committed row version without waiting for an active writer to complete. It significantly reduces lock wait time and deadlocks in OLTP workloads.

### Recommendation
Enable `CUR_COMMIT` to improve read/write concurrency. This is the default behavior in DB2 LUW 10.1+ and is recommended for production OLTP databases. Applications do not need to be changed — behavior is transparent to readers.

### DB2 Command to Apply
```sql
db2 connect to VISPRD
db2 "UPDATE DB CFG FOR VISPRD USING CUR_COMMIT ON"
db2 connect reset
-- Takes effect for new connections immediately
```

---

## 🟡 REC-05 — AUTO_REVAL Disabled (Package Revalidation Off)

**Category:** Stability / Maintenance  
**Status:** Open

### Observation
```
AUTO_REVAL = DISABLED
```

When `AUTO_REVAL = DISABLED`, packages that are invalidated by DDL changes (e.g., `ALTER TABLE`, `DROP INDEX`) are **not automatically revalidated** on first use. Instead, applications receive errors until packages are manually rebound. This can cause unexpected failures after schema changes.

### Recommendation
Change to `DEFERRED_FORCE`, which causes DB2 to automatically attempt rebind the first time an invalidated package is used, in the caller's authorization context. This is the recommended setting for production databases.

### DB2 Command to Apply
```sql
db2 connect to VISPRD
db2 "UPDATE DB CFG FOR VISPRD USING AUTO_REVAL DEFERRED_FORCE"
db2 connect reset
```

---

## 🟢 REC-06 — SQL6031N Warning in db2diag.log (Cosmetic)

**Category:** Diagnostics  
**Status:** Informational — No action required

### Observation
The `db2diag.log` (only 1.97 KB, started at 05:48 — server recently restarted) contains:

```
FUNCTION: sqleInitApplicationEnvironment, probe:32
MESSAGE:  ZRC=0xFFFFE871=-6031
          SQL6031N  Error in the db2nodes.cfg file at line number "".
PROC:     db2systray.exe
```

This warning originates from `db2systray.exe` (the system tray icon process), not the DB2 engine itself. On a **single-partition server** where `db2nodes.cfg` is minimal or empty, this is a known cosmetic warning that fires at startup and does not affect database operations.

### Recommendation
No action required. If the warning is unwanted, `db2systray.exe` can be removed from startup, but this has no functional impact on the DB2 instance.

---

## ✅ Verified OK

| Item | Value | Status |
|---|---|---|
| DB2 connection to VISPRD | Successful (`2026-03-12-06.26.30`) | ✅ |
| Authentication mode | KERBEROS | ✅ |
| Kerberos tickets (10 cached) | Valid until 15:46 same day | ✅ |
| SPN `db2/p-no1visprd-db.DEDGE.fk.no` | Registered in AD | ✅ |
| SPN `db2/p-no1visprd-db` (short) | Registered in AD | ✅ |
| Primary log path `E:\Db2PrimaryLogs\` | Exists on disk | ✅ |
| Mirror log path `F:\Db2MirrorLogs\` | Exists on disk | ✅ |
| `LOGARCHMETH1` | `DISK:E:\Db2PrimaryLogs\` (archive logging active) | ✅ |
| `AUTO_RUNSTATS` | ON | ✅ |
| `AUTO_REORG` | ON | ✅ |
| `AUTORESTART` | ON | ✅ |
| Windows Event Log | No DB2 errors in last 24h | ✅ |
| DB2 Windows services | DB2-0 Running (Auto), DB2REMOTECMD Running (Auto) | ✅ |

---

## Recommended Change Script

The following can be applied in a single maintenance window (requires no restart except `DATABASE_MEMORY AUTOMATIC` which needs deactivate/activate):

```sql
-- Connect as SYSADM
db2 connect to VISPRD

-- REC-02: Enable full STMM
db2 "UPDATE DB CFG FOR VISPRD USING SELF_TUNING_MEM ON"
db2 "UPDATE DB CFG FOR VISPRD USING DATABASE_MEMORY AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING LOCKLIST AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING SHEAPTHRES_SHR AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING SORTHEAP AUTOMATIC"
db2 "UPDATE DB CFG FOR VISPRD USING PCKCACHESZ AUTOMATIC"

-- REC-04: Enable Currently Committed
db2 "UPDATE DB CFG FOR VISPRD USING CUR_COMMIT ON"

-- REC-05: Enable auto package revalidation
db2 "UPDATE DB CFG FOR VISPRD USING AUTO_REVAL DEFERRED_FORCE"

db2 connect reset

-- Activate DATABASE_MEMORY AUTOMATIC (requires deactivate/activate)
db2 deactivate database VISPRD
db2 activate database VISPRD
```
