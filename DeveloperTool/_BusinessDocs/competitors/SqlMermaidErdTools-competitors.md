# SqlMermaidErdTools — Competitor Analysis

**Product:** SqlMermaidErdTools (Dedge)
**Category:** SQL-to-Mermaid ERD Converter (NuGet + CLI + REST API + VS Code Extension + Stripe Payment)
**Research Date:** 2026-03-31

## Competitor Summary Table

| # | Name | URL | Pricing | Type |
|---|------|-----|---------|------|
| 1 | dbdiagram.io | https://dbdiagram.io | Free / $8-14/mo Pro / $75-100/mo Team | SaaS web app |
| 2 | ChartDB | https://chartdb.io | Free / Open Source | Web app (self-host or hosted) |
| 3 | GraphMyDB | https://graphmydb.online | Free | SaaS web app + VS Code ext |
| 4 | DiagramDB | https://diagramdb.com | Free | SaaS web app |
| 5 | XDevUtilities SQL-to-Mermaid | https://xdevutilities.com/tools/sql-mermaid | Free | Browser tool |
| 6 | sql2mermaid-cli | https://pypi.org/project/sql2mermaid-cli/ | Free / Open Source | Python CLI |
| 7 | Mermaid JS ERD to SQL (VS Code) | https://marketplace.visualstudio.com/items?itemName=erralb.mermaid-js-erd-to-sql | Free | VS Code extension |
| 8 | SchemaCrawler | https://schemacrawler.com | Free / Open Source | Java CLI + API |
| 9 | DevToolkits SQL to ER | https://zenn.dev/a1221/articles/sql-to-er-introduction | Free | Browser tool |
| 10 | Tusharad SQL to Mermaid ER | https://tusharad.github.io/sql2er/ | Free | Browser tool |

## Detailed Competitor Profiles

### 1. dbdiagram.io
**URL:** https://dbdiagram.io
**Pricing:** Free (10 diagrams) / Personal Pro $8/mo annual ($14/mo monthly) / Team $75/mo annual ($100/mo monthly) / Enterprise custom
**What they do:** Browser-based ERD design tool using a proprietary DSL (DBML). Supports SQL import/export, collaboration, version history, AI assistant (Pro), and PDF/PNG/SVG export. One of the most popular tools in this space with strong brand recognition.
**How SqlMermaidErdTools differs:** SqlMermaidErdTools uses the open Mermaid standard rather than a proprietary DSL, offers bidirectional conversion (SQL-to-Mermaid and Mermaid-to-SQL), provides a NuGet library for programmatic integration in .NET projects, and includes a REST API for server-side automation. dbdiagram.io is browser-only with no embeddable library or CLI.

### 2. ChartDB
**URL:** https://chartdb.io
**Pricing:** Free / Open Source (19K+ GitHub stars)
**What they do:** Open-source database design editor supporting MySQL, MariaDB, PostgreSQL, SQL Server, and SQLite. Features instant database import, real-time team collaboration, AI-powered diagram generation, and SQL/image export.
**How SqlMermaidErdTools differs:** ChartDB generates visual diagrams in a proprietary format, not Mermaid syntax. SqlMermaidErdTools produces portable Mermaid markup that works in GitHub, GitLab, Notion, and any Mermaid-compatible renderer. SqlMermaidErdTools also supports 31+ SQL dialects vs. ChartDB's 5.

### 3. GraphMyDB
**URL:** https://graphmydb.online
**Pricing:** Free
**What they do:** Browser-based SQL schema visualizer accepting MySQL, PostgreSQL, SQLite dumps, CSV, JSON, and Excel. Features live collaboration (up to 4 users), a VS Code extension, and schema comparison for migrations. Runs entirely in-browser.
**How SqlMermaidErdTools differs:** GraphMyDB focuses on visual schema exploration; it does not produce Mermaid output or offer programmatic APIs. SqlMermaidErdTools provides a NuGet package, CLI, and REST API for CI/CD integration and automated documentation generation.

