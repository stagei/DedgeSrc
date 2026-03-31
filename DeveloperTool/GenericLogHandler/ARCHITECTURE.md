# Generic Log Handler - Architecture Documentation

## Executive Summary

The Generic Log Handler is a **well-architected .NET 10 solution** following clean architecture principles with proper separation of concerns, dependency inversion, and extensibility patterns. This document provides a comprehensive architectural overview with diagrams.

---

## Architecture Assessment

### Overall Rating: ✅ Architecturally Sound

| Criteria | Score | Notes |
|----------|-------|-------|
| **Separation of Concerns** | ⭐⭐⭐⭐⭐ | Clear layering (Core → Data → Services) |
| **Dependency Inversion** | ⭐⭐⭐⭐⭐ | Interfaces for all major contracts |
| **Extensibility** | ⭐⭐⭐⭐⭐ | Plugin-style importers and parsers |
| **Testability** | ⭐⭐⭐⭐☆ | Good abstraction, but no test projects yet |
| **Resilience** | ⭐⭐⭐⭐⭐ | Retry logic, circuit breakers, graceful degradation |
| **Performance** | ⭐⭐⭐⭐⭐ | Streaming, batching, pagination, indexing |
| **Security** | ⭐⭐⭐⭐☆ | Windows Auth ready, rate limiting, but needs hardening |
| **Observability** | ⭐⭐⭐⭐⭐ | Serilog, audit logs, import status tracking |

---

## Solution Structure

```mermaid
graph TB
    subgraph Solution["GenericLogHandler.sln"]
        Core["🔷 GenericLogHandler.Core<br/>Domain Models & Interfaces"]
        Data["🔶 GenericLogHandler.Data<br/>EF Core & Repositories"]
        Import["🟢 GenericLogHandler.ImportService<br/>Background Import Service"]
        WebApi["🔵 GenericLogHandler.WebApi<br/>REST API & Static UI"]
        Alert["🟣 GenericLogHandler.AlertAgent<br/>Alert Evaluation Service"]
    end
    
    Core --> Data
    Data --> Import
    Data --> WebApi
    Data --> Alert
    
    style Core fill:#e1f5fe
    style Data fill:#fff3e0
    style Import fill:#e8f5e9
    style WebApi fill:#e3f2fd
    style Alert fill:#f3e5f5
```

---

## Layer Architecture

```mermaid
flowchart TB
    subgraph Presentation["Presentation Layer"]
        UI["Static Web UI<br/>(HTML/CSS/JS)"]
        Controllers["ASP.NET Controllers<br/>(REST API)"]
        OpenApiDocs["OpenAPI + Scalar"]
    end
    
    subgraph Application["Application Layer"]
        ImportSvc["Import Service<br/>(BackgroundService)"]
        AlertSvc["Alert Agent<br/>(BackgroundService)"]
        MaintenanceSvc["Maintenance Services<br/>(DB Cleanup, Sanitation)"]
    end
    
    subgraph Domain["Domain Layer (Core)"]
        Models["Domain Models<br/>(LogEntry, ImportStatus)"]
        Interfaces["Interfaces<br/>(ILogRepository, ILogImporter)"]
        Config["Configuration<br/>(ImportConfiguration)"]
    end
    
    subgraph Infrastructure["Infrastructure Layer (Data)"]
        DbContext["LoggingDbContext<br/>(EF Core)"]
        Repos["LogRepository"]
        Importers["Importers<br/>(File, DB, EventLog)"]
        Parsers["Parsers<br/>(JSON, XML, IIS)"]
    end
    
    subgraph External["External Systems"]
        DB[(PostgreSQL<br/>or DB2)]
        Files["Log Files<br/>(JSON, XML, etc.)"]
        EventLog["Windows<br/>Event Log"]
        SMTP["SMTP Server"]
        Webhooks["External<br/>Webhooks"]
    end
    
    UI --> Controllers
    Controllers --> Interfaces
    ImportSvc --> Interfaces
    AlertSvc --> Interfaces
    MaintenanceSvc --> Interfaces
    
    Interfaces --> Repos
    Importers --> Interfaces
    Repos --> DbContext
    DbContext --> DB
    
    Importers --> Files
    Importers --> EventLog
    AlertSvc --> SMTP
    AlertSvc --> Webhooks
```

---

## Project Dependencies

