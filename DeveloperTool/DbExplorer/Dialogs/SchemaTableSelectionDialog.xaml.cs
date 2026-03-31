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

public partial class SchemaTableSelectionDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler _metadataHandler;
    private readonly string _defaultSchema;
    private readonly Dictionary<string, List<string>> _schemaTableDict = new();
    private readonly Dictionary<string, TableSelectionItem> _tableItems = new();
    
    public List<string> SelectedTables { get; private set; } = new();
    
    public SchemaTableSelectionDialog(IConnectionManager connectionManager, string defaultSchema)
    {
        InitializeComponent();
        
        _connectionManager = connectionManager;
        _metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        _defaultSchema = defaultSchema;
        
        Loaded += SchemaTableSelectionDialog_Loaded;
        FilterTextBox.TextChanged += FilterTextBox_TextChanged;
    }
    
    private async void SchemaTableSelectionDialog_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            Logger.Info("Loading schemas and tables");
            
            await LoadSchemasAndTablesAsync();
            BuildTreeView();
            
            Logger.Info("Loaded {Count} schemas with tables", _schemaTableDict.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load schemas and tables");
            MessageBox.Show(
                $"Failed to load schemas and tables: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Close();
        }
    }
    
    private async Task LoadSchemasAndTablesAsync()
    {
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = "12.1"; // TODO: Get from connection
        var sqlTemplate = _metadataHandler.GetQuery(provider, version, "GetAllSelectableTables");
        var sql = sqlTemplate.Replace("?", $"'{_defaultSchema}'");
        
        Logger.Debug("Using query: GUI_GetAllSelectableTables for schema: {Schema}", _defaultSchema);
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        foreach (DataRow row in result.Rows)
        {
            var schema = row["TABSCHEMA"]?.ToString() ?? string.Empty;
            var table = row["TABNAME"]?.ToString() ?? string.Empty;
            
            if (!_schemaTableDict.ContainsKey(schema))
            {
                _schemaTableDict[schema] = new List<string>();
            }
            
            _schemaTableDict[schema].Add(table);
        }
    }
    
    private void BuildTreeView()
    {
        SchemaTreeView.Items.Clear();
        
        var filter = FilterTextBox.Text.ToLowerInvariant();
        
        foreach (var schema in _schemaTableDict.Keys.OrderBy(s => s))
        {
            var tables = _schemaTableDict[schema];
            
            if (!string.IsNullOrEmpty(filter))
            {
                tables = tables.Where(t => t.ToLowerInvariant().Contains(filter)).ToList();
                if (tables.Count == 0) continue;
            }
            
            var schemaItem = new TreeViewItem
            {
                Header = CreateSchemaHeader(schema, tables.Count),
                Tag = schema
            };
            
            foreach (var table in tables.OrderBy(t => t))
            {
                var fullName = $"{schema}.{table}";
                if (!_tableItems.ContainsKey(fullName))
                {
                    _tableItems[fullName] = new TableSelectionItem
                    {
                        Schema = schema,
                        TableName = table
                    };
                }
                
                var tableItem = new TreeViewItem
                {
                    Header = CreateTableHeader(schema, table),
                    Tag = fullName
                };
                
                schemaItem.Items.Add(tableItem);
            }
            
            schemaItem.Expanded += SchemaItem_Expanded;
            schemaItem.Collapsed += SchemaItem_Collapsed;
            
            SchemaTreeView.Items.Add(schemaItem);
        }
        
        UpdateSelectionCount();
    }
    
    private StackPanel CreateSchemaHeader(string schema, int tableCount)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        
        var checkbox = new CheckBox
        {
            Content = $"📁 {schema} ({tableCount} tables)",
            FontWeight = FontWeights.Bold,
            Margin = new Thickness(0, 0, 10, 0)
        };
        
        checkbox.Checked += (s, e) => SelectSchemaTablesChecked(schema, true);
        checkbox.Unchecked += (s, e) => SelectSchemaTablesChecked(schema, false);
        
        panel.Children.Add(checkbox);
        return panel;
    }
    
    private CheckBox CreateTableHeader(string schema, string table)
    {
        var fullName = $"{schema}.{table}";
        var item = _tableItems.GetValueOrDefault(fullName);
        var fkInfo = item != null ? $" [FK: {item.OutgoingFKCount} outgoing, {item.IncomingFKCount} incoming]" : "";
        
        return new CheckBox
        {
            Content = $"📄 {table}{fkInfo}",
            Margin = new Thickness(20, 2, 0, 2),
            Tag = fullName
        };
    }
    
    private void SelectSchemaTablesChecked(string schema, bool isChecked)
    {
        var schemaItem = SchemaTreeView.Items.Cast<TreeViewItem>()
            .FirstOrDefault(item => item.Tag?.ToString() == schema);
        
        if (schemaItem != null)
        {
            foreach (TreeViewItem tableItem in schemaItem.Items)
            {
                var header = tableItem.Header as CheckBox;
                if (header != null)
                {
                    header.IsChecked = isChecked;
                }
            }
        }
        
        UpdateSelectionCount();
    }
    
    private void SchemaItem_Expanded(object sender, RoutedEventArgs e)
    {
        // Could load additional details here if needed
    }
    
    private void SchemaItem_Collapsed(object sender, RoutedEventArgs e)
    {
        // Could cleanup details here if needed
    }
    
    private void FilterTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        BuildTreeView();
    }
    
    private void SelectAll_Click(object sender, RoutedEventArgs e)
    {
        foreach (TreeViewItem schemaItem in SchemaTreeView.Items)
        {
            var header = schemaItem.Header as StackPanel;
            var checkbox = header?.Children[0] as CheckBox;
            if (checkbox != null)
            {
                checkbox.IsChecked = true;
            }
        }
        
        UpdateSelectionCount();
    }
    
    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        foreach (TreeViewItem schemaItem in SchemaTreeView.Items)
        {
            var header = schemaItem.Header as StackPanel;
            var checkbox = header?.Children[0] as CheckBox;
            if (checkbox != null)
            {
                checkbox.IsChecked = false;
            }
        }
        
        UpdateSelectionCount();
    }
    
    private void UpdateSelectionCount()
    {
        var count = 0;
        
        foreach (TreeViewItem schemaItem in SchemaTreeView.Items)
        {
            foreach (TreeViewItem tableItem in schemaItem.Items)
            {
                var header = tableItem.Header as CheckBox;
                if (header?.IsChecked == true)
                {
                    count++;
                }
            }
        }
        
        SelectionCountText.Text = $"Selected: {count} table(s)";
    }
    
    private void OK_Click(object sender, RoutedEventArgs e)
    {
        SelectedTables.Clear();
        
        foreach (TreeViewItem schemaItem in SchemaTreeView.Items)
        {
            foreach (TreeViewItem tableItem in schemaItem.Items)
            {
                var header = tableItem.Header as CheckBox;
                if (header?.IsChecked == true)
                {
                    var fullTableName = tableItem.Tag?.ToString();
                    if (!string.IsNullOrEmpty(fullTableName))
                    {
                        SelectedTables.Add(fullTableName);
                    }
                }
            }
        }
        
        if (SelectedTables.Count == 0)
        {
            MessageBox.Show(
                "Please select at least one table.",
                "No Tables Selected",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }
        
        Logger.Info("User selected {Count} tables", SelectedTables.Count);
        DialogResult = true;
        Close();
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
            FKStatusText.Text = "Following foreign keys...";
            
            var selectedTableNames = GetSelectedTableNames();
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
            
            foreach (var fullTableName in selectedTableNames)
            {
                var parts = fullTableName.Split('.');
                if (parts.Length != 2) continue;
                
                var schema = parts[0].Trim();
                var tableName = parts[1].Trim();
                
                Logger.Debug("Querying outgoing FKs for {Schema}.{Table}", schema, tableName);
                
                // Query SYSCAT.REFERENCES for outgoing FKs
                var fkQuery = _metadataHandler.GetQuery(provider, version, "GetForeignKeysForTable");
                fkQuery = ReplaceSqlParameters(fkQuery, schema, tableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(fkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    var refSchema = row["REF_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var refTable = row["REF_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{refSchema}.{refTable}";
                    
                    if (!string.IsNullOrEmpty(refSchema) && !string.IsNullOrEmpty(refTable) && 
                        !relatedTables.Contains(key) && !selectedTableNames.Contains(key))
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
                if (SelectTableInTreeView(relatedKey))
                {
                    addedCount++;
                    Logger.Info("Added table to selection via FK: {Table}", relatedKey);
                }
            }
            
            BuildTreeView(); // Refresh to show FK counts
            UpdateSelectionCount();
            
            FKStatusText.Text = addedCount > 0 
                ? $"Added {addedCount} table(s) via foreign key relationships"
                : "No additional tables found via foreign keys";
            
            Logger.Info("FK navigation complete - Added {Count} tables", addedCount);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to follow foreign keys");
            MessageBox.Show($"Error following foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
            FKStatusText.Text = "Error following foreign keys";
        }
        finally
        {
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
            FKStatusText.Text = "Following incoming foreign keys...";
            
            var selectedTableNames = GetSelectedTableNames();
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
            
            foreach (var fullTableName in selectedTableNames)
            {
                var parts = fullTableName.Split('.');
                if (parts.Length != 2) continue;
                
                var schema = parts[0].Trim();
                var tableName = parts[1].Trim();
                
                Logger.Debug("Querying incoming FKs for {Schema}.{Table}", schema, tableName);
                
                // Query SYSCAT.REFERENCES for incoming FKs
                var incomingFkQuery = _metadataHandler.GetQuery(provider, version, "GetIncomingForeignKeys");
                incomingFkQuery = ReplaceSqlParameters(incomingFkQuery, schema, tableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(incomingFkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    var fromSchema = row["REFERENCING_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var fromTable = row["REFERENCING_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{fromSchema}.{fromTable}";
                    
                    if (!string.IsNullOrEmpty(fromSchema) && !string.IsNullOrEmpty(fromTable) &&
                        !relatedTables.Contains(key) && !selectedTableNames.Contains(key))
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
                if (SelectTableInTreeView(relatedKey))
                {
                    addedCount++;
                    Logger.Info("Added table to selection via incoming FK: {Table}", relatedKey);
                }
            }
            
            BuildTreeView(); // Refresh to show FK counts
            UpdateSelectionCount();
            
            FKStatusText.Text = addedCount > 0
                ? $"Added {addedCount} table(s) via incoming foreign key relationships"
                : "No additional tables found via incoming foreign keys";
            
            Logger.Info("Incoming FK navigation complete - Added {Count} tables", addedCount);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to follow incoming foreign keys");
            MessageBox.Show($"Error following incoming foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
            FKStatusText.Text = "Error following incoming foreign keys";
        }
        finally
        {
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
            FKStatusText.Text = "Expanding all related tables...";
            
            Logger.Info("Expanding all related tables");
            
            var processed = new HashSet<string>();
            var toProcess = new Queue<string>(GetSelectedTableNames());
            var totalAdded = 0;
            
            while (toProcess.Count > 0)
            {
                var current = toProcess.Dequeue();
                
                if (processed.Contains(current))
                    continue;
                
                processed.Add(current);
                
                var parts = current.Split('.');
                if (parts.Length != 2) continue;
                
                var schema = parts[0].Trim();
                var tableName = parts[1].Trim();
                
                Logger.Debug("Processing table: {Schema}.{Table}", schema, tableName);
                
                // Follow outgoing FKs
                var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
                var version = "12.1";
                
                var fkQuery = _metadataHandler.GetQuery(provider, version, "GetForeignKeysForTable");
                fkQuery = ReplaceSqlParameters(fkQuery, schema, tableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(fkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    var refSchema = row["REF_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var refTable = row["REF_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{refSchema}.{refTable}";
                    
                    if (!string.IsNullOrEmpty(refSchema) && !string.IsNullOrEmpty(refTable) &&
                        !processed.Contains(key) && !toProcess.Contains(key))
                    {
                        toProcess.Enqueue(key);
                        if (SelectTableInTreeView(key))
                        {
                            totalAdded++;
                        }
                    }
                }
                
                // Follow incoming FKs
                var incomingFkQuery = _metadataHandler.GetQuery(provider, version, "GetIncomingForeignKeys");
                incomingFkQuery = ReplaceSqlParameters(incomingFkQuery, schema, tableName);
                var incomingFkResults = await _connectionManager.ExecuteQueryAsync(incomingFkQuery);
                
                foreach (DataRow row in incomingFkResults.Rows)
                {
                    var fromSchema = row["REFERENCING_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var fromTable = row["REFERENCING_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{fromSchema}.{fromTable}";
                    
                    if (!string.IsNullOrEmpty(fromSchema) && !string.IsNullOrEmpty(fromTable) &&
                        !processed.Contains(key) && !toProcess.Contains(key))
                    {
                        toProcess.Enqueue(key);
                        if (SelectTableInTreeView(key))
                        {
                            totalAdded++;
                        }
                    }
                }
            }
            
            BuildTreeView(); // Refresh to show FK counts
            UpdateSelectionCount();
            
            FKStatusText.Text = $"Expansion complete - {totalAdded} table(s) added. Total: {GetSelectedTableNames().Count} table(s)";
            
            Logger.Info("Expansion complete - {Count} tables in model", GetSelectedTableNames().Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to expand all related tables");
            MessageBox.Show($"Error expanding related tables:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
            FKStatusText.Text = "Error expanding related tables";
        }
        finally
        {
            ExpandAllRelatedButton.IsEnabled = true;
        }
    }
    
    private List<string> GetSelectedTableNames()
    {
        var selected = new List<string>();
        
        foreach (TreeViewItem schemaItem in SchemaTreeView.Items)
        {
            foreach (TreeViewItem tableItem in schemaItem.Items)
            {
                var header = tableItem.Header as CheckBox;
                if (header?.IsChecked == true)
                {
                    var fullName = tableItem.Tag?.ToString();
                    if (!string.IsNullOrEmpty(fullName))
                    {
                        selected.Add(fullName);
                    }
                }
            }
        }
        
        return selected;
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
    
    private bool SelectTableInTreeView(string fullTableName)
    {
        var parts = fullTableName.Split('.');
        if (parts.Length != 2) return false;
        
        var schema = parts[0].Trim();
        var tableName = parts[1].Trim();
        
        // Find schema item
        var schemaItem = SchemaTreeView.Items.Cast<TreeViewItem>()
            .FirstOrDefault(item => item.Tag?.ToString() == schema);
        
        if (schemaItem == null)
        {
            // Schema not in tree - might need to add it
            Logger.Debug("Schema {Schema} not found in tree view", schema);
            return false;
        }
        
        // Find table item
        var tableItem = schemaItem.Items.Cast<TreeViewItem>()
            .FirstOrDefault(item => item.Tag?.ToString() == fullTableName);
        
        if (tableItem == null)
        {
            Logger.Debug("Table {Table} not found in schema {Schema}", tableName, schema);
            return false;
        }
        
        // Select the table
        var header = tableItem.Header as CheckBox;
        if (header != null)
        {
            header.IsChecked = true;
            return true;
        }
        
        return false;
    }
}

