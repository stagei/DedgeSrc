# Configuration Storage Strategy: JSON Files vs Database

Why the Import Service and Alert Agent store configuration where they do, and the architectural reasoning behind the hybrid approach.

## The Short Answer

The system uses **both** JSON files and the database, but for different purposes:

| What | Where | Why |
|------|-------|-----|
| Import sources, parsers, extractors | `import-config.json` → migrated to database | Bootstrap: must exist before the database is reachable |
| Database connection string | `appsettings.json` | Chicken-and-egg: can't read the DB connection from the DB |
| Alert rules and actions | Database (`saved_filters` table) | Runtime data: created/modified by users through the UI |
| Service settings (batch size, concurrency) | `import-config.json` / `appsettings.json` | Infrastructure: rarely changes, needs to be available at startup |

## The Chicken-and-Egg Problem

The most fundamental reason is the **startup dependency chain**. The ImportService and AlertAgent need to know *how* to connect to the database before they can read anything from it.

```mermaid
flowchart TD
    START["Process starts"]
    
    START --> Q1{"Where is the<br/>database?"}
    Q1 -->|"Read from<br/>appsettings.json"| CONN["ConnectionString:<br/>Host=t-no1fkxtst-db;Port=8432;..."]
    
    CONN --> Q2{"What sources<br/>to import?"}
    Q2 -->|"Read from<br/>import-config.json"| SOURCES["6 import sources<br/>with parser configs"]
    
    SOURCES --> Q3{"Database<br/>reachable?"}
    Q3 -->|Yes| MIGRATE["Migrate JSON sources → DB<br/>(first run only)"]
    Q3 -->|No| FALLBACK["Use JSON config directly<br/>(resilient fallback)"]
    
    MIGRATE --> RUN["Run import loop<br/>using DB sources"]
    FALLBACK --> RUN

    style Q1 fill:#f8d7da,stroke:#dc3545
    style FALLBACK fill:#fff3cd,stroke:#ffc107
    style MIGRATE fill:#d4edda,stroke:#28a745
```

If the database is down, unreachable, or has not been created yet (fresh deployment), the ImportService **still starts and works** because it falls back to reading `import-config.json` directly.

## What Lives Where and Why

### 1. `appsettings.json` — Infrastructure That Cannot Be in a Database

```mermaid
flowchart LR
    subgraph "appsettings.json"
        DB_CONN["Database.ConnectionString<br/><i>Where is PostgreSQL?</i>"]
        SMTP["SmtpSettings<br/><i>Where is the mail server?</i>"]
        SERILOG["Serilog config<br/><i>Where do logs go?</i>"]
        DedgeAuth["DedgeAuth config<br/><i>Where is the auth server?</i>"]
        JOB["JobTracking settings<br/><i>Correlation behavior</i>"]
    end

    DB_CONN -->|"Needed before<br/>DB is available"| REASON1["Cannot be in DB"]
    SMTP -->|"Needed before<br/>DB is available"| REASON1
    SERILOG -->|"Needed before<br/>anything else"| REASON1
    DedgeAuth -->|"Needed before<br/>auth middleware"| REASON1

    style REASON1 fill:#f8d7da,stroke:#dc3545
```

These settings define **how to reach external systems**. They must be available the instant the process starts, before any database connection is established. Storing them in the database would create a circular dependency.

### 2. `import-config.json` — Bootstrap Config That Migrates to DB

```mermaid
flowchart TD
    subgraph "import-config.json (on disk)"
        SOURCES["ImportSources[]<br/>6 source definitions"]
        PARSERS["Parser configs<br/>Delimiters, FieldMappings"]
        EXTRACTORS["MessageExtractors<br/>Regex patterns"]
        RETENTION["Retention policy<br/>DefaultDays, ByLevel"]
        GENERAL["General settings<br/>BatchSize, MaxConcurrent"]
        MONITORING["Monitoring thresholds<br/>Error rates, queue sizes"]
    end

    subgraph "First startup"
        SOURCES -->|"MigrateJsonSourcesToDatabaseAsync()"| DB_SOURCES["import_sources table<br/>(database)"]
    end

    subgraph "Subsequent startups"
        DB_SOURCES -->|"GetImportSourcesAsync()<br/>DB sources take priority"| RUNTIME["ImportService runtime"]
        SOURCES -.->|"Fallback only<br/>if DB unavailable"| RUNTIME
    end

    GENERAL -->|"Always from JSON<br/>(not migrated)"| RUNTIME
    RETENTION -->|"Always from JSON<br/>(not migrated)"| RUNTIME

    style DB_SOURCES fill:#d4edda,stroke:#28a745
    style SOURCES fill:#fff3cd,stroke:#ffc107
```

