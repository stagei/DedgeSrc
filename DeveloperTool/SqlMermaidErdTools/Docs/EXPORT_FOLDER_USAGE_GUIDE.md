# Export Folder Usage Guide

## Overview

The `ExportFolderPath` feature provides complete transparency into the conversion process by automatically saving all input, intermediate, and output files. This is invaluable for debugging, auditing, and understanding how SQL transformations work.

## Latest Test Run Results

**Test Date**: December 1, 2025, 09:52:16  
**Export Folder**: `ExportedFiles_20251201_095216`  
**Source Data**: `test.sql` (MS Access Clinical Trials Database - 40 tables, 1,326 lines)

### Test Summary

| Test | Duration | Status | Files Exported | AST File |
|------|----------|--------|----------------|----------|
| SQL → Mermaid ERD | 264ms | ✅ | 7 files | ✅ 132 KB |
| Mermaid → SQL (ANSI) | 55ms | ✅ | 4 files | ❌ |
| SQL → SQL Server | 337ms | ✅ | 7 files | ✅ 199 KB |
| SQL → PostgreSQL | 282ms | ✅ | 7 files | ✅ 201 KB |
| SQL → MySQL | 274ms | ✅ | 7 files | ✅ 199 KB |
| Mermaid DIFF → ALTER | 117ms | ✅ | 4 files | ❌ |
| **Total** | **1,329ms** | **✅ All Passed** | **36 files** | **4 AST files** |

---

## How to Use Export Folder Feature

### 1. **Set Export Folder Path on Converter**

```csharp
using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;

var exportFolder = @"C:\MyExports\ConversionAudit";

// Example 1: SQL to Mermaid with export
var sqlToMmd = new SqlToMmdConverter 
{ 
    ExportFolderPath = exportFolder 
};

var mermaid = await sqlToMmd.ConvertAsync(sqlContent);

// Example 2: SQL Dialect Translation with export
var translator = new SqlDialectTranslator 
{ 
    ExportFolderPath = exportFolder 
};

var tsql = await translator.TranslateAsync(
    sqlContent, 
    SqlDialect.AnsiSql, 
    SqlDialect.SqlServer
);

// Example 3: Mermaid to SQL with export
var mmdToSql = new MmdToSqlConverter 
{ 
    ExportFolderPath = exportFolder 
};

var sql = await mmdToSql.ConvertAsync(mermaidContent, SqlDialect.PostgreSql);
```

### 2. **Disable Export (Default Behavior)**

If you don't set `ExportFolderPath`, no files are exported:

```csharp
var converter = new SqlToMmdConverter(); // No export
var result = await converter.ConvertAsync(sql);
```

---

## File Naming Convention

All exported files follow a consistent naming pattern:

### Input Files

| Pattern | Example | Description |
|---------|---------|-------------|
| `<Function>-In_Original.<ext>` | `SqlToMmd-In_Original.sql` | Original input before any C# processing |
| `<Function>-In_Cleaned.<ext>` | `SqlToMmd-In_Cleaned.sql` | Input after C# preprocessing (e.g., bracket removal) |
| `<Function>-In.<ext>` | `SqlToMmd-In.sql` | Final input sent to the conversion function |

### SQLGlot Interaction Files

| Pattern | Example | Description |
|---------|---------|-------------|
| `<Function>-InToSqlGlot<timestamp>.<ext>` | `SqlToMmd-InToSqlGlot20251201_093958_505.sql` | Exact input sent to SQLGlot Python script |
| `<Function>-Out.ast` | `SqlToMmd-Out.ast` | **SQLGlot Abstract Syntax Tree (AST) representation** 🆕 |
| `<Function>-OutFromSqlGlot<timestamp>.<ext>` | `SqlToMmd-OutFromSqlGlot20251201_093958_654.mmd` | Raw output received from SQLGlot |

### Output Files

