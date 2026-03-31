# Shadow Database Pipeline — Run-FullShadowPipeline.ps1

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-16  
**Technology:** PowerShell / DB2

---

## Overview

`Run-FullShadowPipeline.ps1` is the canonical pipeline script. It orchestrates:  
**Step-1 → Step-2 → Step-3 → Step-5 → Step-4 → Step-5b**

It can be run interactively on the server, triggered via the orchestrator's `RUN_ALL` command,
or deployed and monitored via `--autocur`.

Previous script `Run-Manually.ps1` has been retired to `_old/`.

---

## Top-Level Pipeline Flow

```mermaid
flowchart TD
    START([Run-FullShadowPipeline.ps1]) --> INIT[Load config.json<br/>Resolve SMS number<br/>Test-Db2ServerAndAdmin]
    INIT --> SMS_START[/SMS: Pipeline STARTED/]
    SMS_START --> PH0[Preflight Phase 0:<br/>Federation Restore]
    PH0 --> BACKUP_CHK[Preflight:<br/>Check local restore image<br/>in Db2Restore folder]
    BACKUP_CHK --> SKIP1{SkipPrdRestore AND<br/>SkipShadowCreate?}
    SKIP1 -- Both skip --> STEP2_CHK
    SKIP1 -- At least one runs --> STEP1[Step-1: Create Shadow Database]
    STEP1 --> STEP2_CHK
    STEP2_CHK{SkipCopy?}
    STEP2_CHK -- Yes --> STEP3_CHK
    STEP2_CHK -- No --> STEP2[Step-2: Copy Database Content]
    STEP2 --> GUARD{Step-2 duration<br/>< MinStep2Minutes?}
    GUARD -- Yes --> ABORT[/SMS: ABORTED<br/>too fast = data failure/]
    ABORT --> FAIL_EXIT([exit 1])
    GUARD -- No --> STEP3_CHK
    STEP3_CHK{SkipVerify?}
    STEP3_CHK -- Yes --> STEP4_CHK
    STEP3_CHK -- No --> STEP3[Step-3: Cleanup Shadow Database]
    STEP3 --> STEP5[Step-5: Verify Row Counts]
    STEP5 --> STEP4_CHK
    STEP4_CHK{StopAfterVerify?}
    STEP4_CHK -- Yes --> SUMMARY
    STEP4_CHK -- No --> STEP4[Step-4: Move to Original Instance]
    STEP4 --> STEP5B[Step-5b: Final Verify<br/>Row counts on restored DB]
    STEP5B --> SUMMARY
    SUMMARY --> SMS_OK[/SMS: Pipeline COMPLETE<br/>all steps OK/]
    SMS_OK --> DONE([JOB_COMPLETED])

    STEP1 -- fail --> CATCH
    STEP2 -- fail --> CATCH
    STEP3 -- fail --> CATCH
    STEP5 -- fail --> CATCH
    STEP4 -- fail --> CATCH
    STEP5B -- fail --> CATCH
    CATCH[catch block] --> SMS_FAIL[/SMS: Pipeline FAILED<br/>with error message/]
    SMS_FAIL --> FAIL_EXIT
```

---

## Preflight Phase 0 — Federation Restore

Ensures `DatabasesV2.json` has `XFKMVFT` as `FederatedDb` on the shadow instance,  
undoing Step-4's conversion from the previous run.

```mermaid
flowchart TD
    P0_START([Phase 0: Federation Restore]) --> FIND_V2[Find DatabasesV2.json<br/>on app servers]
    FIND_V2 --> V2_EXISTS{Found?}
    V2_EXISTS -- No --> P0_SKIP([Skip - continue])
    V2_EXISTS -- Yes --> FIND_AP[Find XFKMVFT<br/>access point]
    FIND_AP --> AP_TYPE{AccessPointType?}
    AP_TYPE -- "FederatedDb" --> P0_OK([Already correct<br/>no change needed])
    AP_TYPE -- "Alias" --> RESTORE[Backup DatabasesV2.json<br/>Convert Alias → FederatedDb<br/>Set InstanceName = DB2SH]
    AP_TYPE -- "Not found" --> P0_SKIP
    RESTORE --> P0_DONE([Federation restored])
```

---

## Step-1: Create Shadow Database

