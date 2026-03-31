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

public partial class CdcManagerPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DataCaptureService _cdcService;
    private IConnectionManager? _connectionManager;
    
    public CdcManagerPanel()
    {
        InitializeComponent();
        _cdcService = new DataCaptureService();
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
        SchemaComboBox.Items.Add("*");
        SchemaComboBox.SelectedIndex = 0;
        await RefreshDataAsync();
    }
    
    private async Task RefreshDataAsync()
    {
        if (_connectionManager == null) return;
        try
        {
            StatusText.Text = "Loading...";
            var filter = new CdcMonitorFilter
            {
                SchemaFilter = SchemaComboBox.SelectedItem?.ToString() ?? "*",
                ShowOnlyDisabled = ShowOnlyDisabledCheckBox.IsChecked ?? false
            };
            var cdcInfo = await _cdcService.GetDataCaptureInfoAsync(_connectionManager, filter);
            CdcDataGrid.ItemsSource = cdcInfo;
            StatusText.Text = $"{cdcInfo.Count} tables - {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh CDC data");
            MessageBox.Show($"Error:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshDataAsync();
    
    private void GenerateEnable_Click(object sender, RoutedEventArgs e)
    {
        var tables = CdcDataGrid.ItemsSource as List<DataCaptureInfo>;
        if (tables == null) return;
        var script = _cdcService.GenerateEnableCdcScript(tables);
        ShowScriptDialog("Enable CDC Script", script);
    }
    
    private void GenerateDisable_Click(object sender, RoutedEventArgs e)
    {
        var tables = CdcDataGrid.ItemsSource as List<DataCaptureInfo>;
        if (tables == null) return;
        var script = _cdcService.GenerateDisableCdcScript(tables);
        ShowScriptDialog("Disable CDC Script", script);
    }
    
    private void ShowScriptDialog(string title, string script)
    {
        var window = Services.ThemedWindowHelper.CreateScriptWindow(title, script, 600, 400, Window.GetWindow(this));
        window.ShowDialog();
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var cdcInfo = CdcDataGrid.ItemsSource as List<DataCaptureInfo>;
        if (cdcInfo == null || cdcInfo.Count == 0) return;
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"cdc_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Schema,Table,DataCapture,Status,Tablespace");
            foreach (var c in cdcInfo)
                csv.AppendLine($"{c.SchemaName},{c.TableName},{c.DataCapture},{c.CdcStatus},{c.TablespaceName}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
        }
    }
}

