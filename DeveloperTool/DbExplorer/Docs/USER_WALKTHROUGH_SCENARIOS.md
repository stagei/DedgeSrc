# DbExplorer - User Walkthrough Scenarios

**Date**: 2025-11-20  
**Purpose**: Comprehensive user testing scenarios to validate all functionality

---

## 🎯 SCENARIO 1: First-Time User Onboarding (15 minutes)

### Objective: 
New DBA installs DbExplorer and connects to their first database

### Steps:
1. **Launch Application**
   - ✅ Welcome screen shows "DbExplorer" branding
   - ✅ See "Professional DB2 Database Manager" subtitle
   - ✅ Two prominent buttons: "New Connection" and "Manage Connections"
   - ✅ "Recent Connections" section shows empty state

2. **Create First Connection**
   - Click "➕ New Connection" button
   - ✅ Connection dialog opens with Provider dropdown
   - ✅ Select "IBM DB2" from provider list
   - ✅ Version dropdown populates (12.1, 11.5, 11.1, 10.5)
   - ✅ Default port (50000) appears automatically
   - Enter connection details:
     - Connection Name: "My Production DB"
     - Server: "prod-db-server.company.com"
     - Port: 50000
     - Database: "PRODDB"
     - Username: "DBADMIN"
     - Password: "********"
   - ✅ Click "Test Connection" - should show success message
   - ✅ Click "Connect" - connection tab opens

3. **First Look at Connected UI**
   - ✅ Window title shows "DbExplorer - DB2 Database Manager"
   - ✅ Connection tab header shows "PRODDB @ prod-db-server"
   - ✅ Object Browser on left shows database tree structure
   - ✅ SQL Editor in center with sample query
   - ✅ Empty results grid at bottom
   - ✅ Status bar shows "Ready" and access level badge

4. **Test SQL Intellisense (NEW!)**
   - Clear the SQL editor
   - Type: `SEL` and wait
   - ✅ Completion window appears with SELECT, DELETE, etc.
   - Press Ctrl+Space
   - ✅ Full keyword list appears
   - Type: `SELECT * FROM SYSCAT.`
   - ✅ After dot, table suggestions appear (TABLES, COLUMNS, VIEWS)
   - Complete: `SELECT * FROM SYSCAT.TABLES FETCH FIRST 10 ROWS ONLY`
   - Press F5 to execute
   - ✅ Results appear in grid

5. **Explore Object Browser**
   - ✅ Expand "Schemas" folder
   - ✅ Expand a user schema (e.g., "MYSCHEMA")
   - ✅ See object types: Tables, Views, Indexes, Procedures, Functions, etc.
   - ✅ Expand "Tables" to see table list
   - Single-click a table name
   - ✅ Table name inserts at cursor position in editor
   - Double-click a table
   - ✅ Table Properties dialog opens with full details

6. **Test Theme Switching (FIXED!)**
   - Go to View menu → Toggle Theme
   - ✅ Theme cycles: Dark → Light → System
   - ✅ Light mode works correctly (previously broken)
   - ✅ System theme respects Windows settings
   - ✅ All UI elements adapt to theme (editor, toolbar, grids)

### Expected Outcome:
✅ User successfully connects, explores database, writes SQL with intellisense, and sees results

### Potential Issues to Check:
- [ ] Does connection progress dialog show during connection?
- [ ] Are connection statistics logged?
- [ ] Does RBAC access level badge show correctly?
- [ ] Does theme persist on restart?

---

## 🔍 SCENARIO 2: DBA Database Monitoring (20 minutes)

### Objective:
DBA monitors database health and identifies performance issues

### Steps:

