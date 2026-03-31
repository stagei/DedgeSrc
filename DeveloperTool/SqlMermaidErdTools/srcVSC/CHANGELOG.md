# Change Log

All notable changes to the "SQL ↔ Mermaid ERD Tools" extension will be documented in this file.

## [0.1.0] - 2025-12-01

### Added
- Initial release of SQL ↔ Mermaid ERD Tools
- SQL to Mermaid ERD conversion
- Mermaid ERD to SQL conversion with dialect support:
  - ANSI SQL
  - Microsoft SQL Server (T-SQL)
  - PostgreSQL
  - MySQL
- Live Mermaid diagram preview with auto-refresh
- Context menu integration for `.sql` and `.mmd` files
- Command palette commands
- Configuration options:
  - Default SQL dialect
  - Auto-open preview
  - Output format (new file, clipboard, or both)
  - Custom API endpoint support
  - Custom CLI path
- Support for both local CLI and remote API conversions
- Auto-detection of SqlMermaidErdTools CLI global tool
- Beautiful Mermaid rendering with Mermaid.js v10

### Known Issues
- Preview may not render correctly for very large diagrams (>100 tables)
- Some advanced SQL features may not be fully supported

## [Unreleased]

### Planned Features
- Database connection integration (import schema directly from live database)
- Schema comparison and diff generation
- Batch conversion of multiple files
- Export diagrams to PNG/SVG
- Custom diagram theming
- Syntax highlighting for Mermaid ERD
- Code snippets for common patterns
- Schema validation and linting

