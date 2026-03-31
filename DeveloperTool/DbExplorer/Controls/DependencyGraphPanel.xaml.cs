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

public partial class DependencyGraphPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DependencyAnalyzerService _depService;
    private readonly MetadataLoaderService _metadataService;
    private IConnectionManager? _connectionManager;
    private List<DependencyNode> _dependencies = new();
    
    public DependencyGraphPanel()
    {
        InitializeComponent();
        _depService = new DependencyAnalyzerService();
        _metadataService = new MetadataLoaderService();
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
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
        if (SchemaComboBox.SelectedItem == null || _connectionManager == null) return;
        try
        {
            var schema = SchemaComboBox.SelectedItem.ToString() ?? string.Empty;
            var tables = await _metadataService.GetTablesAsync(_connectionManager, schema);
            TableComboBox.ItemsSource = tables.Select(t => t.Name).ToList();
            if (tables.Count > 0) TableComboBox.SelectedIndex = 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load tables");
        }
    }
    
    private async void AnalyzeButton_Click(object sender, RoutedEventArgs e)
    {
        if (_connectionManager == null || SchemaComboBox.SelectedItem == null || TableComboBox.SelectedItem == null) return;
        
        try
        {
            var schema = SchemaComboBox.SelectedItem.ToString() ?? string.Empty;
            var table = TableComboBox.SelectedItem.ToString() ?? string.Empty;
            
            _dependencies = await _depService.GetTableDependenciesAsync(_connectionManager, schema, table);
            
            var incoming = _dependencies.Where(d => d.Direction == "INCOMING").ToList();
            var outgoing = _dependencies.Where(d => d.Direction == "OUTGOING").ToList();
            
            IncomingDataGrid.ItemsSource = incoming;
            OutgoingDataGrid.ItemsSource = outgoing;
            
            StatusText.Text = $"{incoming.Count} incoming, {outgoing.Count} outgoing dependencies";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to analyze dependencies");
            MessageBox.Show($"Error:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        SchemaComboBox_SelectionChanged(sender, null!);
    }
    
    private void GenerateDrop_Click(object sender, RoutedEventArgs e)
    {
        if (_dependencies.Count == 0) return;
        var script = _depService.GenerateDependencyOrderedDropScript(_dependencies);
        var window = Services.ThemedWindowHelper.CreateScriptWindow("Dependency-Ordered DROP Script", script, 700, 500, Window.GetWindow(this));
        window.ShowDialog();
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        if (_dependencies.Count == 0) return;
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"dependencies_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Schema,Name,Type,DependsOnSchema,DependsOnName,DependsOnType,Direction");
            foreach (var d in _dependencies)
                csv.AppendLine($"{d.Schema},{d.Name},{d.Type},{d.DependsOnSchema},{d.DependsOnName},{d.DependsOnType},{d.Direction}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
        }
    }
}

