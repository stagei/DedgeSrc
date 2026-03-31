# Database Comparison Feature & UI Improvements - Implementation Plan

**Date**: December 14, 2025  
**Status**: 📋 **PLANNING** - Awaiting clarification on unclear elements  
**Framework**: .NET 10 WPF

---

## 🎯 Overview

This document outlines the implementation plan for:
1. **Visual Design Improvements** (font sizes, dark/light mode polish)
2. **Object Browser Enhancements** (async loading, font adjustments)
3. **Package Relationship Improvements** (bidirectional dependencies)
4. **Database Comparison Feature** (NEW - compare objects across databases)

---

## 📊 Current State Analysis

### 1. Object Browser Font Size
**Current State**: TreeView items use `FontSize="13"` (line 91, ConnectionTabControl.xaml)

**Finding**: ✅ Font size is reasonable (13pt), but could be reduced to 11-12pt for better density

**Proposed Change**:
```xml
<!-- Current -->
<Setter Property="FontSize" Value="13"/>

<!-- Proposed -->
<Setter Property="FontSize" Value="11"/>  <!-- or 12 for medium density -->
```

### 2. Object Browser Population Timing
**Current Behavior**: Based on code analysis:
- ✅ Connection is established **synchronously** with progress dialog
- ✅ Metadata collection starts **asynchronously in background** after connection
- ⚠️ Object browser is **NOT populated immediately** - metadata loads in background

**Code Evidence** (ConnectionTabControl.xaml.cs, line 754):
```csharp
_ = Task.Run(async () =>
{
    try
    {
        Logger.Info("Starting background metadata collection");
        var metadataService = new DB2MetadataService();
        await metadataService.CollectMetadataAsync(_connectionManager, _connection.Name);
        Logger.Info("Background metadata collection completed");
    }
    catch (Exception ex) { ... }
});
```

**Finding**: ✅ Object browser loads **asynchronously** in background - user can start working immediately

### 3. Package Details Dialog - Dependencies

**Current State Analysis**:

#### What PackageDetailsDialog Shows:
✅ **Properties Tab**:
- Package name, schema, owner
- Bound by, isolation level
- Create time, remarks

✅ **SQL Statements Tab**:
- All SQL statements in the package
- Statement numbers, types, preview
- View full statement, add to editor

#### ❌ **MISSING**: What Tables/Views/Functions the Package USES
Currently does **NOT** show:
- Which tables are referenced in the package SQL
- Which views are referenced
- Which functions/procedures are called
- Dependency graph showing package → objects

#### Reverse Relationship (Table → Package)
✅ **EXISTS**: TableDetailsDialog shows "Used By Packages" tab
- Shows which packages reference the table
- Implemented via `GetReferencingPackagesAsync()`

**Conclusion**: **One-directional only** - Tables know about packages, but packages don't show their dependencies

---

## 🎨 Visual Design Improvements

### 1. Font Size Adjustments

**Object Browser (TreeView)**:
```xml
<!-- Current: FontSize="13" -->
<!-- Proposed Options -->
<Setter Property="FontSize" Value="11"/>  <!-- Compact (recommended) -->
<Setter Property="FontSize" Value="12"/>  <!-- Medium density -->
```

**Benefits**:
- More objects visible without scrolling
- Better information density
- Matches VS Code/Visual Studio style

### 2. Dark Mode & Light Mode Polish

**Current Issues to Address**:
- ⚠️ Ensure all custom controls respect theme
- ⚠️ Check DataGrid alternating row colors in both modes
- ⚠️ Verify syntax highlighting colors in both modes

**Proposed Changes**:
```xml
<!-- Ensure theme-aware colors throughout -->
<Style TargetType="TreeViewItem">
    <Setter Property="Background" Value="{DynamicResource SystemControlBackgroundAltHighBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource SystemControlForegroundBaseHighBrush}"/>
    <!-- ... -->
</Style>
```

### 3. Object Browser Visual Enhancements

**Proposed Improvements**:
1. **Add loading indicator** during metadata collection
2. **Add object count** in status bar (e.g., "1,234 objects")
3. **Add schema grouping toggle** (flat vs hierarchical view)
4. **Add type icons** for each object type (📋 Table, 👁️ View, ⚙️ Procedure, etc.)

