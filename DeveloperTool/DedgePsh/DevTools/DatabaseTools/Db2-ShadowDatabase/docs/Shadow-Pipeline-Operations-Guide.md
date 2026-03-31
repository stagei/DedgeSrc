# Shadow Database Pipeline — Operations Guide

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-16  
**Technology:** PowerShell / DB2

---

## 1. What This Pipeline Does

The shadow database pipeline creates a complete copy of a production DB2 database
on a shadow instance, verifies data integrity, and then moves the shadow back to the
original instance. This validates the entire backup/restore/copy chain end-to-end.

**Pipeline order:** Step-1 → Step-2 → Step-3 → Step-5 → Step-4 → Step-5b

| Step | Script | Purpose |
|---|---|---|
| Step-1 | `Step-1-CreateShadowDatabase.ps1` | Restore PRD backup, create shadow instance + DB, grant DB2NT |
| Step-2 | `Step-2-CopyDatabaseContent.ps1` | Export DDL and data from source, load into shadow (OS auth) |
| Step-3 | `Step-3-CleanupShadowDatabase.ps1` | Verify schema objects match between source and shadow |
| Step-5 | `Step-5-VerifyRowCounts.ps1` | Verify row counts match between source and shadow |
| Step-4 | `Step-4-MoveToOriginalInstance.ps1` | Backup shadow, drop original, restore shadow as original |
| Step-5b | Inline in pipeline | Final row count verification on restored database |

---

## 2. Running the Pipeline

### 2.1 Standalone on the Server

```powershell
pwsh.exe -NoProfile -File "E:\opt\DedgePshApps\Db2-ShadowDatabase\Run-FullShadowPipeline.ps1"
```

### 2.2 Via Scheduled Task

Deploy and create a one-time scheduled task:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-ShadowDatabase\_deploy.ps1"
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\DatabaseTools\Db2-ShadowDatabase\_install-run-all.ps1"
```

### 2.3 Via Orchestrator (RUN_ALL)

Write `RUN_ALL` to the command file. The orchestrator delegates to `Run-FullShadowPipeline.ps1`.

### 2.4 Via --autocur (AI Agent)

Type `--autocur` in Cursor chat. The agent will deploy, trigger via `Invoke-ServerCommand`
with `-Project 'shadow-pipeline'`, and monitor the logs every 30 minutes until completion.
The `-Project` parameter ensures this pipeline gets its own concurrency slot on the server,
allowing other orchestrator commands to run in parallel.

---

## 3. Skip Switches for Partial Reruns

| Switch | Effect | Use when |
|---|---|---|
| `-SkipPrdRestore` | Skip Phase -1 | Source DB already has fresh PRD data |
| `-SkipShadowCreate` | Skip Phase 1 | Shadow instance already exists |
| `-SkipBackup` | Skip Phase -2 | Pre-migration backup already done |
| `-SkipCopy` | Skip Step-2 | Shadow already has data |
| `-SkipVerify` | Skip Step-3/5 | Verification not needed |
| `-StopAfterVerify` | Stop after Step-5 | Don't move shadow back yet |
| `-MinStep2Minutes N` | Duration guard | Default 120 min |

**Common restart examples:**

```powershell
# Step-1 done, restart from Step-2:
.\Run-FullShadowPipeline.ps1 -SkipPrdRestore -SkipShadowCreate -SkipBackup

# Steps 1-2 done, restart from Step-3:
.\Run-FullShadowPipeline.ps1 -SkipPrdRestore -SkipShadowCreate -SkipBackup -SkipCopy

# Only run Step-4 (move back):
.\Run-FullShadowPipeline.ps1 -SkipPrdRestore -SkipShadowCreate -SkipBackup -SkipCopy -SkipVerify
```

---

## 4. Preflight Phase 0 — Federation Restore

Before Step-1 runs, the pipeline checks `DatabasesV2.json` for the `XFKMVFT` access point.

- If the previous run completed Step-4, that access point was converted from `FederatedDb`
  (on DB2SH) to `Alias` (on DB2). This is the expected end state.
- On a re-run, the preflight restores it back to `FederatedDb` on `DB2SH` so that the
  pipeline can proceed cleanly.

This is idempotent — if the entry is already `FederatedDb`, nothing happens.

---

## 5. Backup Sourcing Logic

The pipeline checks the `Db2Restore` folder for local `FKMVFT*.001` backup files:

1. **Local image exists** → Step-1 uses the local image (no PRD network copy).
2. **No local image, no federation entries** → Step-1 copies from PRD backup share.
3. **No local image, federation entries exist** → Step-1 copies from PRD anyway
   (the shadow instance will be recreated, so federation will be re-established).

---

## 6. Step-2 Duration Guard

If Step-2 (data copy) completes in less than `MinStep2Minutes` (default: 120 minutes),
the pipeline aborts. A fast completion indicates that the data transfer failed silently
(e.g., 0 rows exported due to authentication issues).

---

## 7. Disk Cleanup

Old `.001` backup files are automatically removed before new backups are created:

| Location | When cleaned |
|---|---|
| `Db2Backup` | Step-1 Phase -2 (before pre-migration backup) |
| `PreMigration` | Step-1 Phase -2 (before copying backup) |
| `Db2ShBackup` | Step-4 Phase 1 (before shadow backup) |
| `Db2Restore` | Step-4 Phase 1b (before copying to restore folder) |

This prevents `SQL2059W` (disk full) errors.

---

## 8. ExecLogs Format

Every `--autocur` execution produces a log at:

```
DevTools/DatabaseTools/Db2-ShadowDatabase/ExecLogs/<server>_<yyyyMMdd-HHmmss>.md
```

These are written by the AI agent during monitoring and include:
- Start time and configuration
- Step progress with timestamps
- Errors and root cause analysis
- Bugfixes applied (files changed)
- Redeploy and restart actions
- Final status and total duration

---

## 9. Error Recovery

When the AI agent encounters an error during `--autocur`:

1. Copy the log locally and analyze the error
2. Fix the local source code
3. Deploy via `_deploy.ps1`
4. Kill the running job on the server
5. Restart with appropriate `-Skip*` flags
6. Document the fix in the ExecLog

The agent continues this loop until a clean full run completes.

---

## 10. SMS Notifications

SMS is sent automatically at:
- Pipeline start
- Pipeline completion (success)
- Pipeline failure
- Step-2 duration guard abort

SMS numbers are auto-detected per `$env:USERNAME`.
