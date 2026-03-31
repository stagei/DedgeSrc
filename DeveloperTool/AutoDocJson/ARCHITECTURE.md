# AutoDocJson C# Architecture

## Overview

AutoDocJson is a C# port of the legacy PowerShell-based AutoDoc documentation generation system. It parses legacy source code files (COBOL, REXX, BAT, PS1, SQL, C#) and generates interactive HTML documentation with Mermaid diagrams.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AutoDocJson Solution                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │
│  │   AutoDocJson    │    │ AutoDocJson.Core │    │   AutoDocJson.Parsers    │  │
│  │   (Console)     │───▶│   (Library)     │◀───│      (Library)          │  │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘  │
│          │                      │                         │                 │
│          │              ┌───────┴───────┐                 │                 │
│          │              ▼               ▼                 ▼                 │
│          │     ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
│          │     │   Logger    │  │ BatchRunner │  │   File Parsers      │   │
│          │     │   (NLog)    │  │             │  │ CBL/REX/BAT/PS1/SQL │   │
│          │     └─────────────┘  └─────────────┘  └─────────────────────┘   │
│          │                                                                  │
│          ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      AutoDocJson.Tests                                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐ │   │
│  │  │Comparative   │  │  Browser     │  │     HTML Comparer          │ │   │
│  │  │   Tester     │  │   Tester     │  │                            │ │   │
│  │  └──────────────┘  └──────────────┘  └────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      AutoDocJson.Models                               │   │
│  │                    (Shared Data Models)                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
AutoDocJson/
├── AutoDocJson/                    # Main console application
│   ├── Program.cs                 # Entry point (wires all components)
│   ├── SingleFileParserImpl.cs    # Dispatches to correct parser by file type
│   ├── CSharpProjectRunnerImpl.cs # C# solution/ecosystem parse implementation
│   ├── GsFileRunnerImpl.cs        # GS screenset parse implementation
│   ├── KillProcessHandler.cs      # Process management
│   └── appsettings.json           # Configuration
│
├── AutoDocJson.Core/               # Core library
│   ├── Logger.cs                  # NLog-based logging (unified with PowerShell)
│   ├── BatchRunner.cs             # Main orchestration logic (full PS flow)
│   ├── CommandLineOptions.cs      # CLI argument parsing
│   ├── RegenerationDecider.cs     # Decides if file/table needs regeneration
│   ├── LastBatchRunState.cs        # Manages LastBatchRunStart.json + BatchRunnerStarted.json PID lock
│   ├── GitChangeDetector.cs       # Per-repo git log --since change detection
│   ├── WorklistManager.cs         # File-based worklist creation and processing
│   ├── WorkItem.cs                # Unified work queue item model
│   ├── WorkQueueBuilder.cs        # Builds work queue with regen checks
│   ├── JsonIndexService.cs        # Creates _json index files for web UI
│   ├── CobdokExportService.cs     # DB2 metadata export to CSV
│   ├── RepoSyncService.cs         # Azure DevOps git clone/pull
│   ├── ContentZipHelper.cs        # Zip output / unzip on test server
│   ├── SqlInteractionsScanner.cs  # Scans HTML for SQL table references
│   ├── ISingleFileParser.cs       # Interface for single-file dispatch
│   ├── ICSharpProjectRunner.cs    # Interface for C# solution/ecosystem parse
│   ├── IGsFileRunner.cs           # Interface for GS screenset parse
│   ├── ParserBase.cs              # Shared parser functionality
│   ├── ConfigurationManager.cs    # Settings management
│   ├── PathHelper.cs              # Path utilities
│   ├── SmsService.cs              # SMS notification integration
│   └── appsettings.json           # Logging configuration
│
├── AutoDocJson.Parsers/            # Parser implementations
│   ├── ParserBase.cs              # Abstract base parser
│   ├── MermaidWriter.cs           # Thread-safe Mermaid diagram content builder
│   ├── SqlParseHelper.cs          # Shared SQL detection/extraction logic
│   ├── ExecutionPathHelper.cs     # Shared execution path discovery and SVG generation
│   ├── CblParser.cs               # COBOL parser (3601+ files, 2500+ lines)
│   ├── RexParser.cs               # REXX parser (346 files)
│   ├── BatParser.cs               # Batch file parser (249 files)
│   ├── Ps1Parser.cs               # PowerShell parser (518 files, also .psm1, 2800+ lines)
│   ├── SqlParser.cs               # SQL table documentation parser (1600+ lines)
│   ├── CSharpParser.cs            # C# solution/ecosystem parser (2700+ lines, 30+ functions)
│   └── GsParser.cs                # Dialog System screenset parser (.gs/.imp)
│
├── AutoDocJson.Models/             # Data models
│   └── GlobalSettings.cs          # Configuration models
│
├── AutoDocJson.Tests/              # Test and comparison tools
│   ├── ComparativeTester.cs       # PS vs C# output comparison
│   ├── BrowserTester.cs           # Selenium-based HTML testing
│   ├── HtmlComparer.cs            # HTML diff comparison
│   ├── ComparisonReport.cs        # Test report generation
│   ├── TestRunner.cs              # Generic test runner
│   ├── TestAllCbl.cs              # CBL batch testing
│   ├── TestAllRex.cs              # REX batch testing
│   ├── TestAllBat.cs              # BAT batch testing
│   ├── TestAllPs1.cs              # PS1 batch testing
│   ├── TestAllSql.cs              # SQL batch testing
│   ├── OvernightRunner.ps1        # Overnight automation
│   └── OvernightMonitor.ps1       # SMS monitoring
│
├── ARCHITECTURE.md                # This file
└── POWERSHELL_ORIGINS.md          # Mapping of C# components to PowerShell sources
```

## Component Details

### 1. AutoDocJson (Console Application)

The main entry point that:
- Parses command-line arguments
- Initializes the logger
- Kills conflicting AutoDoc processes
- Runs the BatchRunner

```csharp
// Program.cs - Simplified flow
static int Main(string[] args)
{
    var options = CommandLineParser.Parse(args);
    Logger.ResetLogLevel();
    KillProcessHandler.KillOtherAutoDocProcesses();
    return new BatchRunner(options).Run();
}
```

### 2. AutoDocJson.Core (Core Library)

#### Logger (NLog Integration)
- Uses NLog for robust, configurable logging
- Writes to both application log and global PowerShell log (`FkLog_yyyyMMdd.log`)
- Configuration via `appsettings.json`
- Matches PowerShell log format for unified log analysis

```csharp
// Log format matches PowerShell Write-LogMessage
// timestamp|machine|level|origin|pid|class|method|line|user|message
Logger.LogMessage("Processing file", LogLevel.INFO);
```

#### BatchRunner
- Main orchestration logic (full translation of `AutoDocBatchRunner.ps1` lines 2057-3203)
- Complete flow: Clean → Static assets → Unzip → Repo sync → Cobdok export → Last exec date
  → Single file → Build work queue (with regen checks) → Parallel/Sequential parse
  → CSharp projects → GS screensets → SQL interactions scan → JSON indexes → Zip → Error list → SMS
- Supports all regeneration modes: Incremental, All, Errors, JsonOnly, Single, Clean
- Uses `Parallel.ForEach` for multi-threaded processing with configurable thread count
- Dispatches work items via ISingleFileParser, ICSharpProjectRunner, IGsFileRunner interfaces

#### ParserBase
- Shared functionality for all parsers
- Template loading and CSS injection
- Usage finding across source files
- Path resolution

### 3. AutoDocJson.Parsers (Parser Library)

Each parser follows the same pattern:
1. Read source file (with encoding handling)
2. Pre-process content (remove comments, normalize)
3. Generate Mermaid diagrams (flow + sequence)
4. Load metadata from cobdok CSV files
5. Apply HTML template
6. Write output HTML

#### Shared Parser Utilities

| Utility | Description |
|---------|-------------|
| `MermaidWriter` | Thread-safe builder for Mermaid diagram content (flow + sequence), replaces script-level variables |
| `SqlParseHelper` | Detects and extracts SQL statements (SELECT/INSERT/UPDATE/DELETE/EXEC) from source code of any type |
| `ExecutionPathHelper` | Finds linked scripts/programs, builds execution-path Mermaid diagrams, generates SVG via mmdc |

#### Supported File Types

| Parser | File Type | Typical Count | C# Lines | Key Functions |
|--------|-----------|---------------|-----------|---------------|
| CblParser | *.CBL | 3,601 | ~2,500 | StartCblParse, NewCblNodes, GenerateSqlNodes, WriteMmdFlow/Sequence, FindParagraphCode |
| RexParser | *.REX | 346 | ~800 | StartRexParse, NewRexNodes, variable resolution, metadata |
| BatParser | *.BAT | 249 | ~700 | StartBatParse, NewBatNodes, variable resolution, process diagram |
| Ps1Parser | *.PS1/PSM1 | 518 | ~2,800 | StartPs1Parse, NewPs1Nodes, BuildModuleIndex, FindPs1FunctionCode |
| SqlParser | SQL Tables | Variable | ~1,600 | StartSqlParse, metadata loading, ER diagrams, interaction diagrams |
| CSharpParser | *.sln/*.cs | Variable | ~2,700 | StartCSharpParse, StartCSharpEcosystemParse, 30+ helper functions |
| GsParser | *.gs/*.imp | Variable | ~400 | StartGsParse, screenset parsing |

### 4. AutoDocJson.Tests (Testing Framework)

#### ComparativeTester
Runs both PowerShell and C# parsers on the same files, comparing outputs:
- Executes PowerShell `AutoDocBatchRunner.ps1`
- Executes C# parsers
- Compares HTML output using `HtmlComparer`
- Generates comparison report

#### BrowserTester
Selenium-based testing for generated HTML:
- Validates page structure
- Checks Mermaid diagram rendering
- Verifies navigation links
- Tests JavaScript functionality

### 5. AutoDocJson.Models (Shared Models)

Data structures used across projects:
- Configuration settings
- Parser results
- Report data

## Data Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            INPUT SOURCES                                  │
├────────────────┬───────────────┬────────────────┬───────────────────────┤
│ Azure DevOps   │ cobdok DB     │ Scheduled      │ Source Files          │
│ Repositories   │ (DB2 exports) │ Tasks XML      │ (CBL/REX/BAT/PS1)     │
└───────┬────────┴───────┬───────┴────────┬───────┴───────────┬───────────┘
        │                │                │                   │
        ▼                ▼                ▼                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         BATCH RUNNER                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ Clone/Sync  │  │ Export CSV  │  │ Collect     │  │ Initialize      │  │
│  │ Repos       │─▶│ from cobdok │─▶│ Source Files│─▶│ Thread Workers  │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                      PARALLEL PROCESSING                                  │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Unified Work Queue                             │   │
│  │  Non-CBL first (REX → BAT → PS1 → SQL) then CBL (largest)        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│       │              │              │              │                     │
│       ▼              ▼              ▼              ▼                     │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐               │
│  │Thread 0 │    │Thread 1 │    │Thread 2 │    │Thread N │               │
│  │(Worker) │    │(Worker) │    │(Worker) │    │(Worker) │               │
│  └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘               │
│       │              │              │              │                     │
│       └──────────────┴──────────────┴──────────────┘                     │
│                              │                                           │
└──────────────────────────────┼───────────────────────────────────────────┘
                               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                          OUTPUT GENERATION                                │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────────────┐ │
│  │ HTML Files    │  │ MMD Files     │  │ SVG Diagrams                  │ │
│  │ (*.html)      │  │ (*.flow.mmd)  │  │ (via mmdc CLI)                │ │
│  │               │  │ (*.seq.mmd)   │  │                               │ │
│  └───────────────┘  └───────────────┘  └───────────────────────────────┘ │
│                              │                                           │
│                              ▼                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                 C:\opt\Webs\AutoDocJson\                           │   │
│  │  ├── _css/              (Shared stylesheets)                      │   │
│  │  ├── _js/               (JavaScript for diagrams)                 │   │
│  │  ├── _images/           (Icons and logos)                         │   │
│  │  ├── _templates/        (HTML templates)                          │   │
│  │  ├── _json/             (Index/search data)                       │   │
│  │  ├── *.html             (Generated documentation)                 │   │
│  │  └── *.mmd              (Mermaid source files)                    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

## Configuration

### appsettings.json

```json
{
  "Logging": {
    "LogPath": "C:\\opt\\data\\AutoDocJson",
    "GlobalLogPath": "C:\\opt\\data\\AllPwshLog",
    "LogLevel": "Trace",
    "ArchiveDays": 30
  }
}
```

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-Regenerate` | None, All, Clean | None |
| `-OutputFolder` | HTML output path | `C:\opt\Webs\AutoDocJson` |
| `-Parallel` | Enable parallel processing | true |
| `-ThreadPercentage` | CPU thread usage | 75% |
| `-MaxFilesPerType` | Limit files processed | 0 (all) |

