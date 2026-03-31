using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Microsoft.Win32;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class LockMonitorPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly LockMonitorService _lockMonitorService;
    private IConnectionManager? _connectionManager;
    private DispatcherTimer? _autoRefreshTimer;
    private bool _isAutoRefreshEnabled;
    
    public LockMonitorPanel()
    {
        InitializeComponent();
        _lockMonitorService = new LockMonitorService();
        Logger.Debug("LockMonitorPanel initialized");
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        Logger.Info("Initializing Lock Monitor");
        _connectionManager = connectionManager;
        
        try
        {
            // Initialize filters - load schemas from database
            SchemaComboBox.Items.Clear();
            SchemaComboBox.Items.Add("*");
            
            // Load schemas from database
            await LoadSchemasAsync();
            
            SchemaComboBox.SelectedIndex = 0;
            
            TableComboBox.Items.Clear();
            TableComboBox.Items.Add("*");
            TableComboBox.SelectedIndex = 0;
            
            // Load initial data
            await RefreshDataAsync();
            
            Logger.Info("Lock Monitor initialized successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize Lock Monitor");
            MessageBox.Show($"Failed to initialize lock monitor:\n\n{ex.Message}",
                "Initialization Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async Task LoadSchemasAsync()
    {
        if (_connectionManager == null) return;
        
        try
        {
            Logger.Debug("Loading schemas from database");
            var metadataHandler = new MetadataHandler();
            var sql = metadataHandler.GetStatement("GetSchemasStatement");
            
            var result = await _connectionManager.ExecuteQueryAsync(sql);
            
            foreach (System.Data.DataRow row in result.Rows)
            {
                var schemaName = row["SCHEMANAME"]?.ToString()?.Trim();
                if (!string.IsNullOrEmpty(schemaName))
                {
                    SchemaComboBox.Items.Add(schemaName);
                }
            }
            
            Logger.Debug("Loaded {Count} schemas", result.Rows.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load schemas");
        }
    }
    
    private async void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_connectionManager == null) return;
        
        var selectedSchema = SchemaComboBox.SelectedItem?.ToString();
        Logger.Debug("Schema selection changed to: {Schema}", selectedSchema);
        
        // Clear and reset table combo
        TableComboBox.Items.Clear();
        TableComboBox.Items.Add("*");
        
        if (string.IsNullOrEmpty(selectedSchema) || selectedSchema == "*")
        {
            TableComboBox.SelectedIndex = 0;
            return;
        }
        
        try
        {
            // Load tables for selected schema
            await LoadTablesForSchemaAsync(selectedSchema);
            TableComboBox.SelectedIndex = 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load tables for schema {Schema}", selectedSchema);
        }
    }
    
    private async Task LoadTablesForSchemaAsync(string schema)
    {
        if (_connectionManager == null) return;
        
        try
        {
            Logger.Debug("Loading tables for schema: {Schema}", schema);
            var metadataHandler = new MetadataHandler();
            var sqlTemplate = metadataHandler.GetStatement("GetTablesForSchema");
            
            // Replace parameter placeholder with actual value (properly escaped)
            var sql = sqlTemplate.Replace("?", $"'{schema.Replace("'", "''")}'");
            
            var result = await _connectionManager.ExecuteQueryAsync(sql);
            
            foreach (System.Data.DataRow row in result.Rows)
            {
                var tableName = row["TABNAME"]?.ToString()?.Trim();
                if (!string.IsNullOrEmpty(tableName))
                {
                    TableComboBox.Items.Add(tableName);
                }
            }
            
            Logger.Debug("Loaded {Count} tables for schema {Schema}", result.Rows.Count, schema);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load tables for schema {Schema}", schema);
        }
    }
    
    private async Task RefreshDataAsync()
    {
        Logger.Info("Refreshing lock data");
        
        if (_connectionManager == null)
        {
            Logger.Warn("Connection manager is null");
            StatusText.Text = "No connection";
            return;
        }
        
        try
        {
            StatusText.Text = "Loading...";
            RefreshButton.IsEnabled = false;
            
            var filter = new LockMonitorFilter
            {
                SchemaFilter = SchemaComboBox.SelectedItem?.ToString() ?? "*",
                TableFilter = TableComboBox.SelectedItem?.ToString() ?? "*",
                ShowOnlyBlocked = ShowOnlyBlockedCheckBox.IsChecked ?? false
            };
            
            var locks = await _lockMonitorService.GetCurrentLocksAsync(_connectionManager, filter);
            
            LocksDataGrid.ItemsSource = locks;
            StatusText.Text = $"Found {locks.Count} locks - Last updated: {DateTime.Now:HH:mm:ss}";
            
            Logger.Info("Lock data refreshed - {Count} locks found", locks.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh lock data");
            StatusText.Text = "Error loading locks";
            MessageBox.Show($"Failed to load lock data:\n\n{ex.Message}",
                "Load Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Refresh button clicked");
        await RefreshDataAsync();
    }
    
    private void GenerateScript_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Generate script button clicked");
        
        var locks = LocksDataGrid.ItemsSource as List<LockInfo>;
        if (locks == null || locks.Count == 0)
        {
            MessageBox.Show("No locks to generate script for.", "Generate Script",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        try
        {
            var script = _lockMonitorService.GenerateForceApplicationScript(locks);
            
            var scriptWindow = new Window
            {
                Title = "Force Application Script",
                Width = 600,
                Height = 400,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = Window.GetWindow(this)
            };
            
            var textBox = new TextBox
            {
                Text = script,
                IsReadOnly = true,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                FontFamily = new System.Windows.Media.FontFamily("Consolas"),
                FontSize = 12,
                Margin = new Thickness(10)
            };
            
            scriptWindow.Content = textBox;
            scriptWindow.ShowDialog();
            
            Logger.Info("Force script generated successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate script");
            MessageBox.Show($"Failed to generate script:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Export button clicked");
        
        var locks = LocksDataGrid.ItemsSource as List<LockInfo>;
        if (locks == null || locks.Count == 0)
        {
            MessageBox.Show("No data to export.", "Export",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        try
        {
            var saveDialog = new SaveFileDialog
            {
                Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
                FileName = $"locks_{DateTime.Now:yyyyMMdd_HHmmss}.csv"
            };
            
            if (saveDialog.ShowDialog() == true)
            {
                await ExportToCsvAsync(locks, saveDialog.FileName);
                MessageBox.Show($"Exported {locks.Count} locks to:\n{saveDialog.FileName}",
                    "Export Complete", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export");
            MessageBox.Show($"Failed to export:\n\n{ex.Message}",
                "Export Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void AutoRefreshButton_Click(object sender, RoutedEventArgs e)
    {
        _isAutoRefreshEnabled = !_isAutoRefreshEnabled;
        
        if (_isAutoRefreshEnabled)
        {
            _autoRefreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            _autoRefreshTimer.Tick += async (s, args) => await RefreshDataAsync();
            _autoRefreshTimer.Start();
            AutoRefreshButton.Content = "⏱️ Auto-Refresh: ON";
            Logger.Info("Auto-refresh enabled (5 second interval)");
        }
        else
        {
            _autoRefreshTimer?.Stop();
            _autoRefreshTimer = null;
            AutoRefreshButton.Content = "⏱️ Auto-Refresh: OFF";
            Logger.Info("Auto-refresh disabled");
        }
    }
    
    private async Task ExportToCsvAsync(List<LockInfo> locks, string filePath)
    {
        var csv = new StringBuilder();
        csv.AppendLine("Schema,Table,Lock Mode,Mode Description,Status,User,Application,Client,Agent ID,Severity");
        
        foreach (var lockInfo in locks)
        {
            csv.AppendLine($"{lockInfo.SchemaName},{lockInfo.TableName},{lockInfo.LockMode}," +
                          $"{lockInfo.LockModeDescription},{lockInfo.LockStatus},{lockInfo.AuthorizationId}," +
                          $"{lockInfo.ApplicationName},{lockInfo.ClientName},{lockInfo.AgentId},{lockInfo.LockSeverity}");
        }
        
        await File.WriteAllTextAsync(filePath, csv.ToString());
        Logger.Info("CSV export completed: {File}", filePath);
    }
    
    public void Dispose()
    {
        _autoRefreshTimer?.Stop();
        _autoRefreshTimer = null;
    }
}

