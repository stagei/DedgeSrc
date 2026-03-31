# SqlMermaidErdTools - Complete Architecture

## 📐 Project Overview

The SqlMermaidErdTools solution consists of **4 main projects** that work together:

```
SqlMermaidErdTools/
├── src/SqlMermaidErdTools/          # Core C# Library (NuGet Package)
├── srcCLI/                          # CLI Tool (Global .NET Tool)
├── srcVSC/                          # VS Code Extension (Basic)
└── srcVSCADV/                       # VS Code Extension (Advanced)
```

---

## 🏗️ Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER INTERFACES                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │  CLI Tool    │  │  VS Code     │  │  VS Code Advanced      │   │
│  │  (srcCLI)    │  │  (srcVSC)    │  │  (srcVSCADV)           │   │
│  │              │  │              │  │                        │   │
│  │  Commands:   │  │  Commands:   │  │  Split-View Editor:    │   │
│  │  sql-to-mmd  │  │  Convert     │  │  • Left: SQL/Mermaid   │   │
│  │  mmd-to-sql  │  │  Preview     │  │  • Right: Output       │   │
│  │  diff        │  │  etc.        │  │  • Live Preview        │   │
│  │  license     │  │              │  │  • Auto-convert        │   │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬────────────┘   │
│         │                 │                       │                │
│         │                 └───────────┬───────────┘                │
│         │                             │                            │
│         │                  Calls CLI via child_process.execSync()  │
│         │                             │                            │
└─────────┼─────────────────────────────┼────────────────────────────┘
          │                             │
          ▼                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CLI LAYER (.NET Global Tool)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  SqlMermaidErdTools.CLI (srcCLI)                             │  │
│  │                                                              │  │
│  │  • Commands: SqlToMmdCommand, MmdToSqlCommand, DiffCommand   │  │
│  │  • License: LicenseService (validation, activation)          │  │
│  │  • References: SqlMermaidErdTools.dll                        │  │
│  └──────────────────────────────┬───────────────────────────────┘  │
│                                 │                                  │
└─────────────────────────────────┼──────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CORE LIBRARY (.NET Library)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  SqlMermaidErdTools (src/SqlMermaidErdTools)                 │  │
│  │                                                              │  │
│  │  Converters:                                                 │  │
│  │    • SqlToMmdConverter - SQL → Mermaid                       │  │
│  │    • MmdToSqlConverter - Mermaid → SQL                       │  │
│  │    • MmdDiffToSqlGenerator - Mermaid diff → SQL migration    │  │
│  │    • SqlDialectTranslator - SQL dialect conversion           │  │
│  │                                                              │  │
│  │  Runtime:                                                    │  │
│  │    • RuntimeManager - Manages Python runtime paths           │  │
│  │    • PythonScriptExecutor - Executes Python scripts          │  │
│  │                                                              │  │
│  │  Models:                                                     │  │
│  │    • SqlDialect enum (AnsiSql, SqlServer, PostgreSql, MySql) │  │
│  │                                                              │  │
│  └──────────────────────────────┬───────────────────────────────┘  │
│                                 │                                  │
└─────────────────────────────────┼──────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PYTHON SCRIPTS LAYER                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Python Scripts (src/SqlMermaidErdTools/scripts/)            │  │
│  │                                                              │  │
│  │  • sql_to_mmd.py - Parse SQL with SQLGlot, generate Mermaid │  │
│  │  • mmd_to_sql.py - Parse Mermaid, generate SQL              │  │
│  │  • mmd_diff_to_sql.py - Compare Mermaid, generate ALTER     │  │
│  │  • sql_dialect_translator.py - Translate SQL dialects       │  │
│  │                                                              │  │
│  │  Uses:                                                       │  │
│  │    • SQLGlot library (31+ SQL dialects)                      │  │
│  │    • JSON for data exchange with C#                          │  │
│  │                                                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Data Flow Examples

### Example 1: User Types SQL in VS Code Advanced Editor

```
1. User types SQL in left panel
         ↓
2. TypeScript debounces input (500ms)
         ↓
3. JavaScript sends message to Extension Host
         ↓
4. Extension Host receives message
         ↓
5. ConversionService.sqlToMermaid() called
         ↓
6. Executes: sqlmermaid sql-to-mmd temp.sql -o temp.mmd
         ↓
7. CLI Tool (SqlMermaidErdTools.CLI)
    ├─ Validates license (max tables check)
    ├─ Calls SqlToMmdConverter.ConvertAsync()
    └─ Returns Mermaid code
         ↓
8. SqlToMmdConverter
    ├─ Calls Python script: sql_to_mmd.py
    ├─ Python uses SQLGlot to parse SQL
    ├─ Python generates Mermaid syntax
    └─ Returns Mermaid string to C#
         ↓
9. CLI outputs Mermaid to temp.mmd
         ↓
10. Extension reads temp.mmd file
         ↓
11. Extension sends result back to Webview
         ↓
12. Webview updates:
    ├─ Right panel (Mermaid code)
    └─ Preview panel (Mermaid.js renders diagram)
```

