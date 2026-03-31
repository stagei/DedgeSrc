# Mermaid Designer - Table Selection, FK Navigation & Diff Management Specification

**Feature:** Enhanced table selection with foreign key navigation, baseline snapshots, and automated diff comparison  
**Status:** 📋 SPECIFICATION  
**Related:** `MERMAID_VISUAL_DESIGNER_ADVANCED_SPEC.md`, `SQLMERMAIDERDTOOLS_INTEGRATION.md`

---

## 🎯 OVERVIEW

This specification extends the Mermaid Visual Designer with:
1. **Intelligent Table Selection** - Select tables with easy FK relationship navigation (forward and backward)
2. **Baseline Snapshot Management** - Always maintain a snapshot of current database state for comparison
3. **Automated Diff Detection** - Use SqlMermaidErdTools to detect changes when user modifies Mermaid script
4. **Diff Script Editor** - Open generated diff scripts in new SQL editor tab with same connection for manual verification and execution

---

## 🏗️ ARCHITECTURE COMPONENTS

### Component 1: Enhanced Table Selection Dialog

**File:** `Dialogs/TableSelectionWithFKNavigationDialog.xaml`

**Purpose:** Replace simple checkbox list with intelligent table selection that supports FK navigation.

**Features:**
- Multi-select table list with search/filter
- **"Follow Foreign Keys"** button - Add related tables (forward direction)
- **"Follow Incoming FKs"** button - Add tables that reference selected tables (backward direction)
- **"Expand All Related"** button - Add all tables connected via FK relationships
- Visual indicators showing FK relationships in selection
- Current selection count display
- "Add to Model" button to confirm selection

**UI Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Table Selection - Add Tables to Mermaid Model                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Search: [________________________] 🔍                        │
│                                                              │
│ Schema: [FK ▼]  Filter: [All Tables ▼]                     │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ☑ CUSTOMERS          [FK: 2 outgoing, 0 incoming]      │ │
│ │ ☑ ORDERS             [FK: 1 outgoing, 1 incoming]      │ │
│ │ ☐ ORDER_ITEMS        [FK: 1 outgoing, 0 incoming]      │ │
│ │ ☐ PRODUCTS           [FK: 0 outgoing, 1 incoming]      │ │
│ │ ☐ SHIPMENTS          [FK: 0 outgoing, 1 incoming]      │ │
│ │ ☐ PAYMENTS           [FK: 1 outgoing, 0 incoming]     │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ Selected: 2 tables                                          │
│                                                              │
│ [Follow Foreign Keys →] [← Follow Incoming FKs]             │
│ [Expand All Related] [Clear Selection]                      │
│                                                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Foreign Key Relationships:                              │ │
│ │ • CUSTOMERS → ORDERS (via CUSTOMER_ID)                   │ │
│ │ • ORDERS → ORDER_ITEMS (via ORDER_ID)                   │ │
│ │ • ORDER_ITEMS → PRODUCTS (via PRODUCT_ID)               │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ [Add to Model] [Cancel]                                     │
└─────────────────────────────────────────────────────────────┘
```

**Code-Behind:** `Dialogs/TableSelectionWithFKNavigationDialog.xaml.cs`

**Key Methods:**
```csharp
public class TableSelectionWithFKNavigationDialog : Window
{
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler _metadataHandler;
    private List<TableSelectionItem> _availableTables = new();
    private List<TableSelectionItem> _selectedTables = new();
    
    /// <summary>
    /// Follow foreign keys from selected tables (forward direction)
    /// Adds tables that are referenced by selected tables' FKs
    /// </summary>
    private async Task FollowForeignKeysAsync()
    {
        Logger.Debug("Following foreign keys from {Count} selected tables", _selectedTables.Count);
        
        var relatedTables = new HashSet<string>();
        
        foreach (var selectedTable in _selectedTables)
        {
            // Query SYSCAT.REFERENCES for outgoing FKs
            var fkQuery = _metadataHandler.GetStatement("GetForeignKeysForTable");
            var fkResults = await _connectionManager.ExecuteQueryAsync(
                fkQuery, 
                selectedTable.Schema, 
                selectedTable.TableName);
            
            foreach (DataRow row in fkResults.Rows)
            {
                var refSchema = row["REFTABSCHEMA"].ToString();
                var refTable = row["REFTABNAME"].ToString();
                var key = $"{refSchema}.{refTable}";
                
                if (!relatedTables.Contains(key))
                {
                    relatedTables.Add(key);
                    Logger.Debug("Found related table via FK: {Schema}.{Table}", refSchema, refTable);
                }
            }
        }
        
        // Add related tables to selection
        foreach (var relatedKey in relatedTables)
        {
            var parts = relatedKey.Split('.');
            var table = _availableTables.FirstOrDefault(t => 
                t.Schema == parts[0] && t.TableName == parts[1]);
            
            if (table != null && !_selectedTables.Contains(table))
            {
                _selectedTables.Add(table);
                Logger.Info("Added table to selection via FK: {Table}", relatedKey);
            }
        }
        
        RefreshTableList();
    }
    
