# Mermaid Designer - UI Redesign Proposal

**Date**: December 14, 2025  
**Based On**: CLI Testing Results & SqlMermaidErdTools Integration  
**Purpose**: Redesign Mermaid Designer to fully expose all 4 core functionalities

---

## Current State Analysis

### What Works ✅
1. **Load from DB** → Generates Mermaid diagram
2. **Show Diff** → Displays schema changes
3. **Generate DDL** → Opens AlterStatementReviewDialog

### What's Missing/Incomplete ⚠️
1. **No Mermaid → SQL export** (backend exists, no UI)
2. **No SQL Dialect Translation UI** (backend exists, no UI)
3. **Generated SQL goes to Notepad** (not integrated with app)
4. **No connection selection** for executing SQL
5. **No "Open in Editor" option** for SQL results

---

## The 4 Core Functionalities (Exposed via CLI Testing)

Based on CLI testing, the Mermaid Designer should support:

### 1. **SQL → Mermaid** (Forward Engineering)
**CLI Command**:
```powershell
DbExplorer.exe --profile FKKTOTST \
  --db-to-mermaid \
  --infile tables.txt \
  --outfile diagram.mmd
```

**Current UI**: ✅ "🔽 Load from DB" button
**Status**: Works well

---

### 2. **Mermaid → SQL** (Reverse Engineering)
**CLI Command**:
```powershell
DbExplorer.exe --profile FKKTOTST \
  --mermaid-to-sql \
  --infile diagram.mmd \
  --dialect ANSI \
  --outfile schema.sql
```

**Current UI**: ⚠️ "🔧 Mermaid → SQL" button exists but incomplete
**Status**: Needs dialog + integration

---

### 3. **Mermaid Diff → ALTER** (Schema Migration)
**CLI Command**:
```powershell
DbExplorer.exe --profile FKKTOTST \
  --mermaid-diff-to-alter \
  --original baseline.mmd \
  --modified changes.mmd \
  --outfile migration.sql
```

**Current UI**: ✅ "📝 Generate DDL" button → AlterStatementReviewDialog
**Status**: Works well

---

### 4. **SQL Dialect Translation**
**CLI Command**:
```powershell
DbExplorer.exe --profile FKKTOTST \
  --translate-sql \
  --infile db2_schema.sql \
  --from-dialect DB2 \
  --to-dialect PostgreSQL \
  --outfile postgres_schema.sql
```

**Current UI**: ❌ No UI at all
**Status**: Needs complete implementation

---

## Proposed UI Redesign

### New Toolbar Layout

**Current**:
```
[🔄 Refresh] [⚡ Auto] [🔽 Load] [📊 Diff] [📝 DDL] [❓ Help]
```

**Proposed**:
```
┌─────────────────────────────────────────────────────────────────┐
│ [🔽 Load from DB] [💾 Save MMD] [📂 Open MMD]                  │
│                                                                  │
│ [🔧 Export to SQL ▼] [🔄 Translate SQL ▼] [📝 Generate ALTER] │
│                                                                  │
│ [📊 Show Diff] [⚡ Auto-Refresh] [❓ Help]                     │
└─────────────────────────────────────────────────────────────────┘
```

**New Buttons**:
- **💾 Save MMD** - Save current Mermaid to .mmd file
- **📂 Open MMD** - Load .mmd file into editor
- **🔧 Export to SQL ▼** - Dropdown with dialect options
- **🔄 Translate SQL ▼** - Dropdown for dialect translation

---

## New Dialog 1: SQL Export Dialog

### When Triggered
User clicks **"🔧 Export to SQL"**

### Dialog UI
```
┌─────────────────────────────────────────────────────────┐
│  Export Mermaid to SQL DDL                              │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Target SQL Dialect:                                    │
│  [Dropdown: ANSI SQL ▼]                                 │
│    - ANSI SQL (Standard)                                │
│    - DB2 for LUW                                        │
│    - PostgreSQL 15                                      │
│    - MySQL 8.0                                          │
│    - SQL Server 2022                                    │
│    - Oracle 21c                                         │
│                                                          │
│  ☑ Include CREATE INDEX statements                     │
│  ☑ Include foreign key constraints                     │
│  ☐ Include DROP TABLE statements (clean install)       │
│  ☑ Include IF NOT EXISTS clauses                       │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Output Options:                                  │   │
│  │ ⦿ Open in new SQL Editor tab                    │   │
│  │ ○ Save to file                                   │   │
│  │ ○ Copy to clipboard                              │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  Connection for new tab:                                │
│  ⦿ Use current connection (FKKTOTST)                   │
│  ○ Select different connection: [Dropdown ▼]          │
│  ○ No connection (read-only editor)                    │
│                                                          │
├─────────────────────────────────────────────────────────┤
│              [Generate SQL]  [Cancel]                    │
└─────────────────────────────────────────────────────────┘
```

