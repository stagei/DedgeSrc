# Mermaid Designer - Complete Workflow Design

## Workflow 1: Load Tables from DB → Generate Mermaid ERD

### User Journey:
1. User clicks **"🔽 Load from DB"** button
2. **SchemaTableSelectionDialog** opens
3. User selects tables (can filter, select all, clear all)
4. User clicks **"Generate Diagram"**
5. **System generates DDL** including:
   - CREATE TABLE statements
   - PRIMARY KEY constraints
   - FOREIGN KEY constraints  
   - CREATE INDEX statements ⭐ (ADD THIS)
6. **System converts DDL → Mermaid** using SqlMermaidErdTools
7. Mermaid code appears in editor (left pane)
8. Rendered diagram appears in preview (right pane)
9. **System stores this as "Original" baseline** for diff comparison

### What Happens Behind the Scenes:
```
User Selection → SchemaTableSelectionDialog
               ↓
[Selected Tables List]
               ↓
GenerateDdlFromDb2TablesAsync()
  - For each table:
    - Get columns (SYSCAT.COLUMNS + SYSCAT.KEYCOLUSE)
    - Generate CREATE TABLE with PKs
    - Get foreign keys (SYSCAT.REFERENCES)
    - Generate ALTER TABLE ... ADD CONSTRAINT FK
    - Get indexes (SYSCAT.INDEXES) ⭐ NEW
    - Generate CREATE INDEX statements ⭐ NEW
               ↓
[Complete DDL with FKs and Indexes]
               ↓
SqlMermaidErdTools.ToMermaidAsync(ddl)
               ↓
[Mermaid ERD Code]
               ↓
Display in editor + Store as _originalMermaid
```

---

## Workflow 2: User Modifies Mermaid → Generate ALTER Statements

### User Journey:
1. User has loaded Mermaid diagram from DB (Workflow 1)
2. User modifies the Mermaid code in editor:
   - Adds a new column to a table
   - Removes a column
   - Changes data type
   - Adds a new table
   - Adds/removes foreign key relationship
3. User clicks **"📊 Show Diff"** button
4. **Diff Panel** (bottom) shows color-coded changes:
   - 🟢 Green: Added columns/tables
   - 🔴 Red: Removed columns/tables
   - 🟡 Yellow: Modified columns
5. User reviews changes
6. User clicks **"📝 Generate ALTER"** button (new button!)
7. **AlterStatementReviewDialog** opens showing:
   - List of ALTER TABLE statements
   - Preview of each statement
   - Checkboxes to enable/disable specific statements
   - **"Execute Selected"** button
   - **"Copy to Clipboard"** button
   - **"Save to File"** button
8. User can:
   - Review each ALTER statement
   - Deselect dangerous changes
   - Execute directly in the database
   - Copy for manual execution
   - Save to migration script file

### What Happens Behind the Scenes:
```
[Original Mermaid] + [Modified Mermaid]
               ↓
SchemaDiffAnalyzerService.AnalyzeDiff()
  - Parse both Mermaid diagrams
  - Detect added/removed/modified tables
  - Detect added/removed/modified columns
  - Detect FK relationship changes
               ↓
[SchemaDiff object with all changes]
               ↓
Display in Diff Panel (color-coded)
               ↓
User clicks "Generate ALTER"
               ↓
SqlMermaidErdTools.GenerateDiffAlterStatementsAsync()
  - Input: originalMermaid, modifiedMermaid, SqlDialect
  - Output: ALTER TABLE statements
               ↓
[List of ALTER statements]
               ↓
AlterStatementReviewDialog
  - Shows all statements with checkboxes
  - User selects which to execute
  - Executes via connectionManager.ExecuteNonQueryAsync()
```

---

## Workflow 3: Mermaid → SQL (Export to Different Database)

### User Journey:
1. User has Mermaid diagram (from DB or manually created)
2. User clicks **"🔧 Mermaid → SQL"** button
3. **Dialect Selection Dialog** appears:
   - Target Database: [Dropdown: PostgreSQL, MySQL, SQL Server, Oracle, etc.]
   - Include DROP statements: [Checkbox]
   - Include IF NOT EXISTS: [Checkbox]
4. User selects options and clicks **"Generate"**
5. **SQL DDL Preview Dialog** opens:
   - Shows generated SQL DDL
   - Syntax highlighted
   - **"Copy to Clipboard"** button
   - **"Save to File"** button
   - **"Close"** button

---

## UI Components Needed

### 1. Enhanced Toolbar (MermaidDesigner.html)
```
Current:
[🔄 Refresh] [⚡ Auto-Refresh] [🔽 Load from DB] [📊 Show Diff] [📝 Generate DDL]

New:
[🔄 Refresh] [⚡ Auto] [🔽 Load] [📊 Diff] [📝 ALTER] [🔧 Export SQL] [💾 Save] [❓ Help]
```