```mermaid
graph LR
    subgraph Core["GenericLogHandler.Core"]
        Models["Models"]
        IRepo["ILogRepository"]
        IImport["ILogImporter"]
        Config["Configuration"]
    end
    
    subgraph Data["GenericLogHandler.Data"]
        DbCtx["LoggingDbContext"]
        LogRepo["LogRepository"]
        ConnStr["Connection Strings"]
    end
    
    subgraph Import["GenericLogHandler.ImportService"]
        ImportSvc["ImportService"]
        FileImp["FileImporter"]
        DbImp["DatabaseImporter"]
        EvtImp["EventLogImporter"]
        Retry["RetryService"]
        XmlP["XmlParser"]
        IisP["IisLogParser"]
    end
    
    subgraph WebApi["GenericLogHandler.WebApi"]
        Ctrl["Controllers"]
        Services["Background Services"]
        Static["wwwroot"]
    end
    
    subgraph Alert["GenericLogHandler.AlertAgent"]
        AlertSvc["AlertAgentService"]
        EmailSvc["EmailService"]
    end
    
    Core --> Data
    Core --> Import
    Core --> WebApi
    Core --> Alert
    
    Data --> Import
    Data --> WebApi
    Data --> Alert
```

---

## Data Flow Diagrams

### Import Flow

```mermaid
sequenceDiagram
    participant Source as Log Source
    participant Importer as ILogImporter
    participant Parser as Parser
    participant Retry as RetryService
    participant Repo as ILogRepository
    participant DB as PostgreSQL
    
    loop Every Poll Interval
        Source->>Importer: New logs available
        Importer->>Parser: Parse raw data
        Parser-->>Importer: LogEntry[]
        
        loop Batch Processing
            Importer->>Retry: Execute with retry
            Retry->>Repo: AddBatchAsync(entries)
            Repo->>DB: INSERT INTO log_entries
            DB-->>Repo: Success
            Repo-->>Retry: Count
            
            alt Circuit Breaker Open
                Retry-->>Importer: CircuitBreakerOpenException
            else Success
                Retry-->>Importer: Saved count
            end
        end
        
        Importer->>Repo: UpdateImportStatus
    end
```

### Search Flow

```mermaid
sequenceDiagram
    participant Client as Web UI / API Client
    participant API as LogsController
    participant Repo as ILogRepository
    participant EF as EF Core
    participant DB as PostgreSQL
    
    Client->>API: POST /api/logs/search
    API->>API: Build LogSearchCriteria
    API->>Repo: SearchAsync(criteria)
    
    Repo->>EF: Build IQueryable
    
    alt Has Regex Pattern
        EF->>EF: Add LIKE conditions
    end
    
    alt Has Date Range
        EF->>EF: Filter by Timestamp
    end
    
    EF->>DB: Execute SQL
    DB-->>EF: Result Set
    EF-->>Repo: List<LogEntry>
    Repo-->>API: PagedResult<LogEntry>
    API-->>Client: JSON Response
```

### Alert Evaluation Flow

```mermaid
sequenceDiagram
    participant Timer as PeriodicTimer
    participant Agent as AlertAgentService
    participant DB as Database
    participant Repo as ILogRepository
    participant Action as Alert Action
    
    loop Every 60 seconds
        Timer->>Agent: Tick
        Agent->>DB: Get SavedFilters (IsAlertEnabled=true)
        DB-->>Agent: Filters[]
        
        loop Each Filter
            Agent->>Agent: Parse filter → LogSearchCriteria
            Agent->>Repo: SearchAsync(criteria)
            Repo-->>Agent: PagedResult
            
            alt Count >= ThresholdCount
                Agent->>Agent: Check cooldown
                
                alt Not in cooldown
                    Agent->>Action: Execute (Webhook/Script/Email)
                    Action-->>Agent: Result
                    Agent->>DB: Insert AlertHistory
                end
            end
        end
    end
```

---

## Component Architecture

### Importer Strategy Pattern