### What Happens When User Clicks "Generate SQL"

**Option 1: Open in new SQL Editor tab** (preferred)
```csharp
// Generate SQL from Mermaid
var sqlDdl = await _sqlMermaidService.ConvertMermaidToSqlAsync(
    currentMermaid, 
    selectedDialect);

// Create new ConnectionTabControl
var newTab = new ConnectionTabControl(selectedConnection);
await newTab.OpenConnectionAsync();

// Set SQL in editor
newTab.SetSqlEditorText(sqlDdl);

// Add tab to MainWindow
MainWindow.AddNewTab(newTab, $"Generated SQL - {selectedDialect}");

// Switch to new tab
MainWindow.SelectTab(newTab);
```

**Result**: User sees SQL in a new editor tab, can execute it, modify it, or save it.

---

## New Dialog 2: SQL Dialect Translation Dialog

### When Triggered
User clicks **"🔄 Translate SQL"**

### Dialog UI
```
┌─────────────────────────────────────────────────────────┐
│  Translate SQL Between Dialects                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Source SQL:                                            │
│  ⦿ Use current Mermaid diagram                         │
│  ○ Load from file: [Browse...]                         │
│                                                          │
│  From Dialect:                                          │
│  [Dropdown: DB2 for LUW ▼] (auto-detected)             │
│                                                          │
│  To Dialect:                                            │
│  [Dropdown: PostgreSQL 15 ▼]                            │
│    - PostgreSQL 15                                      │
│    - MySQL 8.0                                          │
│    - SQL Server 2022                                    │
│    - Oracle 21c                                         │
│    - ANSI SQL                                           │
│                                                          │
│  Translation Options:                                   │
│  ☑ Convert data types                                  │
│  ☑ Translate built-in functions                        │
│  ☑ Convert system catalog queries                      │
│  ☐ Include compatibility comments                      │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Output Options:                                  │   │
│  │ ⦿ Open in new SQL Editor tab                    │   │
│  │ ○ Save to file                                   │   │
│  │ ○ Replace current Mermaid                        │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  Target Connection (for new tab):                       │
│  ⦿ Create new connection profile                       │
│  ○ Use existing: [Dropdown: PostgreSQL_DEV ▼]         │
│  ○ No connection (read-only)                           │
│                                                          │
├─────────────────────────────────────────────────────────┤
│              [Translate]  [Cancel]                       │
└─────────────────────────────────────────────────────────┘
```

### Use Case Example

**Scenario**: User has DB2 database, wants to migrate to PostgreSQL

1. User loads DB2 schema into Mermaid Designer
2. User clicks "🔄 Translate SQL"
3. Selects: From DB2 → To PostgreSQL
4. Clicks "Translate"
5. **New tab opens** with PostgreSQL DDL
6. User can:
   - Create new PostgreSQL connection
   - Execute DDL to create schema
   - Compare differences
   - Save for later

---

## New Dialog 3: Enhanced ALTER Statement Review Dialog

### Current State
AlterStatementReviewDialog is good, but can be enhanced.

### Proposed Enhancements

**Add "Execute Target" Options**:
```
┌─────────────────────────────────────────────────────────┐
│  Review and Execute ALTER Statements                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ⚠️ Review ALTER Statements Before Executing            │
│                                                          │
│  5 ALTER statements generated  •  5 selected            │
│                                                          │
│  [List of ALTER statements with checkboxes...]          │
│                                                          │
│  Execute Target:                                        │
│  ⦿ Current connection (FKKTOTST - DB2)                 │
│  ○ Different connection: [Dropdown ▼]                  │
│  ○ Open in new SQL Editor tab (review first)           │
│  ○ Save to migration script file                       │
│                                                          │
│  After Execution:                                       │
│  ☑ Reload Mermaid diagram from database                │
│  ☑ Create backup before executing                      │
│  ☐ Log all changes to audit table                      │
│                                                          │
├─────────────────────────────────────────────────────────┤
│  [📋 Copy All] [📋 Copy Selected] [💾 Save to File]   │
│                          [▶️ Execute] [Cancel]          │
└─────────────────────────────────────────────────────────┘
```