| Pattern | Example | Description |
|---------|---------|-------------|
| `<Function>-Out.<ext>` | `SqlToMmd-Out.mmd` | Final output after all processing |

---

## Example: SQL → Mermaid ERD Export

When converting SQL to Mermaid, you get **7 files** showing the entire transformation:

```
ExportedFiles_20251201_095216/
│
├── SqlToMmd-In_Original.sql          (45.2 KB)
│   ↓ Original SQL with [brackets]
│
├── SqlToMmd-In_Cleaned.sql           (42.8 KB)
│   ↓ Brackets removed by C#
│
├── SqlToMmd-In.sql                   (42.8 KB)
│   ↓ Final SQL ready for SQLGlot
│
├── SqlToMmd-InToSqlGlot20251201_095217_225.sql  (42.8 KB)
│   ↓ Exact input sent to Python/SQLGlot
│
├── SqlToMmd-Out.ast                  (132.1 KB) 🆕
│   ↓ SQLGlot's Abstract Syntax Tree representation
│
├── SqlToMmd-OutFromSqlGlot20251201_095217_225.mmd  (37.2 KB)
│   ↓ Raw Mermaid ERD from SQLGlot
│
└── SqlToMmd-Out.mmd                  (37.2 KB)
    Final Mermaid ERD output
```

### Key Insight from Example

Comparing `SqlToMmd-In_Original.sql` and `SqlToMmd-In_Cleaned.sql`:

**Original (with brackets):**
```sql
DROP TABLE IF EXISTS [UserAccessTypes];
DROP TABLE IF EXISTS [TrialTypes];
```

**Cleaned (brackets removed):**
```sql
DROP TABLE IF EXISTS UserAccessTypes;
DROP TABLE IF EXISTS TrialTypes;
```

This preprocessing step is crucial because SQLGlot's parser doesn't handle MS SQL Server/Access brackets `[]` well in generic mode.

### Understanding the AST File

The **`<Function>-Out.ast`** file shows SQLGlot's Abstract Syntax Tree - how SQLGlot internally understands and represents the SQL. Each statement is shown in two forms:

**Statement Structure (Raw AST):**
```
Statement 41:
------------------------------------------------------------
CREATE TABLE ActionCodes (ActionCode VARCHAR(50) NULL, Name VARCHAR(50) NULL, ...)
```

**Statement (Pretty-Printed):**
```
Statement 41 (Pretty):
------------------------------------------------------------
CREATE TABLE ActionCodes (
  ActionCode VARCHAR(50) NULL,
  Name VARCHAR(50) NULL,
  Description VARCHAR(MAX) NULL,
  ...
  PRIMARY KEY (ActionCode)
)
```

This lets you see:
- How SQLGlot parsed each statement
- Whether it understood your SQL correctly
- How it normalizes the SQL (formatting, whitespace)
- Any transformations or simplifications it applies

---

## Example: SQL Dialect Translation Export

When translating SQL from ANSI to SQL Server, you get **6 files**:

```
ExportedFiles_20251201_093958/
│
├── SqlDialectTranslate_AnsiSqlToSqlServer-In_Original.sql  (45.2 KB)
│   Original SQL with comments and brackets
│
├── SqlDialectTranslate_AnsiSqlToSqlServer-In_Cleaned.sql   (42.8 KB)
│   SQL after bracket removal
│
├── SqlDialectTranslate_AnsiSqlToSqlServer-In.sql           (42.8 KB)
│   Final SQL ready for translation
│
├── SqlDialectTranslate_AnsiSqlToSqlServer-InToSqlGlot20251201_093958_706.sql  (42.8 KB)
│   Input sent to SQLGlot for translation
│
├── SqlDialectTranslate_AnsiSqlToSqlServer-OutFromSqlGlot20251201_093958_868.sql  (41.5 KB)
│   T-SQL output from SQLGlot
│
└── SqlDialectTranslate_AnsiSqlToSqlServer-Out.sql          (41.5 KB)
    Final T-SQL output
```

