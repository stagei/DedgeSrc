# Alert Agent Architecture

How the Alert Agent detects patterns across log entries, and how the full pipeline flows from raw log data through parsing, business identifier extraction, job correlation, and alert evaluation.

## System Overview

The GenericLogHandler has three runtime processes that work together:

```mermaid
flowchart LR
    subgraph "Import Service"
        FS["File Sources<br/>(log, json, xml, delimited)"]
        FI["FileImporter"]
        PARSE["Parser + MessageExtractors"]
        JOB["JobCorrelationService"]
    end

    subgraph "PostgreSQL"
        LOG["log_entries"]
        JOBS["job_executions"]
        SF["saved_filters"]
        AH["alert_history"]
    end

    subgraph "Alert Agent"
        EVAL["AlertAgentService<br/>(60s cycle)"]
        ACTIONS["Action Dispatch<br/>(webhook, script, email, servermonitor)"]
    end

    subgraph "Web API"
        UI["Web UI<br/>(Saved Filters page)"]
        API["REST API<br/>(SavedFiltersController)"]
    end

    FS --> FI --> PARSE --> LOG
    PARSE --> JOB --> JOBS
    SF --> EVAL --> AH
    EVAL --> ACTIONS
    LOG --> EVAL
    UI --> API --> SF

    style LOG fill:#d4edda,stroke:#28a745
    style EVAL fill:#fff3cd,stroke:#ffc107
    style ACTIONS fill:#f8d7da,stroke:#dc3545
```

## The Two-Phase Pattern Detection Architecture

Pattern detection happens in **two distinct phases**, spread across two separate processes:

| Phase | Process | What It Does | Where Patterns Are Defined |
|-------|---------|-------------|---------------------------|
| **Phase 1: Extraction** | Import Service | Parses raw log lines and extracts business identifiers (Ordrenr, Avdnr, AlertId, JobName) using regex `MessageExtractors` from config | `import-config.json` → `Parser.MessageExtractors` |
| **Phase 2: Evaluation** | Alert Agent | Queries extracted fields in the database using saved filter criteria with time windows, thresholds, and cooldowns | `saved_filters` table → `FilterJson` + `AlertConfig` |

```mermaid
flowchart TD
    subgraph "Phase 1: Extraction (ImportService)"
        RAW["Raw log line:<br/>'2025-02-18 10:30:00|SRV01|ERROR|...|Ordrenr: 12345 failed'"]
        DELIM["Delimiter parser<br/>splits on '|'"]
        FIELD["FieldMappings<br/>map columns → LogEntry properties"]
        EXTRACT["MessageExtractors<br/>regex on Message field"]
        ENTRY["LogEntry {<br/>  Timestamp, ComputerName, Level,<br/>  Message, <b>Ordrenr=12345</b>, <b>AlertId=...</b><br/>}"]

        RAW --> DELIM --> FIELD --> EXTRACT --> ENTRY
    end

    subgraph "Phase 2: Evaluation (AlertAgent)"
        FILTER["SavedFilter:<br/>Level=ERROR, Ordrenr=12345,<br/>TimeWindow=15min, Threshold=3"]
        QUERY["ILogRepository.SearchAsync()<br/>EF Core query with all criteria"]
        CHECK{"result.TotalCount<br/>≥ ThresholdCount?"}
        TRIGGER["TriggerAlert()<br/>webhook / script / email"]
        SKIP["Skip<br/>(below threshold)"]

        FILTER --> QUERY --> CHECK
        CHECK -->|Yes| TRIGGER
        CHECK -->|No| SKIP
    end

    ENTRY -->|"stored in PostgreSQL"| QUERY

    style EXTRACT fill:#fff3cd,stroke:#ffc107
    style TRIGGER fill:#f8d7da,stroke:#dc3545
```

## Phase 1: MessageExtractors in import-config.json

MessageExtractors are regex patterns defined per import source. After each log line is parsed into fields (Timestamp, ComputerName, Level, Message, etc.), the extractors scan the **Message** field to pull out business identifiers.

### Config Structure