**New Option: "Open in SQL Editor"**
- Instead of executing immediately
- User can review, test with EXPLAIN, etc.
- Execute when ready

---

## New Feature: Connection Selector for SQL Operations

### Problem
When generating SQL for different database types, user needs to:
1. Have connection profiles for each database
2. Select which connection to use
3. Execute SQL on the correct target

### Solution: Connection Type Selector Dialog

```
┌─────────────────────────────────────────────────────────┐
│  Select Target Connection                               │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  The generated SQL is for: PostgreSQL 15                │
│                                                          │
│  Choose connection profile:                             │
│                                                          │
│  ⦿ Create new PostgreSQL connection                    │
│    Server: [localhost_______________]                   │
│    Port:   [5432]                                       │
│    Database: [mydb________________]                     │
│    User:     [postgres_____________]                    │
│    [Test Connection]                                    │
│                                                          │
│  ○ Use existing connection:                            │
│    [Dropdown: PostgreSQL_DEV ▼]                        │
│      - PostgreSQL_DEV (localhost:5432)                 │
│      - PostgreSQL_TEST (testdb:5432)                   │
│                                                          │
│  ○ No connection (open in read-only editor)            │
│                                                          │
├─────────────────────────────────────────────────────────┤
│                    [Connect]  [Cancel]                   │
└─────────────────────────────────────────────────────────┘
```

---

## Integration with MainWindow Tab System

### Current Tab System
```
[Tab: FKKTOTST @ t-no1inltst-db] [Tab: BASISPRD @ p-no1fkmprd-db]
```

### Enhanced Tab System with Metadata

Each tab should know:
- Connection profile
- Database type (DB2, PostgreSQL, etc.)
- SQL dialect
- Read-only vs read-write
- Source (manual, generated from Mermaid, translated, etc.)

### Tab Headers with Icons

```
[🗄️ FKKTOTST - DB2] [📊 Mermaid - FKKTOTST] [🔄 PostgreSQL DDL] [📝 Migration Script]
```

**Tab Types**:
- 🗄️ Regular connection tab
- 📊 Mermaid Designer tab
- 🔄 Translated SQL (read-only by default)
- 📝 Generated migration script

---

## Workflow Example 1: DB2 → PostgreSQL Migration

**User Story**: "I want to migrate my DB2 schema to PostgreSQL"

**Steps**:
1. User connects to DB2 (FKKTOTST)
2. User opens Mermaid Designer
3. User clicks "🔽 Load from DB" → selects 3 tables
4. Mermaid diagram appears
5. User clicks "🔧 Export to SQL ▼" → selects "PostgreSQL 15"
6. **SqlExportDialog** appears:
   - Dialect: PostgreSQL 15
   - Output: "Open in new SQL Editor tab"
   - Connection: "Create new connection"
7. User fills in PostgreSQL connection details
8. User clicks "Generate SQL"
9. **New tab opens**: "🔄 PostgreSQL DDL"
   - Contains CREATE TABLE statements in PostgreSQL syntax
   - Connected to new PostgreSQL server
10. User can:
    - Review SQL
    - Execute (creates tables in PostgreSQL)
    - Modify as needed
    - Save to file

**Result**: User has successfully migrated schema to PostgreSQL!

---

## Workflow Example 2: Schema Evolution (ALTER Generation)

**User Story**: "I need to add columns to my existing tables"

**Steps**:
1. User opens Mermaid Designer with existing diagram
2. User clicks "📊 Show Diff" → captures baseline
3. User adds 2 columns in Mermaid editor
4. User clicks "📊 Show Diff" again → sees changes highlighted
5. User clicks "📝 Generate ALTER"
6. **AlterStatementReviewDialog** appears:
   - Shows 2 ALTER TABLE ADD COLUMN statements
   - Execute Target: "Current connection (FKKTOTST)"
   - Option: "Open in SQL Editor tab" selected
7. User clicks "Execute"
8. **New tab opens**: "📝 Migration Script - FKKTOTST"
   - Contains ALTER statements
   - Connected to FKKTOTST
9. User reviews, then executes F5
10. Schema updated!
11. Dialog offers: "Reload Mermaid from database?"
12. User clicks "Yes" → diagram refreshes with new columns

**Result**: User safely applied schema changes!

---

## Workflow Example 3: Multi-Database Development

**User Story**: "I develop on PostgreSQL but deploy to DB2"