---

### Example 2: User Runs CLI Command Directly

```
User executes: sqlmermaid sql-to-mmd schema.sql -o schema.mmd
         ↓
1. Program.cs Main() entry point
         ↓
2. System.CommandLine parses arguments
         ↓
3. SqlToMmdCommand.SetHandler() invoked
         ↓
4. LicenseService.ValidateOperation()
    ├─ Reads ~/.sqlmermaid-license
    ├─ Checks table count limit
    └─ Returns validation result
         ↓
5. If validation fails:
    ├─ Print error message
    ├─ Print upgrade message (if Free tier)
    └─ Exit with code 2
         ↓
6. If validation passes:
    ├─ Read SQL from schema.sql
    ├─ Call SqlToMmdConverter.ConvertAsync()
    ├─ Converter calls Python script
    ├─ Python returns Mermaid
    └─ Write to schema.mmd
         ↓
7. Print success message with stats
         ↓
8. Exit with code 0
```

---

## 🧩 Component Relationships

### Core Library (src/SqlMermaidErdTools)

**Purpose**: Reusable conversion logic

**Consumers**:
- ✅ CLI Tool (srcCLI)
- ✅ Future: Web API
- ✅ Future: Desktop applications

**Key Classes**:
```csharp
// Converters
SqlToMmdConverter
MmdToSqlConverter
MmdDiffToSqlGenerator
SqlDialectTranslator

// Runtime
RuntimeManager (Python path detection)
PythonScriptExecutor (Process execution)

// Models
SqlDialect enum
```

**Dependencies**:
- Python runtime (bundled)
- SQLGlot library (bundled)
- Python scripts (bundled)

---

### CLI Tool (srcCLI)

**Purpose**: Command-line interface with license validation

**References**: `SqlMermaidErdTools` project

**Key Features**:
- ✅ System.CommandLine for CLI parsing
- ✅ License validation (table limits, expiry)
- ✅ User-friendly error messages
- ✅ Multiple commands (sql-to-mmd, mmd-to-sql, diff, license)
- ✅ Exit codes (0=success, 1=error, 2=license)

**Packaged as**: .NET Global Tool

**Installation**:
```bash
dotnet tool install -g SqlMermaidErdTools.CLI
```

---

### VS Code Extension - Basic (srcVSC)

**Purpose**: Simple command-based conversions in VS Code

**Language**: TypeScript

**Features**:
- Right-click context menu
- Command palette commands
- Separate preview panel
- File-based conversions

**Uses CLI**: Yes, via `child_process.execSync()`

**Fallback**: API endpoint (if configured)

---

### VS Code Extension - Advanced (srcVSCADV)

**Purpose**: Professional split-view editor

**Language**: TypeScript

**Features**:
- Custom TextEditor provider
- Split-view layout
- Live Mermaid preview
- Auto-convert on typing
- Mode toggle (SQL ↔ Mermaid)
- Dialect selector

**Uses CLI**: Yes, via `child_process.execSync()`

**Architecture**:
```
Extension Host (Node.js)
    ↓
SplitEditorProvider
    ↓
Webview (Chromium)
    ├─ HTML + JavaScript (split UI)
    ├─ Mermaid.js (diagram rendering)
    └─ CSS (VS Code theming)
```

---

## 📦 Package Dependencies

### Core Library (NuGet Package)

```xml
<ProjectReference>
  None - self-contained with bundled Python
</ProjectReference>

Bundled:
  - Python 3.x runtime
  - SQLGlot library
  - Python conversion scripts
```

### CLI Tool (NuGet Tool)

```xml
<ProjectReference>
  src/SqlMermaidErdTools/SqlMermaidErdTools.csproj
</ProjectReference>

<PackageReference>
  System.CommandLine (v2.0.0-beta4)
</PackageReference>
```

### VS Code Extensions (npm packages)

```json
{
  "dependencies": {
    "axios": "^1.6.2"  // For API calls (fallback)
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "@types/vscode": "^1.85.0",
    "typescript": "^5.3.2"
  }
}
```

---

## 🔐 License Validation Flow