1. **Check Database Load**
   - Go to Tools → Database Load Monitor
   - ✅ DatabaseLoadMonitorPanel opens in new tab
   - ✅ Select schema from dropdown
   - Click "Start Monitoring"
   - ✅ Grid populates with table activity metrics
   - ✅ See columns: Table Name, Rows Read, Rows Inserted, Last Activity Time
   - ✅ Data refreshes every 5 seconds
   - Click "Stop Monitoring"
   - ✅ Auto-refresh stops
   - Click "Export to CSV"
   - ✅ Save dialog appears, data exports successfully

2. **Investigate Lock Contention**
   - Go to Tools → Lock Monitor (DBA only)
   - ✅ LockMonitorPanel opens
   - Click "Refresh Locks"
   - ✅ Grid shows current locks with holder/waiter info
   - ✅ Columns: Lock Name, Type, Status, Holder, Waiter, Duration
   - Right-click on a lock
   - ✅ Context menu: "Force Disconnect" (DBA only)
   - Click "Force Disconnect"
   - ✅ Confirmation dialog appears
   - ✅ After confirm, lock is released and logged

3. **Check Active Sessions**
   - Go to Tools → Active Sessions (DBA only)
   - ✅ ActiveSessionsPanel opens
   - ✅ Grid shows all connected users
   - ✅ Columns: Application Name, User, Auth ID, Status, Execution Time
   - Sort by "Execution Time" descending
   - ✅ Identify long-running sessions
   - Right-click longest session
   - ✅ Context menu: "Force Disconnect", "View Details"
   - Click "View Details"
   - ✅ Session details dialog shows full session info

4. **Analyze Table Statistics**
   - Go to Tools → Statistics Manager
   - ✅ StatisticsManagerPanel opens
   - Select schema: "MYSCHEMA"
   - Check "Show only outdated statistics"
   - Click "Analyze"
   - ✅ Grid shows tables with outdated RUNSTATS
   - ✅ Columns: Table, Last Stats Time, Status, Cardinality
   - Select multiple outdated tables (Ctrl+Click)
   - Click "Generate RUNSTATS"
   - ✅ Dialog shows generated RUNSTATS commands
   - ✅ Option to "Execute Now" or "Copy to Clipboard"

### Expected Outcome:
✅ DBA identifies performance issues, monitors locks, manages sessions, updates statistics

### Potential Issues to Check:
- [ ] Does access level restrict non-DBA users from force disconnect?
- [ ] Are all monitoring operations logged?
- [ ] Does auto-refresh properly clean up on tab close?
- [ ] Are RUNSTATS commands syntactically correct?

---

## 🛠️ SCENARIO 3: Database Development Workflow (25 minutes)

### Objective:
Developer creates tables, writes procedures, and manages schema changes

### Steps:

1. **Browse Source Code**
   - Go to Tools → Source Code Browser
   - ✅ SourceCodeBrowserPanel opens with 3-column layout
   - Left: Schema dropdown and object type tabs
   - Select schema: "MYSCHEMA"
   - Click "Procedures" tab
   - ✅ Middle column shows procedure list
   - Click on a procedure
   - ✅ Right column shows procedure source code
   - ✅ Syntax highlighting works
   - Click "📋 Copy" button
   - ✅ Source code copied to clipboard
   - Click "💾 Export to File"
   - ✅ Save dialog appears

2. **Generate DDL**
   - In Object Browser, right-click on a table
   - ✅ Context menu: "Properties", "Generate DDL Create", "Generate DDL Drop"
   - Click "Generate DDL Create"
   - ✅ New SQL editor tab opens with CREATE TABLE statement
   - ✅ DDL includes columns, data types, constraints, indexes
   - Review DDL (do not execute)
   - Click "Generate DDL Drop"
   - ✅ New tab with DROP TABLE statement

3. **Analyze Dependencies**
   - Go to Tools → Dependency Graph
   - ✅ DependencyGraphPanel opens
   - Select target table: "ORDERS"
   - Click "Analyze Dependencies"
   - ✅ TreeView shows:
     - Tables referencing ORDERS (FK relationships)
     - Tables referenced by ORDERS
     - Views using ORDERS
     - Procedures/Functions using ORDERS
     - Triggers on ORDERS
   - Right-click on a dependent object
   - ✅ Context menu: "View Properties", "Show DDL"
   - Click "Export Graph"
   - ✅ Option to export as text or Mermaid diagram