---

## 📦 Package Relationship Improvements

### Current State
- ✅ Tables/Views/Procedures show "Used By Packages" (reverse relationship)
- ❌ Packages do NOT show what tables/views/functions they use (forward relationship)

### Proposed Enhancement: Add "Dependencies" Tab to PackageDetailsDialog

**New Tab**: **"🔗 Dependencies"**

**Sub-Tabs**:
1. **Tables Used** - Tables referenced in package SQL
2. **Views Used** - Views referenced in package SQL
3. **Procedures Called** - Procedures called from package
4. **Functions Called** - Functions called from package

**Implementation Approach**:
```sql
-- Parse package SQL statements and extract object references
SELECT DISTINCT
    TRIM(T.TABSCHEMA) AS Schema,
    TRIM(T.TABNAME) AS TableName,
    'TABLE' AS ObjectType
FROM SYSCAT.STATEMENTS S
JOIN SYSCAT.TABLES T ON ... (need to parse SQL text)
WHERE S.PKGSCHEMA = ? AND S.PKGNAME = ?
```

**Challenge**: DB2 doesn't have built-in dependency tracking for packages
**Solution**: Parse SQL text from SYSCAT.STATEMENTS to extract object references

---

## 🔄 Database Comparison Feature (NEW)

### Concept

**Goal**: Compare the same object (table, view, function, procedure) across **multiple databases** (different connections).

**Use Cases**:
1. **Schema Drift Detection**: Compare PROD vs DEV to find differences
2. **Migration Validation**: Verify DEV changes before promoting to PROD
3. **Multi-Environment Sync**: Ensure all environments have same structure
4. **DDL Generation**: Generate ALTER statements to sync environments

### Feature Design

#### 1. **Database Comparison Dialog**

**Dialog Name**: `DatabaseComparisonDialog`

**UI Layout**:
```
╔═══════════════════════════════════════════════════════════════╗
║  Database Comparison Tool                                     ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Object to Compare: [Dropdown: Table/View/Procedure/Function]║
║  Object Name:       [INL.BILAGNR               ]  [Browse...] ║
║                                                               ║
║  ┌─ Environments to Compare ─────────────────────────────┐  ║
║  │                                                         │  ║
║  │  ☑ DEV     (FKKTOTST)   - Currently Connected         │  ║
║  │  ☑ TEST    (FKKTEST)    - Select Connection...        │  ║
║  │  ☑ PROD    (FKKPROD)    - Select Connection...        │  ║
║  │  ☐ BACKUP  (FKKBACK)    - Select Connection...        │  ║
║  │                                                         │  ║
║  │  [+ Add Environment]                                   │  ║
║  └─────────────────────────────────────────────────────────┘  ║
║                                                               ║
║  Comparison Type:                                            ║
║  ○ Structure Only (DDL comparison)                           ║
║  ○ Structure + Data (include row counts, statistics)         ║
║  ○ Source Code (for views/procedures/functions)              ║
║                                                               ║
║                                     [Cancel]  [Compare]      ║
╚═══════════════════════════════════════════════════════════════╝
```

#### 2. **Comparison Results Window**

**Dialog Name**: `DatabaseComparisonResultsDialog`