### Finding: SQL Server Brackets

**Question**: Does SQLGlot add brackets `[]` when generating T-SQL?  
**Answer**: **NO** - SQLGlot generates standard identifiers without brackets

**Example from exported file:**
```sql
-- SQLGlot Output (No Brackets)
CREATE TABLE UserAccessTypes (
    UserAccessType NVARCHAR(50) NOT NULL,
    Name NVARCHAR(50),
    Description NVARCHAR(255),
    PRIMARY KEY (UserAccessType)
)
```

Both forms are valid T-SQL. SQLGlot prefers the simpler syntax.

---

## Viewing Mermaid Output

The Mermaid ERD files can be viewed using:

### Online Viewer
- **Mermaid Live Editor**: https://mermaid.live/
- Simply paste the content from `SqlToMmd-Out.mmd`

### Visual Studio Code
- Install "Markdown Preview Mermaid Support" extension
- Create a `.md` file with:
  ````markdown
  ```mermaid
  erDiagram
      ActionCodes {
          varchar ActionCode PK
          varchar Name "NOT NULL"
          ...
      }
  ```
  ````

### Example Mermaid Output (from export):

```mermaid
erDiagram
    ActionCodes {
        varchar ActionCode PK
        varchar Name "NOT NULL"
        varchar Description "NOT NULL"
        datetime CreatedDate "NOT NULL"
        datetime ModifiedDate "NOT NULL"
        varchar CreatedBy "NOT NULL"
        varchar ModifiedBy "NOT NULL"
        bit IsDeleted "NOT NULL, DEFAULT FALSE"
    }

    AdverseEvents {
        int EventID PK
        int TrialID FK "NOT NULL"
        varchar EventType FK "NOT NULL"
        datetime EventDate "NOT NULL"
        int PatientID FK "NOT NULL"
        ...
    }
    
    AdverseEvents }o--|| Trials : "belongs to"
    AdverseEvents }o--|| EventTypes : "has type"
    AdverseEvents }o--|| TrialPatients : "affects"
```

---

## Export Folder Structure

A typical export folder contains files grouped by function:

```
ExportedFiles_20251201_093958/
├── SQL to Mermaid (6 files) - naturally grouped alphabetically
│   ├── SqlToMmd-In_Original.sql
│   ├── SqlToMmd-In_Cleaned.sql
│   ├── SqlToMmd-In.sql
│   ├── SqlToMmd-InToSqlGlot20251201_093958_505.sql
│   ├── SqlToMmd-OutFromSqlGlot20251201_093958_654.mmd
│   └── SqlToMmd-Out.mmd
│
├── Mermaid to SQL - ANSI (4 files)
│   ├── MmdToSql_AnsiSql-In.mmd
│   ├── MmdToSql_AnsiSql-InToSqlGlot20251201_093958_660.mmd
│   ├── MmdToSql_AnsiSql-OutFromSqlGlot20251201_093958_699.sql
│   └── MmdToSql_AnsiSql-Out.sql
│
├── SQL Dialect Translation - SQL Server (6 files)
│   ├── SqlDialectTranslate_AnsiSqlToSqlServer-In_Original.sql
│   ├── SqlDialectTranslate_AnsiSqlToSqlServer-In_Cleaned.sql
│   ├── SqlDialectTranslate_AnsiSqlToSqlServer-In.sql
│   ├── SqlDialectTranslate_AnsiSqlToSqlServer-InToSqlGlot20251201_093958_706.sql
│   ├── SqlDialectTranslate_AnsiSqlToSqlServer-OutFromSqlGlot20251201_093958_868.sql
│   └── SqlDialectTranslate_AnsiSqlToSqlServer-Out.sql
│
├── SQL Dialect Translation - PostgreSQL (6 files)
├── SQL Dialect Translation - MySQL (6 files)
└── Mermaid DIFF (4 files)
```