4. **Manage Table Comments**
   - Go to Tools → Comment Manager
   - ✅ CommentManagerPanel opens
   - Select schema: "MYSCHEMA"
   - Click "Load Tables"
   - ✅ Grid shows all tables with current comments
   - ✅ Columns: Table Name, Current Comment, Modified
   - Click on a table row to edit
   - Enter new comment: "Customer order details - updated schema"
   - Click "Save Comments"
   - ✅ COMMENT ON TABLE statement generated and executed
   - ✅ Success message shown
   - Click "Export Comments"
   - ✅ All comments exported to CSV

5. **Design Mermaid ER Diagram**
   - Go to Tools → Mermaid Designer
   - ✅ MermaidDesignerWindow opens (full window)
   - Click "Select Tables"
   - ✅ SchemaTableSelectionDialog opens with TreeView
   - Select schema: "MYSCHEMA"
   - Check tables: CUSTOMERS, ORDERS, ORDER_ITEMS, PRODUCTS
   - Click "Generate Diagram"
   - ✅ Mermaid ERD code appears in left editor
   - ✅ Live preview renders in right WebView2 panel
   - ✅ Shows relationships (FK lines between tables)
   - Click on a table header in rendered diagram
   - ✅ Table properties dialog opens (if implemented)
   - Edit Mermaid code manually
   - ✅ Preview updates in real-time
   - Click "Compare to Database"
   - ✅ Shows differences between model and current DB schema
   - Click "Generate Migration DDL"
   - ✅ ALTER TABLE statements appear in new editor tab

### Expected Outcome:
✅ Developer browses code, generates DDL, analyzes dependencies, manages comments, designs ER diagrams

### Potential Issues to Check:
- [ ] Is generated DDL syntactically correct?
- [ ] Do FK relationships render correctly in Mermaid?
- [ ] Does WebView2 Mermaid rendering work on all machines?
- [ ] Are comments properly escaped in SQL statements?
- [ ] Does dependency analysis detect circular references?

---

## 📊 SCENARIO 4: Database Maintenance Tasks (20 minutes)

### Objective:
DBA performs routine maintenance and optimization

### Steps:

1. **Identify Unused Objects**
   - Go to Tools → Unused Objects (DBA only)
   - ✅ UnusedObjectsPanel opens
   - Select schema: "MYSCHEMA"
   - Click "Analyze"
   - ✅ Grid shows tables, indexes, views not accessed recently
   - ✅ Columns: Object Type, Name, Last Used, Size, Recommendation
   - Filter by: "Not used in 90+ days"
   - ✅ Filtered list appears
   - Select multiple unused indexes
   - Click "Generate DROP Scripts"
   - ✅ DROP INDEX statements appear in new tab
   - Review carefully before execution
   - ✅ Warning message about irreversible action

2. **Manage CDC (Change Data Capture)**
   - Go to Tools → CDC Manager (DBA only)
   - ✅ CdcManagerPanel opens
   - Click "Scan Database"
   - ✅ Grid shows all tables with CDC status
   - ✅ Columns: Table, CDC Enabled, Capture Table, State
   - Select a table without CDC
   - Click "Enable CDC"
   - ✅ Confirmation dialog with options:
     - Capture all columns / Select columns
     - Retention period
   - Click "Enable"
   - ✅ ALTER TABLE statement executed
   - ✅ Table now shows "Enabled" status
   - Select a CDC-enabled table
   - Click "View Capture Data"
   - ✅ New tab shows CDC capture table contents