```json
{
  "ImportSources": [{
    "Name": "ServerMonitor Logs",
    "Type": "file",
    "Config": {
      "Parser": {
        "Delimiter": "|",
        "FieldMappings": {
          "0": { "TargetColumn": "Timestamp", "DateFormat": "yyyy-MM-dd HH:mm:ss" },
          "1": { "TargetColumn": "ComputerName" },
          "9": { "TargetColumn": "Message" }
        },
        "MessageExtractors": [
          {
            "Name": "ordrenr",
            "Pattern": "(?:ordrenr|ordrenummer|orderno)[:\\s=]+(?<value>\\d+)",
            "TargetColumn": "Ordrenr",
            "CaptureGroup": "value",
            "IgnoreCase": true
          }
        ]
      }
    }
  }]
}
```

### Extraction Flow

```mermaid
sequenceDiagram
    participant LINE as Raw Log Line
    participant PARSER as Delimiter/Regex Parser
    participant LE as LogEntry object
    participant EXT as MessageExtractors
    participant DB as PostgreSQL

    LINE->>PARSER: "2025-02-18 10:30:00|SRV01|ERROR|...|Ordrenr: 12345 failed"
    PARSER->>LE: Split on '|', map fields via FieldMappings
    Note over LE: Timestamp=2025-02-18 10:30:00<br/>ComputerName=SRV01<br/>Level=ERROR<br/>Message="Ordrenr: 12345 failed"

    LE->>EXT: ApplyMessageExtractors(entry)

    loop For each MessageExtractor
        EXT->>EXT: Regex.Match(entry.Message, pattern)
        alt Match found
            EXT->>LE: SetLogEntryProperty("Ordrenr", "12345")
        else No match
            EXT->>EXT: Skip, try next extractor
        end
    end

    EXT->>LE: GenerateConcatenatedSearchString()
    Note over LE: Rebuild the full-text search column<br/>with all extracted fields

    LE->>DB: AddBatchAsync(entries)
```

### MessageExtractor Properties

| Property | Type | Description |
|----------|------|-------------|
| `Name` | string | Identifier for logging (e.g., "ordrenr") |
| `Pattern` | string | Regex with named capture group |
| `TargetColumn` | string | LogEntry property to populate (e.g., "Ordrenr", "Avdnr", "AlertId") |
| `CaptureGroup` | string | Named group to extract (default: "value") |
| `IgnoreCase` | bool | Case-insensitive matching (default: true) |

### Standard Extractors Used Across Sources

These three extractors are configured on most import sources:

```mermaid
flowchart LR
    MSG["Message field content"]
    
    MSG --> E1["ordrenr extractor<br/><code>(?:ordrenr|ordrenummer|orderno)[:\\s=]+(?&lt;value&gt;\\d+)</code>"]
    MSG --> E2["avdnr extractor<br/><code>(?:avdnr|avdeling)[:\\s=]+(?&lt;value&gt;\\d+)</code>"]
    MSG --> E3["alert_id extractor<br/><code>(?:alert_id|alertid|alarm_id)[:\\s=]+(?&lt;value&gt;[A-Za-z0-9_-]+)</code>"]

    E1 -->|"12345"| P1["LogEntry.Ordrenr"]
    E2 -->|"410"| P2["LogEntry.Avdnr"]
    E3 -->|"DISK_FULL"| P3["LogEntry.AlertId"]

    style E1 fill:#d4edda,stroke:#28a745
    style E2 fill:#cce5ff,stroke:#004085
    style E3 fill:#fff3cd,stroke:#ffc107
```

## Phase 1b: Job Correlation (Multi-Entry Pattern)

The `JobCorrelationService` in the Import Service performs **multi-entry pattern detection** by correlating "Started" and "Completed"/"Failed" log entries for the same job.

### How It Links Entries