```mermaid
flowchart TD
    S1_START([Step-1]) --> S1_PH0[Phase 0:<br/>Federation Restore]
    S1_PH0 --> SKIP_BK{SkipBackup?}

    subgraph phase2 [Phase -2: Pre-Migration Backup]
        SKIP_BK -- Yes --> PH2_SKIP([Skipped])
        SKIP_BK -- No --> CLEAN_BK[Remove old .001 files<br/>from Db2Backup folder]
        CLEAN_BK --> RUN_BK[Start-Db2Backup<br/>Online backup of source DB]
        RUN_BK --> CLEAN_PM[Remove old PreMigration files]
        CLEAN_PM --> COPY_PM[Copy backup to<br/>PreMigration folder]
    end

    PH2_SKIP --> PH1_CHK
    COPY_PM --> PH1_CHK

    subgraph phase1neg [Phase -1: PRD Restore Decision]
        PH1_CHK{SkipPrdRestore?}
        PH1_CHK -- Yes --> PH1_SKIP([Skipped])
        PH1_CHK -- No --> FED_CHK[Check DatabasesV2.json<br/>for FederatedDb entries]
        FED_CHK --> FED_EXISTS{FederatedDb<br/>entries exist?}
        FED_EXISTS -- No --> PRD_GO([Safe to restore])
        FED_EXISTS -- Yes --> LOCAL_CHK{Local .001 in<br/>Restore folder?}
        LOCAL_CHK -- Yes --> PH1_SKIP_LOCAL([Skip restore<br/>use local image])
        LOCAL_CHK -- No --> PRD_FORCE([Proceed with PRD<br/>shadow will be recreated])
    end

    PRD_GO --> PRD_RESTORE
    PRD_FORCE --> PRD_RESTORE

    subgraph phase1exec [Phase -1: Execution]
        PRD_RESTORE[Run Db2-CreateInitialDatabases<br/>StdAllUseNewConfig.ps1<br/>GetBackupFromEnvironment = PRD]
    end

    PH1_SKIP --> PHASE1
    PH1_SKIP_LOCAL --> PHASE1
    PRD_RESTORE --> PHASE1

    subgraph phase1create [Phase 1: Create Shadow Instance]
        PHASE1[Run Db2-CreateInitialDatabases<br/>ShadowUseNewConfig.ps1<br/>Creates DB2SH + FKMVFTSH]
    end

    PHASE1 --> PH15

    subgraph phase15 [Phase 1.5: Grant DB2NT]
        PH15[GRANT DBADM, DATAACCESS,<br/>ACCESSCTRL, SECADM<br/>to DB2NT on shadow + source DB]
    end

    PH15 --> S1_DONE([Step-1 Complete])
```

---

## Step-2: Copy Database Content (Cross-Instance)

All DB2 connections use **OS authentication** (service account = SYSADM).

```mermaid
flowchart TD
    S2_START([Step-2]) --> MODE{Same instance?}
    MODE -- Yes --> COPY_MODE[db2move COPY<br/>DDL_AND_LOAD<br/>TABLESPACE_MAP SYS_ANY]
    MODE -- No --> CROSS

    subgraph crossInst [Cross-Instance Pipeline]
        CROSS[Phase 2a0: Reset buffer pools<br/>+ enable STMM on source] --> REBIND[Phase 2a1: Rebind packages]
        REBIND --> DDL[Phase 2a: db2look<br/>extract DDL from source]
        DDL --> CLEAN_DDL[Phase 2b: Clean DDL<br/>strip tablespace/federation/<br/>grant/bufferpool statements]
        CLEAN_DDL --> APPLY[Apply cleaned DDL<br/>to shadow DB - OS auth]
        APPLY --> STMM_SH[Phase 2b1: Enable STMM<br/>on shadow DB]
        STMM_SH --> EXPORT[Phase 2c: db2move EXPORT<br/>from source - OS auth]
        EXPORT --> LOAD[Phase 2d: db2move LOAD<br/>into shadow - OS auth]
        LOAD --> PENDING[Phase 2e: Clear<br/>LOAD PENDING state]
        PENDING --> TRIGGERS[Phase 2f: Verify triggers]
    end

    COPY_MODE --> VALIDATE
    TRIGGERS --> VALIDATE

    VALIDATE[Phase 3: Validate<br/>table counts] --> CONTROL[Phase 5: Control SQL<br/>verify row count > 0]
    CONTROL --> S2_DONE([Step-2 Complete])
```

---

## Step-2 Duration Guard

```mermaid
flowchart LR
    S2_RESULT[Step-2 result] --> CHECK{Duration<br/>less than 120 min?}
    CHECK -- "Yes - too fast" --> ABORT[/SMS: ABORTED/]
    ABORT --> EXIT([exit 1])
    CHECK -- "No - normal" --> CONTINUE([Continue to Step-3])
```

