# SqlMermaid ERD Tools CLI

Command-line tool for bidirectional SQL DDL and Mermaid ERD conversion.

## Installation

### Install as Global Tool

```bash
dotnet tool install -g SqlMermaidErdTools.CLI
```

### Update

```bash
dotnet tool update -g SqlMermaidErdTools.CLI
```

### Uninstall

```bash
dotnet tool uninstall -g SqlMermaidErdTools.CLI
```

## Usage

### SQL to Mermaid

```bash
# Convert to stdout
sqlmermaid sql-to-mmd schema.sql

# Convert to file
sqlmermaid sql-to-mmd schema.sql --output schema.mmd

# With debug export
sqlmermaid sql-to-mmd schema.sql -o schema.mmd --export-dir ./debug
```

### Mermaid to SQL

```bash
# Convert with default dialect (ANSI SQL)
sqlmermaid mmd-to-sql schema.mmd

# Convert to specific dialect
sqlmermaid mmd-to-sql schema.mmd --dialect PostgreSql -o schema.sql

# All dialects
sqlmermaid mmd-to-sql schema.mmd -d AnsiSql -o ansi.sql
sqlmermaid mmd-to-sql schema.mmd -d SqlServer -o sqlserver.sql
sqlmermaid mmd-to-sql schema.mmd -d PostgreSql -o postgres.sql
sqlmermaid mmd-to-sql schema.mmd -d MySql -o mysql.sql
```

### Schema Diff (Migration)

```bash
# Generate ALTER statements
sqlmermaid diff before.mmd after.mmd --dialect PostgreSql -o migration.sql
```

### License Management

```bash
# Show current license
sqlmermaid license show

# Activate license
sqlmermaid license activate --key SQLMMD-PRO-XXXX-XXXX --email you@example.com

# Deactivate license
sqlmermaid license deactivate
```

### Version

```bash
sqlmermaid version
```

## License Tiers

### Free Tier
- ✅ Up to 10 tables per conversion
- ✅ All SQL dialects
- ✅ Community support

### Pro Tier ($99/year or $249 perpetual)
- ✅ Unlimited tables
- ✅ All SQL dialects
- ✅ Email support
- ✅ Commercial use license

### Team Tier ($399/year for 5 seats)
- ✅ Everything in Pro
- ✅ Team collaboration features
- ✅ Priority support

### Enterprise Tier ($1,999/year)
- ✅ Everything in Team
- ✅ SLA
- ✅ Dedicated support
- ✅ Custom features

## Examples

### Example 1: Document Existing Database

```bash
# Export your database schema to SQL
pg_dump -s mydb > schema.sql

# Convert to Mermaid ERD
sqlmermaid sql-to-mmd schema.sql -o schema.mmd

# Add to your README.md
cat schema.mmd >> README.md
```

### Example 2: Design New Schema

```bash
# Create Mermaid ERD in schema.mmd
# Convert to PostgreSQL
sqlmermaid mmd-to-sql schema.mmd -d PostgreSql -o create_schema.sql

# Run on database
psql mydb < create_schema.sql
```

### Example 3: Schema Migration

```bash
# Edit your Mermaid diagram (schema_v2.mmd)
# Generate migration script
sqlmermaid diff schema_v1.mmd schema_v2.mmd -d PostgreSql -o migration.sql

# Review and run
cat migration.sql
psql mydb < migration.sql
```

## Exit Codes

- `0`: Success
- `1`: Conversion error (invalid input, file not found, etc.)
- `2`: License validation failed (table limit exceeded, expired license)

## Support

- 📖 [Documentation](https://github.com/yourusername/SqlMermaidErdTools/wiki)
- 🐛 [Issue Tracker](https://github.com/yourusername/SqlMermaidErdTools/issues)
- 💬 [Discussions](https://github.com/yourusername/SqlMermaidErdTools/discussions)

## License

MIT License - see LICENSE file for details