The import sources start in JSON and **migrate to the database on first run**. After that, the database version is authoritative. But the JSON file remains as:

- A **bootstrap mechanism** for fresh deployments
- A **fallback** when the database is unavailable
- A **hot-reload source** for development (edit the file, ImportService picks it up via `FileSystemWatcher`)
- A **version-controlled record** of the initial configuration (committed to git)

### 3. `saved_filters` table — Pure Runtime Data

```mermaid
flowchart TD
    subgraph "Database only"
        SF["saved_filters<br/>Alert rules + filter criteria"]
        AH["alert_history<br/>Trigger history"]
        JE["job_executions<br/>Correlated job runs"]
        IS["import_sources<br/>Migrated from JSON"]
    end

    subgraph "Created by"
        UI["Web UI<br/>(users create/edit filters)"]
        AGENT["AlertAgent<br/>(writes trigger history)"]
        IMPORT["ImportService<br/>(writes job executions)"]
        MIGRATE["Migration<br/>(copies JSON → DB)"]
    end

    UI --> SF
    AGENT --> AH
    IMPORT --> JE
    MIGRATE --> IS

    style SF fill:#d4edda,stroke:#28a745
    style AH fill:#d4edda,stroke:#28a745
```

Alert rules live **exclusively in the database** because they are:

- Created and modified by users through the Web UI at runtime
- Not needed at startup (the AlertAgent loads them each 60-second cycle)
- Frequently updated (enable/disable, change thresholds, add new alerts)
- User-owned data, not infrastructure configuration

## The Hybrid Lifecycle

```mermaid
sequenceDiagram
    participant DISK as JSON Files<br/>(import-config.json)
    participant APP as ImportService
    participant DB as PostgreSQL
    participant UI as Web UI
    participant AGENT as AlertAgent

    Note over DISK,DB: Fresh deployment

    APP->>DISK: Read import-config.json<br/>(connection string, sources, parsers)
    APP->>DB: Connect using ConnectionString
    APP->>DB: Auto-migrate schema (EF Core)
    APP->>DB: MigrateJsonSourcesToDatabaseAsync()<br/>Copy 6 sources → import_sources table

    Note over DISK,DB: Normal operation

    loop Every 30 seconds
        APP->>DB: GetImportSourcesAsync()<br/>Load from import_sources (priority)
        APP->>APP: Run importers
    end

    UI->>DB: User creates SavedFilter<br/>with IsAlertEnabled=true, AlertConfig

    loop Every 60 seconds
        AGENT->>DB: Load saved_filters<br/>WHERE IsAlertEnabled
        AGENT->>DB: SearchAsync(criteria)
        AGENT->>DB: Write alert_history
    end

    Note over DISK,DB: Database outage

    APP->>DB: GetImportSourcesAsync() fails
    APP->>DISK: Fallback to import-config.json
    APP->>APP: Continue importing (degraded)
    Note over AGENT: AlertAgent pauses<br/>(cannot query log_entries)

    Note over DISK,DB: Config change during development

    DISK->>DISK: Developer edits import-config.json
    APP->>APP: FileSystemWatcher detects change
    APP->>APP: ReloadConfiguration()
    APP->>APP: ReinitializeImporters()
    Note over APP: New config active without restart
```

## Why Not Store Everything in the Database?

