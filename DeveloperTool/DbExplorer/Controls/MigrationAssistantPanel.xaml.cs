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

public partial class MigrationAssistantPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MigrationPlannerService _migrationService;
    private readonly MetadataLoaderService _metadataService;
    private IConnectionManager? _connectionManager;
    
    public MigrationAssistantPanel()
    {
        InitializeComponent();
        _migrationService = new MigrationPlannerService();
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
    
    private async void AnalyzeButton_Click(object sender, RoutedEventArgs e)
    {
        if (_connectionManager == null || SchemaComboBox.SelectedItem == null) return;
        
        try
        {
            var schema = SchemaComboBox.SelectedItem.ToString() ?? string.Empty;
            var threshold = int.TryParse(ThresholdTextBox.Text, out var years) ? years : 3;
            
            var candidates = await _migrationService.IdentifyMigrationCandidatesAsync(_connectionManager, schema, threshold);
            CandidatesDataGrid.ItemsSource = candidates;
            
            var activeCount = candidates.Count(c => c.IsActive);
            var archiveCount = candidates.Count - activeCount;
            
            StatusText.Text = $"{activeCount} active tables, {archiveCount} to archive";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to analyze");
            MessageBox.Show($"Error:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void GenerateScript_Click(object sender, RoutedEventArgs e)
    {
        var candidates = CandidatesDataGrid.ItemsSource as List<MigrationCandidate>;
        if (candidates == null || candidates.Count == 0 || _connectionManager == null) return;
        
        try
        {
            var script = await _migrationService.GenerateMigrationScriptAsync(_connectionManager, candidates);
            var window = Services.ThemedWindowHelper.CreateScriptWindow("Migration Plan", script, 700, 500, Window.GetWindow(this));
            window.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate script");
        }
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var candidates = CandidatesDataGrid.ItemsSource as List<MigrationCandidate>;
        if (candidates == null || candidates.Count == 0) return;
        
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"migration_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Schema,Table,Last Used,Row Count,Is Active,Migration Status");
            foreach (var c in candidates)
                csv.AppendLine($"{c.Schema},{c.TableName},{c.LastUsed},{c.RowCount},{c.IsActive},{c.MigrationStatus}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
        }
    }
}

