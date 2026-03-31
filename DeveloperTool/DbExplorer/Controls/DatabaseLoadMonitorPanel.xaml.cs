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

public partial class DatabaseLoadMonitorPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DatabaseLoadMonitorService _loadMonitorService;
    private IConnectionManager? _connectionManager;
    private DispatcherTimer? _autoRefreshTimer;
    private bool _isAutoRefreshEnabled;
    
    public DatabaseLoadMonitorPanel()
    {
        InitializeComponent();
        _loadMonitorService = new DatabaseLoadMonitorService();
        Logger.Debug("DatabaseLoadMonitorPanel initialized");
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
    }
    
    /// <summary>
    /// Initialize with connection manager
    /// </summary>
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        Logger.Info("Initializing Database Load Monitor");
        _connectionManager = connectionManager;
        
        try
        {
            // Load available schemas
            await LoadSchemasAsync();
            
            // Load initial data
            await RefreshDataAsync();
            
            Logger.Info("Database Load Monitor initialized successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize Database Load Monitor");
            MessageBox.Show($"Failed to initialize load monitor:\n\n{ex.Message}",
                "Initialization Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Load available schemas into dropdown
    /// </summary>
    private async Task LoadSchemasAsync()
    {
        Logger.Debug("Loading available schemas");
        
        if (_connectionManager == null)
        {
            Logger.Warn("Connection manager is null, cannot load schemas");
            return;
        }
        
        try
        {
            var excludeSystem = ExcludeSystemCheckBox.IsChecked ?? true;
            var schemas = await _loadMonitorService.GetAvailableSchemasAsync(_connectionManager, excludeSystem);
            
            SchemaComboBox.Items.Clear();
            foreach (var schema in schemas)
            {
                SchemaComboBox.Items.Add(schema);
            }
            
            SchemaComboBox.SelectedIndex = 0; // Select "*" by default
            
            Logger.Info("Loaded {Count} schemas", schemas.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load schemas");
        }
    }
    
    /// <summary>
    /// Load tables for selected schema
    /// </summary>
    private async Task LoadTablesAsync(string schema)
    {
        Logger.Debug("Loading tables for schema: {Schema}", schema);
        
        if (_connectionManager == null)
        {
            Logger.Warn("Connection manager is null, cannot load tables");
            return;
        }
        
        try
        {
            var tables = await _loadMonitorService.GetTablesForSchemaAsync(_connectionManager, schema);
            
            TableComboBox.Items.Clear();
            foreach (var table in tables)
            {
                TableComboBox.Items.Add(table);
            }
            
            TableComboBox.SelectedIndex = 0; // Select "*" by default
            
            Logger.Info("Loaded {Count} tables for schema {Schema}", tables.Count, schema);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load tables for schema: {Schema}", schema);
        }
    }
    
    /// <summary>
    /// Refresh activity data
    /// </summary>
    private async Task RefreshDataAsync()
    {
        Logger.Info("Refreshing database load data");
        
        if (_connectionManager == null)
        {
            Logger.Warn("Connection manager is null, cannot refresh data");
            StatusText.Text = "No connection";
            return;
        }
        
        try
        {
            StatusText.Text = "Loading...";
            RefreshButton.IsEnabled = false;
            
            var filter = new LoadMonitorFilter
            {
                SelectedSchema = SchemaComboBox.SelectedItem?.ToString() ?? "*",
                SelectedTable = TableComboBox.SelectedItem?.ToString() ?? "*",
                ExcludeSystemSchemas = ExcludeSystemCheckBox.IsChecked ?? true
            };
            
            var metrics = await _loadMonitorService.GetTableActivityAsync(_connectionManager, filter);
            
            // Update data grid
            ActivityDataGrid.ItemsSource = metrics;
            
            // Update summary statistics
            UpdateSummaryStatistics(metrics);
            
            StatusText.Text = $"Last updated: {DateTime.Now:HH:mm:ss}";
            
            Logger.Info("Data refreshed successfully - {Count} tables", metrics.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh data");
            StatusText.Text = "Error loading data";
            MessageBox.Show($"Failed to load activity data:\n\n{ex.Message}",
                "Load Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
        }
    }
    
    /// <summary>
    /// Update summary statistics
    /// </summary>
    private void UpdateSummaryStatistics(List<TableActivityMetrics> metrics)
    {
        TotalTablesText.Text = metrics.Count.ToString("N0");
        TotalReadsText.Text = metrics.Sum(m => m.TotalRowsRead).ToString("N0");
        TotalInsertsText.Text = metrics.Sum(m => m.TotalRowsInserted).ToString("N0");
        TotalUpdatesText.Text = metrics.Sum(m => m.TotalRowsUpdated).ToString("N0");
        TotalDeletesText.Text = metrics.Sum(m => m.TotalRowsDeleted).ToString("N0");
        
        Logger.Debug("Summary stats updated - Tables: {Tables}, Total Activity: {Activity}",
            metrics.Count, metrics.Sum(m => m.TotalActivity));
    }
    
    // Event Handlers
    
    private async void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selectedSchema = SchemaComboBox.SelectedItem?.ToString();
        if (!string.IsNullOrEmpty(selectedSchema))
        {
            Logger.Debug("Schema selection changed: {Schema}", selectedSchema);
            await LoadTablesAsync(selectedSchema);
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Refresh button clicked");
        await RefreshDataAsync();
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Export button clicked");
        
        var metrics = ActivityDataGrid.ItemsSource as List<TableActivityMetrics>;
        if (metrics == null || metrics.Count == 0)
        {
            MessageBox.Show("No data to export.", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        try
        {
            var saveDialog = new SaveFileDialog
            {
                Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
                FileName = $"db_activity_{DateTime.Now:yyyyMMdd_HHmmss}.csv"
            };
            
            if (saveDialog.ShowDialog() == true)
            {
                await ExportToCsvAsync(metrics, saveDialog.FileName);
                MessageBox.Show($"Exported {metrics.Count} rows to:\n{saveDialog.FileName}",
                    "Export Complete", MessageBoxButton.OK, MessageBoxImage.Information);
                Logger.Info("Data exported to: {File}", saveDialog.FileName);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export data");
            MessageBox.Show($"Failed to export data:\n\n{ex.Message}",
                "Export Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void AutoRefreshButton_Click(object sender, RoutedEventArgs e)
    {
        _isAutoRefreshEnabled = !_isAutoRefreshEnabled;
        
        if (_isAutoRefreshEnabled)
        {
            // Start auto-refresh timer (10 seconds)
            _autoRefreshTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(10)
            };
            _autoRefreshTimer.Tick += async (s, args) => await RefreshDataAsync();
            _autoRefreshTimer.Start();
            
            AutoRefreshButton.Content = "⏱️ Auto-Refresh: ON";
            Logger.Info("Auto-refresh enabled (10 second interval)");
        }
        else
        {
            // Stop auto-refresh timer
            _autoRefreshTimer?.Stop();
            _autoRefreshTimer = null;
            
            AutoRefreshButton.Content = "⏱️ Auto-Refresh: OFF";
            Logger.Info("Auto-refresh disabled");
        }
    }
    
    /// <summary>
    /// Export metrics to CSV file
    /// </summary>
    private async Task ExportToCsvAsync(List<TableActivityMetrics> metrics, string filePath)
    {
        Logger.Debug("Exporting {Count} metrics to CSV: {File}", metrics.Count, filePath);
        
        var csv = new StringBuilder();
        
        // Header
        csv.AppendLine("Schema,Table,Tablespace,Rows Read,Rows Inserted,Rows Updated,Rows Deleted,Total Activity,Read %,Write %,Activity Level");
        
        // Data rows
        foreach (var metric in metrics)
        {
            csv.AppendLine($"{metric.SchemaName},{metric.TableName},{metric.TablespaceName}," +
                          $"{metric.TotalRowsRead},{metric.TotalRowsInserted}," +
                          $"{metric.TotalRowsUpdated},{metric.TotalRowsDeleted}," +
                          $"{metric.TotalActivity},{metric.ReadPercentage:F1}," +
                          $"{metric.WritePercentage:F1},{metric.ActivityLevel}");
        }
        
        await File.WriteAllTextAsync(filePath, csv.ToString());
        Logger.Info("CSV export completed: {File}", filePath);
    }
    
    /// <summary>
    /// Cleanup resources
    /// </summary>
    public void Dispose()
    {
        Logger.Debug("Disposing DatabaseLoadMonitorPanel");
        _autoRefreshTimer?.Stop();
        _autoRefreshTimer = null;
    }
}

