# Backend Components for SqlMmdConverter

## Overview

This document outlines existing open-source libraries and tools that can be leveraged as backend components for the SqlMmdConverter NuGet package. Instead of building SQL parsing and conversion from scratch, we can utilize mature, well-tested libraries.

## Available SQL Conversion Libraries

### ✅ SQL Dialect Conversion Tools

| Name / Project | Description & Strengths | Language | License |
|---------------|------------------------|----------|---------|
| **SQLGlot** | Generic SQL parser and transpiler supporting 31+ dialects (DuckDB, Presto/Trino, Spark/Databricks, Snowflake, BigQuery, PostgreSQL, MySQL, SQL Server, etc.) | Python | MIT |
| **sql-translate** (pkit) | TypeScript/JS-based tool for translating between SQL dialects — can be used in browser or integrated into web apps | TypeScript/JavaScript | MIT |
| **dbt-sqlx** | CLI tool that converts SQL models (e.g., in dbt projects) between different dialects — useful for making model files portable across databases | Python | - |
| **SQLines** | Classic migration tool that converts not just SELECT/INSERT, but also DDL (schema), views, procedures, triggers, etc. — especially useful for migrations between systems like MS SQL ↔ MySQL | C++/CLI | Commercial & Free |
| **SQL‑Translator** (gahtan-syarif) | Simple GUI app based on SQLGlot — quick and easy for manual conversion without overhead | Python | - |

### ⚠️ Mermaid ERD → SQL DDL Conversion Tools (Very Limited Options)

| Name / Project | Description & Strengths | Supported Dialects | Platform | Status |
|---------------|------------------------|-------------------|----------|--------|
| **little-mermaid-2-the-sql** | Node/TypeScript-based CLI/library that parses Mermaid ER diagrams and generates CREATE TABLE scripts — can specify database type at runtime | PostgreSQL, MySQL, SQLite, MSSQL | Node.js/npm | ❌ **BROKEN** (v0.1.1 has ES module bug) |
| **Mermaid JS ERD to SQL** | VS Code extension that converts .md/.mmd files with Mermaid ER diagrams to SQL DDL — handles primary keys, foreign keys, and relationships | MySQL, PostgreSQL, SQLite | VS Code Extension | ⚠️ **Not Embeddable** (Extension only, no API) |

**⚠️ Research Finding (Nov 30, 2025):**  
After extensive web search and GitHub exploration, **only 2 tools exist** for Mermaid → SQL conversion. The Node.js library has a critical bug (ES module compatibility), and the VS Code extension cannot be embedded in applications. **No other viable alternatives were found.**

**See:** `MMD_TO_SQL_ALTERNATIVES_ANALYSIS.md` for complete research findings and recommendation.

### Links

