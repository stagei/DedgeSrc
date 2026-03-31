# Mermaid Visual Database Designer - Advanced Specification

**Feature:** Visual database design with live diff detection and DDL generation  
**Concept:** Edit database structure visually, generate migration scripts  
**Output:** CREATE/ALTER TABLE scripts based on diagram changes

---

## 🎯 ADVANCED WORKFLOW

### Phase 1: Load Current Database State
```
User selects tables → Generate .mmd from DB2 → Load in editor
```

### Phase 2: Visual Editing
```
User edits .mmd → Live preview updates → Diff detection runs
```

### Phase 3: Generate Migration Scripts
```
User clicks "Generate DDL" → Compare original vs edited → Create ALTER scripts → Open in SQL editor
```

### Phase 4: Manual Execution
```
User reviews scripts → Executes manually → Database updated
```

---

## 🏗️ COMPONENT ARCHITECTURE

### Component 1: Dual-Pane Editor/Viewer

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│ Mermaid Visual Designer                                 │
├──────────────────┬──────────────────────────────────────┤
│ Mermaid Source   │ Live Preview                         │
│ (Editable)       │ (Read-only, updates on change)      │
├──────────────────┼──────────────────────────────────────┤
│ erDiagram        │ [Rendered Diagram]                   │
│   CUSTOMERS {    │                                      │
│     int ID PK    │  ┌─────────────┐                    │
│     varchar NAME │  │  CUSTOMERS  │                    │
│   }              │  ├─────────────┤                    │
│                  │  │ ID (PK)     │                    │
│ CUSTOMERS ||--o{│  │ NAME        │                    │
│   ORDERS         │  └─────────────┘                    │
│                  │         │                            │
│                  │         ▼                            │
│                  │  ┌─────────────┐                    │
│                  │  │   ORDERS    │                    │
│                  │  └─────────────┘                    │
├──────────────────┴──────────────────────────────────────┤
│ 🔄 Changes Detected: 2 tables modified, 1 column added │
│ [📊 Show Diff] [⚡ Generate DDL Scripts]               │
└─────────────────────────────────────────────────────────┘
```

**File:** `Controls/MermaidVisualDesignerPanel.xaml`

```xml
<UserControl>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/> <!-- Status bar -->
            <RowDefinition Height="Auto"/> <!-- Actions -->
        </Grid.RowDefinitions>
        
        <Grid Grid.Row="0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="5"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <!-- Left: Mermaid Source Editor -->
            <Grid Grid.Column="0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="10">
                    <Button x:Name="LoadFromDBButton" 
                            Content="📥 Load from DB" 
                            Click="LoadFromDB_Click" 
                            Padding="10,5"/>
                    <Button x:Name="RevertButton" 
                            Content="↩️ Revert Changes" 
                            Click="Revert_Click" 
                            Padding="10,5" 
                            Margin="10,0,0,0"/>
                </StackPanel>
                
                <avalonedit:TextEditor Grid.Row="1" 
                                       x:Name="MermaidEditor"
                                       FontFamily="Consolas"
                                       FontSize="12"
                                       ShowLineNumbers="True"
                                       TextChanged="MermaidEditor_TextChanged"/>
            </Grid>
            
            <GridSplitter Grid.Column="1" HorizontalAlignment="Stretch"/>
            
            <!-- Right: Live Preview -->
            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <TextBlock Grid.Row="0" 
                           Text="Live Preview (Click tables to open properties)" 
                           Margin="10"
                           FontWeight="Bold"/>
                
                <wv2:WebView2 Grid.Row="1" 
                              x:Name="PreviewWebView"
                              Margin="10"/>
            </Grid>
        </Grid>
        
        <!-- Status Bar (Shows Diff Summary) -->
        <Border Grid.Row="1" 
                Background="{DynamicResource SystemControlBackgroundAccentBrush}"
                Padding="10">
            <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="DiffStatusText" 
                           Text="No changes detected"
                           Foreground="White"
                           FontWeight="Bold"/>
                <Button x:Name="ShowDiffButton" 
                        Content="📊 Show Detailed Diff" 
                        Click="ShowDiff_Click" 
                        Padding="8,4" 
                        Margin="20,0,0,0"
                        Visibility="Collapsed"/>
            </StackPanel>
        </Border>
        
        <!-- Actions -->
        <StackPanel Grid.Row="2" 
                    Orientation="Horizontal" 
                    HorizontalAlignment="Right" 
                    Margin="10">
            <Button x:Name="GenerateDDLButton" 
                    Content="⚡ Generate DDL Scripts" 
                    Click="GenerateDDL_Click" 
                    Padding="15,8"
                    IsEnabled="False"/>
            <Button x:Name="SaveMermaidButton" 
                    Content="💾 Save .mmd File" 
                    Click="SaveMermaid_Click" 
                    Padding="15,8" 
                    Margin="10,0,0,0"/>
            <Button x:Name="ExportImageButton" 
                    Content="📸 Export PNG" 
                    Click="ExportImage_Click" 
                    Padding="15,8" 
                    Margin="10,0,0,0"/>
        </StackPanel>
    </Grid>
</UserControl>
```

---

## 🔄 DIFF DETECTION ENGINE

### Component 2: Schema Diff Analyzer

**Service:** `Services/SchemaDiffAnalyzerService.cs`

**Purpose:** Compare original DB2 structure with edited Mermaid diagram

**Models:**
```csharp
public class SchemaDiff
{
    public List<TableDiff> TableChanges { get; set; } = new();
    public bool HasChanges => TableChanges.Any(t => t.HasChanges);
    public int TotalChanges => TableChanges.Sum(t => t.ChangeCount);
}

public class TableDiff
{
    public string TableName { get; set; }
    public string Schema { get; set; }
    public TableChangeType ChangeType { get; set; } // Added, Removed, Modified
    
    // Column changes
    public List<ColumnChange> AddedColumns { get; set; } = new();
    public List<ColumnChange> RemovedColumns { get; set; } = new();
    public List<ColumnChange> ModifiedColumns { get; set; } = new();
    
    // Relationship changes
    public List<FKChange> AddedForeignKeys { get; set; } = new();
    public List<FKChange> RemovedForeignKeys { get; set; } = new();
    
    public bool HasChanges => 
        AddedColumns.Any() || 
        RemovedColumns.Any() || 
        ModifiedColumns.Any() || 
        AddedForeignKeys.Any() || 
        RemovedForeignKeys.Any() ||
        ChangeType != TableChangeType.None;
    
    public int ChangeCount => 
        AddedColumns.Count + 
        RemovedColumns.Count + 
        ModifiedColumns.Count + 
        AddedForeignKeys.Count + 
        RemovedForeignKeys.Count;
}

public enum TableChangeType
{
    None,
    Added,      // New table in diagram
    Removed,    // Table removed from diagram
    Modified    // Table structure changed
}

public class ColumnChange
{
    public string ColumnName { get; set; }
    public string? OldDataType { get; set; }
    public string? NewDataType { get; set; }
    public bool? OldNullable { get; set; }
    public bool? NewNullable { get; set; }
    public bool IsPrimaryKeyChange { get; set; }
    public ChangeType Type { get; set; } // Added, Removed, TypeChanged, NullabilityChanged
}

public class FKChange
{
    public string ConstraintName { get; set; }
    public string FromTable { get; set; }
    public string ToTable { get; set; }
    public List<string> Columns { get; set; }
    public ChangeType Type { get; set; } // Added, Removed
}

public enum ChangeType
{
    Added,
    Removed,
    Modified
}
```

**Key Methods:**
```csharp
public class SchemaDiffAnalyzerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Compare original DB2 structure with edited Mermaid diagram
    /// </summary>
    public async Task<SchemaDiff> AnalyzeDifferencesAsync(
        string originalMermaid,
        string editedMermaid,
        DB2ConnectionManager connectionManager)
    {
        Logger.Info("Analyzing differences between original and edited diagrams");
        
        // 1. Parse original Mermaid (from DB2)
        var originalTables = ParseMermaidDiagram(originalMermaid);
        
        // 2. Parse edited Mermaid (user modifications)
        var editedTables = ParseMermaidDiagram(editedMermaid);
        
        // 3. Compare structures
        var diff = new SchemaDiff();
        
        // Detect added tables
        var addedTables = editedTables.Keys.Except(originalTables.Keys);
        foreach (var table in addedTables)
        {
            diff.TableChanges.Add(new TableDiff
            {
                TableName = table,
                ChangeType = TableChangeType.Added
            });
        }
        
        // Detect removed tables
        var removedTables = originalTables.Keys.Except(editedTables.Keys);
        foreach (var table in removedTables)
        {
            diff.TableChanges.Add(new TableDiff
            {
                TableName = table,
                ChangeType = TableChangeType.Removed
            });
        }
        
        // Detect modified tables
        var commonTables = originalTables.Keys.Intersect(editedTables.Keys);
        foreach (var tableName in commonTables)
        {
            var tableDiff = CompareTableStructures(
                originalTables[tableName], 
                editedTables[tableName]);
            
            if (tableDiff.HasChanges)
            {
                diff.TableChanges.Add(tableDiff);
            }
        }
        
        Logger.Info("Diff analysis complete - {Count} tables changed", diff.TableChanges.Count);
        return diff;
    }
    
    /// <summary>
    /// Parse Mermaid ER diagram syntax into structured data
    /// </summary>
    private Dictionary<string, MermaidTable> ParseMermaidDiagram(string mermaidCode)
    {
        var tables = new Dictionary<string, MermaidTable>();
        
        // Regex patterns to parse Mermaid syntax
        // Pattern for table definition: TABLENAME { ... }
        // Pattern for column: datatype columnname PK/FK "comment"
        // Pattern for relationship: TABLE1 ||--o{ TABLE2 : "name"
        
        var lines = mermaidCode.Split('\n');
        MermaidTable? currentTable = null;
        
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            
            // Detect table start: TABLENAME {
            if (Regex.IsMatch(trimmed, @"^(\w+)\s*\{"))
            {
                var match = Regex.Match(trimmed, @"^(\w+)\s*\{");
                currentTable = new MermaidTable { Name = match.Groups[1].Value };
                tables[currentTable.Name] = currentTable;
            }
            // Detect table end: }
            else if (trimmed == "}")
            {
                currentTable = null;
            }
            // Detect column definition
            else if (currentTable != null && !string.IsNullOrWhiteSpace(trimmed))
            {
                var column = ParseMermaidColumn(trimmed);
                if (column != null)
                {
                    currentTable.Columns.Add(column);
                }
            }
            // Detect relationship
            else if (Regex.IsMatch(trimmed, @"\|\|--|\}o--|--o\{|--\|\{"))
            {
                var relationship = ParseMermaidRelationship(trimmed);
                // Store for FK generation
            }
        }
        
        return tables;
    }
    
    /// <summary>
    /// Compare two table structures and detect changes
    /// </summary>
    private TableDiff CompareTableStructures(
        MermaidTable original, 
        MermaidTable edited)
    {
        var diff = new TableDiff
        {
            TableName = original.Name,
            ChangeType = TableChangeType.Modified
        };
        
        // Compare columns
        var originalCols = original.Columns.Select(c => c.Name).ToHashSet();
        var editedCols = edited.Columns.Select(c => c.Name).ToHashSet();
        
        // Added columns
        foreach (var colName in editedCols.Except(originalCols))
        {
            var column = edited.Columns.First(c => c.Name == colName);
            diff.AddedColumns.Add(new ColumnChange
            {
                ColumnName = colName,
                NewDataType = column.DataType,
                NewNullable = column.IsNullable,
                Type = ChangeType.Added
            });
        }
        
        // Removed columns
        foreach (var colName in originalCols.Except(editedCols))
        {
            diff.RemovedColumns.Add(new ColumnChange
            {
                ColumnName = colName,
                Type = ChangeType.Removed
            });
        }
        
        // Modified columns (type or nullability changed)
        foreach (var colName in originalCols.Intersect(editedCols))
        {
            var origCol = original.Columns.First(c => c.Name == colName);
            var editCol = edited.Columns.First(c => c.Name == colName);
            
            if (origCol.DataType != editCol.DataType || 
                origCol.IsNullable != editCol.IsNullable ||
                origCol.IsPrimaryKey != editCol.IsPrimaryKey)
            {
                diff.ModifiedColumns.Add(new ColumnChange
                {
                    ColumnName = colName,
                    OldDataType = origCol.DataType,
                    NewDataType = editCol.DataType,
                    OldNullable = origCol.IsNullable,
                    NewNullable = editCol.IsNullable,
                    Type = ChangeType.Modified
                });
            }
        }
        
        return diff;
    }
}
```

---

## ⚡ LIVE DIFF DETECTION

### Real-Time Change Tracking

**Implementation:**
```csharp
public partial class MermaidVisualDesignerPanel : UserControl
{
    private string _originalMermaid = string.Empty;
    private Timer? _diffCheckTimer;
    