    /// <summary>
    /// Follow incoming foreign keys (backward direction)
    /// Adds tables that have FKs pointing to selected tables
    /// </summary>
    private async Task FollowIncomingForeignKeysAsync()
    {
        Logger.Debug("Following incoming foreign keys for {Count} selected tables", _selectedTables.Count);
        
        var relatedTables = new HashSet<string>();
        
        foreach (var selectedTable in _selectedTables)
        {
            // Query SYSCAT.REFERENCES for incoming FKs
            var incomingFkQuery = _metadataHandler.GetStatement("GetIncomingForeignKeys");
            var fkResults = await _connectionManager.ExecuteQueryAsync(
                incomingFkQuery,
                selectedTable.Schema,
                selectedTable.TableName);
            
            foreach (DataRow row in fkResults.Rows)
            {
                var fromSchema = row["TABSCHEMA"].ToString();
                var fromTable = row["TABNAME"].ToString();
                var key = $"{fromSchema}.{fromTable}";
                
                if (!relatedTables.Contains(key))
                {
                    relatedTables.Add(key);
                    Logger.Debug("Found table with incoming FK: {Schema}.{Table}", fromSchema, fromTable);
                }
            }
        }
        
        // Add related tables to selection
        foreach (var relatedKey in relatedTables)
        {
            var parts = relatedKey.Split('.');
            var table = _availableTables.FirstOrDefault(t => 
                t.Schema == parts[0] && t.TableName == parts[1]);
            
            if (table != null && !_selectedTables.Contains(table))
            {
                _selectedTables.Add(table);
                Logger.Info("Added table to selection via incoming FK: {Table}", relatedKey);
            }
        }
        
        RefreshTableList();
    }
    
    /// <summary>
    /// Expand all related tables (both directions, recursively)
    /// </summary>
    private async Task ExpandAllRelatedAsync()
    {
        Logger.Info("Expanding all related tables for {Count} selected tables", _selectedTables.Count);
        
        var processed = new HashSet<string>();
        var toProcess = new Queue<TableSelectionItem>(_selectedTables);
        
        while (toProcess.Count > 0)
        {
            var current = toProcess.Dequeue();
            var key = $"{current.Schema}.{current.TableName}";
            
            if (processed.Contains(key))
                continue;
            
            processed.Add(key);
            
            // Follow outgoing FKs
            await FollowForeignKeysAsync();
            
            // Follow incoming FKs
            await FollowIncomingForeignKeysAsync();
            
            // Add newly discovered tables to queue
            var newlyAdded = _selectedTables.Where(t => 
                !processed.Contains($"{t.Schema}.{t.TableName}")).ToList();
            
            foreach (var newTable in newlyAdded)
            {
                toProcess.Enqueue(newTable);
            }
        }
        
        RefreshTableList();
        Logger.Info("Expansion complete - {Count} tables in model", _selectedTables.Count);
    }
}
```

**Model:**
```csharp
public class TableSelectionItem
{
    public string Schema { get; set; }
    public string TableName { get; set; }
    public string FullName => $"{Schema}.{TableName}";
    public bool IsSelected { get; set; }
    public int OutgoingFKCount { get; set; }
    public int IncomingFKCount { get; set; }
    public List<ForeignKeyInfo> OutgoingFKs { get; set; } = new();
    public List<ForeignKeyInfo> IncomingFKs { get; set; } = new();
}