**Steps**:
1. User creates schema in Mermaid Designer
2. User clicks "🔧 Export to SQL ▼" → "PostgreSQL 15"
3. New tab opens with PostgreSQL DDL
4. User connects to PostgreSQL dev database
5. User executes DDL (creates tables)
6. User develops application...
7. **When ready for production**:
8. User goes back to Mermaid tab
9. User clicks "🔧 Export to SQL ▼" → "DB2 for LUW"
10. New tab opens with DB2 DDL
11. User connects to production DB2 server
12. User executes DDL (creates tables in production)

**Result**: Same schema in two different databases!

---

## Implementation Priority

### Phase 1: Core Dialogs (2-3 hours)
1. **SqlExportDialog.xaml** (~100 lines)
   - Dialect dropdown
   - Output options (new tab, file, clipboard)
   - Connection selector
2. **Enhance AlterStatementReviewDialog** (~50 lines)
   - Add "Open in Editor" option
   - Add connection selector
3. **Wire up to toolbar buttons** (~50 lines)

### Phase 2: Tab Integration (1-2 hours)
4. **Add "Open SQL in New Tab" method to MainWindow** (~100 lines)
   - Create new ConnectionTabControl
   - Set SQL content
   - Add to tab list
   - Switch to new tab
5. **Add tab metadata** (tab type, source, dialect) (~50 lines)

### Phase 3: Dialect Translation (2-3 hours)
6. **SqlDialectTranslationDialog.xaml** (~120 lines)
   - From/To dialect dropdowns
   - Translation options
   - Output options
7. **Wire up "Translate SQL" button** (~50 lines)

### Phase 4: Polish (1-2 hours)
8. **Add tab icons** (differentiate tab types)
9. **Add keyboard shortcuts** (Ctrl+Shift+E for export, etc.)
10. **Add tooltips** (explain each button)
11. **Update help panel** (document new workflows)

**Total Estimated Time**: 6-10 hours of development

---

## CLI Test Plan (Revised)

### Test 1: DB → Mermaid (File I/O)
```powershell
# Input: text file with table names
# Output: .mmd file
DbExplorer.exe --profile FKKTOTST \
  --db-to-mermaid \
  --infile test_tables_input.txt \
  --outfile test1_output.mmd

# Verify: test1_output.mmd contains valid Mermaid syntax
```

### Test 2: Mermaid → SQL
```powershell
# Input: .mmd file
# Output: .sql file with CREATE TABLE statements
DbExplorer.exe \
  --mermaid-to-sql \
  --infile test1_output.mmd \
  --dialect ANSI \
  --outfile test2_output.sql

# Verify: test2_output.sql contains valid SQL DDL
```

### Test 3: Mermaid Diff → ALTER
```powershell
# Input: original.mmd + modified.mmd
# Output: .sql file with ALTER statements
DbExplorer.exe \
  --mermaid-diff-to-alter \
  --original test1_output.mmd \
  --modified test3_modified.mmd \
  --outfile test3_alter.sql

# Verify: test3_alter.sql contains ALTER TABLE statements
```

### Test 4: SQL Dialect Translation
```powershell
# Input: DB2 SQL
# Output: PostgreSQL SQL
DbExplorer.exe \
  --translate-sql \
  --infile test2_output.sql \
  --from-dialect DB2 \
  --to-dialect PostgreSQL \
  --outfile test4_postgres.sql

# Verify: test4_postgres.sql uses PostgreSQL syntax
```

**These CLI tests drive the UI redesign!**

---

## Benefits of This Redesign

### For Users
✅ **Clear workflows** for all 4 functionalities  
✅ **Integrated experience** - no need for external editors  
✅ **Multi-database support** - easy migration between DB types  
✅ **Safe schema changes** - review before executing  
✅ **Professional tooling** - comparable to DBeaver, DataGrip

### For Development
✅ **CLI testing validates UI** - tests inform design  
✅ **Reusable dialogs** - same patterns across features  
✅ **Modular architecture** - easy to add new dialects  
✅ **Clear separation** - UI ↔ Services ↔ SqlMermaidErdTools

---

## Conclusion

The CLI tests will reveal:
1. What file formats are needed (`.mmd`, `.sql`)
2. What parameters are required (dialect, connection, options)
3. What workflows make sense (export → new tab → execute)
4. What error handling is needed (invalid Mermaid, connection failures)

The UI redesign provides:
1. **Proper dialogs** for all 4 functionalities
2. **Tab integration** for SQL output
3. **Connection management** for multi-database work
4. **Professional UX** comparable to commercial tools

**Next Step**: Implement CLI file I/O (~90 lines) → Run tests → Use results to build dialogs

---

**Status**: Redesign proposal complete, ready for implementation