3. **Analyze Package Performance**
   - Go to Tools → Package Analyzer (DBA only)
   - ✅ PackageAnalyzerPanel opens
   - Select schema: "NULLID" (system packages)
   - Click "Load Packages"
   - ✅ Grid shows all packages
   - ✅ Columns: Package Name, Last Used, Statements, Bind Time
   - Click on a package
   - ✅ Bottom panel shows SQL statements in package
   - Select a statement
   - Click "View Full SQL"
   - ✅ SqlStatementViewerDialog opens with formatted SQL
   - Click "Add to Editor"
   - ✅ SQL inserted into main editor tab

4. **Plan Schema Migration**
   - Go to Tools → Migration Assistant (DBA only)
   - ✅ MigrationAssistantPanel opens
   - Section 1: Source Analysis
     - Select source schema: "OLD_SCHEMA"
     - Click "Analyze"
     - ✅ Shows object count, dependencies, size
   - Section 2: Target Definition
     - Enter target schema: "NEW_SCHEMA"
     - Options: Include data, Include grants, Include comments
   - Section 3: Generate Migration
     - Click "Generate Migration Plan"
     - ✅ Step-by-step migration plan appears
     - ✅ Shows: CREATE SCHEMA, CREATE TABLES, CREATE INDEXES, etc.
   - Click "Generate SQL Scripts"
   - ✅ Multiple editor tabs open:
     - 01_create_schema.sql
     - 02_create_tables.sql
     - 03_create_indexes.sql
     - 04_migrate_data.sql
   - Review all scripts
   - Execute manually in order

### Expected Outcome:
✅ DBA performs maintenance, enables CDC, analyzes packages, plans migrations

### Potential Issues to Check:
- [ ] Does unused object detection consider all access methods?
- [ ] Is CDC ALTER TABLE syntax correct for DB2 12.1?
- [ ] Do migration scripts respect FK constraints order?
- [ ] Are object sizes calculated correctly?

---

## 🔐 SCENARIO 5: Security and Access Control (15 minutes)

### Objective:
Verify RBAC (Role-Based Access Control) works correctly

### Steps:

1. **Connect as DBA User**
   - Create connection with DBA credentials
   - ✅ Access level badge shows "🔑 DBA"
   - Check View menu
   - ✅ All tools visible:
     - Lock Monitor ✓
     - Active Sessions ✓
     - CDC Manager ✓
     - Unused Objects ✓
     - Force Disconnect options ✓
   - Open Lock Monitor
   - Right-click on a lock
   - ✅ "Force Disconnect" option available

2. **Connect as Advanced User**
   - Create new connection with middle-level user
   - ✅ Access level badge shows "🔧 ADVANCED"
   - Check View menu
   - ✅ Some tools visible:
     - Database Load Monitor ✓
     - Statistics Manager ✓
     - Source Code Browser ✓
   - ✅ Some tools hidden:
     - Lock Monitor (Force Disconnect) ✗
     - Active Sessions (Force Disconnect) ✗
     - CDC Manager ✗
     - Unused Objects (DROP scripts) ✗
   - Open Statistics Manager
   - ✅ Can view statistics
   - ✅ "Generate RUNSTATS" button disabled

3. **Connect as Standard User (Read-Only)**
   - Create connection with standard user (not in DBAUTH)
   - ✅ Access level badge shows "👤 STANDARD" or "🔒 READ-ONLY"
   - Check View menu
   - ✅ Very limited tools visible:
     - Only read-only operations
   - Try to execute UPDATE statement
   - ✅ Error message: "Permission denied - read-only access"
   - Try to execute SELECT statement
   - ✅ Works fine
   - Object Browser
   - Right-click on table
   - ✅ Only "Properties" option (no DDL generation)

### Expected Outcome:
✅ RBAC properly restricts functionality based on user permissions

### Potential Issues to Check:
- [ ] Is username parsed correctly (removing domain prefix)?
- [ ] Does SYSCAT.DBAUTH query work for all DB2 versions?
- [ ] Are menu items properly tagged with access levels?
- [ ] Does read-only mode prevent ALL modifications?

