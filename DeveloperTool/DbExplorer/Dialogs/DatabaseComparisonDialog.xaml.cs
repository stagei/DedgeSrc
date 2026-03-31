using NLog;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class DatabaseComparisonDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly DatabaseComparisonService _comparisonService;
    private readonly MetadataHandler _metadataHandler;

    public DatabaseComparisonDialog(IConnectionManager connectionManager)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _comparisonService = new DatabaseComparisonService();
        _metadataHandler = new MetadataHandler();

        Loaded += async (s, e) => await LoadSchemasAsync();
    }

    private async Task LoadSchemasAsync()
    {
        try
        {
            Logger.Debug("Loading schemas for comparison dialog");
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1"; // TODO: Get from connection
            var sql = _metadataHandler.GetQuery(provider, version, "GetSchemasStatement");
            var result = await _connectionManager.ExecuteQueryAsync(sql);

            var schemas = new List<string>();
            foreach (System.Data.DataRow row in result.Rows)
            {
                var schemaName = row["SCHEMANAME"]?.ToString()?.Trim() ?? "";
                if (!string.IsNullOrEmpty(schemaName) && !schemaName.StartsWith("SYS"))
                {
                    schemas.Add(schemaName);
                }
            }

            SourceComboBox.ItemsSource = schemas;
            TargetComboBox.ItemsSource = schemas;

            Logger.Info("Loaded {Count} schemas for comparison", schemas.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading schemas");
            MessageBox.Show($"Error loading schemas: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void Compare_Click(object sender, RoutedEventArgs e)
    {
        if (SourceComboBox.SelectedItem == null || TargetComboBox.SelectedItem == null)
        {
            MessageBox.Show("Please select both source and target schemas", "Select Schemas", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            var sourceSchema = SourceComboBox.SelectedItem.ToString() ?? "";
            var targetSchema = TargetComboBox.SelectedItem.ToString() ?? "";

            Logger.Info("Comparing schemas: {Source} vs {Target}", sourceSchema, targetSchema);

            // Step 1: Get all tables in both schemas using MetadataHandler
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1"; // TODO: Get from connection
            var sourceTablesQuery = _metadataHandler.GetQuery(provider, version, "GetTablesForSchema")
                .Replace("TRIM(TABSCHEMA) = ?", $"TRIM(TABSCHEMA) = '{sourceSchema}'");
            var targetTablesQuery = _metadataHandler.GetQuery(provider, version, "GetTablesForSchema")
                .Replace("TRIM(TABSCHEMA) = ?", $"TRIM(TABSCHEMA) = '{targetSchema}'");
            
            var sourceTables = await _connectionManager.ExecuteQueryAsync(sourceTablesQuery);
            var targetTables = await _connectionManager.ExecuteQueryAsync(targetTablesQuery);
            
            Logger.Debug("Source schema {Source} has {Count} tables", sourceSchema, sourceTables.Rows.Count);
            Logger.Debug("Target schema {Target} has {Count} tables", targetSchema, targetTables.Rows.Count);
            
            // Step 2: Find tables only in source
            var sourceTableNames = new HashSet<string>();
            var targetTableNames = new HashSet<string>();
            
            foreach (System.Data.DataRow row in sourceTables.Rows)
            {
                sourceTableNames.Add(row["TABNAME"]?.ToString()?.Trim() ?? "");
            }
            
            foreach (System.Data.DataRow row in targetTables.Rows)
            {
                targetTableNames.Add(row["TABNAME"]?.ToString()?.Trim() ?? "");
            }
            
            var onlyInSource = sourceTableNames.Except(targetTableNames).ToList();
            var onlyInTarget = targetTableNames.Except(sourceTableNames).ToList();
            var inBoth = sourceTableNames.Intersect(targetTableNames).ToList();
            
            // Step 3: Display results
            SummaryText.Text = $"Comparison: {sourceSchema} vs {targetSchema}\n\n" +
                              $"✅ Tables in both: {inBoth.Count}\n" +
                              $"➡️ Only in {sourceSchema}: {onlyInSource.Count}\n" +
                              $"⬅️ Only in {targetSchema}: {onlyInTarget.Count}\n\n" +
                              $"Total tables compared: {sourceTableNames.Count + targetTableNames.Count}";
            
            OnlyInSourceList.Items.Clear();
            OnlyInTargetList.Items.Clear();
            DifferentList.Items.Clear();
            
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
                DifferentList.Items.Add($"{sourceSchema}.{table} ↔ {targetSchema}.{table}");
            }
            
            // Step 4: Generate migration DDL for missing tables
            var ddl = "-- Migration DDL to sync Target to Source\n\n";
            
            if (onlyInSource.Count > 0)
            {
                ddl += $"-- Tables to create in {targetSchema} (from {sourceSchema}):\n";
                foreach (var table in onlyInSource.Take(5)) // Limit to first 5 for preview
                {
                    ddl += $"-- CREATE TABLE {targetSchema}.{table} (source: {sourceSchema}.{table})\n";
                }
                if (onlyInSource.Count > 5)
                {
                    ddl += $"-- ... and {onlyInSource.Count - 5} more tables\n";
                }
                ddl += "\n";
            }
            
            if (onlyInTarget.Count > 0)
            {
                ddl += $"-- Tables to drop from {targetSchema} (not in {sourceSchema}):\n";
                foreach (var table in onlyInTarget.Take(5))
                {
                    ddl += $"-- DROP TABLE {targetSchema}.{table};\n";
                }
                if (onlyInTarget.Count > 5)
                {
                    ddl += $"-- ... and {onlyInTarget.Count - 5} more tables\n";
                }
            }
            
            MigrationDdlTextBox.Text = ddl;
            ResultsTabControl.Visibility = Visibility.Visible;

            Logger.Info("Comparison completed: {OnlySource} only in source, {OnlyTarget} only in target, {Both} in both", 
                onlyInSource.Count, onlyInTarget.Count, inBoth.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during comparison");
            MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

