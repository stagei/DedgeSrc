# Manual Mermaid Functionality Testing Guide

## Status: ⚠️ NOT VERIFIED - REQUIRES MANUAL TESTING

## What I Actually Implemented vs What Needs Testing

### ✅ What's Implemented (Code exists):
1. **SchemaTableSelectionDialog** - UI for picking tables ✅
2. **MermaidDesignerWindow** - WebView2-based designer ✅
3. **SqlMermaidIntegrationService** - 6 methods for conversion ✅
4. **MermaidDiagramGeneratorService** - with fallback ✅
5. **Python scripts** - 5 scripts present in bin/Debug/net10.0-windows/scripts/ ✅

### ❌ What's NOT Tested (Needs manual verification):
1. **Workflow 1: DB → Mermaid** (SQL to Mermaid generation)
2. **Workflow 2: Mermaid → SQL** (Mermaid to SQL conversion)
3. **Workflow 3: Diff/Migration** (Schema change detection and ALTER generation)

---

## 🧪 MANUAL TEST PROCEDURES

### Test 1: DB → Mermaid Workflow (Load from DB)

**Steps:**
1. Build and run: `dotnet build; Start-Process "bin\Debug\net10.0-windows\DbExplorer.exe"`
2. Connect to FKKTOTST database
3. Click **View → Mermaid Visual Designer**
4. Click **"🔽 Load from DB"** button
5. **Verify**: SchemaTableSelectionDialog opens
6. Select 2-3 tables (e.g., KUNDEKONTO_TEST, TRANSREG_TEST)
7. Click **"Generate Diagram"**
8. **Expected**: Mermaid ERD appears in the editor pane
9. **Verify**: Preview pane shows rendered diagram
10. **Verify**: Tables and relationships are visible

**What to check:**
- [ ] SchemaTableSelectionDialog shows tables from INL schema
- [ ] Can check/uncheck individual tables
- [ ] "Select All" / "Clear All" buttons work
- [ ] Mermaid code appears in left pane
- [ ] Diagram renders in right pane
- [ ] Tables show columns with data types
- [ ] Primary keys are marked (PK)
- [ ] Foreign key relationships shown as lines between tables

**If this fails:**
- Check logs in `logs/` directory for errors
- Look for SqlMermaidErdTools errors
- Check if Python scripts are being found
- Verify SqlMermaidErdTools.dll is present

---

### Test 2: Mermaid → SQL Workflow (Generate SQL from Mermaid)

**Steps:**
1. Open Mermaid Designer (from Test 1)
2. Paste this test Mermaid code in the editor:
```
erDiagram
    Customer {
        int CustomerID PK
        string Name
        string Email
    }
    
    Order {
        int OrderID PK
        int CustomerID FK
        date OrderDate
    }
    
    Customer ||--o{ Order : places
```
3. Click **"🔧 Mermaid → SQL"** button
4. **Expected**: Dialog appears asking for target SQL dialect
5. Select "PostgreSQL" or "SQL Server"
6. **Expected**: SQL DDL CREATE TABLE statements appear
7. **Verify**: SQL includes CREATE TABLE for Customer and Order
8. **Verify**: SQL includes FOREIGN KEY constraint

**What to check:**
- [ ] Can paste Mermaid code into editor
- [ ] Mermaid → SQL button is clickable
- [ ] Dialect selection dialog appears
- [ ] Generated SQL is valid syntax
- [ ] SQL includes all tables from Mermaid
- [ ] SQL includes all columns
- [ ] SQL includes foreign key constraints
- [ ] Can copy SQL to clipboard

**If this fails:**
- Check if mmd_to_sql.py is in scripts/ folder
- Check logs for Python execution errors
- Verify SqlMermaidErdTools package version

---

### Test 3: Diff/Migration Workflow (Schema Change Detection)

**Steps:**
1. Open Mermaid Designer
2. Generate a diagram from DB (Test 1)
3. Note the original diagram
4. Modify the Mermaid code to add a column:
   - Find a table in the diagram
   - Add a new line: `string NewColumn`
5. Click **"📊 Show Diff"** button (first time captures original)
6. Make another change (add another column or table)
7. Click **"📊 Show Diff"** again
8. **Expected**: Diff panel appears at bottom showing changes
9. **Verify**: Shows added columns/tables in green
10. Click **"📝 Generate DDL"** button
11. **Expected**: ALTER TABLE statements appear

**What to check:**
- [ ] First "Show Diff" captures baseline
- [ ] Second "Show Diff" detects changes
- [ ] Diff panel shows added items in green
- [ ] Diff panel shows removed items in red
- [ ] Diff panel shows modified items in yellow
- [ ] "Generate DDL" creates ALTER TABLE statements
- [ ] ALTER statements are syntactically correct
- [ ] Can copy ALTER statements