public class ForeignKeyInfo
{
    public string FromSchema { get; set; }
    public string FromTable { get; set; }
    public string ToSchema { get; set; }
    public string ToTable { get; set; }
    public string ConstraintName { get; set; }
    public List<string> FromColumns { get; set; }
    public List<string> ToColumns { get; set; }
}
```

---

### Component 2: Baseline Snapshot Manager

**File:** `Services/MermaidBaselineSnapshotService.cs`

**Purpose:** Maintain a snapshot of the current database state (Mermaid diagram) that represents the "truth" for comparison.

**Key Concepts:**
- **Baseline Snapshot**: The Mermaid ERD generated from current database state
- **Auto-Refresh**: When user loads from DB, baseline is automatically updated
- **Persistent Storage**: Baseline stored in memory and optionally saved to file
- **Comparison Source**: Used as "before" state for diff operations

**Implementation:**
```csharp
public class MermaidBaselineSnapshotService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private string? _currentBaselineMermaid;
    private DateTime? _baselineTimestamp;
    private string? _baselineConnectionProfile;
    private List<string> _baselineTableList = new();
    
    /// <summary>
    /// Capture current database state as baseline snapshot
    /// Called automatically when user loads tables from DB
    /// </summary>
    public async Task CaptureBaselineAsync(
        IConnectionManager connectionManager,
        List<string> selectedTables,
        string mermaidDiagram)
    {
        Logger.Info("Capturing baseline snapshot for {Count} tables", selectedTables.Count);
        
        _currentBaselineMermaid = mermaidDiagram;
        _baselineTimestamp = DateTime.Now;
        _baselineConnectionProfile = connectionManager.ConnectionInfo.ConnectionName;
        _baselineTableList = new List<string>(selectedTables);
        
        Logger.Info("Baseline captured at {Timestamp} for profile {Profile}", 
            _baselineTimestamp, _baselineConnectionProfile);
        Logger.Debug("Baseline Mermaid length: {Length} characters", mermaidDiagram.Length);
    }
    
    /// <summary>
    /// Get current baseline snapshot
    /// </summary>
    public string? GetBaseline()
    {
        return _currentBaselineMermaid;
    }
    
    /// <summary>
    /// Check if baseline exists
    /// </summary>
    public bool HasBaseline()
    {
        return !string.IsNullOrEmpty(_currentBaselineMermaid);
    }
    
    /// <summary>
    /// Get baseline metadata
    /// </summary>
    public BaselineMetadata GetBaselineMetadata()
    {
        return new BaselineMetadata
        {
            Timestamp = _baselineTimestamp,
            ConnectionProfile = _baselineConnectionProfile,
            TableCount = _baselineTableList.Count,
            Tables = new List<string>(_baselineTableList)
        };
    }
    
    /// <summary>
    /// Clear baseline (when user starts fresh)
    /// </summary>
    public void ClearBaseline()
    {
        Logger.Info("Clearing baseline snapshot");
        _currentBaselineMermaid = null;
        _baselineTimestamp = null;
        _baselineConnectionProfile = null;
        _baselineTableList.Clear();
    }
}

public class BaselineMetadata
{
    public DateTime? Timestamp { get; set; }
    public string? ConnectionProfile { get; set; }
    public int TableCount { get; set; }
    public List<string> Tables { get; set; } = new();
}
```

**Integration with MermaidDesignerWindow:**
```csharp
private async Task LoadFromDatabaseAsync()
{
    // ... existing table selection code ...
    
    // Generate Mermaid from selected tables
    var mermaid = await _sqlMermaidService.GenerateMermaidFromDb2TablesAsync(
        _connectionManager,
        selectedTables);
    
    // Update editor
    MermaidEditor.Text = mermaid;
    
    // CRITICAL: Capture baseline snapshot
    await _baselineService.CaptureBaselineAsync(
        _connectionManager,
        selectedTables,
        mermaid);
    
    // Update UI to show baseline status
    UpdateBaselineStatus();
    
    Logger.Info("Loaded {Count} tables and captured baseline snapshot", selectedTables.Count);
}