```mermaid
sequenceDiagram
    participant IS as ImportService
    participant JCS as JobCorrelationService
    participant DB as PostgreSQL (job_executions)

    Note over IS: Batch of new log entries imported

    IS->>JCS: CorrelateJobsAsync(entries)

    JCS->>JCS: Filter entries with<br/>JobStatus != null AND JobName != null
    JCS->>JCS: Order by Timestamp

    loop For each job entry
        alt JobStatus == "Started"
            JCS->>DB: Check for existing open execution<br/>(same JobName + ComputerName + ProcessId)
            alt No duplicate found
                JCS->>DB: INSERT job_executions<br/>{JobName, StartedAt, Status="Started",<br/>StartLogEntryId}
            end
        else JobStatus == "Completed" or "Failed"
            JCS->>DB: Find matching open execution<br/>(same JobName + ComputerName + ProcessId,<br/>Status="Started")
            alt Match found
                JCS->>DB: UPDATE job_executions<br/>SET CompletedAt, Status, EndLogEntryId,<br/>DurationSeconds
            else No match (orphaned completion)
                JCS->>DB: INSERT job_executions<br/>{JobName, Status, StartedAt≈CompletedAt-1min}
            end
        end
    end
```

### JobExecution Lifecycle

```mermaid
statediagram-v2
    [*] --> Started : LogEntry with JobStatus="Started"
    Started --> Completed : LogEntry with JobStatus="Completed"<br/>(same JobName + ComputerName)
    Started --> Failed : LogEntry with JobStatus="Failed"
    Started --> TimedOut : No completion after<br/>OrphanTimeoutHours (default 24h)
    Completed --> [*]
    Failed --> [*]
    TimedOut --> [*]
```

### Job Correlation Config

Configured in `appsettings.json` under `JobTracking`:

| Property | Default | Description |
|----------|---------|-------------|
| `EnableJobCorrelation` | true | Enable/disable job linking |
| `OrphanTimeoutHours` | 24 | Hours before a started-but-not-completed job is marked TimedOut |
| `CheckIntervalMinutes` | 15 | How often to check for orphaned jobs |
| `AutoMarkOrphanedJobs` | true | Automatically mark orphans as TimedOut |
| `RetentionDays` | 90 | Days to keep job execution history |

## Phase 2: Alert Agent Evaluation

The Alert Agent is a separate background service that polls the database every 60 seconds.

### Alert Architecture

Alerts are **not** defined in `import-config.json`. They are defined through the Web UI and stored in the `saved_filters` database table. Each saved filter optionally has:

- `IsAlertEnabled` (bool) — tells the Alert Agent to evaluate this filter
- `FilterJson` — serialized search criteria (levels, message text, regex, business IDs, etc.)
- `AlertConfig` — serialized action configuration (type, threshold, cooldown, endpoints)

```mermaid
erDiagram
    saved_filters {
        uuid id PK
        string name
        string description
        text filter_json "LogSearchCriteria JSON"
        bool is_alert_enabled "AlertAgent reads this"
        text alert_config "AlertConfig JSON"
        datetime last_evaluated_at
        datetime last_triggered_at
        string created_by
        bool is_shared
        string category
    }

    alert_history {
        uuid id PK
        uuid filter_id FK
        string filter_name
        datetime triggered_at
        int match_count
        string action_type
        string action_taken
        bool success
        string error_message
        string action_response
        long execution_duration_ms
        string sample_entry_ids
    }

    log_entries {
        uuid id PK
        datetime timestamp
        string level
        string computer_name
        string message
        string ordrenr "Extracted by MessageExtractor"
        string avdnr "Extracted by MessageExtractor"
        string alert_id "Extracted by MessageExtractor"
        string job_name
        string job_status
    }

    job_executions {
        uuid id PK
        string job_name
        datetime started_at
        datetime completed_at
        string status
        uuid start_log_entry_id FK
        uuid end_log_entry_id FK
        double duration_seconds
    }

    saved_filters ||--o{ alert_history : "triggers"
    log_entries ||--o{ job_executions : "correlates"
    saved_filters }o--o{ log_entries : "queries"
```

### Alert Agent Main Loop