**UI Layout** (VSCode-style side-by-side comparison):
```
╔═════════════════════════════════════════════════════════════════════════╗
║  Database Comparison Results - INL.BILAGNR                              ║
╠═════════════════════════════════════════════════════════════════════════╣
║                                                                         ║
║  Environments: DEV ↔ TEST ↔ PROD                                       ║
║  Object Type: Table                                                     ║
║  Differences Found: 3                                                   ║
║                                                                         ║
║  ┌─ Comparison View ─────────────────────────────────────────────────┐ ║
║  │                                                                     │ ║
║  │  [Structure] [Source Code] [Statistics] [Differences Only]         │ ║
║  │                                                                     │ ║
║  │  ┌─ DEV (FKKTOTST) ────┬─ TEST (FKKTEST) ───┬─ PROD (FKKPROD) ──┐ │ ║
║  │  │ CREATE TABLE        │ CREATE TABLE        │ CREATE TABLE      │ │ ║
║  │  │ INL.BILAGNR (       │ INL.BILAGNR (       │ INL.BILAGNR (     │ │ ║
║  │  │   BILAGNR DECIMAL   │   BILAGNR DECIMAL   │   BILAGNR DECIMAL │ │ ║
║  │  │   BILAGDATO DATE    │   BILAGDATO DATE    │   BILAGDATO DATE  │ │ ║
║  │  │ + NEW_COL VARCHAR   │                     │                   │ │ ║  ← Difference!
║  │  │ );                  │ );                  │ );                │ │ ║
║  │  │                     │                     │                   │ │ ║
║  │  └─────────────────────┴─────────────────────┴───────────────────┘ │ ║
║  │                                                                     │ ║
║  │  Differences:                                                       │ ║
║  │  ✓ Column NEW_COL exists in DEV but missing in TEST and PROD       │ ║
║  │  ✓ Column order differs in TEST                                    │ ║
║  │  ✓ Index IX_BILAGNR missing in PROD                                │ ║
║  │                                                                     │ ║
║  └─────────────────────────────────────────────────────────────────────┘ ║
║                                                                         ║
║  Actions:                                                               ║
║  [Copy Line from DEV to TEST]  [Copy Line from DEV to PROD]           ║
║  [Generate ALTER for TEST]     [Generate ALTER for PROD]               ║
║  [Apply Source from DEV to TEST] (for views/procedures)                ║
║                                                                         ║
║                                            [Export DDL]  [Close]       ║
╚═════════════════════════════════════════════════════════════════════════╝
```

---

## 🚀 Implementation Plan

### Phase 1: UI Visual Improvements (Quick Wins)
**Estimated Time**: 1-2 hours

#### Task 1.1: Adjust Object Browser Font Size
- Reduce TreeView FontSize from 13 to 11 or 12
- Test in both dark and light modes
- Ensure readability is maintained

#### Task 1.2: Theme Consistency Audit
- Review all dialogs and panels
- Ensure all colors use `{DynamicResource ...}` 
- Test switching between dark/light modes
- Fix any hard-coded colors

#### Task 1.3: Object Browser Loading Indicator
- Add "Loading objects..." indicator when background metadata collection is running
- Update status bar with object count when complete
- Show progress for large schemas

---

### Phase 2: Package Relationship Enhancement
**Estimated Time**: 3-4 hours

#### Task 2.1: Analyze Package SQL Dependencies
**Approach**: Parse SYSCAT.STATEMENTS to extract object references

**Implementation**:
```csharp
public class PackageDependencyAnalyzer
{
    public async Task<List<ObjectReference>> AnalyzePackageDependenciesAsync(
        DB2ConnectionManager connectionManager,
        string schema,
        string packageName)
    {
        // 1. Get all SQL statements from SYSCAT.STATEMENTS
        // 2. Parse SQL text to find table/view/procedure references
        // 3. Use regex to extract: FROM, JOIN, CALL statements
        // 4. Query SYSCAT to verify objects exist
        // 5. Return structured dependency list
    }
}
```

#### Task 2.2: Add Dependencies Tab to PackageDetailsDialog
- New tab: "🔗 Dependencies"
- Sub-tabs: Tables, Views, Procedures, Functions
- DataGrid showing referenced objects
- Double-click to open object details

#### Task 2.3: Bidirectional Package Links
- Ensure tables show "Used By Packages" ✅ (already exists)
- Ensure packages show "Uses Tables/Views/Functions" ⚠️ (new)

---

### Phase 3: Database Comparison Feature (MAJOR)
**Estimated Time**: 12-16 hours

#### Task 3.1: Create DatabaseComparisonDialog

**Features**:
- Select object type (Table, View, Procedure, Function)
- Enter object name or browse
- Select 2-4 databases/connections to compare
- Choose comparison type (Structure, Source Code, Statistics)

**Connection Management**:
```csharp
public class MultiDatabaseConnectionManager
{
    private Dictionary<string, DB2ConnectionManager> _connections = new();
    
    public async Task<bool> AddConnectionAsync(string alias, ConnectionInfo connection)
    {
        var manager = new DB2ConnectionManager(connection);
        await manager.OpenAsync();
        _connections[alias] = manager;
        return true;
    }
}
```

