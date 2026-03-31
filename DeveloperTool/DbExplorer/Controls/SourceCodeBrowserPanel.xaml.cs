using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class SourceCodeBrowserPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly SourceCodeService _sourceService;
    private IConnectionManager? _connectionManager;
    private List<SourceCodeObject> _currentObjects = new();
    
    public SourceCodeBrowserPanel()
    {
        InitializeComponent();
        _sourceService = new SourceCodeService();
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
        await LoadSchemasAsync();
    }
    
    private async Task LoadSchemasAsync()
    {
        if (_connectionManager == null) return;
        try
        {
            var metadataService = new MetadataLoaderService();
            var schemas = await metadataService.GetAllSchemasAsync(_connectionManager);
            SchemaComboBox.ItemsSource = schemas;
            if (schemas.Count > 0) SchemaComboBox.SelectedIndex = 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load schemas");
        }
    }
    
    private async void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        await LoadObjectsAsync();
    }
    
    private async void ObjectTypeComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        await LoadObjectsAsync();
    }
    
    private async Task LoadObjectsAsync()
    {
        if (_connectionManager == null || SchemaComboBox.SelectedItem == null) return;
        
        var schema = SchemaComboBox.SelectedItem.ToString() ?? string.Empty;
        var objectType = (ObjectTypeComboBox.SelectedItem as ComboBoxItem)?.Content.ToString() ?? "Procedures";
        
        try
        {
            _currentObjects = objectType switch
            {
                "Procedures" => await _sourceService.GetProceduresAsync(_connectionManager, schema),
                "Functions" => await _sourceService.GetFunctionsAsync(_connectionManager, schema),
                "Views" => await _sourceService.GetViewsAsync(_connectionManager, schema),
                _ => new List<SourceCodeObject>()
            };
            
            ObjectsListBox.ItemsSource = _currentObjects.Select(o => o.Name).ToList();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load objects");
        }
    }
    
    private void ObjectsListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ObjectsListBox.SelectedItem == null) return;
        
        var objectName = ObjectsListBox.SelectedItem.ToString();
        var sourceObj = _currentObjects.FirstOrDefault(o => o.Name == objectName);
        
        if (sourceObj != null)
        {
            ObjectNameText.Text = $"{sourceObj.Schema}.{sourceObj.Name} ({sourceObj.ObjectType})";
            SourceCodeEditor.Text = sourceObj.SourceCode ?? "-- No source code available";
        }
    }
    
    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        Clipboard.SetText(SourceCodeEditor.Text);
        MessageBox.Show("Source code copied to clipboard", "Copy", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(SourceCodeEditor.Text)) return;
        
        var saveDialog = new SaveFileDialog 
        { 
            Filter = "SQL Files (*.sql)|*.sql|All Files (*.*)|*.*",
            FileName = $"{ObjectNameText.Text}.sql"
        };
        
        if (saveDialog.ShowDialog() == true)
        {
            await File.WriteAllTextAsync(saveDialog.FileName, SourceCodeEditor.Text);
            MessageBox.Show("Exported successfully", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
}

