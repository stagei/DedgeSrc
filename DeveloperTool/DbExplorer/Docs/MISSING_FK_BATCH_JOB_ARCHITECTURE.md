# Missing FK Discovery Batch Job Architecture

## Overview

The Missing FK Discovery batch job **reuses all components from the main client application**. It does NOT have its own database implementation. Instead, it launches a separate process of the same executable with CLI arguments.

## Architecture Diagram

```mermaid
graph TB
    subgraph "GUI Client Process"
        UI[MissingFKDiscoveryDialog]
        GEN[GenerateInputJsonAsync]
        META[MissingFKMetadataService]
        CONN1[IConnectionManager]
        DB1[(Database)]
        
        UI --> GEN
        GEN --> META
        META --> CONN1
        CONN1 --> DB1
    end
    
    subgraph "Batch Job Process (Separate)"
        CLI[CliCommandHandlerService]
        SCAN[MissingFKScanService]
        TRANS[MissingFKSqlTranslationService]
        IGNORE[MissingFKIgnoreService]
        STATUS[MissingFKJobStatusService]
        CONN2[IConnectionManager]
        DB2[(Database)]
        
        CLI --> SCAN
        SCAN --> TRANS
        SCAN --> IGNORE
        SCAN --> STATUS
        SCAN --> CONN2
        CONN2 --> DB2
    end
    
    subgraph "Shared Components"
        FACTORY[ConnectionManagerFactory]
        STORAGE[ConnectionStorageService]
        PROFILE[connections.json]
        JSON_IN[missing_fk_input.json]
        JSON_OUT[missing_fk_results.json]
        LOCK[.job_lock]
        LOG[job_*.log]
    end
    
    UI -->|"Process.Start()"| CLI
    GEN -->|writes| JSON_IN
    CLI -->|reads| JSON_IN
    SCAN -->|writes| JSON_OUT
    SCAN -->|writes| LOG
    STATUS -->|manages| LOCK
    FACTORY --> CONN1
    FACTORY --> CONN2
    STORAGE -->|loads| PROFILE
```

## Process Flow

```mermaid
sequenceDiagram
    participant User
    participant Dialog as MissingFKDiscoveryDialog
    participant Meta as MissingFKMetadataService
    participant DB as Database
    participant FS as File System
    participant Batch as Batch Process (CLI)
    participant Scan as MissingFKScanService
    
    User->>Dialog: Click "Start Batch Job"
    
    alt Input JSON not exists
        Dialog->>Dialog: GenerateInputJsonAsync()
        Dialog->>Meta: CollectTableMetadataAsync()
        Meta->>DB: Query SYSCAT.COLUMNS, etc.
        DB-->>Meta: Column metadata
        Meta-->>Dialog: Table metadata
        Dialog->>FS: Write missing_fk_input.json
    end
    
    Dialog->>FS: Create .job_lock
    Dialog->>Batch: Process.Start("DbExplorer.exe -command missing-fk-scan ...")
    
    Note over Batch: Separate process starts
    
    Batch->>FS: Read missing_fk_input.json
    Batch->>FS: Read connections.json (profile)
    Batch->>DB: Connect using saved profile
    
    loop For each table pair
        Scan->>DB: Extract sample data
        Scan->>Scan: Compare columns for FK matches
        Scan->>FS: Update job_status.json
        Scan->>FS: Append to job_*.log
    end
    
    Scan->>FS: Write missing_fk_results.json
    Batch->>FS: Release .job_lock
    
    Dialog->>FS: Poll job_status.json
    Dialog->>User: Show "Job completed"
```

## Component Reuse

### Shared Between GUI and Batch Job

| Component | Location | Purpose |
|-----------|----------|---------|
| `IConnectionManager` | `Data/IConnectionManager.cs` | Database connection interface |
| `ConnectionManagerFactory` | `Data/ConnectionManagerFactory.cs` | Creates provider-specific connections |
| `DB2ConnectionManager` | `Data/Providers/DB2/` | DB2-specific connection implementation |
| `ConnectionStorageService` | `Services/` | Loads saved connection profiles |
| `MissingFKSqlTranslationService` | `Services/` | Translates SQL for provider |
| `MetadataHandler` | `Services/` | Loads SQL from JSON config files |

### Batch-Job Specific

| Component | Location | Purpose |
|-----------|----------|---------|
| `MissingFKScanService` | `Services/` | Main batch job logic |
| `MissingFKIgnoreService` | `Services/` | Applies ignore rules |
| `MissingFKJobStatusService` | `Services/` | Manages job lock and status files |
| `CliCommandHandlerService` | `Services/` | CLI command routing |

## How It Works

### 1. GUI Prepares the Job

```csharp
// MissingFKDiscoveryDialog.xaml.cs
private async Task<(bool, string?)> GenerateInputJsonAsync()
{
    // Uses SAME IConnectionManager as GUI
    var tablesMetadata = await _metadataService.CollectTableMetadataAsync(tableRefs);
    
    // Writes input JSON for batch process
    await File.WriteAllTextAsync(inputPath, json);
}
```

### 2. GUI Launches Batch Process