#### Task 3.2: Implement Object Fetchers for Each Database

**For Each Database**:
```csharp
public class DatabaseObjectFetcher
{
    public async Task<TableDefinition> FetchTableDefinitionAsync(
        DB2ConnectionManager connection,
        string schema,
        string tableName)
    {
        // Fetch: Columns, data types, constraints, indexes, foreign keys
        return new TableDefinition { ... };
    }
    
    public async Task<string> FetchViewSourceAsync(...);
    public async Task<string> FetchProcedureSourceAsync(...);
    public async Task<string> FetchFunctionSourceAsync(...);
}
```

#### Task 3.3: Create Comparison Engine

**Service**: `DatabaseComparisonService`

```csharp
public class DatabaseComparisonService
{
    public ComparisonResult CompareTableStructures(
        Dictionary<string, TableDefinition> tables)
    {
        // Compare column definitions
        // Compare data types
        // Compare constraints
        // Compare indexes
        // Identify differences
        return new ComparisonResult { ... };
    }
    
    public ComparisonResult CompareSourceCode(
        Dictionary<string, string> sources)
    {
        // Line-by-line diff
        // Highlight differences
        // Generate unified diff
    }
}
```

#### Task 3.4: Create VSCode-Style Comparison View

**Component**: `DatabaseComparisonResultsDialog`

**Features**:
1. **Multi-column layout** (2-4 columns, one per database)
2. **Synchronized scrolling** across all columns
3. **Line-by-line highlighting** of differences
4. **Color coding**:
   - 🟢 Green: Line exists only in this database
   - 🔴 Red: Line missing from this database
   - 🟡 Yellow: Line differs across databases
   - ⚪ White: Line identical in all databases

5. **Interactive Actions**:
   - Select a line/column and copy to other database
   - Generate ALTER statements for selected database
   - Apply full source from one database to another

**UI Components**:
```xml
<Grid>
    <Grid.ColumnDefinitions>
        <!-- Dynamic columns based on number of databases -->
        <ColumnDefinition Width="*"/> <!-- Database 1 -->
        <ColumnDefinition Width="5"/> <!-- Splitter -->
        <ColumnDefinition Width="*"/> <!-- Database 2 -->
        <ColumnDefinition Width="5"/> <!-- Splitter -->
        <ColumnDefinition Width="*"/> <!-- Database 3 -->
    </Grid.ColumnDefinitions>
    
    <!-- Each column has a header + synchronized editor -->
    <Grid Grid.Column="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        
        <Border Grid.Row="0" Background="DarkBlue" Padding="10">
            <StackPanel>
                <TextBlock Text="DEV (FKKTOTST)" FontWeight="Bold" Foreground="White"/>
                <TextBlock Text="Connected • 15 columns" FontSize="10" Foreground="LightGray"/>
            </StackPanel>
        </Border>
        
        <avalonedit:TextEditor Grid.Row="1" 
                               Name="DevEditor"
                               IsReadOnly="True"
                               FontFamily="Consolas"
                               FontSize="12"
                               ScrollViewer.VerticalScrollBarVisibility="Auto"
                               ScrollChanged="SyncScroll_Changed"/>
    </Grid>
</Grid>
```

#### Task 3.5: Implement "Copy Line" Functionality

**Feature**: User selects a line in one database, clicks "Copy to TEST", and it:
1. Analyzes what the line represents (column definition, constraint, etc.)
2. Generates appropriate ALTER statement
3. Shows ALTER preview
4. User confirms and executes

**Example Workflow**:
```
User Action: Select line "NEW_COL VARCHAR(50)" in DEV
User Action: Click "Copy to PROD"

System: Generates ALTER statement
        ALTER TABLE INL.BILAGNR ADD COLUMN NEW_COL VARCHAR(50);

System: Shows preview in AlterStatementReviewDialog
User: Clicks "Execute"
System: Executes on PROD database
System: Refreshes comparison view
```

#### Task 3.6: Implement "Apply Source" Functionality