## Logging Integration

The C# Logger is designed to write logs in the same format as PowerShell's `Write-LogMessage`:

```
2026-02-05 23:30:00|MACHINE|INFO|CSharp|12345|CblParser|StartCblParse|87|USER|Message
```

This enables:
- Unified log analysis across PowerShell and C#
- Monitoring via `OvernightRunner.ps1`
- SMS notifications via `GlobalFunctions.Send-Sms`

## Testing Strategy

### Comparative Testing
1. Run PowerShell parser on file → Output to `C:\opt\Webs\AutoDoc\`
2. Run C# parser on same file → Output to `C:\opt\Webs\AutoDocJson\`
3. Compare HTML outputs using Levenshtein distance
4. Report differences

### Overnight Automation
- `OvernightRunner.ps1` - Main automation script
- Monitors logs for errors
- Auto-fixes common issues
- Restarts on failures
- Sends SMS updates every 30 minutes
- Validates 5% of generated HTML files

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| NLog | 5.4.0 | Logging framework |
| NLog.Extensions.Logging | 5.4.0 | .NET Core integration |
| Microsoft.Extensions.Configuration | 9.0.1 | Settings management |
| Microsoft.Extensions.Configuration.Json | 9.0.1 | JSON config files |
| Newtonsoft.Json | 13.0.4 | JSON serialization |
| System.Management | 10.0.2 | Process management |

## Key Differences from PowerShell Version

| Aspect | PowerShell | C# |
|--------|------------|-----|
| Execution | Interpreted | Compiled |
| Performance | Slower | Faster (10-50x) |
| Memory | Higher per file | More efficient |
| Threading | `ForEach-Object -Parallel` | `Parallel.ForEach` |
| Output Folder | `C:\opt\Webs\AutoDoc` | `C:\opt\Webs\AutoDocJson` |
| Logging | `Write-LogMessage` | `Logger.LogMessage` (NLog) |
| RAM Disk | Supported (`-UseRamDisk`) | Not implemented (param accepted but ignored) |

## Parser Implementation Status (Feb 2026)

All parsers have been fully translated from PowerShell (`AutoDocFunctions.psm1`) to C# line-by-line:

| Parser | Status | PS Functions Translated |
|--------|--------|------------------------|
| BatParser | Complete | Start-BatParse, New-BatNodes, Get-BatMetaData, Get-BatExecutionPathDiagram |
| RexParser | Complete | Start-RexParse, New-RexNodes, Get-RexMetaData, Get-RexExecutionPathDiagram |
| Ps1Parser | Complete | Start-Ps1Parse, New-Ps1Nodes, Build-ModuleIndex, Find-Ps1FunctionCode, Get-ModuleFunctions, 15+ helpers |
| CblParser | Complete | Start-CblParse, New-CblNodes, GenerateSqlNodes, WriteMmdFlow/Sequence, FindParagraphCode, FindAllFileDefinitions, 20+ helpers |
| SqlParser | Complete | Start-SqlParse, Get-SqlIndexMetadata, Get-SqlConstraintMetadata, New-SqlErDiagram, New-SqlInteractionDiagram, 15+ helpers |
| CSharpParser | Complete | Start-CSharpParse, Start-CSharpEcosystemParse, ReadCSharpFile, NewClassDiagram, NewEcosystemDiagram, 30+ helpers |
| GsParser | Complete | Start-GsParse, screenset parsing |

## Future Enhancements

1. **Web API** - REST endpoints for on-demand documentation
2. **Docker Support** - Containerized execution
3. **Incremental Diagram Updates** - Only regenerate changed diagrams

## See Also

- [POWERSHELL_ORIGINS.md](POWERSHELL_ORIGINS.md) - Complete mapping of C# components to their original PowerShell source files