```
User runs conversion command
         ↓
CLI Command Handler
         ↓
┌─────────────────────────────────────┐
│  LicenseService.ValidateOperation() │
│                                     │
│  1. Read license file               │
│     ~/.sqlmermaid-license           │
│                                     │
│  2. Parse JSON                      │
│     {                               │
│       "Tier": "Pro",                │
│       "MaxTables": null,            │
│       "ExpiryDate": "2025-12-31"    │
│     }                               │
│                                     │
│  3. Check expiry                    │
│     if (ExpiryDate < Now)           │
│       → FAIL                        │
│                                     │
│  4. Check table limit               │
│     if (MaxTables && count > max)   │
│       → FAIL                        │
│                                     │
│  5. Return ValidationResult         │
│     { IsValid, Message, Tier }      │
└─────────────────────────────────────┘
         ↓
If IsValid:
  → Proceed with conversion
  → Print success with stats

If NOT IsValid:
  → Print error message
  → Print upgrade message (Free tier)
  → Exit with code 2
```

---

## 🚀 Deployment Scenarios

### Scenario 1: NuGet Package Only

```
User:
  dotnet add package SqlMermaidErdTools

Code:
  var converter = new SqlToMmdConverter();
  var mermaid = await converter.ConvertAsync(sql);

Result:
  ✅ Works - uses bundled Python
```

### Scenario 2: CLI Tool Only

```
User:
  dotnet tool install -g SqlMermaidErdTools.CLI

Command:
  sqlmermaid sql-to-mmd schema.sql -o schema.mmd

Result:
  ✅ Works - CLI references NuGet package
```

### Scenario 3: VS Code Extension + CLI

```
User:
  1. Install CLI: dotnet tool install -g SqlMermaidErdTools.CLI
  2. Install Extension: code --install-extension sqlmermaid-erd-tools-advanced

Usage:
  Open .sql file → Split Editor → Auto-converts using CLI

Result:
  ✅ Works - Extension calls CLI, CLI uses NuGet package
```

### Scenario 4: VS Code Extension + API (No CLI)

```
User:
  1. Install Extension only
  2. Configure API endpoint in settings

Usage:
  Extension sends HTTP requests to cloud API

Result:
  ✅ Works - No local installation needed
```

---

## 📊 Technology Stack Summary

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Core Library** | C# .NET 10 | Conversion orchestration |
| **Python Scripts** | Python 3 + SQLGlot | SQL parsing & generation |
| **CLI Tool** | C# + System.CommandLine | Command-line interface |
| **VS Code Basic** | TypeScript + VS Code API | Simple commands |
| **VS Code Advanced** | TypeScript + Webview + Mermaid.js | Split-view editor |
| **License System** | JSON file + validation | Usage control |

---

## 🎯 Project Purposes

### Core Library (SqlMermaidErdTools)
- 🎯 **Reusable** conversion logic
- 🎯 **Bundled** runtime (no external dependencies)
- 🎯 **Multi-platform** (Windows, Linux, macOS)

### CLI Tool (SqlMermaidErdTools.CLI)
- 🎯 **Command-line** automation
- 🎯 **CI/CD** integration
- 🎯 **License** enforcement
- 🎯 **DevOps** workflows

### VS Code Basic (srcVSC)
- 🎯 **Simple** conversions
- 🎯 **Quick** usage
- 🎯 **Lightweight**

### VS Code Advanced (srcVSCADV)
- 🎯 **Professional** editor experience
- 🎯 **Live** preview
- 🎯 **Real-time** conversion
- 🎯 **Advanced** features

---

## 📚 Documentation Map

```
SqlMermaidErdTools/
├── README.md                               # Main project overview
├── ARCHITECTURE.md                         # This file
├── Docs/
│   ├── LICENSING_MONETIZATION_GUIDE.md    # License business model
│   ├── LICENSE_IMPLEMENTATION_QUICKSTART.md
│   ├── MARKET_ANALYSIS_AND_DISTRIBUTION_STRATEGY.md
│   └── THIRD-PARTY-LICENSES.md
├── srcCLI/
│   ├── README.md                          # CLI user guide
│   ├── CLI_IMPLEMENTATION_GUIDE.md        # CLI technical guide
│   └── GET_STARTED.md                     # CLI quick start
├── srcVSC/
│   ├── README.md                          # Basic extension guide
│   ├── QUICKSTART.md                      # Basic quick start
│   └── DEVELOPMENT.md                     # Development guide
└── srcVSCADV/
    ├── README.md                          # Advanced extension guide
    ├── QUICKSTART.md                      # Advanced quick start
    ├── VISUAL_GUIDE.md                    # UI documentation
    ├── IMPLEMENTATION_SUMMARY.md          # Technical summary
    └── GET_STARTED_NOW.md                 # 5-minute demo
```

---

## ✅ Summary

**4 Projects. 1 Ecosystem.**

1. **Core Library** (src/SqlMermaidErdTools) - The engine
2. **CLI Tool** (srcCLI) - Command-line interface with licensing
3. **VS Code Basic** (srcVSC) - Simple extension
4. **VS Code Advanced** (srcVSCADV) - Professional split-view editor

All working together to provide the best SQL ↔ Mermaid conversion experience! 🚀

---

Made with ❤️ for the database and documentation community