**For Views/Procedures/Functions**:
```
User Action: Click "Apply Source from DEV to PROD"

System: Fetches CREATE statement from DEV
System: Generates DROP + CREATE for PROD
System: Shows preview with warning
User: Confirms
System: Executes DROP IF EXISTS, then CREATE
System: Refreshes comparison view
```

**Safety Features**:
- ⚠️ Always show preview before execution
- ⚠️ Require explicit confirmation
- ⚠️ Support transaction rollback
- ⚠️ Create backup script before changes
- ⚠️ Log all changes with timestamp

---

## ❓ UNCLEAR ELEMENTS - Need User Clarification

### Question 1: Comparison UI Layout Preference

**Option A: Side-by-Side (2-3 databases)**
```
┌─ DEV ─────────┬─ TEST ────────┬─ PROD ────────┐
│ CREATE TABLE  │ CREATE TABLE  │ CREATE TABLE  │
│   COL1 INT    │   COL1 INT    │   COL1 INT    │
│ + COL2 VAR    │               │               │ ← NEW in DEV
│   COL3 DATE   │   COL3 DATE   │   COL3 DATE   │
└───────────────┴───────────────┴───────────────┘
```

**Option B: Base + Diff View (1 base, N diffs)**
```
┌─ BASE: DEV ───────────────────────────────────┐
│ CREATE TABLE INL.BILAGNR (                    │
│   COL1 INT,                                   │
│   COL2 VARCHAR(50),  ← Missing in TEST, PROD │
│   COL3 DATE                                   │
│ );                                            │
└───────────────────────────────────────────────┘

Differences in TEST:
  - Missing: COL2 VARCHAR(50)
  
Differences in PROD:
  - Missing: COL2 VARCHAR(50)
  - Different: COL3 is TIMESTAMP (not DATE)
```

**Option C: Unified Diff View**
```
  CREATE TABLE INL.BILAGNR (
    COL1 INT,
+ COL2 VARCHAR(50)         [DEV only]
- COL2 VARCHAR(100)        [TEST only]
  COL3 DATE                [All databases]
  );
```

**Which layout do you prefer?** (A, B, or C)

---

### Question 2: Line Copy Behavior

When user selects a line (e.g., column definition) and clicks "Copy to TEST":

**Option A: Generate ALTER Immediately**
- Generate ALTER TABLE ADD COLUMN ...
- Show in AlterStatementReviewDialog
- Execute if confirmed

**Option B: Add to Staging Area**
- Add to a "pending changes" list
- Allow multiple selections
- Generate batch ALTER script
- Execute all at once

**Which approach do you prefer?** (A or B)

---

### Question 3: Source Code Application

For views/procedures/functions, when applying source from one database to another:

**Option A: DROP + CREATE**
```sql
-- Drop existing
DROP VIEW IF EXISTS INL.MY_VIEW;

-- Create from source database
CREATE VIEW INL.MY_VIEW AS
  SELECT ... (from DEV)
```

**Option B: CREATE OR REPLACE** (if DB2 supports it)
```sql
CREATE OR REPLACE VIEW INL.MY_VIEW AS
  SELECT ... (from DEV)
```

**Option C: Smart ALTER (for tables only)**
```sql
-- For each difference, generate appropriate ALTER
ALTER TABLE INL.BILAGNR ADD COLUMN NEW_COL VARCHAR(50);
ALTER TABLE INL.BILAGNR DROP COLUMN OLD_COL;
ALTER TABLE INL.BILAGNR ALTER COLUMN EXISTING_COL SET DATA TYPE VARCHAR(100);
```

**Which approach for views/procedures?** (A or B)
**For tables?** (Always C - ALTER based, not DROP+CREATE)

---

### Question 4: Multi-Database Connection Management

**Option A: Reuse Existing Connections**
- Use already-open connections from tabs
- If database not connected, open new connection
- Keep connections alive during comparison

**Option B: Fresh Connections for Comparison**
- Always open new dedicated connections for comparison
- Close when comparison complete
- Ensure isolation from user's active work

**Which approach?** (A or B)

---

### Question 5: Comparison Scope

