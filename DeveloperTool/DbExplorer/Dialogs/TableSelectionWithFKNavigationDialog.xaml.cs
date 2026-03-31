using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

/// <summary>
/// Enhanced table selection dialog with foreign key navigation capabilities.
/// Allows users to easily follow FK relationships (forward and backward) to build complete models.
/// </summary>
public partial class TableSelectionWithFKNavigationDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler _metadataHandler;
    private readonly string _defaultSchema;
    private List<TableSelectionItem> _allTables = new();
    private List<TableSelectionItem> _selectedTables = new();
    private bool _isInitializing = true; // Prevent events from firing during initialization
    
    public List<string> SelectedTables { get; private set; } = new();
    
    public TableSelectionWithFKNavigationDialog(IConnectionManager connectionManager, string defaultSchema)
    {
        InitializeComponent();
        
        _connectionManager = connectionManager;
        _metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        _defaultSchema = defaultSchema;
        
        Loaded += TableSelectionWithFKNavigationDialog_Loaded;
    }
    
    private async void TableSelectionWithFKNavigationDialog_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            Logger.Info("Loading tables for schema: {Schema}", _defaultSchema);
            
            // Show loading overlay
            ShowLoading("Loading tables from database...");
            
            Logger.Debug("Step 1: Loading all tables");
            await LoadTablesAsync();
            
            Logger.Debug("Step 2: Populating schema dropdown");
            PopulateSchemaComboBox();
            
            // Initialization complete - now allow events to trigger RefreshTableList
            _isInitializing = false;
            
            Logger.Debug("Step 3: Refreshing table list");
            RefreshTableList();
            
            Logger.Info("Loaded {Count} tables from database", _allTables.Count);
            StatusText.Text = $"Loaded {_allTables.Count} tables. Loading FK information...";
            
            // Load FK counts in background - this is important for the FK display!
            LoadingText.Text = "Analyzing foreign key relationships...";
            await LoadFKCountsAsync();
            
            HideLoading();
            StatusText.Text = $"Ready - {_allTables.Count} tables, {_allTables.Sum(t => t.OutgoingFKCount)} outgoing FKs, {_allTables.Sum(t => t.IncomingFKCount)} incoming FKs";
            RefreshTableList(); // Refresh to show FK counts
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load tables");
            HideLoading();
            MessageBox.Show(
                $"Failed to load tables: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Close();
        }
    }
    
    private void ShowLoading(string message)
    {
        LoadingText.Text = message;
        LoadingOverlay.Visibility = Visibility.Visible;
    }
    
    private void HideLoading()
    {
        LoadingOverlay.Visibility = Visibility.Collapsed;
    }
    
    private async Task LoadTablesAsync()
    {
        Logger.Debug("Loading ALL user tables (default schema: {Schema})", _defaultSchema);
        
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = "12.1";
        
        // Load ALL user tables (not just default schema) so schema dropdown works
        var sql = @"SELECT DISTINCT TRIM(TABSCHEMA) AS TABSCHEMA, TRIM(TABNAME) AS TABNAME 
                    FROM SYSCAT.TABLES 
                    WHERE TYPE = 'T' 
                      AND TABSCHEMA NOT LIKE 'SYS%'
                    ORDER BY TABSCHEMA, TABNAME";
        
        Logger.Debug("Executing query: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        Logger.Debug("Query returned {Count} rows", result.Rows.Count);
        
        _allTables.Clear();
        foreach (DataRow row in result.Rows)
        {
            var schema = row["TABSCHEMA"]?.ToString()?.Trim() ?? string.Empty;
            var tableName = row["TABNAME"]?.ToString()?.Trim() ?? string.Empty;
            
            if (!string.IsNullOrEmpty(schema) && !string.IsNullOrEmpty(tableName))
            {
                _allTables.Add(new TableSelectionItem
                {
                    Schema = schema,
                    TableName = tableName,
                    IsSelected = false
                });
            }
        }
        
        Logger.Info("Loaded {Count} tables from {SchemaCount} schemas", 
            _allTables.Count, _allTables.Select(t => t.Schema).Distinct().Count());
    }
    
    private async Task LoadFKCountsAsync()
    {
        Logger.Debug("Loading FK counts for {Count} tables", _allTables.Count);
        
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = "12.1";
        
        foreach (var table in _allTables)
        {
            try
            {
                // Get outgoing FK count
                var outgoingFkQuery = _metadataHandler.GetQuery(provider, version, "GetForeignKeysForTable");
                outgoingFkQuery = ReplaceSqlParameters(outgoingFkQuery, table.Schema, table.TableName);
                var outgoingFkResults = await _connectionManager.ExecuteQueryAsync(outgoingFkQuery);
                table.OutgoingFKCount = outgoingFkResults.Rows.Count;
                
                // Get incoming FK count
                var incomingFkQuery = _metadataHandler.GetQuery(provider, version, "GetIncomingForeignKeys");
                incomingFkQuery = ReplaceSqlParameters(incomingFkQuery, table.Schema, table.TableName);
                var incomingFkResults = await _connectionManager.ExecuteQueryAsync(incomingFkQuery);
                table.IncomingFKCount = incomingFkResults.Rows.Count;
                
                Logger.Debug("Table {Schema}.{Table}: {Outgoing} outgoing, {Incoming} incoming FKs",
                    table.Schema, table.TableName, table.OutgoingFKCount, table.IncomingFKCount);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to load FK counts for {Schema}.{Table}", table.Schema, table.TableName);
                // Continue with other tables
            }
        }
        
        Logger.Info("FK counts loaded for all tables");
    }
    
    private void RefreshTableList()
    {
        // Skip during initialization to prevent null reference errors
        if (_isInitializing)
        {
            Logger.Debug("RefreshTableList called during initialization - skipping");
            return;
        }
        
        // Guard against null references during initialization
        if (_allTables == null || !_allTables.Any())
        {
            Logger.Debug("RefreshTableList called but _allTables is empty/null - skipping");
            return;
        }
        
        if (TablesList == null || SchemaComboBox == null || FilterComboBox == null || SearchTextBox == null)
        {
            Logger.Debug("RefreshTableList called but controls not initialized - skipping");
            return;
        }
        
        try
        {
            var searchText = SearchTextBox.Text?.ToLowerInvariant() ?? string.Empty;
            var selectedSchema = SchemaComboBox.SelectedItem?.ToString() ?? "All";
            var filterType = (FilterComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "All Tables";
            
            Logger.Debug("RefreshTableList: search='{Search}', schema='{Schema}', filter='{Filter}'", 
                searchText, selectedSchema, filterType);
            
            var filtered = _allTables.Where(t =>
                (string.IsNullOrEmpty(searchText) || t.TableName.ToLowerInvariant().Contains(searchText) || t.Schema.ToLowerInvariant().Contains(searchText)) &&
                (selectedSchema == "All" || t.Schema == selectedSchema)
            );
            
            // Apply FK filter
            if (filterType == "With FKs")
            {
                filtered = filtered.Where(t => t.OutgoingFKCount > 0 || t.IncomingFKCount > 0);
            }
            else if (filterType == "Referenced")
            {
                filtered = filtered.Where(t => t.IncomingFKCount > 0);
            }
            
            var filteredList = filtered.ToList();
            Logger.Debug("RefreshTableList: {Count} tables after filtering", filteredList.Count);
            
            TablesList.ItemsSource = filteredList;
            UpdateSelectionCount();
            UpdateFKRelationships();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "RefreshTableList failed");
        }
    }
    
    private void PopulateSchemaComboBox()
    {
        var schemas = _allTables.Select(t => t.Schema).Distinct().OrderBy(s => s).ToList();
        Logger.Debug("Found {Count} distinct schemas: {Schemas}", schemas.Count, string.Join(", ", schemas.Take(10)));
        
        SchemaComboBox.Items.Clear();
        SchemaComboBox.Items.Add("All");
        foreach (var schema in schemas)
        {
            SchemaComboBox.Items.Add(schema);
        }
        
        // Select the default schema if it exists, otherwise select "All"
        var defaultSchemaIndex = schemas.IndexOf(_defaultSchema);
        if (defaultSchemaIndex >= 0)
        {
            SchemaComboBox.SelectedIndex = defaultSchemaIndex + 1; // +1 for "All" item
            Logger.Debug("Set schema to default: {Schema} at index {Index}", _defaultSchema, defaultSchemaIndex + 1);
        }
        else
        {
            SchemaComboBox.SelectedIndex = 0; // "All"
            Logger.Debug("Default schema {Schema} not found, selecting 'All'", _defaultSchema);
        }
    }
    
    private void UpdateSelectionCount()
    {
        if (_allTables == null || SelectionCountText == null)
            return;
            
        var selected = _allTables.Where(t => t.IsSelected).ToList();
        var totalFKs = selected.Sum(t => t.OutgoingFKCount + t.IncomingFKCount);
        SelectionCountText.Text = $"✓ Selected: {selected.Count} table(s) with {totalFKs} FK relationship(s)";
    }
    
    private void UpdateFKRelationships()
    {
        if (_allTables == null || FKRelationshipsList == null)
            return;
            
        var selected = _allTables.Where(t => t.IsSelected).ToList();
        var relationships = new List<string>();
        
        foreach (var table in selected)
        {
            if (table.OutgoingFKCount > 0)
            {
                relationships.Add($"{table.FullName} → {table.OutgoingFKCount} referenced table(s)");
            }
            if (table.IncomingFKCount > 0)
            {
                relationships.Add($"{table.FullName} ← {table.IncomingFKCount} referencing table(s)");
            }
        }
        
        FKRelationshipsList.ItemsSource = relationships;
    }
    
    /// <summary>
    /// Follow foreign keys from selected tables (forward direction).
    /// Adds tables that are referenced by selected tables' FKs.
    /// </summary>
    private async void FollowFK_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            FollowFKButton.IsEnabled = false;
            ShowLoading("Following outgoing foreign keys...");
            Logger.Debug("Following foreign keys...");
            
            var selectedTableNames = _allTables.Where(t => t.IsSelected).ToList();
            if (selectedTableNames.Count == 0)
            {
                MessageBox.Show("Please select at least one table first.", "No Selection",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            
            Logger.Debug("Following foreign keys from {Count} selected tables", selectedTableNames.Count);
            
            var relatedTables = new HashSet<string>();
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1";
            
            foreach (var table in selectedTableNames)
            {
                Logger.Debug("Querying outgoing FKs for {Schema}.{Table}", table.Schema, table.TableName);
                
                var fkQuery = _metadataHandler.GetQuery(provider, version, "GetForeignKeysForTable");
                fkQuery = ReplaceSqlParameters(fkQuery, table.Schema, table.TableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(fkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    // Query "GetForeignKeysForTable" returns REF_SCHEMA and REF_TABLE columns
                    var refSchema = row["REF_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var refTable = row["REF_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{refSchema}.{refTable}";
                    
                    Logger.Debug("FK result row: REF_SCHEMA={RefSchema}, REF_TABLE={RefTable}", refSchema, refTable);
                    
                    if (!string.IsNullOrEmpty(refSchema) && !string.IsNullOrEmpty(refTable) &&
                        !relatedTables.Contains(key) && !selectedTableNames.Any(t => t.FullName == key))
                    {
                        relatedTables.Add(key);
                        Logger.Debug("Found related table via FK: {Schema}.{Table}", refSchema, refTable);
                    }
                }
            }
            
            // Add related tables to selection
            var addedCount = 0;
            foreach (var relatedKey in relatedTables)
            {
                var parts = relatedKey.Split('.');
                if (parts.Length != 2) continue;
                
                var table = _allTables.FirstOrDefault(t => t.Schema == parts[0].Trim() && t.TableName == parts[1].Trim());
                if (table != null && !table.IsSelected)
                {
                    table.IsSelected = true;
                    addedCount++;
                    Logger.Info("Added table to selection via FK: {Table}", relatedKey);
                }
            }
            
            RefreshTableList();
            
            if (addedCount > 0)
            {
                Logger.Info("Added {Count} table(s) via foreign key relationships", addedCount);
            }
            
            Logger.Info("FK navigation complete - Added {Count} tables", addedCount);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to follow foreign keys");
            MessageBox.Show($"Error following foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            HideLoading();
            FollowFKButton.IsEnabled = true;
        }
    }
    
    /// <summary>
    /// Follow incoming foreign keys (backward direction).
    /// Adds tables that have FKs pointing to selected tables.
    /// </summary>
    private async void FollowIncomingFK_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            FollowIncomingFKButton.IsEnabled = false;
            ShowLoading("Following incoming foreign keys...");
            Logger.Debug("Following incoming foreign keys...");
            
            var selectedTableNames = _allTables.Where(t => t.IsSelected).ToList();
            if (selectedTableNames.Count == 0)
            {
                MessageBox.Show("Please select at least one table first.", "No Selection",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            
            Logger.Debug("Following incoming foreign keys for {Count} selected tables", selectedTableNames.Count);
            
            var relatedTables = new HashSet<string>();
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1";
            
            foreach (var table in selectedTableNames)
            {
                Logger.Debug("Querying incoming FKs for {Schema}.{Table}", table.Schema, table.TableName);
                
                var incomingFkQuery = _metadataHandler.GetQuery(provider, version, "GetIncomingForeignKeys");
                incomingFkQuery = ReplaceSqlParameters(incomingFkQuery, table.Schema, table.TableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(incomingFkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    var fromSchema = row["REFERENCING_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var fromTable = row["REFERENCING_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{fromSchema}.{fromTable}";
                    
                    if (!string.IsNullOrEmpty(fromSchema) && !string.IsNullOrEmpty(fromTable) &&
                        !relatedTables.Contains(key) && !selectedTableNames.Any(t => t.FullName == key))
                    {
                        relatedTables.Add(key);
                        Logger.Debug("Found table with incoming FK: {Schema}.{Table}", fromSchema, fromTable);
                    }
                }
            }
            
            // Add related tables to selection
            var addedCount = 0;
            foreach (var relatedKey in relatedTables)
            {
                var parts = relatedKey.Split('.');
                if (parts.Length != 2) continue;
                
                var table = _allTables.FirstOrDefault(t => t.Schema == parts[0].Trim() && t.TableName == parts[1].Trim());
                if (table != null && !table.IsSelected)
                {
                    table.IsSelected = true;
                    addedCount++;
                    Logger.Info("Added table to selection via incoming FK: {Table}", relatedKey);
                }
            }
            
            RefreshTableList();
            
            if (addedCount > 0)
            {
                Logger.Info("Added {Count} table(s) via incoming foreign key relationships", addedCount);
            }
            
            Logger.Info("Incoming FK navigation complete - Added {Count} tables", addedCount);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to follow incoming foreign keys");
            MessageBox.Show($"Error following incoming foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            HideLoading();
            FollowIncomingFKButton.IsEnabled = true;
        }
    }
    
    /// <summary>
    /// Expand all related tables (both directions, recursively).
    /// </summary>
    private async void ExpandAllRelated_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            ExpandAllRelatedButton.IsEnabled = false;
            ShowLoading("Expanding all related tables...");
            Logger.Info("Expanding all related tables...");
            
            var processed = new HashSet<string>();
            var toProcess = new Queue<TableSelectionItem>(_allTables.Where(t => t.IsSelected));
            var totalAdded = 0;
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1";
            
            while (toProcess.Count > 0)
            {
                var current = toProcess.Dequeue();
                var currentKey = current.FullName;
                
                if (processed.Contains(currentKey))
                    continue;
                
                processed.Add(currentKey);
                
                Logger.Debug("Processing table: {Schema}.{Table}", current.Schema, current.TableName);
                
                // Follow outgoing FKs
                var fkQuery = _metadataHandler.GetQuery(provider, version, "GetForeignKeysForTable");
                fkQuery = ReplaceSqlParameters(fkQuery, current.Schema, current.TableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(fkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    var refSchema = row["REF_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var refTable = row["REF_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{refSchema}.{refTable}";
                    
                    if (!string.IsNullOrEmpty(refSchema) && !string.IsNullOrEmpty(refTable) &&
                        !processed.Contains(key))
                    {
                        var relatedTable = _allTables.FirstOrDefault(t => t.FullName == key);
                        if (relatedTable != null && !relatedTable.IsSelected)
                        {
                            relatedTable.IsSelected = true;
                            toProcess.Enqueue(relatedTable);
                            totalAdded++;
                        }
                    }
                }
                
                // Follow incoming FKs
                var incomingFkQuery = _metadataHandler.GetQuery(provider, version, "GetIncomingForeignKeys");
                incomingFkQuery = ReplaceSqlParameters(incomingFkQuery, current.Schema, current.TableName);
                var incomingFkResults = await _connectionManager.ExecuteQueryAsync(incomingFkQuery);
                
                foreach (DataRow row in incomingFkResults.Rows)
                {
                    var fromSchema = row["REFERENCING_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var fromTable = row["REFERENCING_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{fromSchema}.{fromTable}";
                    
                    if (!string.IsNullOrEmpty(fromSchema) && !string.IsNullOrEmpty(fromTable) &&
                        !processed.Contains(key))
                    {
                        var relatedTable = _allTables.FirstOrDefault(t => t.FullName == key);
                        if (relatedTable != null && !relatedTable.IsSelected)
                        {
                            relatedTable.IsSelected = true;
                            toProcess.Enqueue(relatedTable);
                            totalAdded++;
                        }
                    }
                }
            }
            
            RefreshTableList();
            
            Logger.Info("Expansion complete - {TotalAdded} table(s) added. Total: {Total} table(s)", 
                totalAdded, _allTables.Count(t => t.IsSelected));
            
            Logger.Info("Expansion complete - {Count} tables in model", _allTables.Count(t => t.IsSelected));
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to expand all related tables");
            MessageBox.Show($"Error expanding related tables:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            HideLoading();
            ExpandAllRelatedButton.IsEnabled = true;
        }
    }
    
    private void SearchTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshTableList();
    }
    
    private void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshTableList();
    }
    
    private void FilterComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshTableList();
    }
    
    private void SelectAll_Click(object sender, RoutedEventArgs e)
    {
        foreach (var table in _allTables)
        {
            table.IsSelected = true;
        }
        RefreshTableList();
    }
    
    private void ClearSelection_Click(object sender, RoutedEventArgs e)
    {
        foreach (var table in _allTables)
        {
            table.IsSelected = false;
        }
        RefreshTableList();
    }
    
    private void AddToModel_Click(object sender, RoutedEventArgs e)
    {
        SelectedTables.Clear();
        
        var selected = _allTables.Where(t => t.IsSelected).ToList();
        if (selected.Count == 0)
        {
            MessageBox.Show(
                "Please select at least one table.",
                "No Tables Selected",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }
        
        foreach (var table in selected)
        {
            SelectedTables.Add(table.FullName);
        }
        
        Logger.Info("User selected {Count} tables", SelectedTables.Count);
        DialogResult = true;
        Close();
    }
    
    /// <summary>
    /// Helper method to replace SQL parameter placeholders with values.
    /// </summary>
    private string ReplaceSqlParameters(string sql, params string[] values)
    {
        var result = sql;
        foreach (var value in values)
        {
            var index = result.IndexOf('?');
            if (index >= 0)
            {
                result = result.Substring(0, index) + $"'{value}'" + result.Substring(index + 1);
            }
        }
        return result;
    }
}
