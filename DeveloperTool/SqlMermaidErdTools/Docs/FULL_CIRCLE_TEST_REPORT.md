# Full Circle Test Report - test.sql
**Generated:** 2025-12-01 11:46:24
**Export Directory:** `D:\opt\src\SqlMermaidErdTools\TestSuite\ComprehensiveTest\FullCircle_Export_20251201_114624`

## Test Overview
This test performs a complete round-trip conversion of the test.sql file:
1. **SQL → MMD**: Convert original SQL to Mermaid ERD
2. **MMD → SQL**: Convert generated MMD back to SQL (multiple dialects)
3. **SQL → SQL**: Translate SQL between different dialects

## Input File
- **File:** `TestFiles/test.sql`
- **Size:** 46 328 bytes
- **Lines:** 1 326

## Step 1: SQL → Mermaid ERD Conversion
- **Status:** ✅ Success
- **Duration:** 599ms
- **Output Size:** 38 124 bytes
- **Output Lines:** 957
- **Output File:** `roundtrip.mmd`

## Step 2: Mermaid → SQL Conversion (Multiple Dialects)
### ANSI SQL
- **Status:** ✅ Success
- **Duration:** 110ms
- **Output Size:** 22 901 bytes
- **File:** `AnsiSql/roundtrip_AnsiSql.sql`

### T-SQL (SQL Server)
- **Status:** ✅ Success
- **Duration:** 108ms
- **Output Size:** 22 669 bytes
- **File:** `SqlServer/roundtrip_SqlServer.sql`

### PostgreSQL
- **Status:** ✅ Success
- **Duration:** 96ms
- **Output Size:** 22 901 bytes
- **File:** `PostgreSql/roundtrip_PostgreSql.sql`

### MySQL
- **Status:** ✅ Success
- **Duration:** 104ms
- **Output Size:** 22 901 bytes
- **File:** `MySql/roundtrip_MySql.sql`

## Step 3: SQL Dialect Translation
### ANSI → T-SQL (SQL Server)
- **Status:** ✅ Success
- **Duration:** 674ms
- **Output Size:** 42 454 bytes
- **File:** `Translated_SqlServer/translated_SqlServer.sql`
- **Contains SQL Server brackets []:** False

### ANSI → PostgreSQL
- **Status:** ✅ Success
- **Duration:** 699ms
- **Output Size:** 43 546 bytes
- **File:** `Translated_PostgreSql/translated_PostgreSql.sql`

### ANSI → MySQL
- **Status:** ✅ Success
- **Duration:** 627ms
- **Output Size:** 41 785 bytes
- **File:** `Translated_MySql/translated_MySql.sql`

## Summary

### Key Observations
- ✅ SQL successfully converted to Mermaid ERD
- ✅ Mermaid ERD successfully converted back to SQL (multiple dialects)
- ✅ SQL dialect translation completed
- All intermediate files (AST, SQLGlot I/O) preserved in export folder

### Round-Trip Notes
- **Data Type Normalization**: SQLGlot may normalize data types (e.g., `VARCHAR(255)` → `VARCHAR`)
- **Formatting**: Whitespace, indentation, and capitalization may differ
- **Semantic Equivalence**: Focus is on schema structure, not text-exact matching
- **SQL Server Brackets**: SQLGlot does not add `[]` brackets by default (optional in T-SQL)