**For Tables**:
- ✅ Column definitions (names, types, lengths, nullability)
- ✅ Primary keys
- ✅ Foreign keys
- ✅ Indexes
- ❓ Triggers on the table?
- ❓ Table comments/remarks?
- ❓ Row counts and statistics?

**For Views/Procedures/Functions**:
- ✅ Full source code (CREATE statement)
- ❓ Dependencies (what they reference)?
- ❓ Comments/remarks?
- ❓ Permissions/grants?

**What level of detail do you want?** (Basic or Comprehensive)

---

### Question 6: Diff Algorithm

**Option A: Simple Line-by-Line Diff**
- Compare each line as text
- Highlight additions/deletions
- Fast but less intelligent

**Option B: Structural Diff** (Smarter)
- Parse DDL into structure (AST)
- Compare columns as objects
- Detect renames, type changes, moves
- Slower but more accurate

**Which algorithm?** (A for speed, B for accuracy)

---

### Question 7: Integration Point

Where should Database Comparison be accessible?

**Option A: View Menu** (alongside Migration Assistant)
```
View
  ├─ ...
  ├─ Migration Assistant...
  ├─ Mermaid Visual Designer...
  ├─ Database Comparison...     ← NEW
  └─ Settings...
```

**Option B: Context Menu** (right-click on object in tree)
```
Right-click on INL.BILAGNR:
  ├─ View Details
  ├─ Generate DDL
  ├─ Export Data
  ├─ Compare Across Databases...  ← NEW
  └─ ...
```

**Option C: Both**
- Add to View menu for discovery
- Add to context menu for convenience

**Which integration?** (A, B, or C)

---

## 🛠️ Technical Implementation Details

### Required New Components

1. **`Services/DatabaseComparisonService.cs`**
   - Core comparison logic
   - Diff generation
   - ALTER statement generation

2. **`Services/DatabaseObjectFetcherService.cs`**
   - Fetch object definitions from any database
   - Normalize structure for comparison
   - Cache results for performance

3. **`Services/MultiDatabaseConnectionManager.cs`**
   - Manage multiple connections simultaneously
   - Connection pooling
   - Dispose pattern

4. **`Dialogs/DatabaseComparisonDialog.xaml`**
   - Initial dialog to select objects and databases
   - Connection selector
   - Comparison options

5. **`Dialogs/DatabaseComparisonResultsDialog.xaml`**
   - VSCode-style multi-column diff view
   - Synchronized scrolling
   - Interactive line selection
   - Action buttons

6. **`Models/ComparisonModels.cs`**
   - `ComparisonRequest`
   - `ComparisonResult`
   - `ObjectDifference`
   - `DatabaseObjectDefinition`

7. **`Utils/DiffEngine.cs`**
   - Line-by-line diff algorithm
   - Structural diff (if needed)
   - Unified diff format

8. **`Controls/SynchronizedTextEditor.cs`**
   - Custom control for synchronized scrolling
   - Multi-editor layout
   - Difference highlighting

---

## 📋 Implementation Checklist

### Phase 1: Visual Improvements
- [ ] Reduce object browser font size to 11-12pt
- [ ] Audit all dialogs for theme consistency
- [ ] Add loading indicator to object browser
- [ ] Test dark/light mode switching thoroughly
- [ ] Add object count to status bar

### Phase 2: Package Dependencies
- [ ] Create PackageDependencyAnalyzer service
- [ ] Parse SQL statements to extract object references
- [ ] Add "Dependencies" tab to PackageDetailsDialog
- [ ] Create sub-tabs for Tables, Views, Procedures, Functions
- [ ] Test with real packages in FKKTOTST

### Phase 3: Database Comparison
- [ ] Create MultiDatabaseConnectionManager
- [ ] Create DatabaseObjectFetcherService
- [ ] Create DatabaseComparisonService
- [ ] Create ComparisonModels
- [ ] Implement diff algorithm (simple or structural?)
- [ ] Create DatabaseComparisonDialog UI
- [ ] Create DatabaseComparisonResultsDialog UI
- [ ] Implement synchronized scrolling
- [ ] Implement difference highlighting
- [ ] Add "Copy Line" functionality
- [ ] Add "Generate ALTER" functionality
- [ ] Add "Apply Source" functionality
- [ ] Add to View menu
- [ ] Add to context menu (optional)
- [ ] Create CLI commands for automation
- [ ] Add comprehensive logging
- [ ] Create automated tests
- [ ] Update TASKLIST.md

