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
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class StatisticsManagerPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly StatisticsService _statisticsService;
    private IConnectionManager? _connectionManager;
    
    public StatisticsManagerPanel()
    {
        InitializeComponent();
        _statisticsService = new StatisticsService();
        Logger.Debug("StatisticsManagerPanel initialized");
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        Logger.Info("Initializing Statistics Manager");
        _connectionManager = connectionManager;
        
        try
        {
            SchemaComboBox.Items.Add("*");
            SchemaComboBox.SelectedIndex = 0;
            await RefreshDataAsync();
            Logger.Info("Statistics Manager initialized");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize Statistics Manager");
            MessageBox.Show($"Failed to initialize:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async Task RefreshDataAsync()
    {
        if (_connectionManager == null) return;
        
        try
        {
            StatusText.Text = "Loading...";
            RefreshButton.IsEnabled = false;
            
            var filter = new StatisticsFilter
            {
                SchemaFilter = SchemaComboBox.SelectedItem?.ToString() ?? "*",
                ShowOnlyOutdated = ShowOnlyOutdatedCheckBox.IsChecked ?? false,
                OutdatedThresholdDays = int.TryParse(ThresholdDaysTextBox.Text, out var days) ? days : 30
            };
            
            var stats = await _statisticsService.GetTableStatisticsAsync(_connectionManager, filter);
            StatisticsDataGrid.ItemsSource = stats;
            StatusText.Text = $"Found {stats.Count} tables - {DateTime.Now:HH:mm:ss}";
            Logger.Info("Statistics refreshed - {Count} tables", stats.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh statistics");
            StatusText.Text = "Error";
            MessageBox.Show($"Failed to load statistics:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await RefreshDataAsync();
    }
    
    private void GenerateRunstats_Click(object sender, RoutedEventArgs e)
    {
        var stats = StatisticsDataGrid.SelectedItems.Cast<TableStatistics>().ToList();
        if (stats.Count == 0)
        {
            MessageBox.Show("Please select tables to generate RUNSTATS for.",
                "Generate RUNSTATS", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        var script = _statisticsService.GenerateRunstatsScript(stats);
        
        // Open script in a new editor tab
        if (Application.Current.MainWindow is MainWindow mainWindow)
        {
            mainWindow.CreateNewTabWithSql(script, "RUNSTATS Script");
            
            // Close the Statistics Manager dialog if it's in a separate window
            var parentWindow = Window.GetWindow(this);
            if (parentWindow != null && parentWindow != mainWindow)
            {
                parentWindow.Close();
            }
        }
        else
        {
            // Fallback: copy to clipboard if main window not accessible
            Clipboard.SetText(script);
            MessageBox.Show($"RUNSTATS script for {stats.Count} table(s) copied to clipboard.",
                "Generate RUNSTATS", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var stats = StatisticsDataGrid.ItemsSource as List<TableStatistics>;
        if (stats == null || stats.Count == 0) return;
        
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"statistics_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Schema,Table,Last Update,Days Old,Row Count,Tablespace,Status");
            foreach (var s in stats)
                csv.AppendLine($"{s.SchemaName},{s.TableName},{s.StatsTime},{s.DaysSinceUpdate},{s.CardinalityEstimate},{s.TablespaceName},{s.StatsStatus}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
            MessageBox.Show("Exported successfully", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
}