```mermaid
flowchart TD
    START["AlertAgentService starts<br/>10s initial delay"]
    
    START --> LOOP["Wait 60 seconds"]
    LOOP --> LOAD["Load saved_filters<br/>WHERE IsAlertEnabled = true"]
    
    LOAD --> EMPTY{"Any filters<br/>found?"}
    EMPTY -->|No| LOOP
    EMPTY -->|Yes| FOREACH

    FOREACH["For each SavedFilter"]
    FOREACH --> PARSE_CFG["Deserialize AlertConfig JSON"]
    PARSE_CFG --> ACTIVE{"IsActive?"}
    ACTIVE -->|No| NEXT["Next filter"]

    ACTIVE -->|Yes| COOLDOWN{"In cooldown?<br/>(LastTriggered + CooldownMinutes<br/>> now)"}
    COOLDOWN -->|Yes| NEXT

    COOLDOWN -->|No| CRITERIA["Build LogSearchCriteria<br/>from FilterJson"]
    CRITERIA --> WINDOW["Apply time window"]
    WINDOW --> SEARCH["ILogRepository.SearchAsync()"]
    SEARCH --> THRESHOLD{"TotalCount ≥<br/>ThresholdCount?"}
    
    THRESHOLD -->|No| UPDATE["Update LastEvaluatedAt"]
    THRESHOLD -->|Yes| TRIGGER["TriggerAlert()"]
    TRIGGER --> DISPATCH["Dispatch action"]
    DISPATCH --> HISTORY["Write AlertHistory record"]
    HISTORY --> UPDATE
    UPDATE --> NEXT
    NEXT --> FOREACH

    style TRIGGER fill:#f8d7da,stroke:#dc3545
    style SEARCH fill:#d4edda,stroke:#28a745
```

### Time Window Logic

The Alert Agent applies a time window to each query, so it only evaluates recent log entries:

```mermaid
flowchart TD
    TW{"TimeWindowMinutes<br/>setting"}
    
    TW -->|"> 0"| FIXED["Fixed window:<br/>FROM = now - TimeWindowMinutes<br/>TO = now"]
    TW -->|"= 0"| CHECK{"Filter has<br/>FromDate/ToDate?"}
    CHECK -->|Yes| CUSTOM["Use filter's own dates"]
    CHECK -->|No| DEFAULT["Default window:<br/>FROM = now - 5 minutes<br/>TO = now"]

    FIXED --> QUERY["SearchAsync(criteria)"]
    CUSTOM --> QUERY
    DEFAULT --> QUERY

    style DEFAULT fill:#fff3cd,stroke:#ffc107
```

### Multi-Entry Pattern Detection Through Filters

The Alert Agent detects multi-entry patterns **through the combination of filter criteria and threshold**. A saved filter can match many entries across a time window:

```mermaid
flowchart TD
    subgraph "Example: Detect Repeated Errors for Order 12345"
        F["SavedFilter:<br/>Level = ERROR<br/>Ordrenr = 12345<br/>TimeWindowMinutes = 15<br/>ThresholdCount = 3"]
        
        E1["LogEntry 10:01<br/>ERROR | Ordrenr: 12345 validation failed"]
        E2["LogEntry 10:05<br/>ERROR | Ordrenr: 12345 DB insert error"]
        E3["LogEntry 10:09<br/>ERROR | Ordrenr: 12345 retry exhausted"]
        E4["LogEntry 10:14<br/>WARN  | Ordrenr: 12345 fallback used"]

        F --> QUERY["SearchAsync:<br/>Level=ERROR, Ordrenr=12345,<br/>FROM=9:59, TO=10:14"]
        E1 --> QUERY
        E2 --> QUERY
        E3 --> QUERY
        E4 -.->|"WARN ≠ ERROR<br/>excluded"| QUERY

        QUERY --> COUNT["TotalCount = 3"]
        COUNT --> MATCH["3 ≥ 3 → ALERT TRIGGERED"]
    end

    style MATCH fill:#f8d7da,stroke:#dc3545
    style E4 fill:#f8f9fa,stroke:#6c757d
```

