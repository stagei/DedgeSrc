# AutoDoc Regeneration Logic

**Author:** Geir Helge Starholm, www.dEdge.no  
**Description:** This document explains when AutoDoc regenerates HTML documentation files for source code and SQL tables.

---

## Overview

AutoDoc uses **incremental regeneration** to avoid re-processing unchanged files. This significantly reduces processing time when running daily scheduled tasks.

There are two main regeneration functions:

| Function | Purpose |
|----------|---------|
| `RegenerateAutoDoc` | Determines if CBL, PS1, REX, or BAT files need regeneration |
| `RegenerateAutoDocSql` | Determines if SQL table documentation needs regeneration |

---

## Source File Regeneration (CBL, PS1, REX, BAT)

```mermaid
flowchart TD
    START([Start: Check if file needs regeneration]) --> OLD_CHECK{Is file in<br/>_old folder?}
    OLD_CHECK -->|Yes| SKIP_OLD[Skip - Return FALSE]
    OLD_CHECK -->|No| ERR_MODE{regenerate<br/>mode = 'err'?}
    
    ERR_MODE -->|Yes| ERR_EXISTS{Error file<br/>exists?}
    ERR_EXISTS -->|Yes| REGEN_ERR[Regenerate - Return TRUE]
    ERR_EXISTS -->|No| SKIP_ERR[Skip - Return FALSE]
    
    ERR_MODE -->|No| GLOBAL_CHECK{GlobalFunctions.psm1<br/>changed since<br/>lastGenerationDate?}
    GLOBAL_CHECK -->|Yes| REGEN_GLOBAL[Regenerate - Return TRUE]
    GLOBAL_CHECK -->|No| TEMPLATE_CHECK{Template file<br/>changed?<br/>cblmmdtemplate.html<br/>ps1mmdtemplate.html<br/>etc.}
    
    TEMPLATE_CHECK -->|Yes| REGEN_TEMPLATE[Regenerate - Return TRUE]
    TEMPLATE_CHECK -->|No| MODULE_CHECK{Parser module<br/>changed?<br/>CblParseFunctions.psm1<br/>Ps1ParseFunctions.psm1<br/>etc.}
    
    MODULE_CHECK -->|Yes| REGEN_MODULE[Regenerate - Return TRUE]
    MODULE_CHECK -->|No| HTML_EXISTS{HTML file<br/>already exists?}
    
    HTML_EXISTS -->|No| REGEN_NEW[Regenerate - Return TRUE<br/>Not previously generated]
    HTML_EXISTS -->|Yes| ALL_MODE{regenerate<br/>mode = 'all'?}
    
    ALL_MODE -->|Yes| REGEN_ALL[Regenerate - Return TRUE]
    ALL_MODE -->|No| GIT_CHECK{Git last commit date<br/>> lastGenerationDate?}
    
    GIT_CHECK -->|Yes| REGEN_GIT[Regenerate - Return TRUE<br/>Source changed in Git]
    GIT_CHECK -->|No| FINAL_ERR{Error file<br/>exists?}
    
    FINAL_ERR -->|Yes| REGEN_RETRY[Regenerate - Return TRUE<br/>Retry failed file]
    FINAL_ERR -->|No| SKIP_FINAL[Skip - Return FALSE<br/>No changes detected]
    
    style REGEN_ERR fill:#90EE90
    style REGEN_GLOBAL fill:#90EE90
    style REGEN_TEMPLATE fill:#90EE90
    style REGEN_MODULE fill:#90EE90
    style REGEN_NEW fill:#90EE90
    style REGEN_ALL fill:#90EE90
    style REGEN_GIT fill:#90EE90
    style REGEN_RETRY fill:#90EE90
    style SKIP_OLD fill:#FFB6C1
    style SKIP_ERR fill:#FFB6C1
    style SKIP_FINAL fill:#FFB6C1
```

### Key Decision Points for Source Files