    private void MermaidEditor_TextChanged(object sender, EventArgs e)
    {
        // Debounce: Wait 500ms after user stops typing
        _diffCheckTimer?.Stop();
        _diffCheckTimer = new Timer(500);
        _diffCheckTimer.Elapsed += async (s, args) =>
        {
            await DetectChangesAsync();
        };
        _diffCheckTimer.Start();
        
        // Update live preview immediately
        _ = UpdatePreviewAsync();
    }
    
    private async Task DetectChangesAsync()
    {
        var currentMermaid = MermaidEditor.Text;
        
        if (currentMermaid == _originalMermaid)
        {
            // No changes
            Dispatcher.Invoke(() =>
            {
                DiffStatusText.Text = "No changes detected";
                DiffStatusText.Foreground = new SolidColorBrush(Colors.Gray);
                GenerateDDLButton.IsEnabled = false;
                ShowDiffButton.Visibility = Visibility.Collapsed;
            });
            return;
        }
        
        // Analyze differences
        var diffService = new SchemaDiffAnalyzerService();
        var diff = await diffService.AnalyzeDifferencesAsync(
            _originalMermaid, 
            currentMermaid, 
            _connectionManager);
        
        if (diff.HasChanges)
        {
            Dispatcher.Invoke(() =>
            {
                var summary = BuildDiffSummary(diff);
                DiffStatusText.Text = summary;
                DiffStatusText.Foreground = new SolidColorBrush(Colors.Orange);
                GenerateDDLButton.IsEnabled = true;
                ShowDiffButton.Visibility = Visibility.Visible;
            });
            
            // Store diff for DDL generation
            _currentDiff = diff;
        }
    }
    