---

## 💾 SCENARIO 6: Data Export and Reporting (15 minutes)

### Objective:
Export query results in various formats

### Steps:

1. **Execute Query**
   - Write query: `SELECT * FROM SYSCAT.TABLES WHERE TABSCHEMA = 'MYSCHEMA'`
   - Press F5
   - ✅ Results appear in grid (50 tables)

2. **Export to JSON**
   - Click "💾 Export" button
   - ✅ ExportToFileDialog opens
   - Select format: JSON
   - Enter filename: "schema_tables.json"
   - Click "Export"
   - ✅ File saved successfully
   - ✅ Success message shows row count
   - Open file in text editor
   - ✅ Verify JSON structure is valid
   - ✅ Check that CHAR columns are trimmed (no trailing spaces)

3. **Export to CSV**
   - Same query results
   - Click "Export"
   - Select format: CSV
   - Options: Include headers, Field separator: comma
   - Click "Export"
   - ✅ CSV file created
   - Open in Excel
   - ✅ Columns properly separated
   - ✅ Special characters escaped correctly

4. **Copy to Clipboard**
   - Select specific rows in results grid (Ctrl+Click)
   - Right-click → "📋 Copy to Clipboard..."
   - ✅ CopySelectionDialog opens
   - Choose format: CSV
   - Click "Copy"
   - ✅ Data copied to clipboard
   - Paste into Excel
   - ✅ Data pastes correctly

5. **Export Large Dataset**
   - Write query: `SELECT * FROM SYSCAT.COLUMNS` (5000+ rows)
   - Press F5
   - ✅ Pagination appears (showing page 1 of 50)
   - Click "Export"
   - Select format: TSV (Tab-Separated)
   - ✅ Export dialog shows "Exporting all pages (5000+ rows)"
   - Click "Export"
   - ✅ Progress indicator (if implemented)
   - ✅ File saved with all rows

### Expected Outcome:
✅ Data exports successfully in all formats, large datasets handled correctly

### Potential Issues to Check:
- [ ] Are special characters (quotes, newlines) properly escaped?
- [ ] Do CHAR columns get trimmed in exports?
- [ ] Does pagination export ALL pages or just current page?
- [ ] Is there a size limit for exports?

---

## ⌨️ SCENARIO 7: Keyboard Shortcuts and Productivity (10 minutes)

### Objective:
Test all keyboard shortcuts work correctly

### Steps:

1. **Connection Management**
   - Press `Ctrl+N`
   - ✅ New Connection dialog opens
   - Press `Escape`
   - ✅ Dialog closes
   - Press `Ctrl+W`
   - ✅ Current tab closes

2. **SQL Editing**
   - In editor, press `Ctrl+A`
   - ✅ All text selected
   - Press `Delete`
   - Type some SQL
   - Press `Ctrl+Z`
   - ✅ Undo works
   - Press `Ctrl+Y`
   - ✅ Redo works
   - Press `Ctrl+S`
   - ✅ Save SQL Script dialog opens

3. **Query Execution**
   - Type: `SELECT COUNT(*) FROM SYSCAT.TABLES`
   - Press `F5`
   - ✅ Query executes
   - Press `Ctrl+Enter` (if implemented)
   - ✅ Executes current statement only

4. **Intellisense**
   - Type: `SEL`
   - Press `Ctrl+Space`
   - ✅ Completion window appears
   - Use arrow keys to navigate
   - ✅ Selection changes
   - Press `Enter`
   - ✅ Text inserted
   - Press `Escape` while completion window open
   - ✅ Window closes

5. **Formatting**
   - Type messy SQL: `select*from syscat.tables where tabschema='MYSCHEMA'`
   - Press `Ctrl+Shift+F`
   - ✅ SQL formatted beautifully:
     ```sql
     SELECT * 
     FROM SYSCAT.TABLES 
     WHERE TABSCHEMA = 'MYSCHEMA'
     ```

