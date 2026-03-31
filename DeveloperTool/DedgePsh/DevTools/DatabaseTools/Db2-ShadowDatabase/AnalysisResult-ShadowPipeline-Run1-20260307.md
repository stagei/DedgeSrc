# Shadow Database Pipeline — Run 1 Report

**Date:** 2026-03-07 10:45 → 2026-03-08 09:29  
**Server:** t-no1fkmvft-db  
**Pipeline:** Run-FullShadowPipeline.ps1 -SkipBackup  
**Total Duration:** 1364.1 minutes (~22.7 hours)  
**Overall Result:** COMPLETED with critical data loss — only 30/~3000 tables created

---

## Pipeline Summary

| Step | Duration | Result |
|------|----------|--------|
| Step 1 (PRD Restore + Shadow Create) | 348.8 min | OK |
| Step 2 (Copy Data) | 897.7 min | OK* (critical DDL failure) |
| Step 3 (Verify Schema Objects) | 5.0 min | OK (warnings ignored) |
| Step 5 (Verify Row Counts - Shadow) | 78.5 min | OK (massive mismatches) |
| Step 4 (Move to Original Instance) | 33.9 min | OK |
| Final Verify | < 1 min | OK (row count pass, table count not checked) |

## Final State After Step 4

| Metric | Value |
|--------|-------|
| Database | FKMVFT on DB2 instance |
| User tables (SYSCAT.TABLES) | **30** |
| Rows in dbm.AH_ORDREHODE | 36,635,806 |

## Root Cause: DDL Extraction Failure

The `db2look` command in Step 2 Phase 2a was missing the `-a` flag:

```
# Before (broken): only extracts objects owned by connected user
db2look -d FKMVFT -e -l -td @ -o "file"

# After (fixed): extracts ALL objects regardless of owner
db2look -d FKMVFT -e -a -l -td @ -o "file"
```

Without `-a`, `db2look -e` only extracts objects created by the current authorization ID.
After the PRD restore, most tables are owned by production schemas (DBM, ASK, SVI, TCA, etc.),
not the service account `t1_srv_fkmvft_db`. Result: 59 KB DDL (251 statements) instead of
expected ~7.5 MB DDL (~3000+ statements).

| Run | source_ddl size | Cleaned DDL statements | Tables created |
|-----|----------------|----------------------|----------------|
| March 3-4 (old code?) | 7,479,685 bytes | ~3000+ | ~3000 |
| March 7 (this run) | 59,429 bytes | 251 | ~30 |

## Error Summary

| Error | Count | Impact |
|-------|-------|--------|
| SQL0204N (object not defined) | 2,966 | Tables missing from shadow DB during row count verification |
| SQL0554N (self-grant) | 7 | Non-critical, expected |
| SQL1218N (buffer pool exhaustion) | 1 | Non-critical during export |
| SQL1116N (backup pending) | 1 | Normal after config changes |
| Total ERROR lines | 3,041 | |

## Schemas Discovered (Step 2)

ASK, BUT, CRM, DB2ADMIN, DB2DBG, DB2NT, DBE, DBM, DMP, DV, EBJ, EGR, EIKER,
EKO, FKR, HST, INL, LFR, PGR, SVI, TCA, TRU, TV (23 schemas)

## Step 2 Timing

| Phase | Duration |
|-------|----------|
| Export (db2move EXPORT, 2969 tables) | 50,103 sec (~13.9 hours) |
| Load (db2move LOAD) | 3,536 sec (~59 min) |
| Load failures (SQL3304N) | ~2,916 tables |
| Load successes | ~20 tables |

## Fix Applied

File: `Step-2-CopyDatabaseContent.ps1` line 179  
Change: Added `-a` flag to `db2look` command  
Deploy: Via `_deploy.ps1` to all configured servers

## Rerun Plan

Rerun the full pipeline with `-SkipBackup` to reuse the existing PRD backup copy
in F:\Db2Restore (since we have not passed midnight of the backup date).