```csharp
// MissingFKDiscoveryDialog.xaml.cs - StartBatchJob_Click
var exePath = Assembly.GetExecutingAssembly().Location; // Same executable!

var args = new List<string>
{
    "-profile", _connectionProfile,        // Use saved connection
    "-command", "missing-fk-scan",         // CLI command
    "-input", inputPath,                   // Input JSON path
    "-out", _outputFolder                  // Output folder
};

Process.Start(new ProcessStartInfo
{
    FileName = exePath,
    Arguments = string.Join(" ", args),
    CreateNoWindow = true
});
```

### 3. Batch Process Executes

```csharp
// CliCommandHandlerService.cs
case "missing-fk-scan":
    // Load input JSON
    var inputModel = JsonSerializer.Deserialize<MissingFKInputModel>(inputJson);
    
    // Create SAME services used by GUI
    var scanService = new MissingFKScanService(
        sqlTranslationService,    // Same as GUI uses
        ignoreService,
        jobStatusService,
        connectionManager,        // Same IConnectionManager interface
        outputFolder,
        inputModel.JobId,
        inputModel
    );
    
    // Execute scan
    var results = await scanService.ExecuteAsync();
```

### 4. Database Access

The batch job creates its own `IConnectionManager` using the same factory:

```csharp
// ConnectionStorageService loads the profile
var profile = connectionStorage.GetConnectionByName(profileName);

// ConnectionManagerFactory creates the connection
var connectionManager = ConnectionManagerFactory.CreateConnectionManager(profile);

// Same DB2ConnectionManager as GUI!
await connectionManager.ConnectAsync();
```

## File Communication (PID-Based Tracking)

```mermaid
graph LR
    subgraph "Input Files"
        IN1[missing_fk_input.json]
        IN2[missing_fk_ignore.json]
    end
    
    subgraph "Status File (MissingFK/)"
        PID[running_job.json]
    end
    
    subgraph "Output Files (Projects/...)"
        OUT1[missing_fk_results.json]
        LOG[job_*.log]
    end
    
    GUI -->|"writes (auto-generated)"| IN1
    GUI -->|writes| IN2
    GUI -->|"saves PID"| PID
    
    BATCH -->|reads| IN1
    BATCH -->|reads| IN2
    BATCH -->|writes| OUT1
    BATCH -->|writes| LOG
    
    GUI -->|"Process.Exited event"| PID
    GUI -->|reads| LOG
```

### How PID Tracking Works

1. **On Start Job**: Client saves `running_job.json` with `{ProcessId, JobId, ProjectFolder, StartedAtUtc}`
2. **On Dialog Open**: Client reads `running_job.json`, checks if PID exists using `Process.GetProcessById()`
3. **If Process Running**: Attach to `Process.Exited` event for immediate notification
4. **On Process Exit**: Event fires immediately, client clears `running_job.json` and re-enables Start button
5. **Cleanup**: Old status files are automatically cleaned up on dialog open

## Why This Architecture?

### Benefits

1. **Code Reuse**: No duplicate database code - same `DB2ConnectionManager` handles all queries
2. **Provider Agnostic**: When PostgreSQL support is added, batch job works automatically
3. **Maintainability**: Fix a bug once, it's fixed for both GUI and batch
4. **Testability**: CLI can be tested independently
5. **Long-Running Jobs**: Batch process can run while GUI closes

### Trade-offs

1. **Process Overhead**: Starts new process (but acceptable for long jobs)
2. **File-Based IPC**: Uses JSON files instead of in-memory communication
3. **Profile Dependency**: Must have saved connection profile

## SQL Provider Abstraction

The batch job uses the same SQL translation system via `MetadataHandler`:

```mermaid
graph TB
    SCAN[MissingFKScanService]
    TRANS[MissingFKSqlTranslationService]
    META[MetadataHandler]
    
    subgraph "JSON Config Files"
        DB2[db2_12.1_sql_statements.json]
        ANSI[missing_fk_sql_statements.json]
    end
    
    SCAN -->|"GetTranslatedStatementAsync()"| TRANS
    TRANS -->|"provider=DB2"| META
    META -->|"GetStatement()"| DB2
    TRANS -->|"provider=other"| ANSI
    
    DB2 -->|"SYSCAT.COLUMNS"| SYSCAT[DB2 System Catalog]
    ANSI -->|"INFORMATION_SCHEMA"| INFO[ANSI Standard]
```

### Key SQL Statements (in `db2_12.1_sql_statements.json`)

| Statement Name | Purpose |
|----------------|---------|
| `GetTableColumnsForMissingFK` | Get column metadata for FK candidate matching |
| `GetTablePrimaryKey` | Get primary key columns |
| `GetTableUniqueKeys` | Get unique constraint columns |
| `GetTableForeignKeysForMissingFK` | Get existing FK relationships |
| `GetTableRowCount` | Get table row count |
| `GetTableDataForExport` | Sample data for FK value matching |

## Summary

**The batch job is NOT a separate implementation.** It is:

- The same `DbExplorer.exe` executable
- Running with CLI arguments (`-command missing-fk-scan`)
- Using the same `IConnectionManager`, `DB2ConnectionManager`, and all services
- Communicating via JSON files (input, status, results)
- Managed by lock files to prevent concurrent jobs

This ensures 100% code reuse and consistency between GUI and batch operations.