---

## 🎯 Success Criteria

### Visual Improvements
- ✅ Font size allows more objects visible
- ✅ All dialogs work perfectly in dark mode
- ✅ All dialogs work perfectly in light mode
- ✅ Loading indicators provide feedback
- ✅ No hard-coded colors

### Package Dependencies
- ✅ PackageDetailsDialog shows all referenced tables
- ✅ PackageDetailsDialog shows all referenced views/procedures/functions
- ✅ Bidirectional navigation works (table ↔ package)
- ✅ Accurate dependency parsing from SQL

### Database Comparison
- ✅ Compare tables across 2-4 databases
- ✅ Compare views/procedures/functions across databases
- ✅ Highlight differences clearly
- ✅ Generate ALTER statements automatically
- ✅ Copy individual lines between databases
- ✅ Apply full source from one database to another
- ✅ Support transaction rollback
- ✅ Create backup scripts before changes
- ✅ Works offline (no external dependencies)

---

## ⚡ Priority Recommendations

### Immediate (Do First)
1. **Visual improvements** - Quick wins, improves UX immediately
2. **Answer clarification questions** - Needed before database comparison implementation

### High Priority (After Clarification)
3. **Database comparison feature** - High-value feature for DBAs
4. **Package dependency analysis** - Completes the package analysis feature

### Medium Priority
5. **Context menu integration** - Nice-to-have convenience feature
6. **CLI commands for database comparison** - Automation support

---

## 🤔 Questions for User (CLARIFICATION NEEDED)

Before implementing the Database Comparison feature, please clarify:

1. **UI Layout**: Side-by-side (A), Base+Diff (B), or Unified Diff (C)?
2. **Line Copy Behavior**: Immediate ALTER (A) or Staging Area (B)?
3. **Source Code Application**: DROP+CREATE (A) or CREATE OR REPLACE (B)?
4. **Connection Management**: Reuse existing (A) or Fresh connections (B)?
5. **Comparison Scope**: Basic or Comprehensive (include triggers, grants, comments)?
6. **Diff Algorithm**: Simple line-by-line (A) or Structural/Smart (B)?
7. **Integration Point**: View menu only (A), Context menu only (B), or Both (C)?

---

## 📝 Additional Suggestions

### Enhancement 1: Comparison Templates
Save common comparison configurations:
```
Template: "Promote DEV to PROD"
  - Source: DEV (FKKTOTST)
  - Targets: TEST, PROD
  - Auto-generate migration scripts
```

### Enhancement 2: Batch Comparison
Compare multiple objects at once:
```
Select: All tables in INL schema
Compare across: DEV, TEST, PROD
Generate: Comprehensive migration report
```

### Enhancement 3: Comparison History
Track comparison results:
```
Comparison History:
  - 2025-12-14 18:00 - INL.BILAGNR across DEV/TEST/PROD - 3 differences
  - 2025-12-13 15:30 - INL.FASTE_LISTE - 0 differences
```

### Enhancement 4: Export Comparison Report
Export as:
- Markdown report
- HTML report (with syntax highlighting)
- Excel file (side-by-side comparison)
- PDF report

---

## 🎯 Recommendation: Start with Phase 1

**Immediate Action**:
1. Implement visual improvements (1-2 hours)
2. Get user answers to clarification questions
3. Then implement Database Comparison feature (12-16 hours)
4. Package dependencies can be done in parallel (3-4 hours)

**Total Estimated Time**: 16-22 hours (over 2-3 sessions)

---

## 🚦 Status

**Current Status**: ⏸️ **PAUSED - Awaiting User Input**

**Blocked On**: 7 clarification questions (see above)

**Ready to Implement**:
- ✅ Visual improvements (no blockers)
- ✅ Package dependency analysis (no blockers)

**Needs Clarification**:
- ❓ Database comparison feature design decisions

---

**Next Steps**: User provides answers to questions 1-7, then continuous implementation begins.