| Priority | Condition | Result |
|----------|-----------|--------|
| 1 | File is in `_old` folder | **SKIP** - Archived files are ignored |
| 2 | Mode is `err` and error file exists | **REGENERATE** - Retry failed files |
| 3 | `GlobalFunctions.psm1` changed | **REGENERATE** - Core module updated |
| 4 | Template HTML changed | **REGENERATE** - Output format changed |
| 5 | Parser module changed | **REGENERATE** - Parsing logic updated |
| 6 | HTML file doesn't exist | **REGENERATE** - Never generated before |
| 7 | Mode is `all` | **REGENERATE** - Force all |
| 8 | Git commit date > lastGenerationDate | **REGENERATE** - Source code changed |
| 9 | Error file exists | **REGENERATE** - Retry previous failure |
| 10 | None of the above | **SKIP** - No changes detected |

---

## SQL Table Regeneration

```mermaid
flowchart TD
    START([Start: Check if SQL table<br/>needs regeneration]) --> GLOBAL_CHECK{GlobalFunctions.psm1<br/>changed since<br/>lastGenerationDate?}
    
    GLOBAL_CHECK -->|Yes| REGEN_GLOBAL[Regenerate - Return TRUE]
    GLOBAL_CHECK -->|No| TEMPLATE_CHECK{sqlmmdtemplate.html<br/>changed?}
    
    TEMPLATE_CHECK -->|Yes| REGEN_TEMPLATE[Regenerate - Return TRUE]
    TEMPLATE_CHECK -->|No| MODULE_CHECK{SqlParseFunctions.psm1<br/>changed?}
    
    MODULE_CHECK -->|Yes| REGEN_MODULE[Regenerate - Return TRUE]
    MODULE_CHECK -->|No| HTML_EXISTS{HTML file<br/>already exists?}
    
    HTML_EXISTS -->|No| REGEN_NEW[Regenerate - Return TRUE<br/>Not previously generated]
    HTML_EXISTS -->|Yes| ALL_MODE{regenerate<br/>mode = 'all'?}
    
    ALL_MODE -->|Yes| REGEN_ALL[Regenerate - Return TRUE]
    ALL_MODE -->|No| ALTER_CHECK{ALTER_TIME from<br/>syscat.tables ><br/>HTML LastWriteTime?}
    
    ALTER_CHECK -->|Yes| REGEN_DDL[Regenerate - Return TRUE<br/>Table DDL changed]
    ALTER_CHECK -->|No| SKIP_FINAL[Skip - Return FALSE<br/>No changes detected]
    
    style REGEN_GLOBAL fill:#90EE90
    style REGEN_TEMPLATE fill:#90EE90
    style REGEN_MODULE fill:#90EE90
    style REGEN_NEW fill:#90EE90
    style REGEN_ALL fill:#90EE90
    style REGEN_DDL fill:#90EE90
    style SKIP_FINAL fill:#FFB6C1
```

### Key Decision Points for SQL Tables

| Priority | Condition | Result |
|----------|-----------|--------|
| 1 | `GlobalFunctions.psm1` changed | **REGENERATE** - Core module updated |
| 2 | `sqlmmdtemplate.html` changed | **REGENERATE** - Output format changed |
| 3 | `SqlParseFunctions.psm1` changed | **REGENERATE** - Parsing logic updated |
| 4 | HTML file doesn't exist | **REGENERATE** - Never generated before |
| 5 | Mode is `all` | **REGENERATE** - Force all |
| 6 | `ALTER_TIME` > HTML file date | **REGENERATE** - Table DDL changed |
| 7 | None of the above | **SKIP** - No changes detected |

---

## ALTER_TIME Comparison (SQL Tables)

The `ALTER_TIME` column in `syscat.tables` stores the timestamp of the last DDL change (CREATE, ALTER) for each table.

```mermaid
sequenceDiagram
    participant AutoDoc as AutoDocBatchRunner
    participant DB2 as DB2 syscat.tables
    participant FS as File System
    
    AutoDoc->>DB2: Export tables.csv<br/>(includes ALTER_TIME)
    DB2-->>AutoDoc: schemaName, tableName, comment, type, ALTER_TIME
    
    loop For each table
        AutoDoc->>FS: Get HTML file LastWriteTime<br/>(DBM_MYTABLE.sql.html)
        FS-->>AutoDoc: 2026-01-15 08:30:00
        
        AutoDoc->>AutoDoc: Parse ALTER_TIME<br/>(2026-01-20-14.25.30.123456)
        
        alt ALTER_TIME > HTML LastWriteTime
            AutoDoc->>AutoDoc: Return TRUE<br/>Table structure changed
            Note over AutoDoc: Will regenerate HTML
        else ALTER_TIME <= HTML LastWriteTime
            AutoDoc->>AutoDoc: Return FALSE<br/>No DDL changes
            Note over AutoDoc: Skip regeneration
        end
    end
```