    private string BuildDiffSummary(SchemaDiff diff)
    {
        var parts = new List<string>();
        
        var tablesAdded = diff.TableChanges.Count(t => t.ChangeType == TableChangeType.Added);
        var tablesRemoved = diff.TableChanges.Count(t => t.ChangeType == TableChangeType.Removed);
        var tablesModified = diff.TableChanges.Count(t => t.ChangeType == TableChangeType.Modified);
        
        if (tablesAdded > 0) parts.Add($"{tablesAdded} table(s) added");
        if (tablesRemoved > 0) parts.Add($"{tablesRemoved} table(s) removed");
        if (tablesModified > 0) parts.Add($"{tablesModified} table(s) modified");
        
        var totalColumnChanges = diff.TableChanges.Sum(t => t.ChangeCount);
        parts.Add($"{totalColumnChanges} total changes");
        
        return "🔄 Changes: " + string.Join(", ", parts);
    }
}
```

---

## 📝 DDL SCRIPT GENERATION

### Component 3: DDL Generator from Diff

**Service:** `Services/DiffBasedDdlGeneratorService.cs`

**Purpose:** Generate CREATE/ALTER scripts based on detected changes

**Key Method:**
```csharp
public class DiffBasedDdlGeneratorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Generate DDL scripts from schema diff
    /// </summary>
    public string GenerateMigrationScripts(SchemaDiff diff, string targetSchema)
    {
        Logger.Info("Generating migration scripts for {Count} changed tables", diff.TableChanges.Count);
        
        var ddl = new StringBuilder();
        ddl.AppendLine("-- Migration Script Generated from Mermaid Diagram");
        ddl.AppendLine($"-- Generated: {DateTime.Now}");
        ddl.AppendLine($"-- Target Schema: {targetSchema}");
        ddl.AppendLine("-- WARNING: Review carefully before executing!");
        ddl.AppendLine();
        
        // 1. CREATE new tables
        foreach (var table in diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Added))
        {
            ddl.AppendLine(GenerateCreateTableScript(table, targetSchema));
            ddl.AppendLine();
        }
        
        // 2. ALTER existing tables
        foreach (var table in diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Modified))
        {
            ddl.AppendLine($"-- Modify table: {targetSchema}.{table.TableName}");
            ddl.AppendLine();
            
            // Add new columns
            foreach (var col in table.AddedColumns)
            {
                ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                ddl.AppendLine($"  ADD COLUMN {col.ColumnName} {col.NewDataType}");
                if (col.NewNullable == false)
                    ddl.AppendLine("  NOT NULL");
                ddl.AppendLine(";");
                ddl.AppendLine();
            }
            
            // Modify existing columns
            foreach (var col in table.ModifiedColumns)
            {
                ddl.AppendLine($"-- Modify column: {col.ColumnName}");
                ddl.AppendLine($"-- Old type: {col.OldDataType}, New type: {col.NewDataType}");
                ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                ddl.AppendLine($"  ALTER COLUMN {col.ColumnName} SET DATA TYPE {col.NewDataType};");
                ddl.AppendLine();
                
                // Handle nullability change
                if (col.OldNullable != col.NewNullable)
                {
                    if (col.NewNullable == false)
                    {
                        ddl.AppendLine($"-- Make column NOT NULL");
                        ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                        ddl.AppendLine($"  ALTER COLUMN {col.ColumnName} SET NOT NULL;");
                    }
                    else
                    {
                        ddl.AppendLine($"-- Make column NULLABLE");
                        ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                        ddl.AppendLine($"  ALTER COLUMN {col.ColumnName} DROP NOT NULL;");
                    }
                    ddl.AppendLine();
                }
            }
            
            // Remove columns (with warning)
            foreach (var col in table.RemovedColumns)
            {
                ddl.AppendLine($"-- WARNING: Removing column will DELETE DATA!");
                ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                ddl.AppendLine($"  DROP COLUMN {col.ColumnName};");
                ddl.AppendLine();
            }
            
            // Add foreign keys
            foreach (var fk in table.AddedForeignKeys)
            {
                ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                ddl.AppendLine($"  ADD CONSTRAINT {fk.ConstraintName}");
                ddl.AppendLine($"  FOREIGN KEY ({string.Join(", ", fk.Columns)})");
                ddl.AppendLine($"  REFERENCES {fk.ToTable} ({string.Join(", ", fk.Columns)});");
                ddl.AppendLine();
            }
            
            // Remove foreign keys
            foreach (var fk in table.RemovedForeignKeys)
            {
                ddl.AppendLine($"ALTER TABLE {targetSchema}.{table.TableName}");
                ddl.AppendLine($"  DROP CONSTRAINT {fk.ConstraintName};");
                ddl.AppendLine();
            }
        }
        
        // 3. DROP removed tables (at end, with warnings)
        foreach (var table in diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Removed))
        {
            ddl.AppendLine($"-- WARNING: Dropping table will DELETE ALL DATA!");
            ddl.AppendLine($"-- Table: {targetSchema}.{table.TableName}");
            ddl.AppendLine($"-- DROP TABLE {targetSchema}.{table.TableName};");
            ddl.AppendLine($"-- (Commented out for safety - uncomment to execute)");
            ddl.AppendLine();
        }
        
        Logger.Info("Migration scripts generated successfully");
        return ddl.ToString();
    }
    
    private string GenerateCreateTableScript(TableDiff table, string schema)
    {
        var ddl = new StringBuilder();
        ddl.AppendLine($"-- Create new table: {schema}.{table.TableName}");
        ddl.AppendLine($"CREATE TABLE {schema}.{table.TableName} (");
        
        var columnDefs = new List<string>();
        foreach (var col in table.AddedColumns)
        {
            var def = $"    {col.ColumnName} {col.NewDataType}";
            if (col.NewNullable == false)
                def += " NOT NULL";
            if (col.IsPrimaryKeyChange)
                def += " PRIMARY KEY";
            columnDefs.Add(def);
        }
        
        ddl.AppendLine(string.Join(",\n", columnDefs));
        ddl.AppendLine(");");
        
        return ddl.ToString();
    }
}
```

---

## 🖥️ USER EXPERIENCE FLOW

### Step-by-Step Workflow:

**1. User Opens Visual Designer**
```
View → Mermaid Visual Designer
```

**2. Select Tables**
```
Left panel: TreeView with schemas/tables
User checks: FK.CUSTOMERS, FK.ORDERS, FK.PRODUCTS
Click "Load from DB"
```

**3. System Generates Original Mermaid**
```
Background Process:
- Query SYSCAT.COLUMNS for all selected tables
- Query SYSCAT.REFERENCES for relationships
- Generate Mermaid ER diagram
- Load into left editor (original state saved)
- Render in right preview
```

**4. User Edits Diagram**
```
User modifies in left editor:
- Add new column: ALTER TABLE CUSTOMERS ADD EMAIL VARCHAR(255)
- Change data type: CUSTOMER_NAME VARCHAR(100) → VARCHAR(200)
- Add new FK relationship: ORDERS ||--o{ SHIPMENTS

Changes:
erDiagram
    CUSTOMERS {
        INTEGER CUSTOMER_ID PK
        VARCHAR(200) CUSTOMER_NAME    ← CHANGED (was 100)
        VARCHAR(255) EMAIL             ← NEW COLUMN ADDED
    }
    ORDERS ||--o{ SHIPMENTS : "shipped"  ← NEW RELATIONSHIP
```

**5. Live Diff Detection (Automatic)**
```
Status bar updates immediately:
🔄 Changes: 1 table modified, 1 column added, 1 type changed, 1 FK added

Preview updates in real-time (right panel)
"Generate DDL Scripts" button becomes enabled
```

**6. User Clicks "Show Detailed Diff"**
```
Opens dialog showing:

TABLE: CUSTOMERS
  ✅ Added Column: EMAIL VARCHAR(255)
  📝 Modified Column: CUSTOMER_NAME
     Old: VARCHAR(100)
     New: VARCHAR(200)

RELATIONSHIPS:
  ✅ Added FK: ORDERS → SHIPMENTS
```

**7. User Clicks "Generate DDL Scripts"**
```
System generates:
-- Migration Script
ALTER TABLE FK.CUSTOMERS
  ADD COLUMN EMAIL VARCHAR(255);

ALTER TABLE FK.CUSTOMERS
  ALTER COLUMN CUSTOMER_NAME SET DATA TYPE VARCHAR(200);

ALTER TABLE FK.ORDERS
  ADD CONSTRAINT FK_ORD_SHIP
  FOREIGN KEY (SHIPMENT_ID)
  REFERENCES FK.SHIPMENTS (SHIPMENT_ID);
```

**8. Scripts Open in SQL Editor**
```
Automatically opens in ConnectionTabControl SQL editor
User reviews scripts
User executes manually (F5)
Database updated
```

---

## 🔗 INTEGRATION WITH EXISTING FEATURES

### Opening Generated DDL in Current Connection

**Code:**
```csharp
private async void GenerateDDL_Click(object sender, RoutedEventArgs e)
{
    if (_currentDiff == null || !_currentDiff.HasChanges)
    {
        MessageBox.Show("No changes detected to generate scripts for.",
            "Generate DDL", MessageBoxButton.OK, MessageBoxImage.Information);
        return;
    }
    
    try
    {
        // Generate DDL from diff
        var ddlService = new DiffBasedDdlGeneratorService();
        var ddlScripts = ddlService.GenerateMigrationScripts(_currentDiff, _targetSchema);
        
        Logger.Info("DDL scripts generated - {Length} characters", ddlScripts.Length);
        
        // Find active ConnectionTabControl
        var activeTab = GetActiveConnectionTab();
        if (activeTab != null)
        {
            // Inject DDL into SQL editor
            activeTab.LoadScriptIntoEditor(ddlScripts);
            
            // Show message
            MessageBox.Show(
                $"Migration scripts generated and loaded into SQL editor.\n\n" +
                $"Changes detected:\n" +
                $"- {_currentDiff.TotalChanges} total changes\n" +
                $"- {_currentDiff.TableChanges.Count} tables affected\n\n" +
                $"REVIEW CAREFULLY before executing!",
                "DDL Generated", 
                MessageBoxButton.OK, 
                MessageBoxImage.Warning);
            
            // Close designer window, focus SQL editor
            Window.GetWindow(this)?.Close();
        }
        else
        {
            // No active tab - show in dialog
            var window = new Window
            {
                Title = "Generated Migration Scripts",
                Width = 800,
                Height = 600,
                Content = new TextBox 
                { 
                    Text = ddlScripts, 
                    IsReadOnly = true,
                    FontFamily = new FontFamily("Consolas"),
                    VerticalScrollBarVisibility = ScrollBarVisibility.Auto
                }
            };
            window.ShowDialog();
        }
    }
    catch (Exception ex)
    {
        Logger.Error(ex, "Failed to generate DDL scripts");
        MessageBox.Show($"Failed to generate scripts:\n\n{ex.Message}",
            "Error", MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
```

**Add Method to ConnectionTabControl:**
```csharp
public void LoadScriptIntoEditor(string sqlScript)
{
    Logger.Info("Loading script into SQL editor ({Length} characters)", sqlScript.Length);
    
    SqlEditor.Text = sqlScript;
    SqlEditor.Focus();
    
    StatusText.Text = "Migration scripts loaded - REVIEW before executing!";
    StatusText.Foreground = new SolidColorBrush(Colors.Red);
}
```

---

## 📊 DIFF VISUALIZATION

### Detailed Diff Dialog

**File:** `Dialogs/SchemaDiffDialog.xaml`

```xml
<Window Title="Schema Changes Detected" Width="800" Height="600">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TabControl Grid.Row="0">
            <TabItem Header="📊 Summary">
                <DataGrid x:Name="SummaryGrid" AutoGenerateColumns="False">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Table" Binding="{Binding TableName}"/>
                        <DataGridTextColumn Header="Change Type" Binding="{Binding ChangeType}"/>
                        <DataGridTextColumn Header="Changes" Binding="{Binding ChangeCount}"/>
                    </DataGrid.Columns>
                </DataGrid>
            </TabItem>
            
            <TabItem Header="➕ Added Columns">
                <DataGrid x:Name="AddedColumnsGrid" AutoGenerateColumns="False">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Table" Binding="{Binding TableName}"/>
                        <DataGridTextColumn Header="Column" Binding="{Binding ColumnName}"/>
                        <DataGridTextColumn Header="Data Type" Binding="{Binding NewDataType}"/>
                        <DataGridTextColumn Header="Nullable" Binding="{Binding NewNullable}"/>
                    </DataGrid.Columns>
                </DataGrid>
            </TabItem>
            
            <TabItem Header="❌ Removed Columns">
                <DataGrid x:Name="RemovedColumnsGrid" AutoGenerateColumns="False">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Table" Binding="{Binding TableName}"/>
                        <DataGridTextColumn Header="Column" Binding="{Binding ColumnName}"/>
                        <DataGridTextColumn Header="Warning" Value="DATA WILL BE LOST!"/>
                    </DataGrid.Columns>
                </DataGrid>
            </TabItem>
            
            <TabItem Header="📝 Modified Columns">
                <DataGrid x:Name="ModifiedColumnsGrid" AutoGenerateColumns="False">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Table" Binding="{Binding TableName}"/>
                        <DataGridTextColumn Header="Column" Binding="{Binding ColumnName}"/>
                        <DataGridTextColumn Header="Old Type" Binding="{Binding OldDataType}"/>
                        <DataGridTextColumn Header="New Type" Binding="{Binding NewDataType}"/>
                    </DataGrid.Columns>
                </DataGrid>
            </TabItem>
            
            <TabItem Header="🔗 Foreign Keys">
                <StackPanel>
                    <TextBlock Text="Added Foreign Keys:" FontWeight="Bold" Margin="10"/>
                    <DataGrid x:Name="AddedFKGrid" Height="200" Margin="10"/>
                    
                    <TextBlock Text="Removed Foreign Keys:" FontWeight="Bold" Margin="10,20,10,10"/>
                    <DataGrid x:Name="RemovedFKGrid" Height="200" Margin="10"/>
                </StackPanel>
            </TabItem>
        </TabControl>
        
        <Button Grid.Row="1" Content="Close" Click="Close_Click" 
                Padding="15,8" HorizontalAlignment="Right"/>
    </Grid>
</Window>
```

---

## 🎨 VISUAL FEEDBACK FOR CHANGES

### Highlighting Changes in Preview

**Enhanced HTML Template:**
```html
<style>
    /* Highlight tables with changes */
    .entity-added {
        stroke: green !important;
        stroke-width: 3px !important;
    }
    .entity-modified {
        stroke: orange !important;
        stroke-width: 3px !important;
    }
    .entity-removed {
        stroke: red !important;
        stroke-dasharray: 5, 5 !important;
    }
</style>

<script>
    window.highlightChanges = function(changes) {
        // changes = { added: ['TABLE1'], modified: ['TABLE2'], removed: ['TABLE3'] }
        
        changes.added.forEach(table => {
            var element = document.querySelector(`[data-table="${table}"]`);
            if (element) element.classList.add('entity-added');
        });
        
        changes.modified.forEach(table => {
            var element = document.querySelector(`[data-table="${table}"]`);
            if (element) element.classList.add('entity-modified');
        });
        
        changes.removed.forEach(table => {
            var element = document.querySelector(`[data-table="${table}"]`);
            if (element) element.classList.add('entity-removed');
        });
    };
</script>
```

**Call from C#:**
```csharp
// After rendering diagram, highlight changes
var changesJson = JsonSerializer.Serialize(new
{
    added = diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Added).Select(t => t.TableName),
    modified = diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Modified).Select(t => t.TableName),
    removed = diff.TableChanges.Where(t => t.ChangeType == TableChangeType.Removed).Select(t => t.TableName)
});

await PreviewWebView.CoreWebView2.ExecuteScriptAsync($"highlightChanges({changesJson})");
```

---

## 🎯 WHAT'S POSSIBLE vs LIMITATIONS

### ✅ Fully Possible:

1. **Generate Mermaid from DB2** ✅
   - Query all metadata
   - Build ER diagram syntax
   - Include columns, PK, FK

2. **Editable Mermaid in Left Panel** ✅
   - AvalonEdit for editing
   - Syntax highlighting possible
   - User can modify freely

3. **Live Preview in Right Panel** ✅
   - WebView2 with Mermaid.js
   - Updates on text change (debounced)
   - Beautiful rendering

4. **Diff Detection** ✅
   - Parse original Mermaid
   - Parse edited Mermaid
   - Compare structures
   - Detect all changes

5. **Visual Change Highlighting** ✅
   - Color-code changed tables
   - Green = Added
   - Orange = Modified
   - Red = Removed

6. **Click Interactivity** ✅
   - JavaScript click detection
   - Message to C#
   - Open TableDetailsDialog
   - Pass table name

7. **DDL Generation** ✅
   - ALTER TABLE for modifications
   - CREATE TABLE for new tables
   - ADD/DROP COLUMN
   - ADD/DROP CONSTRAINT
   - Change data types

8. **Auto-Open in SQL Editor** ✅
   - Inject into ConnectionTabControl
   - Focus SQL editor
   - User executes manually

---

### ⚠️ Challenges & Solutions:

**Challenge 1: Mermaid Parsing Complexity**
- Mermaid syntax can be complex
- Solution: Use regex patterns + state machine
- Fallback: Structured format only (no freeform)

**Challenge 2: Ambiguous Changes**
- Hard to detect renamed columns vs add/remove
- Solution: Assume add/remove (safer)
- User can manually adjust

**Challenge 3: Complex Data Types**
- DB2 has many data types (DECIMAL(10,2), VARCHAR(100), etc.)
- Solution: Parse with regex, validate against DB2 types

**Challenge 4: Dependency Order**
- FK must be added after referenced tables exist
- Solution: Topological sort of dependencies

**Challenge 5: Data Loss Risk**
- DROP COLUMN, ALTER TYPE can lose data
- Solution: Comment out dangerous operations, add warnings

---

## 📋 IMPLEMENTATION PRIORITY

### High Priority (Core Features):
1. ✅ Generate Mermaid from DB2 (read-only visualization)
2. ✅ Display in WebView2
3. ✅ Click tables to open properties
4. ✅ Save .mmd files

### Medium Priority (Visual Editing):
5. ✅ Editable Mermaid in left panel
6. ✅ Live preview updates
7. ✅ Basic diff detection (added/removed tables)

### Advanced Priority (Full Designer):
8. ✅ Column-level diff detection
9. ✅ DDL script generation
10. ✅ Auto-open in SQL editor
11. ✅ Visual change highlighting

---

## 🎊 RECOMMENDED APPROACH

### Phase 1: Mermaid Viewer Only (4-6 hours)
**Implement:**
- Generate .mmd from DB2 ✅
- Display in WebView2 ✅
- Click to open properties ✅
- Save .mmd files ✅

**Skip for now:**
- Editing capability
- Diff detection
- DDL generation

**Value:** Documentation and visualization

---

### Phase 2: Add Editor + Diff (4-6 hours)
**Implement:**
- Editable left panel ✅
- Live preview ✅
- Diff detection ✅
- Show changes summary ✅

**Skip for now:**
- DDL generation

**Value:** Visual design tool

---

### Phase 3: Full Designer with DDL (4-6 hours)
**Implement:**
- DDL generation from diff ✅
- Auto-open in SQL editor ✅
- Validation and warnings ✅

**Value:** Complete visual database designer

---

## 🎯 FINAL SPECIFICATION SUMMARY

**Feature:** Mermaid Visual Database Designer with Diff & DDL Generation

**Components:**
1. **MermaidDiagramGeneratorService** - Generate .mmd from DB2
2. **SchemaDiffAnalyzerService** - Compare original vs edited
3. **DiffBasedDdlGeneratorService** - Generate ALTER scripts
4. **MermaidVisualDesignerPanel** - Dual-pane editor/viewer
5. **MermaidDiagramViewer** - WebView2 with Mermaid.js
6. **SchemaDiffDialog** - Visual diff display

**Workflow:**
1. Load from DB2 → Generate Mermaid → Save original
2. User edits Mermaid → Live preview updates → Diff detection
3. User reviews diff → Generate DDL → Auto-open in editor
4. User executes manually → Database updated

**Technologies:**
- WebView2 (embedded Chromium)
- Mermaid.js (client-side rendering)
- JavaScript ↔ C# messaging
- Regex parsing for Mermaid syntax
- SYSCAT metadata queries

**Estimated Implementation:**
- Phase 1 (Viewer): 4-6 hours
- Phase 2 (Editor + Diff): 4-6 hours
- Phase 3 (DDL Generation): 4-6 hours
- **Total:** 12-18 hours

**Value:**
- Visual documentation
- Schema comparison tool
- Migration script generator
- Database design tool

---

**Specification Status:** ✅ COMPLETE AND DETAILED  
**Feasibility:** ✅ Fully Possible  
**Complexity:** High (but well-defined)  
**Recommendation:** Implement in phases (viewer first, then editor, then DDL)

