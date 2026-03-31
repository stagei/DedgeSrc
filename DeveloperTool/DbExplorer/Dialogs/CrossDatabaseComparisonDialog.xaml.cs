using NLog;
using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

/// <summary>
/// Dialog for comparing schemas across different database connections
/// </summary>
public partial class CrossDatabaseComparisonDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly ConnectionStorageService _connectionStorage;
    private readonly MetadataHandler _metadataHandler;
    
    private IConnectionManager? _sourceConnection;
    private IConnectionManager? _targetConnection;
    private List<SavedConnection> _savedConnections = new();
    
    // Current connection passed in - used as default source
    private readonly IConnectionManager? _currentConnection;
    private readonly string? _currentConnectionName;
    private bool _isInitializing = true;

    /// <summary>
    /// Default constructor
    /// </summary>
    public CrossDatabaseComparisonDialog()
    {
        InitializeComponent();
        _connectionStorage = new ConnectionStorageService();
        _metadataHandler = new MetadataHandler();

        Loaded += async (s, e) => 
        {
            // Apply all UI styles from the unified style service
            UIStyleService.ApplyStyles(this);
            await LoadConnectionProfilesAsync();
        };
    }
    
    /// <summary>
    /// Constructor that accepts the current active connection as the default source
    /// </summary>
    /// <param name="currentConnection">The currently active connection to use as source</param>
    /// <param name="connectionName">Name of the current connection profile</param>
    public CrossDatabaseComparisonDialog(IConnectionManager currentConnection, string connectionName) : this()
    {
        _currentConnection = currentConnection;
        _currentConnectionName = connectionName;
        Logger.Debug("CrossDatabaseComparisonDialog opened with current connection: {Name}", connectionName);
    }

    private async Task LoadConnectionProfilesAsync()
    {
        try
        {
            _isInitializing = true;
            Logger.Info("Loading saved connections for cross-database comparison");
            
            // Load from ConnectionStorageService (the actual saved connections with encrypted passwords)
            _savedConnections = _connectionStorage.LoadConnections();
            
            if (_savedConnections.Count == 0)
            {
                MessageBox.Show(
                    "No saved connections found.\n\nPlease create connections using File → New Connection before using this feature.",
                    "No Saved Connections",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                Close();
                return;
            }
            
            // Populate connection dropdowns
            var connectionNames = _savedConnections.Select(c => c.Name).ToList();
            
            SourceConnectionComboBox.ItemsSource = connectionNames;
            TargetConnectionComboBox.ItemsSource = connectionNames;
            
            Logger.Info("Loaded {Count} saved connections", _savedConnections.Count);
            
            // If we have a current connection, use it as the source
            if (_currentConnection != null && !string.IsNullOrEmpty(_currentConnectionName))
            {
                Logger.Debug("Setting current connection as source: {Name}", _currentConnectionName);
                
                // Set the source dropdown to current connection (case-insensitive match)
                var matchingName = connectionNames.FirstOrDefault(n => 
                    n.Equals(_currentConnectionName, StringComparison.OrdinalIgnoreCase));
                    
                if (matchingName != null)
                {
                    SourceConnectionComboBox.SelectedItem = matchingName;
                    
                    // Use the existing connection - don't create a new one
                    _sourceConnection = _currentConnection;
                    
                    // Load schemas for the current connection
                    await LoadSchemasForExistingConnectionAsync(_sourceConnection, true);
                    
                    // Pre-select a different connection as target if available
                    var otherConnections = connectionNames.Where(n => 
                        !n.Equals(_currentConnectionName, StringComparison.OrdinalIgnoreCase)).ToList();
                    if (otherConnections.Count > 0)
                    {
                        TargetConnectionComboBox.SelectedItem = otherConnections[0];
                        // This will trigger auto-connect via SelectionChanged
                    }
                }
                else
                {
                    // Current connection name not in saved list - still use it as source
                    Logger.Debug("Current connection not in saved list, adding temporarily");
                    connectionNames.Insert(0, _currentConnectionName);
                    SourceConnectionComboBox.ItemsSource = connectionNames;
                    SourceConnectionComboBox.SelectedItem = _currentConnectionName;
                    
                    _sourceConnection = _currentConnection;
                    await LoadSchemasForExistingConnectionAsync(_sourceConnection, true);
                    
                    // Select first other connection as target
                    if (connectionNames.Count > 1)
                    {
                        TargetConnectionComboBox.SelectedItem = connectionNames[1];
                    }
                }
            }
            
            _isInitializing = false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading saved connections");
            MessageBox.Show($"Error loading saved connections: {ex.Message}", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
            _isInitializing = false;
        }
    }
    
    /// <summary>
    /// Load schemas using an existing connection (no need to reconnect)
    /// </summary>
    private async Task LoadSchemasForExistingConnectionAsync(IConnectionManager connectionManager, bool isSource)
    {
        var infoText = isSource ? SourceInfoText : TargetInfoText;
        var schemaComboBox = isSource ? SourceSchemaComboBox : TargetSchemaComboBox;
        
        try
        {
            infoText.Text = "Loading schemas...";
            
            var provider = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1"; // TODO: Get from connection
            var sql = _metadataHandler.GetQuery(provider, version, "GetSchemasStatement");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var schemas = new List<string>();
            foreach (DataRow row in result.Rows)
            {
                var schemaName = row["SCHEMANAME"]?.ToString()?.Trim() ?? "";
                if (!string.IsNullOrEmpty(schemaName) && !schemaName.StartsWith("SYS"))
                {
                    schemas.Add(schemaName);
                }
            }
            
            schemaComboBox.ItemsSource = schemas.OrderBy(s => s).ToList();
            infoText.Text = $"Connected - {schemas.Count} schemas available";
            
            // Auto-select if only one schema
            if (schemas.Count == 1)
            {
                schemaComboBox.SelectedIndex = 0;
            }
            
            Logger.Info("Loaded {Count} schemas from existing connection", schemas.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading schemas from existing connection");
            infoText.Text = $"Error loading schemas: {ex.Message}";
        }
    }

    private async void SourceConnection_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SourceConnectionComboBox.SelectedItem == null) return;
        
        var profileName = SourceConnectionComboBox.SelectedItem.ToString()!;
        
        // If this is the current connection and we already have it, just load schemas
        if (profileName == _currentConnectionName && _sourceConnection == _currentConnection && _sourceConnection != null)
        {
            // Already loaded during initialization
            if (!_isInitializing)
            {
                await LoadSchemasForExistingConnectionAsync(_sourceConnection, true);
            }
            return;
        }
        
        await ConnectAndLoadSchemasAsync(profileName, true);
    }

    private async void TargetConnection_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (TargetConnectionComboBox.SelectedItem == null) return;
        
        var profileName = TargetConnectionComboBox.SelectedItem.ToString()!;
        
        // Check if user selected the same profile as source - share the connection
        var sourceProfileName = SourceConnectionComboBox.SelectedItem?.ToString();
        if (profileName == sourceProfileName && _sourceConnection != null)
        {
            // Reuse source connection for target (same database, possibly different schema)
            _targetConnection = _sourceConnection;
            await LoadSchemasForExistingConnectionAsync(_targetConnection, false);
            return;
        }
        
        await ConnectAndLoadSchemasAsync(profileName, false);
    }

    private async Task ConnectAndLoadSchemasAsync(string connectionName, bool isSource)
    {
        var infoText = isSource ? SourceInfoText : TargetInfoText;
        var schemaComboBox = isSource ? SourceSchemaComboBox : TargetSchemaComboBox;
        
        try
        {
            infoText.Text = "Connecting...";
            schemaComboBox.ItemsSource = null;
            
            // Get connection with decrypted password from storage
            var connection = _connectionStorage.GetConnection(connectionName);
            if (connection == null)
            {
                infoText.Text = "Connection not found";
                Logger.Warn("Connection not found in storage: {Name}", connectionName);
                return;
            }
            
            Logger.Info("Connecting to {Connection} for {Side} comparison", connectionName, isSource ? "source" : "target");
            
            // Create connection manager and open
            var connectionManager = ConnectionManagerFactory.CreateConnectionManager(connection);
            await connectionManager.OpenAsync();
            
            if (isSource)
            {
                _sourceConnection?.Dispose();
                _sourceConnection = connectionManager;
            }
            else
            {
                _targetConnection?.Dispose();
                _targetConnection = connectionManager;
            }
            
            // Load schemas
            var provider = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1"; // TODO: Get from connection
            var sql = _metadataHandler.GetQuery(provider, version, "GetSchemasStatement");
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var schemas = new List<string>();
            foreach (DataRow row in result.Rows)
            {
                var schemaName = row["SCHEMANAME"]?.ToString()?.Trim() ?? "";
                if (!string.IsNullOrEmpty(schemaName) && !schemaName.StartsWith("SYS"))
                {
                    schemas.Add(schemaName);
                }
            }
            
            schemaComboBox.ItemsSource = schemas.OrderBy(s => s).ToList();
            infoText.Text = $"Connected - {schemas.Count} schemas available";
            
            // Auto-select if only one schema
            if (schemas.Count == 1)
            {
                schemaComboBox.SelectedIndex = 0;
            }
            
            Logger.Info("Loaded {Count} schemas from {Connection}", schemas.Count, connectionName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error connecting to {Connection}", connectionName);
            infoText.Text = $"Connection failed: {ex.Message}";
            
            if (isSource)
            {
                _sourceConnection?.Dispose();
                _sourceConnection = null;
            }
            else
            {
                _targetConnection?.Dispose();
                _targetConnection = null;
            }
        }
    }

    private async void Compare_Click(object sender, RoutedEventArgs e)
    {
        // Validate selections
        if (_sourceConnection == null)
        {
            MessageBox.Show("Please select and connect to a source database.", "Select Source", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        
        if (_targetConnection == null)
        {
            MessageBox.Show("Please select and connect to a target database.", "Select Target", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        
        if (SourceSchemaComboBox.SelectedItem == null)
        {
            MessageBox.Show("Please select a source schema.", "Select Schema", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        
        if (TargetSchemaComboBox.SelectedItem == null)
        {
            MessageBox.Show("Please select a target schema.", "Select Schema", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            CompareButton.IsEnabled = false;
            CompareButton.Content = "⏳ Comparing...";
            ProgressBar.Visibility = Visibility.Visible;
            ProgressBar.IsIndeterminate = true;

            var sourceSchema = SourceSchemaComboBox.SelectedItem.ToString()!;
            var targetSchema = TargetSchemaComboBox.SelectedItem.ToString()!;
            var sourceProfile = SourceConnectionComboBox.SelectedItem.ToString()!;
            var targetProfile = TargetConnectionComboBox.SelectedItem.ToString()!;

            Logger.Info("Comparing {SourceProfile}.{SourceSchema} vs {TargetProfile}.{TargetSchema}", 
                sourceProfile, sourceSchema, targetProfile, targetSchema);

            // Get tables from both databases
            var provider = _sourceConnection?.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1"; // TODO: Get from connection
            var sourceTablesQuery = _metadataHandler.GetQuery(provider, version, "GetTablesForSchema")
                .Replace("TRIM(TABSCHEMA) = ?", $"TRIM(TABSCHEMA) = '{sourceSchema}'");
            var targetTablesQuery = _metadataHandler.GetQuery(provider, version, "GetTablesForSchema")
                .Replace("TRIM(TABSCHEMA) = ?", $"TRIM(TABSCHEMA) = '{targetSchema}'");

            var sourceTables = await _sourceConnection.ExecuteQueryAsync(sourceTablesQuery);
            var targetTables = await _targetConnection.ExecuteQueryAsync(targetTablesQuery);

            // Extract table names
            var sourceTableNames = new HashSet<string>();
            var targetTableNames = new HashSet<string>();

            foreach (DataRow row in sourceTables.Rows)
            {
                sourceTableNames.Add(row["TABNAME"]?.ToString()?.Trim() ?? "");
            }

            foreach (DataRow row in targetTables.Rows)
            {
                targetTableNames.Add(row["TABNAME"]?.ToString()?.Trim() ?? "");
            }

            var onlyInSource = sourceTableNames.Except(targetTableNames).OrderBy(t => t).ToList();
            var onlyInTarget = targetTableNames.Except(sourceTableNames).OrderBy(t => t).ToList();
            var inBoth = sourceTableNames.Intersect(targetTableNames).OrderBy(t => t).ToList();

            // Build summary
            var summary = new StringBuilder();
            summary.AppendLine($"📊 Cross-Database Schema Comparison Results");
            summary.AppendLine($"═══════════════════════════════════════════════════════");
            summary.AppendLine();
            summary.AppendLine($"📥 Source: {sourceProfile} → {sourceSchema}");
            summary.AppendLine($"📤 Target: {targetProfile} → {targetSchema}");
            summary.AppendLine();
            summary.AppendLine($"📋 Table Summary:");
            summary.AppendLine($"   ✅ Tables in both databases: {inBoth.Count}");
            summary.AppendLine($"   ➕ Only in source: {onlyInSource.Count}");
            summary.AppendLine($"   ➖ Only in target: {onlyInTarget.Count}");
            summary.AppendLine();
            summary.AppendLine($"Total tables compared: {sourceTableNames.Count} (source) vs {targetTableNames.Count} (target)");

            SummaryText.Text = summary.ToString();

            // Populate lists
            OnlyInSourceList.Items.Clear();
            OnlyInTargetList.Items.Clear();
            InBothList.Items.Clear();

            OnlyInSourceHeader.Text = $"Tables that exist only in {sourceProfile}.{sourceSchema} ({onlyInSource.Count}):";
            OnlyInTargetHeader.Text = $"Tables that exist only in {targetProfile}.{targetSchema} ({onlyInTarget.Count}):";

            foreach (var table in onlyInSource)
            {
                OnlyInSourceList.Items.Add($"{sourceSchema}.{table}");
            }

            foreach (var table in onlyInTarget)
            {
                OnlyInTargetList.Items.Add($"{targetSchema}.{table}");
            }

            foreach (var table in inBoth)
            {
                InBothList.Items.Add($"{sourceSchema}.{table} ↔ {targetSchema}.{table}");
            }

            // Generate migration DDL
            var ddl = new StringBuilder();
            ddl.AppendLine($"-- Cross-Database Migration DDL");
            ddl.AppendLine($"-- Source: {sourceProfile}.{sourceSchema}");
            ddl.AppendLine($"-- Target: {targetProfile}.{targetSchema}");
            ddl.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            ddl.AppendLine();

            if (onlyInSource.Count > 0)
            {
                ddl.AppendLine($"-- ═══════════════════════════════════════════════════════");
                ddl.AppendLine($"-- TABLES TO CREATE IN TARGET (exist only in source)");
                ddl.AppendLine($"-- ═══════════════════════════════════════════════════════");
                ddl.AppendLine();

                foreach (var table in onlyInSource)
                {
                    ddl.AppendLine($"-- TODO: Generate CREATE TABLE statement for {targetSchema}.{table}");
                    ddl.AppendLine($"-- Copy structure from {sourceSchema}.{table} in source database");
                    ddl.AppendLine();
                }
            }

            if (onlyInTarget.Count > 0)
            {
                ddl.AppendLine($"-- ═══════════════════════════════════════════════════════");
                ddl.AppendLine($"-- TABLES TO DROP FROM TARGET (don't exist in source)");
                ddl.AppendLine($"-- ═══════════════════════════════════════════════════════");
                ddl.AppendLine();

                foreach (var table in onlyInTarget)
                {
                    ddl.AppendLine($"-- WARNING: Dropping table will lose all data!");
                    ddl.AppendLine($"-- DROP TABLE {targetSchema}.{table};");
                    ddl.AppendLine();
                }
            }

            MigrationDdlTextBox.Text = ddl.ToString();

            ResultsTabControl.Visibility = Visibility.Visible;

            Logger.Info("Comparison completed: {OnlySource} only in source, {OnlyTarget} only in target, {Both} in both",
                onlyInSource.Count, onlyInTarget.Count, inBoth.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during cross-database comparison");
            MessageBox.Show($"Error during comparison: {ex.Message}", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            CompareButton.IsEnabled = true;
            CompareButton.Content = "🔍 Compare Schemas";
            ProgressBar.Visibility = Visibility.Collapsed;
        }
    }

    private void CopyDdl_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(MigrationDdlTextBox.Text))
        {
            Clipboard.SetText(MigrationDdlTextBox.Text);
            MessageBox.Show("DDL copied to clipboard!", "Copied", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private void SaveDdl_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(MigrationDdlTextBox.Text))
        {
            MessageBox.Show("No DDL to save.", "Save DDL", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var saveDialog = new SaveFileDialog
        {
            Filter = "SQL Files (*.sql)|*.sql|All Files (*.*)|*.*",
            DefaultExt = ".sql",
            FileName = $"migration_{DateTime.Now:yyyyMMdd_HHmmss}.sql"
        };

        if (saveDialog.ShowDialog() == true)
        {
            try
            {
                File.WriteAllText(saveDialog.FileName, MigrationDdlTextBox.Text);
                MessageBox.Show($"DDL saved to:\n{saveDialog.FileName}", "Saved", 
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error saving DDL file");
                MessageBox.Show($"Error saving file: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        base.OnClosed(e);
        
        // Dispose connections
        _sourceConnection?.Dispose();
        _targetConnection?.Dispose();
    }
}