6. **Theme Toggle**
   - Press `Ctrl+D`
   - ✅ Theme toggles Dark → Light → System → Dark

7. **Find and Replace**
   - Press `Ctrl+F`
   - ✅ Find dialog opens
   - Press `Ctrl+H`
   - ✅ Replace dialog opens

### Expected Outcome:
✅ All keyboard shortcuts work as documented

### Potential Issues to Check:
- [ ] Do shortcuts conflict with each other?
- [ ] Are shortcuts documented in tooltips?
- [ ] Do shortcuts work across all tabs?

---

## 🐛 SCENARIO 8: Edge Cases and Error Handling (20 minutes)

### Objective:
Test application behavior under unusual conditions

### Steps:

1. **Network Interruption**
   - Connect to database
   - Execute long-running query
   - Disconnect network cable (or disable network adapter)
   - ✅ Connection timeout error after ~30 seconds
   - ✅ Error message is user-friendly
   - ✅ Error logged with full details
   - Reconnect network
   - Click "Retry" (if available)
   - ✅ Connection re-established

2. **Invalid SQL**
   - Type: `SLECT * FORM SYSCAT.TABLES` (typos)
   - Press F5
   - ✅ DB2 syntax error shown
   - ✅ Error includes SQL state code
   - ✅ Error logged in log file

3. **Large Result Sets**
   - Execute: `SELECT * FROM SYSCAT.COLUMNS` (10,000+ rows)
   - ✅ Pagination appears
   - ✅ Only first page loaded (performance)
   - Click "Next Page"
   - ✅ Second page loads
   - Click "Export All"
   - ✅ All pages exported (not just current page)

4. **Concurrent Connections**
   - Open 5 connection tabs simultaneously
   - Execute different queries in each
   - ✅ Each maintains independent connection
   - ✅ No interference between tabs
   - Close one tab
   - ✅ Other tabs unaffected
   - ✅ Connection properly disposed

5. **Special Characters**
   - Execute: `SELECT 'Test "quotes" and ''apostrophes''' FROM SYSIBM.SYSDUMMY1`
   - ✅ Result displays correctly
   - Export to CSV
   - ✅ Quotes properly escaped
   - Export to JSON
   - ✅ JSON valid with escaped characters

6. **Empty Results**
   - Execute: `SELECT * FROM SYSCAT.TABLES WHERE TABNAME = 'NONEXISTENT'`
   - ✅ Grid shows "No results" message
   - ✅ Row count shows "0 rows"
   - Click "Export"
   - ✅ Exports empty file with headers only

7. **Connection Timeout**
   - Enter invalid server address
   - Click "Connect"
   - ✅ Connection times out after configured period
   - ✅ User-friendly error message
   - ✅ Can retry without restarting app

### Expected Outcome:
✅ Application handles errors gracefully, no crashes

### Potential Issues to Check:
- [ ] Are all exceptions caught and logged?
- [ ] Do error messages help user fix the problem?
- [ ] Are connections properly disposed on errors?
- [ ] Does app recover from transient network issues?

---

## 📝 SCENARIO 9: Multi-Window Workflow (15 minutes)

### Objective:
Test working with multiple tabs and windows

### Steps:

1. **Open Multiple Connections**
   - Connect to database 1: "PRODDB"
   - Connect to database 2: "TESTDB"
   - Connect to database 3: "DEVDB"
   - ✅ Three tabs open, each with own Object Browser
   - ✅ Tab headers show different database names
   - Switch between tabs (Ctrl+Tab if implemented)
   - ✅ Each tab maintains its state

2. **Open Multiple Tool Panels**
   - In PRODDB tab: Open Database Load Monitor
   - In TESTDB tab: Open Statistics Manager
   - In DEVDB tab: Open Source Code Browser
   - ✅ Each tool opens in separate sub-tab within connection
   - Switch between connection tabs
   - ✅ Tool panels persist