```mermaid
classDiagram
    class ILogImporter {
        <<interface>>
        +Name: string
        +SupportedSourceTypes: IEnumerable~string~
        +InitializeAsync(source)
        +ImportAsync(): ImportResult
        +TestConnectionAsync(): bool
        +GetStatusAsync(): ImportStatus
    }
    
    class FileImporter {
        -FileSystemWatcher _watcher
        -Dictionary~string,FileTrackingInfo~ _fileTracking
        +ParseJsonFile()
        +ParseXmlFile()
        +ParseLogFile()
        +QuarantineFile()
    }
    
    class DatabaseImporter {
        -DbConnection _connection
        +ExecuteQuery()
        +TrackIncrementalColumn()
    }
    
    class EventLogImporter {
        -EventLogReader _reader
        +ReadNewEvents()
    }
    
    ILogImporter <|.. FileImporter
    ILogImporter <|.. DatabaseImporter
    ILogImporter <|.. EventLogImporter
    
    class ImportService {
        -List~ILogImporter~ _importers
        -SemaphoreSlim _semaphore
        -RetryService _retryService
        +CreateImporter(source): ILogImporter
        +RunImportCycle()
    }
    
    ImportService --> ILogImporter : creates
```

### Repository Pattern

```mermaid
classDiagram
    class ILogRepository {
        <<interface>>
        +AddAsync(entry): LogEntry
        +AddBatchAsync(entries): int
        +GetByIdAsync(id): LogEntry?
        +SearchAsync(criteria): PagedResult
        +GetStatisticsAsync(): LogStatistics
        +DeleteOlderThanAsync(date): int
        +DeleteOlderThanByLevelAsync(date, level): int
        +GetDistinctValuesAsync(field): List~string~
        +GetByIdsAsync(ids): List~LogEntry~
        +SetProtectedAsync(ids, protected): int
        +DeleteByIdsAsync(ids): int
    }
    
    class LogRepository {
        -LoggingDbContext _context
        -ILogger _logger
        +BuildSearchQuery()
        +ApplyFilters()
    }
    
    class LoggingDbContext {
        +LogEntries: DbSet~LogEntry~
        +ImportStatuses: DbSet~ImportStatus~
        +SavedFilters: DbSet~SavedFilter~
        +AlertHistories: DbSet~AlertHistory~
        +AuditLogs: DbSet~AuditLog~
    }
    
    ILogRepository <|.. LogRepository
    LogRepository --> LoggingDbContext : uses
```

---

## Database Schema

```mermaid
erDiagram
    log_entries {
        uuid id PK
        bigint internal_id UK
        timestamp timestamp
        varchar level
        int process_id
        varchar computer_name
        varchar user_name
        text message
        text concatenated_search_string
        varchar source_file
        varchar source_type
        timestamp import_timestamp
        varchar import_batch_id
        boolean protected
        varchar job_name
        varchar job_status
        varchar alert_id
        varchar ordrenr
        varchar avdnr
    }
    
    import_status {
        uuid id PK
        varchar source_name
        varchar file_path
        varchar source_type
        varchar status
        timestamp last_import_timestamp
        bigint last_processed_line
        bigint records_processed
        bigint records_failed
    }
    
    saved_filters {
        uuid id PK
        varchar name
        text filter_json
        timestamp created_at
        varchar created_by
        boolean is_alert_enabled
        text alert_config_json
    }
    
    alert_history {
        uuid id PK
        uuid filter_id FK
        timestamp triggered_at
        int matched_count
        varchar action_type
        boolean success
        text error_message
    }
    
    audit_log {
        bigint id PK
        timestamp timestamp
        varchar user_id
        varchar action
        varchar entity_type
        varchar entity_id
        text details
        boolean success
    }
    
    log_entries ||--o{ import_status : "tracked by"
    saved_filters ||--o{ alert_history : "triggers"
```

---

## Frontend Architecture

```mermaid
graph TB
    subgraph Pages["HTML Pages"]
        Index["index.html<br/>(Dashboard)"]
        Search["log-search.html<br/>(Search)"]
        Jobs["job-status.html"]
        Analytics["analytics.html"]
        Maint["maintenance.html"]
        Audit["audit-log.html"]
        Import["import-status.html"]
        Filters["saved-filters.html"]
    end
    
    subgraph Components["JS Components"]
        Api["api.js<br/>(Fetch wrapper)"]
        Events["events.js<br/>(SSE client)"]
        Theme["theme.js"]
        Toast["toast.js"]
        Modal["modal.js"]
        Loader["loader.js"]
        Table["table.js"]
        ColMgr["column-manager.js"]
        Search2["search-enhancements.js"]
        Shortcuts["shortcuts.js"]
        VScroll["virtual-scroll.js"]
    end
    
    subgraph Styles["CSS"]
        Dashboard["dashboard.css<br/>(All styles)"]
    end
    
    Pages --> Api
    Pages --> Events
    Pages --> Components
    Pages --> Styles
    
    Api --> |fetch + credentials| Backend["WebApi"]
    Events --> |SSE stream| Backend
```