A Step-2 completing in under 2 hours indicates a data transfer failure.

---

## Step-4: Move Shadow Back to Original Instance

```mermaid
flowchart TD
    S4_START([Step-4]) --> S4_PH0

    subgraph s4phase0 [Phase 0: Convert Federation]
        S4_PH0[DatabasesV2.json:<br/>FederatedDb → Alias<br/>on primary instance]
    end

    S4_PH0 --> CLEAN_SH_BK[Remove old .001 files<br/>from Db2ShBackup]
    CLEAN_SH_BK --> S4_PH1

    subgraph s4phase1 [Phase 1: Backup Shadow DB]
        S4_PH1[db2 backup database FKMVFTSH<br/>to Db2ShBackup folder]
        S4_PH1 --> S4_COPY[Copy backup to<br/>target Db2Restore folder]
    end

    S4_COPY --> S4_PH2

    subgraph s4phase2 [Phase 2: Drop Old Target]
        S4_PH2{DropExistingTarget?}
        S4_PH2 -- Yes --> DROP[Drop FKMVFT on DB2<br/>Clean log/temp folders]
        S4_PH2 -- No --> S4_PH3
    end

    DROP --> S4_PH3

    subgraph s4phase3 [Phase 3: Restore to Original]
        S4_PH3[Run Db2-CreateInitialDatabases<br/>StdAllUseNewConfig.ps1<br/>Restore shadow backup to DB2]
    end

    S4_PH3 --> S4_CTL[Phase 3b: Control SQL<br/>verify row count > 0]
    S4_CTL --> CLEANUP{CleanupSourceAfter?}
    CLEANUP -- Yes --> S4_PH4[Phase 4: Drop shadow DB<br/>Clean DB2SH folders]
    CLEANUP -- No --> S4_DONE
    S4_PH4 --> S4_DONE([Step-4 Complete])
```

---

## Backup Source Decision Tree

```mermaid
flowchart TD
    START([Need source DB data]) --> LOCAL{Local .001 in<br/>Db2Restore?}
    LOCAL -- Yes --> USE_LOCAL([Use local image<br/>skip PRD copy])
    LOCAL -- No --> FED{FederatedDb entries<br/>in DatabasesV2.json?}
    FED -- No --> PRD([Copy from PRD<br/>backup share])
    FED -- Yes --> PRD_FORCE([Copy from PRD anyway<br/>shadow will be recreated])
```

---

## DatabasesV2.json Federation Lifecycle

```mermaid
stateDiagram-v2
    direction LR

    [*] --> FederatedDb : Initial state

    FederatedDb --> Alias : Step-4 Phase 0<br/>Pipeline complete

    Alias --> FederatedDb : Preflight Phase 0<br/>Pipeline restart

    note right of FederatedDb
        InstanceName = DB2SH
        NodeName = XFKMVFT
        Auth = KerberosServerEncrypt
    end note

    note right of Alias
        InstanceName = DB2
        NodeName = XFKMVFT
        Auth = KerberosServerEncrypt
    end note
```

---

## Skip Switches for Partial Reruns

| Switch | Effect |
|---|---|
| `-SkipPrdRestore` | Skip Step-1 Phase -1 (PRD restore) |
| `-SkipShadowCreate` | Skip Step-1 Phase 1 (shadow instance creation) |
| `-SkipBackup` | Skip Step-1 Phase -2 (pre-migration backup) |
| `-SkipCopy` | Skip Step-2 entirely |
| `-SkipVerify` | Skip Step-3 and Step-5 |
| `-StopAfterVerify` | Stop after Step-3/5, do not run Step-4 |

When both `-SkipPrdRestore` and `-SkipShadowCreate` are set, Step-1 is skipped entirely.

---

## Disk Cleanup Points

| When | Folder | What is removed |
|---|---|---|
| Step-1 Phase -2 (before backup) | `Db2Backup` | Old `.001` files |
| Step-1 Phase -2 (before copy) | `PreMigration` | Old `.001` files |
| Step-4 Phase 1 (before backup) | `Db2ShBackup` | Old `.001` files |
| Step-4 Phase 1b (before copy) | `Db2Restore` | Old `.001` files |

---

## SMS Notification Points

| Trigger | Message |
|---|---|
| Pipeline start | `Shadow pipeline STARTED on <server>: FKMVFT->FKMVFTSH` |
| Step-2 too fast | `Shadow pipeline ABORTED: Step-2 completed in X min` |
| Any step fails | `Shadow pipeline FAILED after X min: <error>` |
| All steps complete | `Shadow pipeline COMPLETE: all steps OK in X min` |