### 2. New Dialog: AlterStatementReviewDialog.xaml
- Window title: "Review and Execute ALTER Statements"
- Top section: Warning message about executing ALTERs
- Middle section: CheckedListBox with ALTER statements
- Bottom section: Buttons
  - [Execute Selected] [Copy All] [Copy Selected] [Save to File] [Cancel]

### 3. Enhanced Diff Panel (already exists, just style)
- Show change count: "5 changes detected"
- Color-coded items:
  - Added: Green background, + icon
  - Removed: Red background, - icon
  - Modified: Yellow background, ± icon

---

## Implementation Plan

### Phase 1: Complete DDL Generation ⭐
- [ ] Add `GenerateIndexDdlAsync()` method to SqlMermaidIntegrationService
- [ ] Query SYSCAT.INDEXES for CREATE INDEX statements
- [ ] Include indexes in GenerateDdlFromDb2TablesAsync output
- [ ] Test: Verify indexes appear in generated DDL

### Phase 2: Implement ALTER Statement Dialog ⭐
- [ ] Create `Dialogs/AlterStatementReviewDialog.xaml`
- [ ] Create `Dialogs/AlterStatementReviewDialog.xaml.cs`
- [ ] Add CheckedListBox for ALTER statements
- [ ] Implement Execute Selected functionality
- [ ] Implement Copy to Clipboard
- [ ] Implement Save to File (.sql)

### Phase 3: Enhance Diff Workflow ⭐
- [ ] Store _originalMermaid when user loads from DB
- [ ] Update "Show Diff" button behavior:
  - First click: Capture baseline
  - Second click: Show diff panel
- [ ] Add "Generate ALTER" button (replaces "Generate DDL")
- [ ] Connect to AlterStatementReviewDialog

### Phase 4: Add Mermaid → SQL Export ⭐
- [ ] Create `Dialogs/SqlExportDialog.xaml` (dialect selection)
- [ ] Create `Dialogs/SqlPreviewDialog.xaml` (show generated SQL)
- [ ] Wire up "Export SQL" button
- [ ] Implement ConvertMermaidToSqlAsync call
- [ ] Add syntax highlighting for SQL preview

### Phase 5: Update Help Documentation
- [ ] Update help panel in MermaidDesigner.html
- [ ] Add workflow diagrams
- [ ] Add keyboard shortcuts reference
- [ ] Add troubleshooting tips

---

## User Experience Improvements

### Clear Status Messages
- "Loaded 5 tables from database"
- "Baseline captured - make changes and click Diff again"
- "3 changes detected - click Generate ALTER to create migration"
- "5 ALTER statements generated - review before executing"
- "Executed 5 ALTER statements successfully"

### Confirmation Dialogs
- Before executing ALTER: "Execute 5 ALTER statements in FKKTOTST database?"
- After execution: "Successfully executed 5 statements. Refresh diagram?"

### Error Handling
- If Python script fails: Show friendly message + link to error dump
- If ALTER fails: Show which statement failed, allow retry
- If no changes detected: "No schema changes detected"

---

## Testing Checklist

### Manual Test: Full Workflow
1. [ ] Connect to FKKTOTST
2. [ ] Open Mermaid Designer
3. [ ] Load from DB (select 3 tables)
4. [ ] Verify Mermaid appears with tables, columns, FKs, indexes
5. [ ] Verify diagram renders visually
6. [ ] Modify Mermaid (add column)
7. [ ] Click "Show Diff" - verify baseline captured
8. [ ] Click "Show Diff" again - verify changes shown in green
9. [ ] Click "Generate ALTER"
10. [ ] Review ALTER statements in dialog
11. [ ] Verify ALTER TABLE ADD COLUMN statement is correct
12. [ ] Execute ALTER statement (⚠️ use test table!)
13. [ ] Verify table structure changed in DB
14. [ ] Reload from DB - verify new column appears
15. [ ] Export to PostgreSQL SQL
16. [ ] Verify generated SQL is valid PostgreSQL syntax

---

## Success Criteria

✅ **User can:**
1. Select tables from their database
2. Generate accurate Mermaid ERD (with FKs and indexes)
3. Modify the Mermaid diagram visually
4. See a clear diff of what changed
5. Generate ALTER statements automatically
6. Review ALTER statements before executing
7. Execute selected ALTER statements safely
8. Export Mermaid to SQL for other databases
9. Save Mermaid diagrams and reload later

✅ **System provides:**
1. Clear status messages at each step
2. Confirmation dialogs for dangerous operations
3. Error handling with helpful messages
4. Undo/redo for diagram edits
5. Auto-save of work in progress
6. Comprehensive help documentation

---

## Next Steps

1. **Implement Phase 1** (indexes in DDL)
2. **Implement Phase 2** (ALTER review dialog)
3. **Test manually** with real database
4. **Iterate based on findings**
5. **Complete remaining phases**

This design ensures users have a complete, logical workflow for:
- **DB → Mermaid** (with full DDL including indexes)
- **Mermaid changes → ALTER statements** (with safe review/execution)
- **Mermaid → SQL** (for exporting to other databases)

