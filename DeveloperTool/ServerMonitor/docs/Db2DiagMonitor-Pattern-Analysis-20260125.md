# DB2 Diagnostic Pattern Analysis - 2026-01-25

## Source

- **Server**: `p-no1fkmprd-db`
- **Snapshot Time**: 2026-01-25 ~16:30 UTC
- **Total DB2 Alerts**: 990
- **Analysis Date**: 2026-01-25

---

## 1. Summary by Severity

| Severity | Count | Percentage |
|----------|-------|------------|
| Critical | 9 | 0.9% |
| Informational | 981 | 99.1% |

---

## 2. New Patterns Discovered

### 2.1 Critical Errors (NEW - Not in existing guide)

#### Pattern: QPLEX Connection User Error

| Attribute | Value |
|-----------|-------|
| **Count** | 8 occurrences |
| **Function** | `DB2 UDB, Query Gateway, sqlqgGetUserOptions, probe:721` |
| **Message** | "It can't get valid connected user name or disabled the platform user for QPLEX connection" |
| **Database** | FKMPRD |
| **Current Severity** | Critical |

**Sample Entry:**
```
2026-01-25-10.20.02.326000+060 I50068432F810        LEVEL: Error
INSTANCE: DB2                  NODE : 000           DB   : FKMPRD
AUTHID  : KIT                  HOSTNAME: p-no1fkmprd-db
FUNCTION: DB2 UDB, Query Gateway, sqlqgGetUserOptions, probe:721
MESSAGE : It can't get valid connected user name or disabled the platform user for QPLEX connection
```

**Recommended Regex:**
```regex
FUNCTION:\s*DB2 UDB,\s*Query Gateway,\s*sqlqgGetUserOptions
```
or
```regex
can't get valid connected user name.*QPLEX
```

**Recommended Action:** 
- **Keep as Warning** - This is a federated query configuration issue
- Affected users: KIT, ANDHAN, ASPTOV, FKGJESAN, FKGERHAA, FKROAHEL, FKODDGIS, FKMERSKY
- May indicate missing user mappings for QPLEX federated connections

---

#### Pattern: Deadlock Detected (ZRC=0x80100002)

| Attribute | Value |
|-----------|-------|
| **Count** | 1 occurrence |
| **Function** | `DB2 UDB, catalog services, sqlrlCatalogScan::fetch, probe:45` |
| **ZRC Code** | `0x80100002` = -2146435070 = SQLP_LDED |
| **Message** | "Dead lock detected" DIA8002C |
| **Database** | FKMPRD |
| **Current Severity** | Critical |

**Sample Entry:**
```
2026-01-25-08.47.19.893000+060 I40730385F1433       LEVEL: Error
INSTANCE: DB2                  NODE : 000           DB   : FKMPRD
AUTHID  : ROA
FUNCTION: DB2 UDB, catalog services, sqlrlCatalogScan::fetch, probe:45
RETCODE : ZRC=0x80100002=-2146435070=SQLP_LDED "Dead lock detected"
          DIA8002C A deadlock has occurred, rolling back transaction.
```

**Recommended Regex:**
```regex
ZRC=0x80100002|SQLP_LDED|Dead\s*lock\s*detected|DIA8002C
```

**Recommended Action:**
- **Keep as Critical** - Deadlocks indicate serious contention issues
- This is documented in existing guide but now confirmed in production

---

### 2.2 Event Level Patterns (Noise - Should Filter)

These patterns are generating 99% of alerts but have no operational impact.

#### Pattern: Self Tuning Memory Manager (STMM)

| Attribute | Value |
|-----------|-------|
| **Count** | 434 occurrences (43.8% of total) |
| **Component** | `Self tuning memory manager` |
| **Functions** | `stmmLog, probe:1085`, `stmmLog, probe:1245`, `stmmLogGetFileStats, probe:558` |

**Recommended Regex:**
```regex
FUNCTION:\s*DB2 UDB,\s*Self tuning memory manager
```

**Recommended Action:** **Skip** - Normal DB2 self-optimization

---

#### Pattern: Base System Utilities / FirstConnect

| Attribute | Value |
|-----------|-------|
| **Count** | 284 occurrences (28.7% of total) |
| **Component** | `base sys utilities` |
| **Function** | `sqeLocalDatabase::FirstConnect, probe:1000` |

**Recommended Regex:**
```regex
FUNCTION:\s*DB2 UDB,\s*base sys utilities,\s*sqeLocalDatabase::FirstConnect
```

