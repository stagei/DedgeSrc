using System;
using System.Data;
using System.Linq;
using System.Windows;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class TableDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly TableRelationshipService _relationshipService;
    private readonly StatisticsService _statisticsService;
    private readonly MetadataHandler _metadataHandler;
    private readonly string _fullTableName;
    private readonly string _schema;
    private readonly string _tableName;

    public string? SelectedRelatedTable { get; private set; }
    public bool ShouldQueryTable { get; private set; }
    
    // Public accessors for GUI testing - allows GuiTestingService to extract form data
    public System.Windows.Controls.DataGrid ColumnsGridPublic => ColumnsGrid;
    public System.Windows.Controls.DataGrid ForeignKeysGridPublic => ForeignKeysGrid;
    public System.Windows.Controls.DataGrid IndexesGridPublic => IndexesGrid;
    public System.Windows.Controls.TextBox DDLTextBoxPublic => DDLTextBox;
    public System.Windows.Controls.DataGrid IncomingFKGridPublic => IncomingFKGrid;
    public System.Windows.Controls.DataGrid PackagesGridPublic => PackagesGrid;
    public System.Windows.Controls.DataGrid ViewsGridPublic => ViewsGrid;
    public System.Windows.Controls.DataGrid RoutinesGridPublic => RoutinesGrid;
    public System.Windows.Controls.TextBlock RowCountTextPublic => RowCountText;
    public System.Windows.Controls.TextBlock ColumnCountTextPublic => ColumnCountText;
    public System.Windows.Controls.TextBlock FKCountTextPublic => FKCountText;
    public System.Windows.Controls.TextBlock IndexCountTextPublic => IndexCountText;
    public System.Windows.Controls.TextBlock TableTypeTextPublic => TableTypeText;
    public System.Windows.Controls.TextBlock TablespaceTextPublic => TablespaceText;

    public TableDetailsDialog(IConnectionManager connectionManager, string fullTableName)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _relationshipService = new TableRelationshipService();
        _statisticsService = new StatisticsService();
        _metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        _fullTableName = fullTableName;
        
        // Parse schema and table name - trim both parts
        var parts = fullTableName.Split('.');
        if (parts.Length == 2)
        {
            _schema = parts[0].Trim();
            _tableName = parts[1].Trim();
        }
        else
        {
            _schema = "";
            _tableName = fullTableName?.Trim() ?? string.Empty;
        }
        
        Logger.Debug("TableDetailsDialog opened for: {Table}", fullTableName);
        
        TableNameText.Text = _tableName;
        TableInfoText.Text = $"Schema: {_schema} • Full Name: {_fullTableName}";
        
        // Apply all UI styles from the unified style service
        this.Loaded += (s, e) => UIStyleService.ApplyStyles(this);
        
        _ = LoadTableDetailsAsync();
    }
    
    /// <summary>
    /// Activates a specific tab by name for automated testing and direct navigation
    /// </summary>
    public void ActivateTab(string? tabName)
    {
        if (string.IsNullOrEmpty(tabName))
            return;
            
        Logger.Debug("Activating tab: {Tab}", tabName);
        
        var tab = tabName.ToLowerInvariant() switch
        {
            "columns" => ColumnsTab,
            "foreign-keys" or "foreignkeys" or "fks" => ForeignKeysTab,
            "indexes" => IndexesTab,
            "ddl-script" or "ddlscript" or "ddl" => DdlScriptTab,
            "statistics" or "stats" => StatisticsTab,
            "incoming-fk" or "incomingfk" or "incoming" => IncomingFKTab,
            "packages" or "used-by-packages" => PackagesTab,
            "views" or "used-by-views" => ViewsTab,
            "routines" or "used-by-routines" => RoutinesTab,
            _ => null
        };
        
        if (tab != null)
        {
            DetailsTabControl.SelectedItem = tab;
            Logger.Info("Activated tab: {Tab}", tabName);
        }
        else
        {
            Logger.Warn("Unknown tab name: {Tab}", tabName);
        }
    }

    private async Task LoadTableDetailsAsync()
    {
        Logger.Info("Loading details for table: {Table}", _fullTableName);
        
        try
        {
            // Load all details in parallel
            var columnsTask = LoadColumnsAsync();
            var foreignKeysTask = LoadForeignKeysAsync();
            var indexesTask = LoadIndexesAsync();
            var statsTask = LoadStatisticsAsync();
            var ddlTask = GenerateDDLAsync();
            var incomingFKTask = LoadIncomingForeignKeysAsync();
            var packagesTask = LoadReferencingPackagesAsync();
            var viewsTask = LoadReferencingViewsAsync();
            var routinesTask = LoadReferencingRoutinesAsync();
            
            await Task.WhenAll(columnsTask, foreignKeysTask, indexesTask, statsTask, ddlTask, 
                              incomingFKTask, packagesTask, viewsTask, routinesTask);
            
            Logger.Info("Table details loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load table details");
            MessageBox.Show($"Error loading table details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task LoadColumnsAsync()
    {
        Logger.Debug("Loading columns for: {Table}", _tableName);
        
        try
        {
            var provider = GetProviderFromConnection();
            var version = GetVersionFromConnection();
            var sqlTemplate = _metadataHandler.GetQuery(provider, version, "GetTableColumns_Display");
            var sql = ReplacePlaceholders(sqlTemplate, _schema, _tableName);
            
            Logger.Debug("Using query: GUI_GetTableColumns");
            var dataTable = await _connectionManager.ExecuteQueryAsync(sql);
            
            Dispatcher.Invoke(() =>
            {
                ColumnsGrid.ItemsSource = dataTable.DefaultView;
                ColumnCountText.Text = dataTable.Rows.Count.ToString();
            });
            
            Logger.Info("Loaded {Count} columns", dataTable.Rows.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load columns");
            Dispatcher.Invoke(() => ColumnCountText.Text = "Error");
        }
    }

    private async Task LoadForeignKeysAsync()
    {
        Logger.Debug("Loading foreign keys for: {Table}", _tableName);
        
        try
        {
            var provider = GetProviderFromConnection();
            var version = GetVersionFromConnection();
            var sqlTemplate = _metadataHandler.GetQuery(provider, version, "GetTableForeignKeys_Detailed");
            var sql = ReplacePlaceholders(sqlTemplate, _schema, _tableName);
            
            Logger.Debug("Using query: GUI_GetTableForeignKeys");
            var dataTable = await _connectionManager.ExecuteQueryAsync(sql);
            
            Dispatcher.Invoke(() =>
            {
                ForeignKeysGrid.ItemsSource = dataTable.DefaultView;
                FKCountText.Text = dataTable.Rows.Count.ToString();
                
                // Update status text
                if (dataTable.Rows.Count == 0)
                {
                    ForeignKeysStatusText.Text = "No foreign keys defined - This table does not reference other tables.";
                }
                else
                {
                    // Count unique referenced tables
                    var referencedTables = new HashSet<string>();
                    foreach (DataRow row in dataTable.Rows)
                    {
                        referencedTables.Add(row["PKTable"]?.ToString() ?? "");
                    }
                    
                    if (dataTable.Rows.Count == 1)
                    {
                        ForeignKeysStatusText.Text = $"✅ Found 1 foreign key constraint referencing {referencedTables.Count} table(s)";
                    }
                    else
                    {
                        ForeignKeysStatusText.Text = $"✅ Found {dataTable.Rows.Count} foreign key constraints referencing {referencedTables.Count} table(s)";
                    }
                }
            });
            
            Logger.Info("Loaded {Count} foreign keys", dataTable.Rows.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load foreign keys");
            Dispatcher.Invoke(() => FKCountText.Text = "Error");
        }
    }

    private async Task LoadIndexesAsync()
    {
        Logger.Debug("Loading indexes for: {Table}", _tableName);
        
        try
        {
            var provider = GetProviderFromConnection();
            var version = GetVersionFromConnection();
            var sqlTemplate = _metadataHandler.GetQuery(provider, version, "GetTableIndexes_Aggregated");
            var sql = ReplacePlaceholders(sqlTemplate, _schema, _tableName);
            
            Logger.Debug("Using query: GUI_GetTableIndexes");
            var dataTable = await _connectionManager.ExecuteQueryAsync(sql);
            
            Dispatcher.Invoke(() =>
            {
                IndexesGrid.ItemsSource = dataTable.DefaultView;
                IndexCountText.Text = dataTable.Rows.Count.ToString();
            });
            
            Logger.Info("Loaded {Count} indexes", dataTable.Rows.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load indexes");
            Dispatcher.Invoke(() => IndexCountText.Text = "Error");
        }
    }

    private async Task LoadStatisticsAsync()
    {
        Logger.Debug("Loading statistics for: {Table}", _tableName);
        
        try
        {
            // Use StatisticsService to get comprehensive statistics for this specific table
            var filter = new StatisticsFilter
            {
                SchemaFilter = _schema,
                ShowOnlyOutdated = false,
                OutdatedThresholdDays = 30
            };
            
            var allStats = await _statisticsService.GetTableStatisticsAsync(_connectionManager, filter);
            var tableStats = allStats.FirstOrDefault(s => 
                s.SchemaName.Equals(_schema, StringComparison.OrdinalIgnoreCase) && 
                s.TableName.Equals(_tableName, StringComparison.OrdinalIgnoreCase));
            
            if (tableStats != null)
            {
                Dispatcher.Invoke(() =>
                {
                    // Statistics information
                    StatsTimeText.Text = tableStats.StatsTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "Never";
                    DaysSinceUpdateText.Text = tableStats.DaysSinceUpdate?.ToString() ?? "-";
                    RowCountText.Text = tableStats.CardinalityEstimate?.ToString("N0") ?? "Unknown";
                    TablespaceText.Text = tableStats.TablespaceName ?? "-";
                    
                    // Status with color coding
                    StatsStatusText.Text = $"{tableStats.StatsIcon} {tableStats.StatsStatus}";
                    StatsStatusText.Foreground = tableStats.StatsStatus switch
                    {
                        "Critical" => System.Windows.Media.Brushes.Red,
                        "Warning" => System.Windows.Media.Brushes.Orange,
                        "Good" => System.Windows.Media.Brushes.Green,
                        _ => System.Windows.Media.Brushes.Gray
                    };
                    
                    // Recommendation text based on status
                    if (tableStats.DaysSinceUpdate > 90)
                    {
                        StatsRecommendationText.Text = $"⚠️ Statistics are {tableStats.DaysSinceUpdate} days old. " +
                            "Consider running RUNSTATS to improve query performance. Outdated statistics can lead to " +
                            "poor query plans and slow performance.";
                        StatsRecommendationText.Foreground = System.Windows.Media.Brushes.Red;
                    }
                    else if (tableStats.DaysSinceUpdate > 30)
                    {
                        StatsRecommendationText.Text = $"⚠️ Statistics are {tableStats.DaysSinceUpdate} days old. " +
                            "Running RUNSTATS soon is recommended.";
                        StatsRecommendationText.Foreground = System.Windows.Media.Brushes.Orange;
                    }
                    else
                    {
                        StatsRecommendationText.Text = "✅ Statistics are up-to-date. No action needed.";
                        StatsRecommendationText.Foreground = System.Windows.Media.Brushes.Green;
                    }
                });
            }
            else
            {
                // If not found in stats service, fallback to basic info
                await LoadBasicStatisticsAsync();
            }
            
            Logger.Info("Statistics loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load statistics");
            await LoadBasicStatisticsAsync();
        }
    }
    
    /// <summary>
    /// Fallback method for basic statistics if StatisticsService fails
    /// </summary>
    private async Task LoadBasicStatisticsAsync()
    {
        try
        {
            // Get row count
            var countSql = $"SELECT COUNT(*) FROM {_fullTableName}";
            var rowCount = await _connectionManager.ExecuteScalarAsync(countSql);
            
            // Get table info
            var infoSqlTemplate = _metadataHandler.GetQuery("DB2", "12.1", "GetTableBasicInfo");
            var infoSql = ReplacePlaceholders(infoSqlTemplate, _schema, _tableName);
            
            var infoTable = await _connectionManager.ExecuteQueryAsync(infoSql);
            
            Dispatcher.Invoke(() =>
            {
                RowCountText.Text = rowCount != null ? Convert.ToInt64(rowCount).ToString("N0") : "Unknown";
                StatsTimeText.Text = "Unknown";
                DaysSinceUpdateText.Text = "-";
                StatsStatusText.Text = "Unknown";
                
                if (infoTable.Rows.Count > 0)
                {
                    var type = infoTable.Rows[0]["TableType"]?.ToString() ?? "Unknown";
                    var tbspace = infoTable.Rows[0]["Tablespace"]?.ToString() ?? "Unknown";
                    
                    TableTypeText.Text = type switch
                    {
                        "T" => "Table",
                        "V" => "View",
                        "S" => "System Table",
                        "A" => "Alias",
                        _ => type
                    };
                    
                    TablespaceText.Text = tbspace;
                }
                
                StatsRecommendationText.Text = "Unable to retrieve detailed statistics. Basic information shown.";
                StatsRecommendationText.Foreground = System.Windows.Media.Brushes.Gray;
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load basic statistics");
            Dispatcher.Invoke(() =>
            {
                RowCountText.Text = "Error";
                StatsTimeText.Text = "Error";
            });
        }
    }

    private async Task GenerateDDLAsync()
    {
        Logger.Debug("Generating DDL for: {Table}", _tableName);
        
        try
        {
            // Get columns for DDL
            var provider = GetProviderFromConnection();
            var version = GetVersionFromConnection();
            var columnsSqlTemplate = _metadataHandler.GetQuery(provider, version, "GetTableDdlColumns");
            var columnsSql = ReplacePlaceholders(columnsSqlTemplate, _schema, _tableName);
            
            Logger.Debug("Using query: GUI_GetTableDdlColumns");
            var columnsTable = await _connectionManager.ExecuteQueryAsync(columnsSql);
            
            // Build DDL
            var ddl = new System.Text.StringBuilder();
            ddl.AppendLine($"-- DDL for table {_fullTableName}");
            ddl.AppendLine();
            ddl.AppendLine($"CREATE TABLE {_fullTableName} (");
            
            for (int i = 0; i < columnsTable.Rows.Count; i++)
            {
                var row = columnsTable.Rows[i];
                var colName = row["COLNAME"].ToString();
                var typeName = row["TYPENAME"].ToString();
                var length = row["LENGTH"].ToString();
                var scale = row["SCALE"].ToString();
                var nulls = row["NULLS"].ToString();
                var defaultVal = row["DEFAULT"]?.ToString();
                
                ddl.Append($"    {colName} {typeName}");
                
                if (typeName == "VARCHAR" || typeName == "CHAR" || typeName == "GRAPHIC" || typeName == "VARGRAPHIC")
                {
                    ddl.Append($"({length})");
                }
                else if (typeName == "DECIMAL" || typeName == "NUMERIC")
                {
                    ddl.Append($"({length},{scale})");
                }
                
                if (nulls == "N")
                {
                    ddl.Append(" NOT NULL");
                }
                
                if (!string.IsNullOrEmpty(defaultVal) && defaultVal != "null")
                {
                    ddl.Append($" DEFAULT {defaultVal}");
                }
                
                if (i < columnsTable.Rows.Count - 1)
                {
                    ddl.AppendLine(",");
                }
                else
                {
                    ddl.AppendLine();
                }
            }
            
            ddl.AppendLine(");");
            
            Dispatcher.Invoke(() =>
            {
                DDLTextBox.Text = ddl.ToString();
            });
            
            Logger.Debug("DDL generated successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate DDL");
            Dispatcher.Invoke(() => DDLTextBox.Text = $"-- Error generating DDL:\n-- {ex.Message}");
        }
    }

    private void ForeignKey_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (ForeignKeysGrid.SelectedItem is DataRowView row)
        {
            var relatedTable = row["PKTable"]?.ToString();
            if (!string.IsNullOrEmpty(relatedTable))
            {
                Logger.Info("Opening related table: {Table}", relatedTable);
                SelectedRelatedTable = relatedTable;
                DialogResult = true;
                Close();
            }
        }
    }

    private void QueryTable_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Query top 1000 rows requested for: {Table}", _fullTableName);
        ShouldQueryTable = true;
        DialogResult = true;
        Close();
    }

    private void CopyDDL_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(DDLTextBox.Text);
            MessageBox.Show("DDL copied to clipboard!", "Success", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            Logger.Debug("DDL copied to clipboard");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy DDL to clipboard");
            MessageBox.Show($"Failed to copy to clipboard:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task LoadIncomingForeignKeysAsync()
    {
        try
        {
            var incomingFKs = await _relationshipService.GetIncomingForeignKeysAsync(_connectionManager, _schema, _tableName);
            IncomingFKGrid.ItemsSource = incomingFKs;
            
            // Update status text
            if (incomingFKs.Count == 0)
            {
                IncomingFKStatusText.Text = "No incoming foreign keys found - No other tables reference this table.";
            }
            else if (incomingFKs.Count == 1)
            {
                IncomingFKStatusText.Text = $"✅ Found 1 incoming foreign key dependency from 1 table";
            }
            else
            {
                var uniqueTables = incomingFKs.Select(fk => $"{fk.ReferencingSchema}.{fk.ReferencingTable}").Distinct().Count();
                IncomingFKStatusText.Text = $"✅ Found {incomingFKs.Count} incoming foreign key dependencies from {uniqueTables} table(s)";
            }
            
            Logger.Info("Loaded {Count} incoming foreign keys", incomingFKs.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load incoming foreign keys");
            IncomingFKStatusText.Text = "❌ Error loading incoming foreign keys";
        }
    }
    
    /// <summary>
    /// Handle double-click on incoming foreign key to view the referencing table
    /// </summary>
    private void IncomingFK_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (IncomingFKGrid.SelectedItem is Services.IncomingForeignKey selectedFK)
        {
            Logger.Info("Opening referencing table: {Schema}.{Table}", 
                selectedFK.ReferencingSchema, selectedFK.ReferencingTable);
            
            try
            {
                var fullTableName = $"{selectedFK.ReferencingSchema}.{selectedFK.ReferencingTable}";
                
                // Open the referencing table in a new tab
                if (Application.Current.MainWindow is MainWindow mainWindow)
                {
                    mainWindow.CreateTabWithTableDetails(_connectionManager, fullTableName, selectedFK.ReferencingTable);
                    
                    // Close this dialog
                    Close();
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to open referencing table");
                MessageBox.Show($"Failed to open table:\n\n{ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
    
    private async Task LoadReferencingPackagesAsync()
    {
        try
        {
            var packages = await _relationshipService.GetReferencingPackagesAsync(_connectionManager, _schema, _tableName);
            PackagesGrid.ItemsSource = packages;
            Logger.Info("Loaded {Count} referencing packages", packages.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load referencing packages");
        }
    }
    
    private async Task LoadReferencingViewsAsync()
    {
        try
        {
            var views = await _relationshipService.GetReferencingViewsAsync(_connectionManager, _schema, _tableName);
            ViewsGrid.ItemsSource = views;
            Logger.Info("Loaded {Count} referencing views", views.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load referencing views");
        }
    }
    
    private async Task LoadReferencingRoutinesAsync()
    {
        try
        {
            var routines = await _relationshipService.GetReferencingRoutinesAsync(_connectionManager, _schema, _tableName);
            RoutinesGrid.ItemsSource = routines;
            Logger.Info("Loaded {Count} referencing routines", routines.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load referencing routines");
        }
    }
    
    private void Close_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
    
    private void DockAsTab_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Docking TableDetailsDialog as tab: {Table}", _fullTableName);
        
        try
        {
            if (System.Windows.Application.Current.MainWindow is MainWindow mainWindow)
            {
                // Create a new tab with the same table details content
                mainWindow.CreateTabWithTableDetails(_connectionManager, _fullTableName, _tableName);
                
                // Close this dialog
                Close();
            }
            else
            {
                MessageBox.Show("Could not access main window to dock the tab.", 
                    "Dock Failed", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to dock as tab");
            MessageBox.Show($"Failed to dock as tab: {ex.Message}", 
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void ExportAiContext_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("AI Context Export requires AI provider configuration.\n\nConfigure Ollama, OpenAI, Claude, or another AI provider in Settings to enable this feature.", 
            "Export AI Context", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    private void AnalyzeTable_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("AI Table Analysis requires AI provider configuration.\n\nConfigure an AI provider in Settings to enable:\n• Table purpose explanation\n• Usage pattern analysis\n• Optimization suggestions\n• Relationship explanations", 
            "Analyze Table with AI", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    /// <summary>
    /// Helper method to replace ? placeholders in SQL templates with actual values
    /// </summary>
    private string ReplacePlaceholders(string sqlTemplate, params string[] values)
    {
        var result = sqlTemplate;
        foreach (var value in values)
        {
            var index = result.IndexOf('?');
            if (index >= 0)
            {
                result = result.Remove(index, 1).Insert(index, $"'{value}'");
            }
        }
        return result;
    }
    
    /// <summary>
    /// Get provider type from connection (defaults to "DB2" for backward compatibility)
    /// </summary>
    private string GetProviderFromConnection()
    {
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        return provider switch
        {
            "POSTGRESQL" or "POSTGRES" => "POSTGRESQL",
            "SQLSERVER" or "MSSQL" => "SQLSERVER",
            "ORACLE" => "ORACLE",
            "MYSQL" => "MYSQL",
            _ => "DB2" // Default to DB2
        };
    }
    
    /// <summary>
    /// Get version from connection (defaults to "12.1" for DB2, can be enhanced with version detection)
    /// </summary>
    private string GetVersionFromConnection()
    {
        // TODO: Implement version detection from connection
        // For now, default to 12.1 for DB2, or provider-specific defaults
        var provider = GetProviderFromConnection();
        return provider switch
        {
            "POSTGRESQL" => "15",
            "SQLSERVER" => "2022",
            "ORACLE" => "21",
            "MYSQL" => "8.0",
            _ => "12.1" // DB2 default
        };
    }
    
    /// <summary>
    /// Generate RUNSTATS script for this table
    /// </summary>
    private void GenerateRunstats_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Logger.Info("Generating RUNSTATS for table: {Table}", _fullTableName);
            
            // Create a simple TableStatistics object for this table
            var tableStats = new TableStatistics
            {
                SchemaName = _schema,
                TableName = _tableName
            };
            
            var script = _statisticsService.GenerateRunstatsScript(new List<TableStatistics> { tableStats });
            
            // Open script in a new editor tab
            if (Application.Current.MainWindow is MainWindow mainWindow)
            {
                mainWindow.CreateNewTabWithSql(script, $"RUNSTATS - {_tableName}");
                Logger.Info("RUNSTATS script opened in new tab");
            }
            else
            {
                // Fallback: copy to clipboard
                Clipboard.SetText(script);
                MessageBox.Show("RUNSTATS script copied to clipboard.",
                    "Generate RUNSTATS", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate RUNSTATS");
            MessageBox.Show($"Failed to generate RUNSTATS:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Refresh statistics data
    /// </summary>
    private async void RefreshStats_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Logger.Info("Refreshing statistics for table: {Table}", _fullTableName);
            await LoadStatisticsAsync();
            MessageBox.Show("Statistics refreshed successfully.",
                "Refresh Statistics", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh statistics");
            MessageBox.Show($"Failed to refresh statistics:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}


