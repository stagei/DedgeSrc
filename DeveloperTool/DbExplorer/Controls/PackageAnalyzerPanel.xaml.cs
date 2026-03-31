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

public partial class PackageAnalyzerPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly PackageAnalyzerService _packageService;
    private readonly MetadataLoaderService _metadataService;
    private IConnectionManager? _connectionManager;
    private List<PackageAnalysisInfo> _packages = new();
    
    public PackageAnalyzerPanel()
    {
        InitializeComponent();
        _packageService = new PackageAnalyzerService();
        _metadataService = new MetadataLoaderService();
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
        try
        {
            var schemas = await _metadataService.GetAllSchemasAsync(_connectionManager);
            SchemaComboBox.ItemsSource = schemas;
            if (schemas.Count > 0) SchemaComboBox.SelectedIndex = 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize");
        }
    }
    
    private async void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        await RefreshDataAsync();
    }
    
    private async Task RefreshDataAsync()
    {
        if (_connectionManager == null || SchemaComboBox.SelectedItem == null) return;
        try
        {
            var schema = SchemaComboBox.SelectedItem.ToString() ?? string.Empty;
            _packages = await _packageService.GetPackagesAsync(_connectionManager, schema);
            PackagesListBox.ItemsSource = _packages.Select(p => p.Name).ToList();
            StatusText.Text = $"{_packages.Count} packages";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh");
        }
    }
    
    private async void PackagesListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (PackagesListBox.SelectedItem == null || _connectionManager == null || SchemaComboBox.SelectedItem == null) return;
        
        try
        {
            var packageName = PackagesListBox.SelectedItem.ToString() ?? string.Empty;
            var schema = SchemaComboBox.SelectedItem.ToString() ?? string.Empty;
            var statements = await _packageService.GetPackageStatementsAsync(_connectionManager, schema, packageName);
            StatementsTextBox.Text = string.Join("\n\n-- Statement --\n\n", statements);
            StatusText.Text = $"{statements.Count} statements in package";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load statements");
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshDataAsync();
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        if (_packages.Count == 0) return;
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"packages_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Schema,Name,Last Used,Definer,Statement Count");
            foreach (var p in _packages)
                csv.AppendLine($"{p.Schema},{p.Name},{p.LastUsed},{p.Definer},{p.StatementCount}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
        }
    }
}

