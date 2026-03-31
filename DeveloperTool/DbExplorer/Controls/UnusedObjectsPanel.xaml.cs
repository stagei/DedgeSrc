using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class UnusedObjectsPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly UnusedObjectDetectorService _unusedService;
    private IConnectionManager? _connectionManager;
    
    public UnusedObjectsPanel()
    {
        InitializeComponent();
        _unusedService = new UnusedObjectDetectorService();
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
        await RefreshDataAsync();
    }
    
    private async Task RefreshDataAsync()
    {
        if (_connectionManager == null) return;
        try
        {
            StatusText.Text = "Loading...";
            var threshold = int.TryParse(ThresholdTextBox.Text, out var days) ? days : 365;
            
            var unusedTables = await _unusedService.FindUnusedTablesAsync(_connectionManager, threshold);
            var allUnused = new List<UnusedObjectInfo>(unusedTables);
            
            if (IncludePackagesCheckBox.IsChecked == true)
            {
                var unusedPackages = await _unusedService.FindUnusedPackagesAsync(_connectionManager, threshold);
                allUnused.AddRange(unusedPackages);
            }
            
            UnusedObjectsDataGrid.ItemsSource = allUnused.OrderByDescending(o => o.DaysUnused).ToList();
            StatusText.Text = $"{allUnused.Count} unused objects - {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh");
            MessageBox.Show($"Error:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshDataAsync();
    
    private void GenerateDrop_Click(object sender, RoutedEventArgs e)
    {
        var objects = UnusedObjectsDataGrid.ItemsSource as List<UnusedObjectInfo>;
        if (objects == null || objects.Count == 0) return;
        var script = _unusedService.GenerateDropScript(objects);
        var window = Services.ThemedWindowHelper.CreateScriptWindow("DROP Script - REVIEW CAREFULLY!", script, 700, 500, Window.GetWindow(this));
        window.ShowDialog();
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var objects = UnusedObjectsDataGrid.ItemsSource as List<UnusedObjectInfo>;
        if (objects == null || objects.Count == 0) return;
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"unused_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Type,Schema,Name,Last Used,Days Unused,Status");
            foreach (var o in objects)
                csv.AppendLine($"{o.ObjectType},{o.Schema},{o.Name},{o.LastUsed},{o.DaysUnused},{o.UnusedStatus}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
        }
    }
}