---

## Deployment Architecture

```mermaid
graph TB
    subgraph Server["Windows Server 2025"]
        subgraph IIS["IIS"]
            WebApp["GenericLogHandler.WebApi<br/>(ASP.NET Core)"]
            Static["wwwroot<br/>(Static Files)"]
        end
        
        subgraph WinServices["Windows Services"]
            ImportSvc["GenericLogHandler.ImportService"]
            AlertSvc["GenericLogHandler.AlertAgent"]
        end
        
        subgraph Data["Data Sources"]
            LogFiles["Log Files<br/>(C:\opt\data\AllPwshLog)"]
            EventLog["Windows Event Log"]
        end
    end
    
    subgraph Database["Database Server"]
        PG[(PostgreSQL 18)]
    end
    
    subgraph External["External"]
        SMTP["SMTP Server"]
        Webhooks["External APIs"]
    end
    
    WebApp --> PG
    ImportSvc --> PG
    AlertSvc --> PG
    
    ImportSvc --> LogFiles
    ImportSvc --> EventLog
    AlertSvc --> SMTP
    AlertSvc --> Webhooks
    
    Client["Web Browser"] --> IIS
```

---

## Key Design Patterns

### 1. Repository Pattern
All database access goes through `ILogRepository`, isolating EF Core details from consumers.

### 2. Strategy Pattern
`ILogImporter` implementations (`FileImporter`, `DatabaseImporter`, `EventLogImporter`) are selected at runtime based on source configuration.

### 3. Factory Method
`ImportService.CreateImporter()` creates the appropriate importer based on `ImportSource.Type`.

### 4. Circuit Breaker
`RetryService` implements a circuit breaker to prevent cascading failures when a source is consistently failing.

### 5. Observer Pattern
Server-Sent Events (`EventsController`) notify connected clients of real-time updates.

### 6. Background Worker
`BackgroundService` implementations for long-running import, alert, and maintenance tasks.

---

## Strengths

| Aspect | Implementation |
|--------|----------------|
| **Clean Architecture** | Core has no dependencies on outer layers |
| **Multi-DB Support** | EF Core providers for PostgreSQL, DB2, SQL Server |
| **Streaming** | Large files processed line-by-line, not loaded entirely |
| **Batch Processing** | Configurable batch sizes for bulk inserts |
| **Hot Reload Config** | FileSystemWatcher monitors config files for changes |
| **Retry Logic** | Exponential backoff with jitter for transient failures |
| **Audit Trail** | All user actions logged to `audit_log` table |
| **Protected Entries** | Logs can be marked protected from automatic cleanup |
| **Quarantine** | Corrupted files moved to quarantine folder |
| **Real-time Updates** | SSE for live dashboard updates |

---

## Areas for Improvement

| Area | Recommendation |
|------|----------------|
| **Unit Tests** | Add test projects with xUnit/Moq |
| **Integration Tests** | Add Testcontainers for DB testing |
| **API Versioning** | Add `/api/v1/` prefix for future compatibility |
| **CQRS** | Consider separating read/write models for scale |
| **Message Queue** | Add RabbitMQ/Azure Service Bus for decoupling |
| **Caching** | Add Redis for frequently-accessed data |
| **Health Checks** | Expand `/health` with dependency checks |
| **OpenTelemetry** | Add distributed tracing |

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Runtime | .NET 10 |
| API Framework | ASP.NET Core 10 |
| ORM | Entity Framework Core 10 |
| Primary Database | PostgreSQL 18 |
| Alternative Databases | IBM DB2, SQL Server |
| Logging | Serilog |
| Authentication | Windows Authentication (Negotiate) |
| Web UI | Vanilla JavaScript (no framework) |
| Background Services | .NET Worker Service |
| Email | MailKit |
| Excel Export | ClosedXML |
| CSV Processing | CsvHelper |

---

## Conclusion

The Generic Log Handler solution follows **solid architectural principles** and is well-suited for its purpose as an enterprise log aggregation and alerting platform. The layered architecture, proper abstraction, and extensibility patterns make it maintainable and scalable.

The main areas for future investment are:
1. **Test coverage** - Critical for enterprise reliability
2. **Distributed tracing** - For production observability
3. **Caching layer** - For improved performance at scale

Overall: **Production-ready architecture** with room for incremental improvements.
