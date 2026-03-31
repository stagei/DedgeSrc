# Import Configuration Architecture

How `import-config.json` flows through the GenericLogHandler solution, from file on disk to processed log entries.

## Configuration Sources

The system supports **two** configuration sources, with database taking priority:

| Source | File | When Used |
|--------|------|-----------|
| **JSON file** | `import-config.json` (repo root) | Initial setup, hot-reload |
| **Database** | `import_sources` table (PostgreSQL) | Runtime, after first migration |

On first startup, JSON sources are **migrated to the database**. After that, database sources take precedence. The JSON file remains as a fallback and can be edited via the Web API's Config Editor.

```mermaid
flowchart TD
    subgraph "Configuration Sources"
        JSON["import-config.json<br/>(repo root)"]
        DB["PostgreSQL<br/>import_sources table"]
        AS["appsettings.json<br/>(fallback)"]
    end

    subgraph "Startup (ImportService Program.cs)"
        LOAD["IConfiguration loads both<br/>import-config.json + appsettings.json"]
        BIND["services.Configure&lt;ImportConfiguration&gt;()"]
    end

    subgraph "Runtime (ImportService.cs)"
        MIGRATE["MigrateJsonSourcesToDatabaseAsync()<br/>First run: JSON → DB"]
        GETSRC["GetImportSourcesAsync()<br/>DB first, JSON fallback"]
        INIT["InitializeImporters()"]
    end

    JSON --> LOAD
    AS --> LOAD
    LOAD --> BIND
    BIND --> MIGRATE
    MIGRATE --> DB
    DB --> GETSRC
    JSON --> GETSRC
    GETSRC --> INIT

    style DB fill:#d4edda,stroke:#28a745
    style JSON fill:#fff3cd,stroke:#ffc107
    style AS fill:#f8d7da,stroke:#dc3545
```

## Config File Discovery

Both ImportService and WebApi search for `import-config.json` in this order:

```mermaid
flowchart LR
    A["AppContext.BaseDirectory/<br/>import-config.json"] -->|not found| B["Directory.GetCurrentDirectory()/<br/>import-config.json"]
    B -->|not found| C["Repository root/<br/>import-config.json"]
    C -->|not found| D["appsettings.json<br/>ImportConfiguration section"]

    A -->|found| USE["Use this file"]
    B -->|found| USE
    C -->|found| USE
    D -->|found| USE

    style USE fill:#d4edda,stroke:#28a745
```

Repository root is found by searching upward from the base directory for `GenericLogHandler.sln` or `import-config.json`.

## import-config.json Structure

```json
{
  "Version": "1.0",
  "Metadata": { "Name": "...", "Description": "..." },
  "General": {
    "ServiceName": "GenericLogHandler",
    "MaxConcurrentImports": 4,
    "BatchSize": 1000,
    "RunOnce": false,
    "RetryAttempts": 3,
    "HealthCheckInterval": 60
  },
  "Database": {
    "Type": "postgresql",
    "ConnectionString": "..."
  },
  "Retention": { "DefaultDays": 90, "CleanupSchedule": "0 2 * * *" },
  "ImportSources": [
    {
      "Name": "COBNT WKMONIT",
      "Type": "file",
      "Enabled": true,
      "Priority": 5,
      "Config": {
        "Path": "\\\\server\\share\\WKMONIT.LOG",
        "Format": "log",
        "IsAppendOnly": true,
        "PollInterval": 30,
        "CopyToLocalPath": "C:\\opt\\data\\...",
        "..."
      }
    }
  ]
}
```

## ImportSource → Importer Factory

The `Type` field on each ImportSource determines which `ILogImporter` implementation is created:

```mermaid
flowchart TD
    SRC["ImportSource<br/>{Name, Type, Enabled, Priority, Config}"]
    
    SRC --> FACTORY["CreateImporter(source)<br/>switch on source.Type.ToLower()"]
    
    FACTORY -->|"file, json, xml, log"| FI["FileImporter"]
    FACTORY -->|"database, db2, sqlserver, odbc"| DI["DatabaseImporter"]
    FACTORY -->|"eventlog"| EI["EventLogImporter<br/>(Windows only)"]
    FACTORY -->|unknown| ERR["NotSupportedException"]

    subgraph "FileImporter capabilities"
        FI --> F1["JSON files (array or JSONL)"]
        FI --> F2["XML files"]
        FI --> F3["Log files (line-by-line)"]
        FI --> F4["Delimited (pipe, CSV, tab)"]
        FI --> F5["Raw/plain text"]
        FI --> F6["WKMONIT/COBNT format"]
    end

    style FI fill:#d4edda,stroke:#28a745
    style DI fill:#cce5ff,stroke:#004085
    style EI fill:#fff3cd,stroke:#ffc107
```