### AlertConfig Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Type` | string | "webhook" | Action type: `webhook`, `script`, `email`, `servermonitor` |
| `Endpoint` | string | — | URL (webhook/servermonitor) or file path (script) |
| `Method` | string | "POST" | HTTP method for webhooks |
| `Headers` | dict | {} | Custom HTTP headers for webhooks |
| `BodyTemplate` | string | — | Template with `{{filterName}}`, `{{matchCount}}`, `{{entries}}` |
| `ThresholdCount` | int | 1 | Minimum matches to trigger |
| `CooldownMinutes` | int | 15 | Suppress re-triggering within this window |
| `TimeWindowMinutes` | int | 0 | Search window (0 = last 5 min default) |
| `IncludeEntries` | bool | true | Include matching entries in payload |
| `MaxEntriesToInclude` | int | 10 | Max entries in payload |
| `IsActive` | bool | true | Enable/disable this alert |
| `ScriptArguments` | list | [] | Extra args for script actions |
| `EmailRecipients` | list | [] | Email addresses for email actions |
| `EmailSubject` | string | "Log Handler Alert: {{filterName}}" | Email subject template |
| `ServerMonitorSeverity` | string | "Warning" | Severity level for ServerMonitor |

## Action Dispatch

```mermaid
flowchart TD
    TRIGGER["TriggerAlert(filter, alertConfig, result)"]
    
    TRIGGER --> TYPE{"alertConfig.Type"}
    
    TYPE -->|webhook| WH["ExecuteWebhook()<br/>HTTP POST/GET to Endpoint<br/>with JSON payload"]
    TYPE -->|script| SC["ExecuteScript()<br/>pwsh.exe -File Endpoint<br/>-PayloadFile temp.json"]
    TYPE -->|email| EM["ExecuteEmail()<br/>SMTP via MailKit<br/>to EmailRecipients"]
    TYPE -->|servermonitor| SM["ExecuteServerMonitor()<br/>POST alarm to<br/>ServerMonitor API"]

    WH --> HIST["Write AlertHistory<br/>{Success, ActionResponse,<br/>ExecutionDurationMs,<br/>SampleEntryIds}"]
    SC --> HIST
    EM --> HIST
    SM --> HIST

    HIST --> COOL["Set filter.LastTriggeredAt = now<br/>(starts cooldown)"]

    style WH fill:#cce5ff,stroke:#004085
    style SC fill:#d4edda,stroke:#28a745
    style EM fill:#fff3cd,stroke:#ffc107
    style SM fill:#f8d7da,stroke:#dc3545
```

### Webhook Payload Structure

```json
{
  "FilterId": "guid",
  "FilterName": "Order 12345 Error Threshold",
  "TriggeredAt": "2025-02-18T10:14:00Z",
  "MatchCount": 3,
  "Threshold": 3,
  "Entries": [
    {
      "Id": "guid",
      "Timestamp": "2025-02-18T10:09:00Z",
      "Level": "ERROR",
      "ComputerName": "SRV01",
      "UserName": "SYSTEM",
      "Message": "Ordrenr: 12345 retry exhausted",
      "ErrorId": null,
      "Ordrenr": "12345",
      "Avdnr": null,
      "JobName": "OrderProcessing"
    }
  ]
}
```

If `BodyTemplate` is set, placeholders are replaced: `{{filterName}}`, `{{matchCount}}`, `{{threshold}}`, `{{triggeredAt}}`, `{{entries}}`.

## End-to-End: Raw Log to Alert