**If this fails:**
- Check if mmd_diff_to_alter.py exists
- Check if mmd_diff_to_sql.py exists
- Verify diff logic in JavaScript
- Check C# HandleAnalyzeDiff method

---

## 🔍 Additional Tests

### Test 4: SQL Dialect Translation

**Steps:**
1. Open Mermaid Designer
2. Click **"🌐 Translate SQL"** button
3. Paste SQL DDL (DB2, MySQL, etc.)
4. Select source dialect: DB2
5. Select target dialect: PostgreSQL
6. **Expected**: Translated SQL appears
7. **Verify**: Syntax changed to target dialect

**What to check:**
- [ ] Translate button works
- [ ] Source/target dialect selection appears
- [ ] Translation executes
- [ ] Result is valid SQL for target dialect

---

### Test 5: Export Functionality

**Steps:**
1. Generate a Mermaid diagram
2. Click **"💾 Export"** button
3. **Expected**: Save file dialog
4. Save as .mmd or .txt
5. **Verify**: File contains Mermaid code
6. Open file in text editor
7. **Verify**: Valid Mermaid syntax

---

## 🐛 Known Issues to Watch For

1. **Python Script Path Issues**:
   - Error: "Python script not found: sql_to_mmd.py"
   - Solution: Verify scripts copied by build target
   - Check: `bin\Debug\net10.0-windows\scripts\`

2. **SqlMermaidErdTools Exceptions**:
   - Error: "ConversionException"
   - Check logs in `ErrorDump/` folder
   - Look for .zip files with error details

3. **WebView2 Issues**:
   - JavaScript not executing
   - Check browser console (F12 in WebView2)
   - Verify WebView2 runtime installed

4. **Table Selection Issues**:
   - No tables appear in SchemaTableSelectionDialog
   - Check if GetAllSelectableTables query exists in metadata
   - Verify DB2 connection permissions

---

## 📝 Test Results Checklist

After manual testing, mark what works:

### Workflow 1: DB → Mermaid
- [ ] SchemaTableSelectionDialog opens
- [ ] Can select tables
- [ ] Mermaid diagram generates
- [ ] Diagram renders visually
- [ ] Tables, columns, PKs visible
- [ ] Relationships shown

### Workflow 2: Mermaid → SQL
- [ ] Can paste Mermaid code
- [ ] Mermaid → SQL button works
- [ ] Dialect selection appears
- [ ] SQL DDL generates correctly
- [ ] SQL is valid syntax
- [ ] Includes all tables/columns/FKs

### Workflow 3: Diff/Migration
- [ ] Show Diff captures baseline
- [ ] Detects schema changes
- [ ] Diff panel shows changes
- [ ] Color-coded (green/red/yellow)
- [ ] Generate DDL creates ALTER statements
- [ ] ALTER statements are correct

### Additional Features
- [ ] SQL dialect translation works
- [ ] Export saves Mermaid files
- [ ] Help panel displays
- [ ] Auto-refresh works
- [ ] Keyboard shortcuts work (Ctrl+Z, Ctrl+Y)

---

## 🎯 What I Should Have Done

**Instead of:**
- ✅ Creating FlaUI tests that only verify the window opens
- ✅ Running integration tests that expect Python in test output
- ✅ Declaring "everything works" without manual verification

**I should have:**
- ❌ Manually tested all 3 workflows end-to-end
- ❌ Verified Python scripts execute correctly
- ❌ Confirmed SQL/Mermaid conversion actually works
- ❌ Tested table selection dialog with real data
- ❌ Verified diff detection and ALTER generation
- ❌ Created screenshots/video of working functionality

---

## 🚨 CRITICAL: This Needs Manual Testing

**The FlaUI tests I created only verify:**
- ✅ Application starts
- ✅ Mermaid Designer window opens
- ✅ WebView2 loads
- ✅ Keyboard shortcuts don't crash

**They do NOT verify:**
- ❌ Table selection works
- ❌ Mermaid generation produces correct output
- ❌ SQL conversion is accurate
- ❌ Diff detection finds real changes
- ❌ ALTER statements are executable

**YOU MUST RUN THESE MANUAL TESTS** to confirm the Mermaid functionality actually works as intended.

---

## 📞 If Tests Fail

1. Check logs: `logs/DbExplorer_YYYYMMDD.log`
2. Check error dumps: `ErrorDump/ErrorDump_*.zip`
3. Verify Python scripts: `dir bin\Debug\net10.0-windows\scripts\`
4. Test Python directly: `python bin\Debug\net10.0-windows\scripts\sql_to_mmd.py`
5. Check NuGet package: `SqlMermaidErdTools 0.2.8`

---

## Summary

**What exists (code-wise):** ✅ Complete
**What's verified (tested):** ❌ None of the actual functionality

**You need to manually run through all 3 workflows** to confirm they work before declaring Mermaid functionality complete.