### ALTER_TIME Format

The `ALTER_TIME` from DB2 `syscat.tables` is in format: `YYYY-MM-DD-HH.MM.SS.nnnnnn`

Example: `2026-01-20-14.25.30.123456`

The code extracts the date portion (`2026-01-20`) and converts it to an integer (`20260120`) for comparison with the HTML file's `LastWriteTime`.

```powershell
# Extract date from ALTER_TIME (first 10 characters)
$alterTimeInt = [int]($tableInfo.alter_time.Substring(0, 10).Replace("-", ""))
# Result: 20260120

# Get HTML file date
$contentFileDate = [int](Get-Item $htmlFilename).LastWriteTime.ToString("yyyyMMdd")
# Result: 20260115

# Compare: If HTML is older than DDL change, regenerate
if ($contentFileDate -lt $alterTimeInt) {
    return $true  # Regenerate
}
```

---

## Regeneration Modes

AutoDoc supports different regeneration modes via the `-regenerate` parameter:

| Mode | Description |
|------|-------------|
| `std` | **Standard** - Regenerate only changed files (default) |
| `all` | **Force All** - Regenerate everything regardless of changes |
| `err` | **Errors Only** - Only regenerate files that previously failed |
| `json` | **JSON Only** - Only update JSON index files, no parsing |
| `single` | **Single File** - Process only one specific file (for testing) |

---

## Complete Flow Diagram

```mermaid
flowchart TB
    subgraph INIT["Initialization"]
        START([AutoDocBatchRunner.ps1]) --> PARAMS[Parse Parameters<br/>regenerate, maxFilesPerType, Parallel]
        PARAMS --> CLONE[Clone/Update Repositories<br/>Dedge, DedgePsh]
        CLONE --> EXPORT[Export cobdok data<br/>from DB2]
        EXPORT --> LOAD_LAST[Load lastGenerationDate<br/>from AutoDocBatchRunner.dat]
    end
    
    subgraph COLLECT["File Collection"]
        LOAD_LAST --> COLLECT_CBL[Collect CBL files]
        COLLECT_CBL --> FILTER_CBL[Filter: RegenerateAutoDoc]
        FILTER_CBL --> COLLECT_REX[Collect REX files]
        COLLECT_REX --> FILTER_REX[Filter: RegenerateAutoDoc]
        FILTER_REX --> COLLECT_BAT[Collect BAT files]
        COLLECT_BAT --> FILTER_BAT[Filter: RegenerateAutoDoc]
        FILTER_BAT --> COLLECT_PS1[Collect PS1 files]
        COLLECT_PS1 --> FILTER_PS1[Filter: RegenerateAutoDoc]
        FILTER_PS1 --> COLLECT_SQL[Collect SQL tables]
        COLLECT_SQL --> FILTER_SQL[Filter: RegenerateAutoDocSql]
    end
    
    subgraph PROCESS["Processing"]
        FILTER_SQL --> WORK_QUEUE[Build unified work queue<br/>with thread assignments]
        WORK_QUEUE --> PARALLEL{Parallel<br/>mode?}
        PARALLEL -->|Yes| PARALLEL_PROC[Process all items<br/>using ForEach-Object -Parallel]
        PARALLEL -->|No| SEQ_PROC[Process items<br/>sequentially]
    end
    
    subgraph OUTPUT["Output"]
        PARALLEL_PROC --> JSON[Generate JSON index files]
        SEQ_PROC --> JSON
        JSON --> COPY[Copy to web folder]
        COPY --> DONE([Complete])
    end
    
    style START fill:#4169E1,color:#fff
    style DONE fill:#228B22,color:#fff
```

---

## Summary

AutoDoc's incremental regeneration saves significant time by only processing files that have actually changed:

1. **Source files (CBL, PS1, REX, BAT)**: Uses **Git last commit date** to detect changes
2. **SQL tables**: Uses **ALTER_TIME from syscat.tables** to detect DDL changes
3. **Infrastructure changes**: If templates or parser modules change, all files of that type are regenerated

This approach ensures documentation stays current while minimizing processing time for daily scheduled runs.