### 4. DiagramDB
**URL:** https://diagramdb.com
**Pricing:** Free
**What they do:** Browser-based SQL formatting, syntax validation, ERD generation, and SQL-to-ERD conversion. No signup required.
**How SqlMermaidErdTools differs:** DiagramDB is a simple web tool with no offline or programmatic capabilities. SqlMermaidErdTools offers a NuGet library for embedding in .NET applications, a CLI for scripting, and a REST API for service integration.

### 5. XDevUtilities SQL to Mermaid
**URL:** https://xdevutilities.com/tools/sql-mermaid
**Pricing:** Free
**What they do:** Converts CREATE TABLE statements into Mermaid ER diagrams. Supports MySQL, PostgreSQL, SQL Server, and SQLite with instant rendering and SVG export. Zero storage policy.
**How SqlMermaidErdTools differs:** XDevUtilities is a one-way web-only tool. SqlMermaidErdTools provides bidirectional conversion, supports 31+ dialects, and ships as a NuGet package + CLI + REST API for automated workflows. No VS Code extension or Stripe monetization in XDevUtilities.

### 6. sql2mermaid-cli (Python)
**URL:** https://pypi.org/project/sql2mermaid-cli/
**Pricing:** Free / Open Source
**What they do:** Python CLI tool (pip install) that converts SQL queries into Mermaid format. Saves output as plain text or markdown. Requires Python >= 3.8.1.
**How SqlMermaidErdTools differs:** sql2mermaid-cli is Python-only and one-way. SqlMermaidErdTools is .NET-native (NuGet), supports bidirectional conversion, handles 31+ SQL dialects, and includes a REST API and VS Code extension in addition to CLI.

### 7. Mermaid JS ERD to SQL (VS Code Extension)
**URL:** https://marketplace.visualstudio.com/items?itemName=erralb.mermaid-js-erd-to-sql
**Pricing:** Free
**What they do:** VS Code extension that converts Mermaid ERD markup to SQL DDL (the reverse direction). Supports MySQL, SQLite, and Postgres with automatic foreign key generation.
**How SqlMermaidErdTools differs:** This extension only does Mermaid-to-SQL (one direction). SqlMermaidErdTools does both directions, supports 31+ SQL dialects, and also ships as a NuGet package and REST API — not just a VS Code extension.

### 8. SchemaCrawler
**URL:** https://schemacrawler.com
**Pricing:** Free / Open Source
**What they do:** Java-based database schema discovery tool. Generates ERD diagrams using Graphviz (PNG, SVG) and supports export to Mermaid, PlantUML, and dbdiagram.io formats. Includes schema linting, regex-based filtering, and works with any JDBC database.
**How SqlMermaidErdTools differs:** SchemaCrawler requires a live database connection and the Java runtime; it cannot convert standalone DDL files. SqlMermaidErdTools parses DDL text directly without a database connection, runs natively on .NET, and offers a REST API for integration.

### 9. DevToolkits SQL to ER
**URL:** https://zenn.dev/a1221/articles/sql-to-er-introduction
**Pricing:** Free
**What they do:** Browser-based tool built with Astro and TypeScript that generates Mermaid ER diagrams from DDL. All processing is client-side using regex-based parsing.
**How SqlMermaidErdTools differs:** A hobby/demo project with limited SQL dialect support and no programmatic API. SqlMermaidErdTools is a commercial-grade product with 31+ dialect support, NuGet package, CLI, REST API, and Stripe-powered licensing.

### 10. Tusharad SQL to Mermaid ER
**URL:** https://tusharad.github.io/sql2er/
**Pricing:** Free
**What they do:** Simple web-based converter supporting PostgreSQL queries to Mermaid diagram format.
**How SqlMermaidErdTools differs:** Single-dialect hobby project. SqlMermaidErdTools supports 31+ SQL dialects, bidirectional conversion, and provides professional tooling (NuGet, CLI, REST API, VS Code extension).

## Key Differentiators for SqlMermaidErdTools

1. **Bidirectional conversion** — most competitors are one-way only
2. **31+ SQL dialect support** — broadest dialect coverage in the market
3. **Multi-surface delivery** — NuGet package, CLI, REST API, and VS Code extension
4. **Mermaid standard** — uses an open, portable diagram format (not proprietary)
5. **Commercial licensing with Stripe** — sustainable product with enterprise billing
6. **.NET native** — first-class citizen in the .NET ecosystem