## Main Import Loop

```mermaid
sequenceDiagram
    participant Timer as 30s Timer
    participant IS as ImportService
    participant IQ as Ingest Queue
    participant SEM as Semaphore(MaxConcurrent)
    participant IMP as Importer(s)
    participant REPO as ILogRepository
    participant DB as PostgreSQL

    loop Every 30 seconds
        Timer->>IS: RunImportCycle()
        
        IS->>IQ: DrainIngestQueueAsync()
        Note over IQ,DB: Process API-submitted entries (FIFO)
        IQ->>DB: Read ingest_queue, convert to LogEntry, delete

        par For each enabled source (concurrent)
            IS->>SEM: WaitAsync()
            SEM->>IMP: ImportAsync()
            IMP->>IMP: Check PollInterval (skip if too soon)
            IMP->>IMP: Process files/database/eventlog
            IMP->>REPO: AddBatchAsync(entries)
            REPO->>DB: INSERT INTO log_entries
            IMP->>IS: ImportResult
            IS->>SEM: Release()
        end
    end
```

## FileImporter: Append-Only Processing Flow

For files configured with `IsAppendOnly: true` (like WKMONIT.LOG):

```mermaid
flowchart TD
    START["ImportAsync() called"]
    
    START --> POLL{"PollInterval elapsed?<br/>(e.g., 30s)"}
    POLL -->|No| SKIP["Return empty result<br/>(skip this cycle)"]
    POLL -->|Yes| CHECK["Check source file exists"]
    
    CHECK --> TRACK{"Tracking info exists<br/>for this file?"}
    TRACK -->|No| RESTORE["Restore from DB<br/>(LastProcessedLine, FileCreationDate)"]
    TRACK -->|Yes| ROTATE
    RESTORE --> ROTATE
    
    ROTATE{"File rotated?<br/>CreationDate changed OR<br/>file size decreased"}
    ROTATE -->|Yes| RESET["Reset to line 0<br/>Update CreationDate"]
    ROTATE -->|No| GROWN
    RESET --> GROWN
    
    GROWN{"File size grown?"}
    GROWN -->|No| NOOP["No new content<br/>Return success"]
    GROWN -->|Yes| COPY
    
    COPY{"CopyToLocalPath set?"}
    COPY -->|Yes| DOCOPY["Copy file to local dir<br/>(async stream, no lock)"]
    COPY -->|No| READ
    DOCOPY --> READ
    
    READ["Open local copy or source<br/>Skip to LastProcessedLine"]
    READ --> PARSE["Parse new lines<br/>(format-specific parser)"]
    PARSE --> BATCH["Batch entries (1000/batch)<br/>Apply level filters"]
    BATCH --> FLUSH["FlushBatch → AddBatchAsync()"]
    FLUSH --> UPDATE["Update tracking:<br/>LastProcessedLine = total lines<br/>LastFileSize = original size<br/>CreationDate = original date"]

    style SKIP fill:#f8f9fa,stroke:#6c757d
    style NOOP fill:#f8f9fa,stroke:#6c757d
    style DOCOPY fill:#d4edda,stroke:#28a745
    style UPDATE fill:#cce5ff,stroke:#004085
```

## CopyToLocalPath: Network File Safety

For business-critical files on network shares:

```mermaid
sequenceDiagram
    participant IMP as FileImporter
    participant NET as Network Share<br/>(\\server\share\WKMONIT.LOG)
    participant LOCAL as Local Copy<br/>(C:\opt\data\...\WKMONIT.LOG)
    participant DB as PostgreSQL

    IMP->>NET: Check CreationDate + FileSize
    Note over IMP: Rotation detection uses ORIGINAL file metadata

    alt File size grew (new content)
        IMP->>NET: Open with FileShare.ReadWrite
        IMP->>LOCAL: Stream copy (async, no lock on source)
        IMP->>NET: Close source stream
        
        IMP->>LOCAL: Open local copy for reading
        IMP->>LOCAL: Skip to LastProcessedLine
        IMP->>LOCAL: Parse new lines
        IMP->>DB: AddBatchAsync(entries)
        
        Note over IMP: Track line position from LOCAL copy
        Note over IMP: Track file size/date from ORIGINAL source
    else File unchanged
        Note over IMP: Skip cycle
    end
```

## Config Properties and Their Effects

### ImportSourceConfig — File Import Properties