```mermaid
sequenceDiagram
    participant SRC as Log Source<br/>(file/network share)
    participant FI as FileImporter
    participant EXT as MessageExtractors
    participant JCS as JobCorrelationService
    participant DB as PostgreSQL
    participant AA as AlertAgent
    participant ACT as Action<br/>(webhook/email/script)

    Note over SRC: Raw file:<br/>2025-02-18 10:01|SRV01|ERROR|OrderProc|...|Ordrenr: 12345 failed

    SRC->>FI: Read new lines (append-only tracking)
    FI->>FI: Parse with delimiter/regex

    FI->>EXT: ApplyMessageExtractors(entry)
    EXT->>EXT: Match "Ordrenr: 12345" → Ordrenr=12345
    EXT->>EXT: Match "alert_id: ORDER_FAIL" → AlertId=ORDER_FAIL

    FI->>JCS: CorrelateJobsAsync(entries)
    JCS->>JCS: Link Started/Completed events<br/>into JobExecution records

    FI->>DB: AddBatchAsync(entries)
    JCS->>DB: Save JobExecution records

    Note over DB: Entries stored with<br/>extracted business identifiers

    loop Every 60 seconds
        AA->>DB: Load saved_filters WHERE IsAlertEnabled
        AA->>DB: SearchAsync(criteria)<br/>Level=ERROR, Ordrenr=12345, TimeWindow=15min
        DB-->>AA: 3 matches found

        alt ThresholdCount met (3 ≥ 3)
            AA->>ACT: Dispatch action (webhook/email/script)
            ACT-->>AA: Response
            AA->>DB: Insert AlertHistory record
            AA->>DB: Update filter.LastTriggeredAt (cooldown starts)
        end
    end
```

## Where Each Piece Is Configured

```mermaid
flowchart TD
    subgraph "import-config.json (file)"
        IC_SOURCES["ImportSources[]<br/>Name, Type, Enabled, Priority"]
        IC_PARSER["Parser<br/>Delimiter, FieldMappings"]
        IC_EXTRACTORS["MessageExtractors[]<br/>Pattern, TargetColumn, CaptureGroup"]

        IC_SOURCES --> IC_PARSER --> IC_EXTRACTORS
    end

    subgraph "appsettings.json (file)"
        AS_JOB["JobTracking<br/>EnableJobCorrelation,<br/>OrphanTimeoutHours"]
        AS_SMTP["SmtpSettings<br/>Host, Port, From"]
    end

    subgraph "saved_filters table (database)"
        SF_FILTER["FilterJson<br/>Levels, MessageText, RegexPattern,<br/>Ordrenr, Avdnr, AlertId, JobName"]
        SF_ALERT["AlertConfig<br/>Type, Threshold, Cooldown,<br/>TimeWindow, Endpoint"]
    end

    IC_EXTRACTORS -->|"Populates entry fields<br/>(Ordrenr, Avdnr, AlertId)"| SF_FILTER
    AS_JOB -->|"Configures"| JCS["JobCorrelationService"]
    AS_SMTP -->|"Configures"| EMAIL["Email alerts"]
    SF_FILTER -->|"Query criteria"| AA["AlertAgent evaluation"]
    SF_ALERT -->|"Action config"| AA

    style IC_EXTRACTORS fill:#fff3cd,stroke:#ffc107
    style SF_ALERT fill:#f8d7da,stroke:#dc3545
    style SF_FILTER fill:#d4edda,stroke:#28a745
```

## Summary

| Concern | Where Configured | Where Executed | How It Works |
|---------|-----------------|----------------|-------------|
| **Line parsing** | `import-config.json` → `Parser.Delimiter` + `FieldMappings` | ImportService → FileImporter | Split line, map columns to LogEntry properties |
| **Business ID extraction** | `import-config.json` → `Parser.MessageExtractors[]` | ImportService → `ApplyMessageExtractors()` | Regex on Message field, populate Ordrenr/Avdnr/AlertId |
| **Job correlation** | `appsettings.json` → `JobTracking` | ImportService → `JobCorrelationService` | Match "Started"→"Completed" entries by JobName+Computer |
| **Alert filter criteria** | `saved_filters` table → `FilterJson` | AlertAgent → `BuildSearchCriteria()` | Multi-field query on log_entries with time window |
| **Alert threshold** | `saved_filters` table → `AlertConfig.ThresholdCount` | AlertAgent → `EvaluateFilter()` | Trigger only when match count ≥ threshold |
| **Alert action** | `saved_filters` table → `AlertConfig.Type` + `Endpoint` | AlertAgent → `TriggerAlert()` | Webhook, script, email, or ServerMonitor |
| **Alert cooldown** | `saved_filters` table → `AlertConfig.CooldownMinutes` | AlertAgent → cooldown check | Suppress re-triggering for N minutes |
| **Alert history** | `alert_history` table | AlertAgent → every trigger | Logs match count, action result, sample entry IDs |
