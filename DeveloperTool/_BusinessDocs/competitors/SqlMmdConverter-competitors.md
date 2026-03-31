# SqlMmdConverter — Competitor Analysis

**Product:** SqlMmdConverter (Dedge)
**Category:** NuGet Package for SQL-to-Mermaid One-Way Conversion (predecessor to SqlMermaidErdTools)
**Research Date:** 2026-03-31

## Competitor Summary Table

| # | Name | URL | Pricing | Type |
|---|------|-----|---------|------|
| 1 | mermerd | https://github.com/KarnerTh/mermerd | Free / Open Source (MIT) | Go CLI |
| 2 | sql2mermaid-cli | https://pypi.org/project/sql2mermaid-cli/ | Free / Open Source | Python CLI (pip) |
| 3 | mermaid-gen | https://nuget.org/packages/mermaid-gen | Free | .NET CLI (NuGet) |
| 4 | Mermaider | https://github.com/nullean/mermaider | Free / Open Source | .NET library (NuGet) |
| 5 | SchemaCrawler | https://schemacrawler.com | Free / Open Source | Java CLI + API |
| 6 | MermaidClassDiagramGenerator | https://nuget.org/packages/MermaidClassDiagramGenerator | Free | .NET library (NuGet) |
| 7 | XDevUtilities SQL to Mermaid | https://xdevutilities.com/tools/sql-mermaid | Free | Browser tool |
| 8 | Tusharad SQL to Mermaid ER | https://tusharad.github.io/sql2er/ | Free | Browser tool |

## Detailed Competitor Profiles

### 1. mermerd
**URL:** https://github.com/KarnerTh/mermerd
**Pricing:** Free / Open Source (MIT License)
**What they do:** Go-based CLI tool that connects to a live database (PostgreSQL, MySQL, MSSQL, SQLite3), lets you select a schema and tables interactively, then generates a Mermaid ERD. Features include constraint visualization (PK, FK, unique), enum values, column comments, NOT NULL constraints, and CI/CD integration via run configurations. 596 GitHub stars, last updated Dec 2025 (v0.13.0).
**How SqlMmdConverter differs:** SqlMmdConverter parses DDL text directly without requiring a live database connection. It is a .NET NuGet package for embedding in C#/.NET projects, while mermerd is a standalone Go binary. SqlMmdConverter supports 31+ SQL dialects; mermerd supports 4.

### 2. sql2mermaid-cli
**URL:** https://pypi.org/project/sql2mermaid-cli/
**Pricing:** Free / Open Source
**What they do:** Python CLI tool (v1.0.1) that converts SQL queries into Mermaid format. Installable via pip, requires Python >= 3.8.1. Saves output as plain text or markdown files.
**How SqlMmdConverter differs:** SqlMmdConverter is a .NET NuGet package designed for programmatic use in C# applications and build pipelines. sql2mermaid-cli is Python-only and CLI-only. SqlMmdConverter supports 31+ SQL dialects with a robust parser; sql2mermaid-cli has limited dialect coverage.

### 3. mermaid-gen
**URL:** https://nuget.org/packages/mermaid-gen
**Pricing:** Free
**What they do:** .NET command-line utility (v0.0.4) that generates ER or class diagrams from EF Core POCOs. Compatible with .NET 5.0 and .NET Core 3.1. Focuses on Entity Framework Core model classes rather than raw SQL DDL.
**How SqlMmdConverter differs:** SqlMmdConverter converts SQL DDL text directly to Mermaid, without requiring Entity Framework models. It supports 31+ SQL dialects and works with raw DDL from any source, not just EF Core code-first models.

### 4. Mermaider
**URL:** https://github.com/nullean/mermaider
**Pricing:** Free / Open Source
**What they do:** Pure .NET parser and renderer that converts Mermaid markup into SVG without requiring JavaScript or external processes. Supports various diagram types including ER diagrams. Works in the opposite direction — rendering Mermaid, not generating it from SQL.
**How SqlMmdConverter differs:** SqlMmdConverter generates Mermaid from SQL (opposite direction). Mermaider renders Mermaid to SVG. They are complementary rather than competing, but both operate in the Mermaid .NET ecosystem.

### 5. SchemaCrawler
**URL:** https://schemacrawler.com
**Pricing:** Free / Open Source
**What they do:** Comprehensive Java-based database schema discovery tool. Generates ERD diagrams via Graphviz and supports export to Mermaid, PlantUML, and dbdiagram.io formats. Includes schema linting, regex-based filtering, and works with any JDBC-compatible database. Available as CLI and Java API.
**How SqlMmdConverter differs:** SqlMmdConverter is .NET-native (NuGet) and parses DDL text without a database connection. SchemaCrawler requires a live JDBC connection and Java runtime. SqlMmdConverter is lightweight and embeddable; SchemaCrawler is a full-featured schema analysis suite.

### 6. MermaidClassDiagramGenerator
**URL:** https://nuget.org/packages/MermaidClassDiagramGenerator
**Pricing:** Free
**What they do:** .NET 8.0 NuGet package for generating Mermaid class diagrams (not ER diagrams) from .NET types. Focused on class/object diagrams for documenting code architecture.
**How SqlMmdConverter differs:** SqlMmdConverter generates entity-relationship diagrams from SQL DDL; MermaidClassDiagramGenerator generates class diagrams from .NET types. Different diagram types targeting different use cases (database vs. code documentation).

### 7. XDevUtilities SQL to Mermaid
**URL:** https://xdevutilities.com/tools/sql-mermaid
**Pricing:** Free
**What they do:** Browser-based tool that converts CREATE TABLE statements into Mermaid ER diagrams. Supports MySQL, PostgreSQL, SQL Server, and SQLite. Instant rendering, SVG export, zero storage policy.
**How SqlMmdConverter differs:** SqlMmdConverter is a NuGet package for programmatic use in .NET applications and CI/CD pipelines. XDevUtilities is a browser-only tool with no API or library. SqlMmdConverter supports 31+ SQL dialects vs. 4.

### 8. Tusharad SQL to Mermaid ER
**URL:** https://tusharad.github.io/sql2er/
**Pricing:** Free
**What they do:** Simple web-based converter supporting PostgreSQL queries to Mermaid diagram format. A hobby/demo project with minimal features.
**How SqlMmdConverter differs:** SqlMmdConverter is a professional NuGet package supporting 31+ SQL dialects, designed for programmatic integration in .NET builds and applications. Tusharad is a single-dialect browser-only hobby tool.

## Key Differentiators for SqlMmdConverter

1. **.NET NuGet package** — embeddable in C# applications, build scripts, and CI/CD pipelines
2. **31+ SQL dialect support** — broadest dialect coverage of any SQL-to-Mermaid library
3. **DDL text parsing** — no live database connection required (unlike mermerd, SchemaCrawler)
4. **Lightweight and focused** — single-responsibility library, not a heavy framework
5. **Upgrade path** — users can graduate to SqlMermaidErdTools for bidirectional conversion, CLI, REST API, and VS Code extension