| Property | Type | Default | Effect |
|----------|------|---------|--------|
| `Path` | string | — | File path or glob pattern (`*.log`) |
| `Format` | string | — | `log`, `json`, `xml`, `delimited`, `raw` |
| `IsAppendOnly` | bool | false | Track position, resume from last line |
| `PollInterval` | int | 30 | Seconds between checks for append-only files |
| `CopyToLocalPath` | string | — | Copy to local dir before reading |
| `WatchDirectory` | bool | false | Use FileSystemWatcher for real-time |
| `MaxFilesPerRun` | int | 0 | Limit files per cycle (0 = unlimited) |
| `MaxFileAgeDays` | int | 30 | Skip files older than N days |
| `SkipHeaderLines` | int | 0 | Skip N lines at top of file |
| `Encoding` | string | utf-8 | File encoding |
| `MoveProcessedFiles` | bool | false | Move to ProcessedFilesLocation after |
| `MaxFullReadMB` | int | 100 | Max size for whole-file JSON/XML read |
| `QuarantineErrorRateThreshold` | double | 50 | % error rate to quarantine file |

### ImportSourceConfig — Parser Properties

| Property | Type | Effect |
|----------|------|--------|
| `Parser.Delimiter` | string | Column separator for delimited formats |
| `Parser.Pattern` | string | Regex with named groups for complex formats |
| `Parser.FieldMappings` | dict | Map column index → LogEntry property |
| `Parser.MessageExtractors` | list | Regex extractors for business identifiers |

### General Settings (affect all sources)

| Property | Default | Effect |
|----------|---------|--------|
| `MaxConcurrentImports` | 4 | Semaphore limit for parallel source processing |
| `BatchSize` | 1000 | Entries per database INSERT batch |
| `RunOnce` | false | Exit after one cycle (for testing) |
| `RetryAttempts` | 3 | Retry count on transient failures |
| `HealthCheckInterval` | 60 | Seconds between health checks |

## Hot-Reload Flow

```mermaid
sequenceDiagram
    participant USER as User / API
    participant FSW as FileSystemWatcher
    participant IS as ImportService
    participant DB as PostgreSQL

    USER->>USER: Edit import-config.json<br/>(or POST /api/config/import-config)
    FSW->>IS: File changed event
    IS->>IS: Debounce (wait for writes to complete)
    IS->>IS: ReloadConfiguration()
    IS->>IS: Deserialize JSON → ImportConfiguration
    IS->>IS: ReinitializeImporters()
    Note over IS: Dispose old importers, create new ones
    IS->>DB: Continue with updated sources
```

## Web API Management Endpoints

```mermaid
flowchart LR
    subgraph "Config Editor (JSON file)"
        GET_CFG["GET /api/config/import-config<br/>Read import-config.json"]
        POST_CFG["POST /api/config/import-config<br/>Save import-config.json<br/>(triggers hot-reload)"]
    end

    subgraph "Import Sources (Database)"
        LIST["GET /api/ImportSources<br/>List all sources"]
        CREATE["POST /api/ImportSources<br/>Create source"]
        UPDATE["PUT /api/ImportSources/{id}<br/>Update source"]
        DELETE["DELETE /api/ImportSources/{id}<br/>Delete source"]
        TOGGLE["POST /api/ImportSources/{id}/toggle<br/>Enable/disable"]
        TEST["POST /api/ImportSources/{id}/test<br/>Test connection"]
    end

    subgraph "Import Status (Read-only)"
        STATUS["GET /api/ImportSources/status<br/>Current import status per source"]
    end
```

## End-to-End: From Config to Log Entry

```mermaid
flowchart LR
    CONFIG["import-config.json"] --> STARTUP["ImportService<br/>startup"]
    STARTUP --> MIGRATE["Migrate to DB"]
    MIGRATE --> LOOP["30s import loop"]
    
    LOOP --> FACTORY["CreateImporter()<br/>based on Type"]
    FACTORY --> IMPORTER["FileImporter /<br/>DatabaseImporter /<br/>EventLogImporter"]
    
    IMPORTER --> PARSE["Parse source data"]
    PARSE --> FILTER["Apply level filters"]
    FILTER --> BATCH["Batch (1000 entries)"]
    BATCH --> REPO["ILogRepository<br/>.AddBatchAsync()"]
    REPO --> PG["PostgreSQL<br/>log_entries table"]
    
    PG --> API["WebApi REST endpoints"]
    API --> UI["Dashboard / Log Search /<br/>Job Status / Analytics"]

    style CONFIG fill:#fff3cd,stroke:#ffc107
    style PG fill:#d4edda,stroke:#28a745
    style UI fill:#cce5ff,stroke:#004085
```