**Recommended Action:** **Skip** - Database activation/connection events

---

#### Pattern: Catalog Cache Initialization

| Attribute | Value |
|-----------|-------|
| **Count** | 263 occurrences (26.5% of total) |
| **Component** | `catcache support` |
| **Function** | `sqlrlc_catcache_init, probe:271` |
| **Message** | "Catalog cache size:" |

**Recommended Regex:**
```regex
FUNCTION:\s*DB2 UDB,\s*catcache support,\s*sqlrlc_catcache_init
```
or
```regex
MESSAGE\s*:\s*Catalog cache size:
```

**Recommended Action:** **Skip** - Normal cache initialization

---

## 3. Comparison with Existing Guide

### Patterns Already Documented (docs/Db2DiagMonitor-Severity-Mapping-Guide.md)

| Pattern | In Guide | Seen Today | Status |
|---------|----------|------------|--------|
| SQL0530N (FK violation) | ✅ Yes | ❌ No | Not in this snapshot |
| SQL0911N (Deadlock SQL) | ✅ Yes | ❌ No | Not in this snapshot |
| Client termination | ✅ Yes | ❌ No | Not in this snapshot |
| STMM auto-tuning | ✅ Yes | ✅ Yes (434) | Already documented |
| Package cache resize | ✅ Yes | ❌ No | Not in this snapshot |
| Config param update | ✅ Yes | ❌ No | Not in this snapshot |
| DRDA wrapper errors | ✅ Yes | ❌ No | Not in this snapshot |

### NEW Patterns to Add to Guide

| Pattern | Count | Recommended Action |
|---------|-------|-------------------|
| QPLEX connection user error | 8 | **Warning** |
| Deadlock ZRC=0x80100002 | 1 | **Critical** (keep) |
| Base sys FirstConnect | 284 | **Skip** |
| Catalog cache init | 263 | **Skip** |

---

## 4. Recommended Configuration Updates

Add these patterns to `appsettings.json` under `Db2DiagMonitoring.PatternsToMonitor`:

```json
{
  "PatternId": "QPLEX-UserError",
  "Description": "Query Gateway QPLEX connection user mapping error",
  "Regex": "Query Gateway.*sqlqgGetUserOptions|can't get valid connected user name.*QPLEX",
  "Enabled": true,
  "Action": "Remap",
  "Level": "Warning",
  "Priority": 50,
  "MessageTemplate": "[{Instance}] [{Database}] QPLEX user mapping error for {AuthId}"
},
{
  "PatternId": "BaseSystemFirstConnect",
  "Description": "Database first connection/activation event",
  "Regex": "base sys utilities.*FirstConnect|sqeLocalDatabase::FirstConnect",
  "Enabled": true,
  "Action": "Skip",
  "Priority": 100
},
{
  "PatternId": "CatalogCacheInit",
  "Description": "Catalog cache initialization size logging",
  "Regex": "catcache support.*sqlrlc_catcache_init|Catalog cache size:",
  "Enabled": true,
  "Action": "Skip",
  "Priority": 100
},
{
  "PatternId": "DeadlockZRC",
  "Description": "Internal deadlock detected via ZRC code",
  "Regex": "ZRC=0x80100002|SQLP_LDED|DIA8002C",
  "Enabled": true,
  "Action": "Escalate",
  "Level": "Critical",
  "Priority": 10,
  "MessageTemplate": "[{Instance}] [{Database}] Deadlock detected for user {AuthId}"
}
```

---

## 5. Impact Analysis

### Before Adding New Patterns

| Metric | Value |
|--------|-------|
| Total alerts | 990 |
| Critical | 9 |
| Informational | 981 |

### After Adding New Patterns (Projected)

| Metric | Value | Change |
|--------|-------|--------|
| Skipped (noise) | 981 | -99% |
| Critical | 1 (deadlock) | Kept |
| Warning | 8 (QPLEX) | Downgraded from Critical |

**Noise Reduction: 99%**

---

## 6. Action Items

1. [ ] Add new patterns to `appsettings.json` on network share
2. [ ] Verify QPLEX user mapping issue with DBA team
3. [ ] Monitor for deadlock frequency over next 7 days
4. [ ] Update `Db2DiagMonitor-Severity-Mapping-Guide.md` with new patterns

---

## 7. References

- Source snapshot: `C:\opt\src\ServerMonitor\p-no1fkmprd-db_snapshot.json`
- Existing guide: `docs/Db2DiagMonitor-Severity-Mapping-Guide.md`
- Config location: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorAgent.json`