3. **Copy SQL Between Tabs**
   - Write query in PRODDB tab: `SELECT * FROM CUSTOMERS`
   - Press Ctrl+A, Ctrl+C
   - Switch to TESTDB tab
   - Press Ctrl+V
   - ✅ Query pasted
   - Execute in TESTDB
   - ✅ Results from TESTDB, not PRODDB

4. **Compare Data Across Connections**
   - PRODDB tab: Execute `SELECT COUNT(*) FROM ORDERS`
   - Note result: 15,432 rows
   - TESTDB tab: Execute same query
   - Note result: 982 rows
   - ✅ Results are independent

### Expected Outcome:
✅ Multiple connections work independently, no state leakage

### Potential Issues to Check:
- [ ] Does closing one tab affect others?
- [ ] Are query histories kept separate per connection?
- [ ] Do tool panels close when parent connection closes?

---

## 🔄 SCENARIO 10: Session Persistence and Recovery (10 minutes)

### Objective:
Test that state persists across restarts

### Steps:

1. **Create Connection and Settings**
   - Create connection: "MYDB"
   - Set theme to Light mode
   - Execute some queries (history)
   - Change editor font size to 16
   - Close application

2. **Restart Application**
   - Launch DbExplorer again
   - ✅ Welcome screen shows "MYDB" in Recent Connections
   - ✅ Last used time is accurate
   - ✅ Use count is correct
   - ✅ Theme is still Light mode
   - Double-click "MYDB"
   - ✅ Connection opens without re-entering credentials

3. **Check Query History**
   - In connection tab, open "History" tab
   - ✅ Previous queries are listed
   - ✅ Timestamps are correct
   - Double-click a history item
   - ✅ Query loads into editor

4. **Check Settings Persistence**
   - Open Settings dialog
   - ✅ All previous settings retained:
     - Theme: Light
     - Font size: 16
     - Auto-commit: Previous state
     - Max rows: Previous value

### Expected Outcome:
✅ All user preferences and history persist across sessions

### Potential Issues to Check:
- [ ] Are passwords securely encrypted?
- [ ] Does history size have a limit?
- [ ] Are settings stored in correct location?

---

## 📊 SUMMARY OF TESTING COVERAGE

### Features Tested:
✅ Connection management (create, test, save, recent)  
✅ SQL editing with intellisense (NEW!)  
✅ Query execution and results display  
✅ Theme switching (Dark/Light/System) (FIXED!)  
✅ Object browser and navigation  
✅ Database monitoring (Load, Locks, Sessions)  
✅ Table statistics and RUNSTATS  
✅ Source code browsing  
✅ DDL generation  
✅ Dependency analysis  
✅ Comment management  
✅ Mermaid ER diagrams  
✅ CDC management  
✅ Package analysis  
✅ Migration planning  
✅ Unused object detection  
✅ Data export (JSON, CSV, TSV, XML)  
✅ RBAC security (DBA/Advanced/Standard)  
✅ Keyboard shortcuts  
✅ Error handling  
✅ Multi-connection workflow  
✅ Session persistence  

### Estimated Testing Time:
**Total: ~3 hours for complete walkthrough**
- Scenario 1: 15 minutes
- Scenario 2: 20 minutes
- Scenario 3: 25 minutes
- Scenario 4: 20 minutes
- Scenario 5: 15 minutes
- Scenario 6: 15 minutes
- Scenario 7: 10 minutes
- Scenario 8: 20 minutes
- Scenario 9: 15 minutes
- Scenario 10: 10 minutes

### Priority Testing (1 hour quick smoke test):
1. Scenario 1 (First-time user) - 15 min
2. Scenario 2 (Monitoring) - 20 min
3. Scenario 6 (Export) - 15 min
4. Scenario 8 (Error handling) - 10 min

---

**Next Steps**: Execute these scenarios systematically and document any bugs or UX issues discovered.