private void UpdateBaselineStatus()
{
    if (_baselineService.HasBaseline())
    {
        var metadata = _baselineService.GetBaselineMetadata();
        BaselineStatusText.Text = $"Baseline: {metadata.TableCount} tables from {metadata.ConnectionProfile} " +
                                 $"({metadata.Timestamp:yyyy-MM-dd HH:mm:ss})";
        BaselineStatusText.Foreground = new SolidColorBrush(Colors.Green);
    }
    else
    {
        BaselineStatusText.Text = "No baseline - Load from DB to capture snapshot";
        BaselineStatusText.Foreground = new SolidColorBrush(Colors.Gray);
    }
}
```

---

### Component 3: Automated Diff Detection with SqlMermaidErdTools

**File:** `Services/MermaidDiffComparisonService.cs`

**Purpose:** Automatically detect changes when user modifies Mermaid script, using SqlMermaidErdTools for comparison.

**Key Features:**
- **Real-time Detection**: Monitor Mermaid editor for changes (debounced)
- **SqlMermaidErdTools Integration**: Use `GenerateDiffAlterStatements()` for accurate diff
- **Change Notification**: Show diff summary in status bar
- **Diff Script Generation**: Generate ALTER statements when changes detected

**Implementation:**
```csharp
public class MermaidDiffComparisonService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly SqlMermaidIntegrationService _sqlMermaidService;
    private readonly MermaidBaselineSnapshotService _baselineService;
    private Timer? _diffCheckTimer;
    private string? _lastCheckedMermaid;
    
    public event EventHandler<DiffDetectedEventArgs>? DiffDetected;
    
    public MermaidDiffComparisonService(
        SqlMermaidIntegrationService sqlMermaidService,
        MermaidBaselineSnapshotService baselineService)
    {
        _sqlMermaidService = sqlMermaidService;
        _baselineService = baselineService;
    }
    
    /// <summary>
    /// Check for differences between baseline and current Mermaid
    /// Called automatically when user edits Mermaid script
    /// </summary>
    public async Task CheckForDifferencesAsync(string currentMermaid)
    {
        // Debounce: Wait 1 second after user stops typing
        _diffCheckTimer?.Stop();
        _diffCheckTimer = new Timer(1000);
        _diffCheckTimer.Elapsed += async (s, e) =>
        {
            await PerformDiffCheckAsync(currentMermaid);
        };
        _diffCheckTimer.Start();
    }
    
    private async Task PerformDiffCheckAsync(string currentMermaid)
    {
        if (string.IsNullOrEmpty(currentMermaid) || currentMermaid == _lastCheckedMermaid)
            return;
        
        _lastCheckedMermaid = currentMermaid;
        
        var baseline = _baselineService.GetBaseline();
        if (string.IsNullOrEmpty(baseline))
        {
            Logger.Debug("No baseline available for diff comparison");
            DiffDetected?.Invoke(this, new DiffDetectedEventArgs
            {
                HasChanges = false,
                Message = "No baseline - Load from DB first"
            });
            return;
        }
        
        if (baseline == currentMermaid)
        {
            Logger.Debug("No changes detected - Mermaid matches baseline");
            DiffDetected?.Invoke(this, new DiffDetectedEventArgs
            {
                HasChanges = false,
                Message = "No changes detected"
            });
            return;
        }
        
        try
        {
            Logger.Info("Detecting differences between baseline and current Mermaid");
            
            // Use SqlMermaidErdTools to generate diff ALTER statements
            var diffDdl = await _sqlMermaidService.GenerateMigrationFromMermaidDiffAsync(
                baseline,
                currentMermaid,
                SqlMermaidErdTools.Models.SqlDialect.AnsiSql);
            
            var hasChanges = !string.IsNullOrWhiteSpace(diffDdl) && 
                            !diffDdl.Contains("-- No changes detected");
            
            if (hasChanges)
            {
                Logger.Info("Changes detected - Generated {Length} characters of ALTER statements", diffDdl.Length);
                
                // Parse diff DDL to count changes
                var changeCount = CountChangesInDdl(diffDdl);
                
                DiffDetected?.Invoke(this, new DiffDetectedEventArgs
                {
                    HasChanges = true,
                    DiffDdl = diffDdl,
                    ChangeCount = changeCount,
                    Message = $"Detected {changeCount} change(s) - Click 'Show Diff' to view"
                });
            }
            else
            {
                Logger.Debug("No changes detected by SqlMermaidErdTools");
                DiffDetected?.Invoke(this, new DiffDetectedEventArgs
                {
                    HasChanges = false,
                    Message = "No changes detected"
                });
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during diff comparison");
            DiffDetected?.Invoke(this, new DiffDetectedEventArgs
            {
                HasChanges = false,
                Message = $"Error: {ex.Message}",
                Error = ex
            });
        }
    }
    
    private int CountChangesInDdl(string ddl)
    {
        // Count ALTER TABLE statements
        var alterMatches = System.Text.RegularExpressions.Regex.Matches(
            ddl, 
            @"ALTER\s+TABLE", 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        return alterMatches.Count;
    }
}

public class DiffDetectedEventArgs : EventArgs
{
    public bool HasChanges { get; set; }
    public string? DiffDdl { get; set; }
    public int ChangeCount { get; set; }
    public string Message { get; set; } = string.Empty;
    public Exception? Error { get; set; }
}
```

**Integration with MermaidDesignerWindow:**
```csharp
private void MermaidEditor_TextChanged(object sender, EventArgs e)
{
    var currentMermaid = MermaidEditor.Text;
    
    // Update live preview
    _ = UpdatePreviewAsync(currentMermaid);
    
    // Trigger diff check (debounced)
    _ = _diffComparisonService.CheckForDifferencesAsync(currentMermaid);
}

private void DiffComparisonService_DiffDetected(object? sender, DiffDetectedEventArgs e)
{
    Dispatcher.Invoke(() =>
    {
        if (e.HasChanges)
        {
            DiffStatusText.Text = e.Message;
            DiffStatusText.Foreground = new SolidColorBrush(Colors.Orange);
            ShowDiffButton.IsEnabled = true;
            GenerateDdlButton.IsEnabled = true;
            
            // Store diff DDL for later use
            _currentDiffDdl = e.DiffDdl;
        }
        else
        {
            DiffStatusText.Text = e.Message;
            DiffStatusText.Foreground = new SolidColorBrush(Colors.Gray);
            ShowDiffButton.IsEnabled = false;
            GenerateDdlButton.IsEnabled = false;
            _currentDiffDdl = null;
        }
    });
}
```

---

### Component 4: Diff Script Editor Integration

**File:** `Dialogs/MermaidDesignerWindow.xaml.cs` (enhancement)

**Purpose:** Open generated diff scripts in a new SQL editor tab with the same connection, for manual verification and execution.

**Key Features:**
- **New Editor Tab**: Create new ConnectionTabControl tab (or use existing)
- **Same Connection**: Use the same connection profile as Mermaid designer
- **Diff Script Loading**: Load generated ALTER statements into SQL editor
- **Manual Execution**: User reviews and executes manually (F5)
- **Clear Indication**: Status bar shows "Migration script loaded - Review before executing"

**Implementation:**
```csharp
private async Task OpenDiffScriptInEditorAsync(string diffDdl)
{
    try
    {
        Logger.Info("Opening diff script in SQL editor - {Length} characters", diffDdl.Length);
        
        // Find or create connection tab with same connection
        var connectionInfo = _connectionManager.ConnectionInfo;
        var connectionTab = FindOrCreateConnectionTab(connectionInfo);
        
        if (connectionTab == null)
        {
            Logger.Error("Could not find or create connection tab");
            MessageBox.Show(
                "Could not open SQL editor. Please ensure a connection tab is available.",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            return;
        }
        
        // Load diff script into SQL editor
        connectionTab.LoadScriptIntoEditor(diffDdl);
        
        // Switch to the connection tab
        SwitchToConnectionTab(connectionTab);
        
        // Show confirmation
        MessageBox.Show(
            $"Migration script loaded into SQL editor.\n\n" +
            $"Connection: {connectionInfo.ConnectionName}\n" +
            $"Script length: {diffDdl.Length} characters\n\n" +
            $"⚠️ REVIEW CAREFULLY before executing (F5)",
            "Diff Script Loaded",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
        
        Logger.Info("Diff script successfully loaded into SQL editor");
    }
    catch (Exception ex)
    {
        Logger.Error(ex, "Failed to open diff script in editor");
        MessageBox.Show(
            $"Failed to open diff script in editor:\n\n{ex.Message}",
            "Error",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }
}

private ConnectionTabControl? FindOrCreateConnectionTab(IConnectionInfo connectionInfo)
{
    // Check if tab already exists for this connection
    var existingTab = MainWindow.Instance?.ConnectionTabs
        .FirstOrDefault(t => t.ConnectionInfo.ConnectionName == connectionInfo.ConnectionName);
    
    if (existingTab != null)
    {
        Logger.Debug("Found existing connection tab: {Connection}", connectionInfo.ConnectionName);
        return existingTab;
    }
    
    // Create new tab
    Logger.Info("Creating new connection tab for: {Connection}", connectionInfo.ConnectionName);
    var newTab = MainWindow.Instance?.CreateNewConnectionTab(connectionInfo);
    
    return newTab;
}

private void SwitchToConnectionTab(ConnectionTabControl tab)
{
    // Find tab item containing this control
    var tabControl = MainWindow.Instance?.MainTabControl;
    if (tabControl == null)
        return;
    
    foreach (TabItem item in tabControl.Items)
    {
        if (item.Content == tab)
        {
            tabControl.SelectedItem = item;
            Logger.Debug("Switched to connection tab");
            break;
        }
    }
}
```

**Enhanced ConnectionTabControl Method:**
```csharp
// In ConnectionTabControl.xaml.cs
public void LoadScriptIntoEditor(string sqlScript, string? title = null)
{
    Logger.Info("Loading script into SQL editor - {Length} characters", sqlScript.Length);
    
    // Clear existing content
    SqlEditor.Text = sqlScript;
    SqlEditor.Focus();
    
    // Move cursor to top
    SqlEditor.CaretOffset = 0;
    SqlEditor.ScrollToHome();
    
    // Update status bar
    if (!string.IsNullOrEmpty(title))
    {
        StatusText.Text = $"📝 {title} - REVIEW before executing (F5)";
    }
    else
    {
        StatusText.Text = "📝 Migration script loaded - REVIEW before executing (F5)";
    }
    StatusText.Foreground = new SolidColorBrush(Colors.Orange);
    
    // Highlight the editor to draw attention
    SqlEditor.Background = new SolidColorBrush(Color.FromArgb(20, 255, 165, 0)); // Light orange
    
    // Reset background after 3 seconds
    var timer = new Timer(3000);
    timer.Elapsed += (s, e) =>
    {
        Dispatcher.Invoke(() =>
        {
            SqlEditor.Background = Brushes.White; // or theme-aware background
            timer.Stop();
            timer.Dispose();
        });
    };
    timer.Start();
}
```

---

## 🔄 COMPLETE USER WORKFLOW

### Workflow 1: Select Tables with FK Navigation

**Step 1: Open Mermaid Designer**
```
View → Mermaid Visual Designer
```

**Step 2: Load Tables from Database**
```
Click "🔽 Load from DB" button
```

**Step 3: Enhanced Table Selection Dialog Opens**
```
User sees:
- List of all tables in selected schema
- FK relationship indicators for each table
- Search/filter functionality
```

**Step 4: Select Initial Tables**
```
User checks:
☑ CUSTOMERS
☑ ORDERS
```

**Step 5: Follow Foreign Keys (Forward)**
```
User clicks "Follow Foreign Keys →" button

System:
1. Queries SYSCAT.REFERENCES for CUSTOMERS and ORDERS
2. Finds: ORDERS → ORDER_ITEMS (via ORDER_ID)
3. Finds: ORDER_ITEMS → PRODUCTS (via PRODUCT_ID)
4. Automatically checks:
   ☑ ORDER_ITEMS
   ☑ PRODUCTS

Status: "Added 2 tables via foreign key relationships"
```

**Step 6: Follow Incoming FKs (Backward)**
```
User clicks "← Follow Incoming FKs" button

System:
1. Queries SYSCAT.REFERENCES for incoming FKs to selected tables
2. Finds: SHIPMENTS → ORDERS (via ORDER_ID)
3. Finds: PAYMENTS → ORDERS (via ORDER_ID)
4. Automatically checks:
   ☑ SHIPMENTS
   ☑ PAYMENTS

Status: "Added 2 tables via incoming foreign key relationships"
```

**Step 7: Expand All Related (Optional)**
```
User clicks "Expand All Related" button

System:
1. Recursively follows all FK relationships (both directions)
2. Adds all connected tables to selection
3. Shows complete relationship graph

Result: All tables in the FK relationship chain are selected
```

**Step 8: Confirm Selection**
```
User clicks "Add to Model" button

System:
1. Generates Mermaid ERD from selected tables
2. Displays in editor
3. **CRITICAL: Captures baseline snapshot**
4. Shows status: "Baseline: 6 tables from FKKTOTST (2025-01-27 14:30:00)"
```

---

### Workflow 2: Modify Mermaid & Auto-Diff Detection

**Step 1: User Has Baseline Loaded**
```
Status bar shows: "Baseline: 6 tables from FKKTOTST (2025-01-27 14:30:00)"
```

**Step 2: User Edits Mermaid Script**
```
User adds column to CUSTOMERS table:
CUSTOMERS {
    int CUSTOMER_ID PK
    varchar NAME
    varchar EMAIL
    varchar PHONE  ← NEW COLUMN ADDED
}
```

**Step 3: Auto-Diff Detection (Debounced)**
```
System (after 1 second):
1. Detects Mermaid text changed
2. Retrieves baseline snapshot
3. Calls SqlMermaidErdTools.GenerateDiffAlterStatements()
4. Generates ALTER TABLE statement
5. Updates status bar: "Detected 1 change(s) - Click 'Show Diff' to view"
```

**Step 4: User Clicks "Show Diff"**
```
System:
1. Shows diff panel with color-coded changes
2. Displays generated ALTER statement:
   ALTER TABLE FK.CUSTOMERS
       ADD COLUMN PHONE VARCHAR(255);
3. Shows "Generate DDL" button enabled
```

**Step 5: User Clicks "Generate DDL"**
```
System:
1. Uses SqlMermaidErdTools to generate final diff DDL
2. Opens new SQL editor tab with same connection (FKKTOTST)
3. Loads ALTER statement into editor
4. Shows warning: "⚠️ REVIEW CAREFULLY before executing (F5)"
5. Highlights editor background (orange tint)
```

**Step 6: User Reviews & Executes**
```
User:
1. Reviews ALTER statement in SQL editor
2. Verifies column name, data type, nullability
3. Presses F5 to execute
4. Confirms execution in dialog
5. Database updated
```

**Step 7: Refresh Baseline (Optional)**
```
User clicks "🔽 Load from DB" again

System:
1. Reloads current database state
2. **Updates baseline snapshot** with new state
3. Status: "Baseline: 6 tables from FKKTOTST (2025-01-27 14:35:00)"
4. Mermaid diagram now includes PHONE column
```

---

## 📋 SQL STATEMENTS REQUIRED

### Get Foreign Keys for Table (Outgoing)
**Statement Name:** `GetForeignKeysForTable`

**SQL:**
```sql
SELECT 
    TRIM(r.REFTABSCHEMA) AS REFTABSCHEMA,
    TRIM(r.REFTABNAME) AS REFTABNAME,
    TRIM(r.CONSTNAME) AS CONSTNAME,
    r.FK_COLNAMES,
    r.PK_COLNAMES
FROM SYSCAT.REFERENCES r
WHERE r.TABSCHEMA = ?
  AND r.TABNAME = ?
ORDER BY r.CONSTNAME
```

### Get Incoming Foreign Keys
**Statement Name:** `GetIncomingForeignKeys`

**SQL:**
```sql
SELECT 
    TRIM(r.TABSCHEMA) AS TABSCHEMA,
    TRIM(r.TABNAME) AS TABNAME,
    TRIM(r.CONSTNAME) AS CONSTNAME,
    r.FK_COLNAMES,
    r.PK_COLNAMES
FROM SYSCAT.REFERENCES r
WHERE r.REFTABSCHEMA = ?
  AND r.REFTABNAME = ?
ORDER BY r.CONSTNAME
```

**Add to:** `ConfigFiles/db2_12.1_sql_statements.json`

---

## 🎨 UI ENHANCEMENTS

### Enhanced Status Bar
```
┌─────────────────────────────────────────────────────────────┐
│ Baseline: 6 tables from FKKTOTST (2025-01-27 14:30:00)     │
│ Changes: Detected 1 change(s) - Click 'Show Diff' to view  │
│ [📊 Show Diff] [📝 Generate DDL]                           │
└─────────────────────────────────────────────────────────────┘
```

### Diff Panel (Bottom)
```
┌─────────────────────────────────────────────────────────────┐
│ Schema Changes Detected                                     │
├─────────────────────────────────────────────────────────────┤
│ TABLE: FK.CUSTOMERS                                          │
│   ✅ Added Column: PHONE VARCHAR(255)                       │
│                                                              │
│ Generated ALTER Statement:                                  │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ALTER TABLE FK.CUSTOMERS                                 │ │
│ │     ADD COLUMN PHONE VARCHAR(255);                      │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ [Open in SQL Editor] [Copy to Clipboard] [Close]            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 IMPLEMENTATION CHECKLIST

### Phase 1: Enhanced Table Selection
- [ ] Create `TableSelectionWithFKNavigationDialog.xaml`
- [ ] Create `TableSelectionWithFKNavigationDialog.xaml.cs`
- [ ] Implement `TableSelectionItem` model
- [ ] Implement `ForeignKeyInfo` model
- [ ] Add SQL statements to `db2_12.1_sql_statements.json`:
  - [ ] `GetForeignKeysForTable`
  - [ ] `GetIncomingForeignKeys`
- [ ] Implement `FollowForeignKeysAsync()` method
- [ ] Implement `FollowIncomingForeignKeysAsync()` method
- [ ] Implement `ExpandAllRelatedAsync()` method
- [ ] Add FK relationship visualization in UI
- [ ] Wire up to "Load from DB" button
- [ ] Add comprehensive DEBUG logging

### Phase 2: Baseline Snapshot Management
- [ ] Create `MermaidBaselineSnapshotService.cs`
- [ ] Implement `CaptureBaselineAsync()` method
- [ ] Implement `GetBaseline()` method
- [ ] Implement `GetBaselineMetadata()` method
- [ ] Add baseline status display to MermaidDesignerWindow
- [ ] Auto-capture baseline when loading from DB
- [ ] Add "Clear Baseline" functionality
- [ ] Add comprehensive DEBUG logging

### Phase 3: Automated Diff Detection
- [ ] Create `MermaidDiffComparisonService.cs`
- [ ] Implement `CheckForDifferencesAsync()` method
- [ ] Integrate with SqlMermaidErdTools
- [ ] Add debounced text change detection
- [ ] Implement `DiffDetected` event
- [ ] Wire up event handler in MermaidDesignerWindow
- [ ] Update status bar with diff information
- [ ] Add comprehensive DEBUG logging

### Phase 4: Diff Script Editor Integration
- [ ] Enhance `MermaidDesignerWindow.xaml.cs` with `OpenDiffScriptInEditorAsync()`
- [ ] Implement `FindOrCreateConnectionTab()` method
- [ ] Implement `SwitchToConnectionTab()` method
- [ ] Enhance `ConnectionTabControl.LoadScriptIntoEditor()` method
- [ ] Add visual highlighting for loaded scripts
- [ ] Add confirmation dialogs
- [ ] Wire up "Generate DDL" button to open in editor
- [ ] Add comprehensive DEBUG logging

### Phase 5: Testing & Validation
- [ ] Test FK navigation (forward direction)
- [ ] Test FK navigation (backward direction)
- [ ] Test "Expand All Related" functionality
- [ ] Test baseline capture on load
- [ ] Test diff detection on Mermaid edit
- [ ] Test diff script generation
- [ ] Test opening diff script in SQL editor
- [ ] Test manual execution of ALTER statements
- [ ] Test baseline refresh after changes
- [ ] Verify all DEBUG logging works correctly

---

## 🎯 SUCCESS CRITERIA

✅ **User can:**
1. Select tables with easy FK navigation (forward and backward)
2. Expand model to include all related tables automatically
3. See baseline snapshot status at all times
4. Modify Mermaid script and see automatic diff detection
5. Generate diff scripts that open in SQL editor
6. Review and execute diff scripts manually
7. Refresh baseline after making changes

✅ **System provides:**
1. Intelligent FK relationship following
2. Persistent baseline snapshot management
3. Real-time diff detection using SqlMermaidErdTools
4. Seamless integration with SQL editor
5. Clear status messages at each step
6. Comprehensive error handling
7. Full DEBUG logging for troubleshooting

---

## 📝 RELATED DOCUMENTATION

- **Mermaid Visual Designer Advanced Spec**: `Docs/MERMAID_VISUAL_DESIGNER_ADVANCED_SPEC.md`
- **SqlMermaidErdTools Integration**: `Docs/SQLMERMAIDERDTOOLS_INTEGRATION.md`
- **Mermaid Workflow Design**: `MERMAID_WORKFLOW_DESIGN.md`
- **Mermaid Diagram Generator Spec**: `Docs/MERMAID_DIAGRAM_GENERATOR_SPEC.md`

---

**Last Updated:** 2025-01-27  
**Status:** 📋 SPECIFICATION COMPLETE  
**Next Step:** Implementation Phase 1