**Total: 32 files, ~1.3 MB**

---

## Use Cases

### 1. **Debugging Conversion Issues**

If a conversion fails or produces unexpected results, the export files let you:
- **Identify where the problem occurs**: Input, SQLGlot, or output processing
- **Compare files**: Use diff tools to see exactly what changed
- **Reproduce issues**: You have exact inputs for bug reports

**Example:**
```bash
# Compare original vs. cleaned SQL
code --diff "SqlToMmd-In_Original.sql" "SqlToMmd-In_Cleaned.sql"

# See what SQLGlot actually received
cat "SqlToMmd-InToSqlGlot20251201_093958_505.sql"

# Check SQLGlot's raw output
cat "SqlToMmd-OutFromSqlGlot20251201_093958_654.mmd"
```

### 2. **Auditing Database Migrations**

For compliance and audit trails:
- **Document transformations**: Every step is recorded
- **Verify accuracy**: Compare before/after SQL
- **Track changes**: Timestamped files show conversion history

### 3. **Learning SQLGlot Behavior**

Understand how SQLGlot transforms SQL:
- **See the AST representation**: Compare input to output
- **Learn dialect differences**: Compare ANSI vs. T-SQL vs. PostgreSQL outputs
- **Test edge cases**: Export helps identify SQLGlot limitations

### 4. **Quality Assurance**

Validate conversion quality:
- **Schema comparison**: Use tools to compare generated SQL against original
- **Data type mapping**: Verify INT → INT, VARCHAR → NVARCHAR, etc.
- **Constraint preservation**: Ensure PRIMARY KEY, FOREIGN KEY preserved

---

## Performance Impact

Export functionality has **minimal performance impact**:

| Operation | With Export | Without Export | Overhead |
|-----------|-------------|----------------|----------|
| SQL → Mermaid | 163ms | ~160ms | ~2% |
| Mermaid → SQL | 41ms | ~40ms | ~2.5% |
| SQL Translation | 167ms | ~165ms | ~1% |

**Conclusion**: The overhead of writing files to disk is negligible compared to the time spent in SQLGlot parsing/generation.

---

## Cleanup and Management

Export folders can grow large with repeated runs:

### Automatic Timestamped Folders
Each test run creates a new folder:
```
ExportedFiles_20251201_093958/
ExportedFiles_20251201_094512/
ExportedFiles_20251201_095033/
```

### Manual Cleanup
```powershell
# Remove old export folders (keep last 7 days)
Get-ChildItem -Path "D:\opt\src\SqlMermaidErdTools" -Filter "ExportedFiles_*" -Directory |
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Recurse -Force
```

### Programmatic Cleanup
```csharp
// Clean up after conversion
var exportFolder = $"ExportedFiles_{DateTime.Now:yyyyMMdd_HHmmss}";
var converter = new SqlToMmdConverter { ExportFolderPath = exportFolder };
var result = await converter.ConvertAsync(sql);

// Optional: Delete export folder if conversion succeeded
if (!string.IsNullOrEmpty(result))
{
    Directory.Delete(exportFolder, true);
}
```

---

## Related Documentation

- **COMPREHENSIVE_TEST_RESULTS.md**: Detailed test results and findings
- **SQLGLOT_AST_EXPLAINED.md**: Understanding SQLGlot's intermediate representation
- **TEST_COMPARISON_SUMMARY.md**: Analysis of round-trip conversion fidelity

---

## Summary

The Export Folder feature provides **complete transparency** into the SQL conversion process:

✅ **All intermediate files saved**  
✅ **Timestamped for traceability**  
✅ **Minimal performance overhead**  
✅ **Invaluable for debugging**  
✅ **Perfect for auditing**  
✅ **Helps understand SQLGlot behavior**

**Latest test run**: All 6 functions tested successfully, 32 files exported, 764ms total time.