| Concern | JSON File | Database |
|---------|-----------|----------|
| **Available before DB connection** | Yes | No (circular dependency) |
| **Works during DB outage** | Yes | No |
| **Version-controlled in git** | Yes | No (requires DB exports) |
| **Editable with a text editor** | Yes | Needs UI or SQL |
| **Hot-reload without restart** | Yes (FileSystemWatcher) | Requires polling |
| **Deployed with the application** | Yes (part of publish) | Requires separate migration |
| **Multi-user editing** | No (file locks) | Yes (concurrent access) |
| **Audit trail** | Git history only | DB triggers/history tables |
| **UI management** | Config Editor page (raw JSON) | Dedicated CRUD pages |

## Why Not Store Everything in JSON Files?

| Concern | JSON File | Database |
|---------|-----------|----------|
| **User-created data** | Awkward (file writes from web) | Natural (INSERT/UPDATE) |
| **Concurrent access** | File locks, corruption risk | ACID transactions |
| **Querying** | Parse entire file | SQL WHERE clauses |
| **Relationships** | Manual (cross-reference by name) | Foreign keys |
| **Schema evolution** | Manual JSON migration | EF Core migrations |
| **Multiple consumers** | File sharing/locking issues | Connection pooling |

## The Decision Matrix

```mermaid
flowchart TD
    Q1{"Does the service need<br/>this BEFORE connecting<br/>to the database?"}
    Q1 -->|Yes| JSON["Store in JSON file<br/>(appsettings.json)"]
    Q1 -->|No| Q2

    Q2{"Is this created/edited<br/>by users at runtime?"}
    Q2 -->|Yes| DB["Store in database<br/>(saved_filters, etc.)"]
    Q2 -->|No| Q3

    Q3{"Does this define<br/>import source structure<br/>and parsers?"}
    Q3 -->|Yes| HYBRID["Hybrid: JSON bootstrap<br/>→ migrate to database<br/>(import-config.json → import_sources)"]
    Q3 -->|No| Q4

    Q4{"Is this an operational<br/>tuning parameter?"}
    Q4 -->|Yes| JSON2["Store in JSON file<br/>(import-config.json General section)"]
    Q4 -->|No| DB2["Default: database"]

    style JSON fill:#fff3cd,stroke:#ffc107
    style DB fill:#d4edda,stroke:#28a745
    style HYBRID fill:#cce5ff,stroke:#004085
    style JSON2 fill:#fff3cd,stroke:#ffc107
    style DB2 fill:#d4edda,stroke:#28a745
```

## Concrete Examples

### Example 1: Database Connection String

**Stored in:** `appsettings.json`  
**Why:** The ImportService needs this to connect to PostgreSQL. It cannot read the connection string from PostgreSQL because it hasn't connected yet.

### Example 2: Import Source "ServerMonitor Logs"

**Stored in:** `import-config.json` initially, then migrated to `import_sources` table  
**Why:** On a fresh deployment, there is no database yet. The JSON file provides the initial seed data. Once the database is up and the migration runs, the database version becomes authoritative. The WebApi's Import Sources page then manages it going forward.

### Example 3: MessageExtractors (Regex Patterns)

**Stored in:** `import-config.json` → `Parser.MessageExtractors`, serialized into `import_sources.config_json` during migration  
**Why:** These are tightly coupled to the parser config for each source. They travel with the source definition — first in JSON, then in the database's `config_json` column.

### Example 4: Alert Rule "Detect 3+ Errors for Order 12345"

**Stored in:** `saved_filters` table (database only)  
**Why:** A user created this through the Saved Filters Maintenance page. It was never in a JSON file. It's runtime data managed through the UI.

### Example 5: BatchSize = 1000

**Stored in:** `import-config.json` → `General.BatchSize`  
**Why:** This is an operational tuning parameter. It's set once and rarely changed. It doesn't belong in the database because it's needed before the database connection is established and it's not user-facing data.

## Summary

The hybrid approach exists because the system must solve three conflicting requirements:

1. **Boot without a database** — JSON files provide everything needed to start, connect, and create the database schema from scratch
2. **Runtime management by users** — Alerts, saved filters, and import source CRUD need a proper database with transactions and a UI
3. **Resilience** — If the database goes down, the ImportService continues processing using the JSON fallback; it doesn't stop dead

The JSON file is the **seed** and **safety net**. The database is the **runtime authority**. The migration bridges them.