**SQL Dialect Conversion:**
- [SQLGlot GitHub](https://github.com/tobymao/sqlglot)
- [sql-translate GitHub](https://github.com/pkit/sql-translate)
- [dbt-sqlx GitHub](https://github.com/NikhilSuthar/dbt-sqlx)
- [SQLines Website](https://www.sqlines.com/sql-server-to-mysql-tool)
- [SQL-Translator GitHub](https://github.com/gahtan-syarif/SQL-Translator)

**Mermaid → SQL Conversion:**
- [Mermaid JS ERD to SQL - VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=erralb.mermaid-js-erd-to-sql)
- [little-mermaid-2-the-sql - npm](https://www.npmjs.com/package/@funktechno/little-mermaid-2-the-sql)

## ⚠️ Important Limitations & Considerations

### Mermaid ERD → SQL Conversion Limitations

1. **Simplified Syntax**: Mermaid ERD syntax is designed for conceptual/logical modeling, not complete physical database schemas
   - Data types, constraints, and advanced database-specific features (triggers, indexes, special data types) often need manual completion
   - Mermaid diagrams must be "enriched" with sufficient metadata (column names, data types, key definitions) for accurate DDL generation

2. **Best Results with Simple Schemas**: Tools work best when ER diagrams are relatively straightforward
   - Tables, columns, primary keys (PK), foreign keys (FK) are well-supported
   - Complex database logic (views, stored procedures, migrations, DB-specific types) typically requires manual post-processing

3. **Limited Dialect Support**: Support is limited to explicitly implemented dialects
   - Typically: MySQL, PostgreSQL, SQLite
   - For exotic or proprietary dialects, manual output modification is required
   - May need custom templates or generators for specialized databases

4. **Metadata Completeness**: Generated SQL quality depends heavily on Mermaid diagram completeness
   - Missing data types default to generic types
   - Constraints must be explicitly defined in Mermaid
   - Relationship cardinality maps to FK constraints

## 🎯 Selection Criteria

### For SQL Dialect Conversion
- **SQLGlot** or **sql-translate**: Best for supporting many different databases (PostgreSQL, MySQL, BigQuery, Spark, etc.)
- **CLI-based tools** (dbt-sqlx, SQLines): Better for deployment pipelines or database backend switching
- **GUI apps** or **JS-based tools**: More flexible for manual conversion or ad-hoc use

### For Mermaid ↔ SQL Conversion
- **little-mermaid-2-the-sql**: Best for programmatic integration (Node.js/TypeScript library)
- **Mermaid JS ERD to SQL**: Best for VS Code users, quick prototyping
- **Custom C# parser**: Best for full control, no external dependencies, NuGet packaging

### SQL Type Support
- **Simple SELECT/INSERT/DML**: Most tools work well
- **Complex DDL, views, triggers, procedures**: SQLines (or similar comprehensive migration tools) are better

### Application Integration
- **SQLGlot**: Has API support, can be integrated directly into a Python application
- **sql-translate**: TypeScript/JavaScript — can be integrated into web frontend/backend
- **little-mermaid-2-the-sql**: Node.js library — can be called from .NET via process execution

## 💡 Integration Strategy for SqlMmdConverter (.NET 10 / C#)

Since our project is a .NET 10 C# NuGet package, we have several integration options:

### Option 1: Python Backend via Process Execution
- **Approach**: Use SQLGlot as a Python subprocess/service
- **Pros**: Most mature SQL parser, supports 31+ dialects, actively maintained
- **Cons**: Requires Python runtime, process overhead, deployment complexity
- **Implementation**: 
  - Package Python scripts with the NuGet package
  - Use `System.Diagnostics.Process` to call Python
  - Consider IronPython for in-process execution

### Option 2: JavaScript Backend via Node/Embedded V8
- **Approach**: Use sql-translate via Node.js or embedded JavaScript engine
- **Pros**: TypeScript-based, good for web scenarios
- **Cons**: Requires Node.js runtime or embedded JS engine
- **Implementation**:
  - Use ClearScript (V8) or Jint for JavaScript execution
  - Bundle sql-translate scripts

### Option 3: Port/Wrap Native Library
- **Approach**: Use SQLines or similar C/C++ based tools via P/Invoke or C++/CLI wrapper
- **Pros**: Native performance, no runtime dependencies
- **Cons**: May require licensing, complex interop
- **Implementation**:
  - Create C++/CLI wrapper library
  - P/Invoke to native DLL

### Option 4: Pure C# Parser (Custom or Existing)
- **Approach**: Use existing C# SQL parsing libraries
- **Pros**: No external dependencies, pure .NET
- **Cons**: May need to write significant parsing code
- **Implementation**:
  - Use Microsoft.SqlServer.TransactSql.ScriptDom for T-SQL
  - Use ANTLR4 with SQL grammars for multi-dialect support
  - Consider libraries like [SqlKata](https://sqlkata.com/) for query building

### Option 5: Leverage Existing Mermaid Tools via Node.js
- **Approach**: Use **little-mermaid-2-the-sql** as backend for Mermaid → SQL conversion
- **Pros**: 
  - Battle-tested Mermaid ERD parser
  - Multi-dialect support (PostgreSQL, MySQL, SQLite)
  - Active maintenance and community support
  - Can focus development effort on SQL → Mermaid direction
- **Cons**: 
  - Requires Node.js runtime
  - Process execution overhead
  - Limited to dialects supported by the library
- **Implementation**:
  - Bundle Node.js scripts with NuGet package
  - Use `System.Diagnostics.Process` to execute little-mermaid-2-the-sql
  - Parse output and enhance with custom templates for additional dialects
  - Use SQLGlot (Python) for dialect-to-dialect conversion if needed

### Option 6: Hybrid Approach (Recommended for Full Control)
- **SQL → Mermaid**: Pure C# using Microsoft ScriptDom or ANTLR4
  - Parse SQL DDL into internal model
  - Generate Mermaid ERD from model
  - No external dependencies needed for this direction
  
- **Mermaid → SQL**: Port/adapt little-mermaid-2-the-sql logic to C#
  - Study the TypeScript implementation
  - Mermaid ERD syntax is simpler than SQL
  - Write custom C# parser for `erDiagram` blocks using Sprache
  - Generate SQL from internal model using dialect-specific templates (Scriban)
  - Full control over output quality and dialect support

### Option 7: Dual-Backend Strategy (Recommended for Fast Delivery)
- **Phase 1 (MVP)**: Use existing tools via process execution
  - **SQL → Mermaid**: Use SQLGlot (Python) or write simple C# generator
  - **Mermaid → SQL**: Use little-mermaid-2-the-sql (Node.js)
  - **Dialect → Dialect**: Use SQLGlot (Python)
  - Quick time-to-market, proven tools
  
- **Phase 2 (Optimization)**: Gradually replace with pure C#
  - Port critical paths to C# based on usage patterns
  - Keep external tools as fallback options
  - Reduce dependencies over time
  - Maintain backward compatibility

## 🔧 Recommended C# Libraries for Implementation

### For SQL Parsing
| Library | Description | Use Case |
|---------|-------------|----------|
| **Microsoft.SqlServer.TransactSql.ScriptDom** | Official Microsoft SQL Parser for T-SQL | Parsing SQL Server DDL statements |
| **ANTLR4** with SQL grammars | Parser generator with ready-made SQL grammars | Multi-dialect SQL parsing |
| **Irony** | .NET Language Implementation Kit | Custom grammar-based parsing |
| **Sprache** | Monadic parser combinator library for C# | Lightweight custom parsers |

### For Code Generation
| Library | Description | Use Case |
|---------|-------------|----------|
| **T4 Templates** | Text Template Transformation Toolkit | Template-based SQL generation |
| **Scriban** | Fast, powerful, safe scripting language and engine for .NET | Template-based code generation |
| **StringBuilder** with fluent API | Custom builder pattern | Simple, controlled SQL generation |

## 📦 NuGet Package Installation & Prerequisites

### Automatic Prerequisite Download Strategy

The NuGet package must handle external dependencies (Python/Node.js) automatically during installation.

#### Option 1: Bundled Portable Runtimes (Recommended)
- **Approach**: Include portable/embeddable versions of Python and Node.js in the NuGet package
- **Pros**: 
  - No user intervention needed
  - Guaranteed version compatibility
  - Works offline
  - No system-wide installations
- **Cons**: 
  - Larger package size (~150-200MB)
  - Platform-specific packages needed (win-x64, linux-x64, osx-x64)
- **Implementation**:
  ```xml
  <PackageReference Include="SqlMmdConverter" Version="1.0.0" />
  <!-- Auto-restores with bundled Python/Node.js for your platform -->
  ```

#### Option 2: Install Script with Auto-Download
- **Approach**: NuGet install.ps1/install.sh scripts that download prerequisites
- **Implementation**:
  ```powershell
  # tools/install.ps1
  $pythonUrl = "https://www.python.org/ftp/python/3.11.0/python-3.11.0-embed-amd64.zip"
  $nodeUrl = "https://nodejs.org/dist/v18.17.0/node-v18.17.0-win-x64.zip"
  
  # Download and extract to package directory
  ```
- **Pros**: Smaller initial download
- **Cons**: Requires internet connection, installation complexity

#### Option 3: Detect Existing Installations
- **Approach**: Check for system Python/Node.js, download only if missing
- **Implementation**:
  ```csharp
  public static class DependencyManager
  {
      public static async Task EnsureDependenciesAsync()
      {
          if (!IsPythonInstalled())
              await DownloadPythonAsync();
          
          if (!IsNodeInstalled())
              await DownloadNodeAsync();
          
          await InstallPythonPackagesAsync(); // pip install sqlglot
          await InstallNodePackagesAsync(); // npm install @funktechno/little-mermaid-2-the-sql
      }
  }
  ```

#### Recommended Approach: Multi-Platform Bundled Package

```xml
<!-- SqlMmdConverter.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <RuntimeIdentifiers>win-x64;linux-x64;osx-x64</RuntimeIdentifiers>
    <PackageId>SqlMmdConverter</PackageId>
  </PropertyGroup>
  
  <!-- Embed Python runtime -->
  <ItemGroup>
    <Content Include="runtimes\$(RuntimeIdentifier)\python\**" 
             PackagePath="runtimes\$(RuntimeIdentifier)\python" 
             Pack="true" />
  </ItemGroup>
  
  <!-- Embed Node.js runtime -->
  <ItemGroup>
    <Content Include="runtimes\$(RuntimeIdentifier)\node\**" 
             PackagePath="runtimes\$(RuntimeIdentifier)\node" 
             Pack="true" />
  </ItemGroup>
  
  <!-- Python scripts -->
  <ItemGroup>
    <Content Include="scripts\python\**" 
             PackagePath="scripts\python" 
             Pack="true" />
  </ItemGroup>
  
  <!-- Node.js scripts -->
  <ItemGroup>
    <Content Include="scripts\node\**" 
             PackagePath="scripts\node" 
             Pack="true" />
  </ItemGroup>
</Project>
```

### Package Structure

```
SqlMmdConverter.1.0.0.nupkg
├── lib/
│   └── net10.0/
│       └── SqlMmdConverter.dll
├── runtimes/
│   ├── win-x64/
│   │   ├── python/
│   │   │   ├── python.exe
│   │   │   └── Lib/... (including sqlglot)
│   │   └── node/
│   │       ├── node.exe
│   │       └── node_modules/@funktechno/little-mermaid-2-the-sql/
│   ├── linux-x64/
│   │   └── ... (similar structure)
│   └── osx-x64/
│       └── ... (similar structure)
└── scripts/
    ├── python/
    │   └── sql_to_mmd.py
    └── node/
        └── mmd_to_sql.js
```

## 📋 Implementation Plan

### Phase 1: Project Setup & Dependencies (Week 1)
- Create solution and project structure
- Configure NuGet package metadata
- Set up bundled runtimes (Python portable + Node.js portable)
- Create install/setup scripts for dependency management
- Define internal domain models (`TableDefinition`, `ColumnDefinition`, `RelationshipDefinition`)
- Support common data types and constraints

### Phase 2: Test Infrastructure (Week 1-2)
- Create reference test data (3-table schema)
  - `reference.sql` with Customer, Order, OrderItem tables
  - `reference.mmd` with corresponding Mermaid ERD
- Set up automated test routines:
  - SQL → MMD conversion test with file comparison
  - MMD → SQL conversion test with file comparison
  - Round-trip tests (both directions)
- Implement semantic comparison utilities
- Configure auto-open functionality for test failures
- Set up xUnit test framework

### Phase 3: SQL → Mermaid Converter (Week 2-3)
- Integrate SQLGlot (Python) wrapper
- Create C# bridge to Python process
- Parse SQL DDL via SQLGlot
- Convert parsed SQL to internal models
- Generate Mermaid ERD syntax from models
- Unit tests for common scenarios
- Integration tests using reference data

### Phase 4: Mermaid → SQL Converter (Week 3-4)
- Integrate little-mermaid-2-the-sql (Node.js) wrapper
- Create C# bridge to Node.js process
- Parse Mermaid ERD diagrams
- Convert Mermaid entities to internal models
- Generate SQL DDL using external tool
- Support for ANSI SQL, PostgreSQL, MySQL, SQLite
- Unit tests for common scenarios
- Integration tests using reference data

### Phase 5: Multi-Dialect Support (Week 5-6)
- Add dialect-specific SQL generators
- Support SQL Server via SQLGlot
- Test all dialect variations with reference data
- Create dialect-specific test fixtures
- Integration tests across all supported dialects

### Phase 6: Testing & Quality Assurance (Week 6-7)
- Comprehensive round-trip testing
- Performance benchmarking
- Edge case testing
- Code coverage analysis (target 80%+)
- Fix bugs and handle edge cases

### Phase 7: Polish & Package (Week 7-8)
- Documentation (README, API docs, samples)
- Sample projects demonstrating usage
- NuGet package configuration and bundling
- CI/CD pipeline setup (GitHub Actions)
- Package testing on different platforms
- Publish to NuGet.org

## 🎯 Final Recommendation

Given the availability of mature tools for both SQL dialect conversion and Mermaid ERD processing, we recommend a **pragmatic dual-backend strategy**:

### Phase 1: MVP with External Tools (Weeks 1-4)

**Architecture:**
```
┌─────────────────────────────────────────┐
│   SqlMmdConverter NuGet Package (C#)   │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────┐    ┌──────────────┐  │
│  │ SQL → Mermaid│    │ Mermaid → SQL│  │
│  │              │    │              │  │
│  │ SQLGlot (Py) │    │ little-mermaid│  │
│  │ via Process  │    │ (Node.js)    │  │
│  └──────────────┘    └──────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │ SQL Dialect → SQL Dialect        │  │
│  │ SQLGlot (Python via Process)     │  │
│  └──────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

**Implementation:**
1. **Mermaid → SQL**: Wrap `little-mermaid-2-the-sql` (Node.js)
   - Bundle with NuGet package
   - Execute via `System.Diagnostics.Process`
   - Support PostgreSQL, MySQL, SQLite out-of-the-box
   
2. **SQL → Mermaid**: Wrap `SQLGlot` (Python)
   - Parse SQL with SQLGlot
   - Generate Mermaid ERD syntax from parsed AST
   - Support 31+ SQL dialects
   
3. **SQL Dialect Conversion**: Use `SQLGlot` (Python)
   - Transpile between dialects
   - Leverage existing battle-tested code

**Pros:**
- ✅ Fast time-to-market (2-4 weeks)
- ✅ Proven, mature parsing and conversion
- ✅ Support for many SQL dialects immediately
- ✅ Community-maintained backends

**Cons:**
- ⚠️ Requires Python and Node.js runtimes
- ⚠️ Process execution overhead
- ⚠️ Complex deployment (bundle runtimes)
- ⚠️ Less control over error handling

### Phase 2: Pure C# Migration (Weeks 5-12) - OPTIONAL

**Gradually replace external dependencies:**

1. **Start with Mermaid Parsing** (simplest)
   - Port Mermaid ERD parser to C# using Sprache
   - Mermaid syntax is simple and well-defined
   - Low complexity, high value

2. **Add Custom SQL Generation** (medium complexity)
   - Use Scriban templates for dialect-specific SQL generation
   - Focus on top 3-5 dialects (SQL Server, PostgreSQL, MySQL, SQLite)
   - Keep SQLGlot as fallback for exotic dialects

3. **Port SQL Parsing** (most complex)
   - Use Microsoft ScriptDom for T-SQL
   - Use ANTLR4 with SQL grammars for other dialects
   - Significant development effort
   - Keep SQLGlot as fallback

**Final Pure C# Architecture:**
```
┌─────────────────────────────────────────┐
│   SqlMmdConverter NuGet Package (C#)   │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────────────────────────┐  │
│  │      Core Domain Models          │  │
│  │  TableDef, ColumnDef, RelDef     │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────┐    ┌──────────────┐  │
│  │ SQL Parsers  │    │ SQL Generators│  │
│  │ ScriptDom    │    │ Scriban      │  │
│  │ ANTLR4       │    │ Templates    │  │
│  └──────────────┘    └──────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   Mermaid ERD Parser (Sprache)  │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   Mermaid ERD Generator          │  │
│  └──────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

**Pros:**
- ✅ No external runtime dependencies
- ✅ Easy NuGet packaging and distribution
- ✅ Better performance (no process overhead)
- ✅ Full control over features and quality
- ✅ Easier debugging and maintenance
- ✅ Cross-platform with .NET 10+
- ✅ Leverage latest C# 13 features

**Cons:**
- ⚠️ Significant development time
- ⚠️ Need to maintain parsers ourselves
- ⚠️ May lag behind SQL dialect evolution

### 💡 Our Recommendation: Start with Phase 1

1. **Quick MVP** using external tools (4 weeks)
2. **Validate market fit** and gather user feedback
3. **Iteratively replace** components based on:
   - Performance bottlenecks
   - Deployment pain points
   - Feature requests
   - Maintenance burden

This approach balances **speed to market** with **long-term maintainability**.

## References

- [Microsoft ScriptDom Documentation](https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom)
- [ANTLR4 C# Target](https://github.com/antlr/antlr4/blob/master/doc/csharp-target.md)
- [Sprache Parser Combinators](https://github.com/sprache/Sprache)
- [Scriban Template Engine](https://github.com/scriban/scriban)
- [Mermaid ERD Syntax Documentation](https://mermaid.js.org/syntax/entityRelationshipDiagram.html)

