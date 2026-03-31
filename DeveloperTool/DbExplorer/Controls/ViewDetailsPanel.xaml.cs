using System;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Controls;

/// <summary>
/// UserControl for displaying view details - can be embedded in dialogs or tabs
/// </summary>
public partial class ViewDetailsPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;
    private readonly string _schema;
    private readonly string _viewName;

    public ViewDetailsPanel(IConnectionManager connectionManager, string schema, string viewName)
    {
        InitializeComponent();
        _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));
        _metadataHandler = App.MetadataHandler;
        _schema = schema?.Trim() ?? "";
        _viewName = viewName?.Trim() ?? "";

        ViewNameText.Text = _viewName;
        ViewInfoText.Text = $"Schema: {_schema} • Full Name: {_schema}.{_viewName}";

        this.Loaded += async (s, e) =>
        {
            UIStyleService.ApplyStyles(this);
            await LoadViewDetailsAsync();
        };
    }

    private async Task LoadViewDetailsAsync()
    {
        try
        {
            if (_metadataHandler == null)
            {
                throw new InvalidOperationException("MetadataHandler not initialized");
            }
            
            // Load view definition - use required statement from JSON config
            var defSqlTemplate = _metadataHandler.GetRequiredStatement("GetViewDefinition");
            var defSql = ReplacePlaceholders(defSqlTemplate, _schema, _viewName);
            var defResult = await _connectionManager.ExecuteQueryAsync(defSql);
            if (defResult.Rows.Count > 0)
            {
                Dispatcher.Invoke(() =>
                {
                    DefinitionTextBox.Text = defResult.Rows[0][0]?.ToString() ?? "No definition found";
                });
            }

            // Load columns - use required statement from JSON config
            var colSqlTemplate = _metadataHandler.GetRequiredStatement("GetViewColumns_Display");
            var colSql = ReplacePlaceholders(colSqlTemplate, _schema, _viewName);
            var colResult = await _connectionManager.ExecuteQueryAsync(colSql);
            Dispatcher.Invoke(() => ColumnsGrid.ItemsSource = colResult.DefaultView);

            // Load dependencies - use required statement from JSON config
            var depSqlTemplate = _metadataHandler.GetRequiredStatement("GetViewDependencies");
            var depSql = ReplacePlaceholders(depSqlTemplate, _schema, _viewName);
            var depResult = await _connectionManager.ExecuteQueryAsync(depSql);
            Dispatcher.Invoke(() =>
            {
                foreach (System.Data.DataRow row in depResult.Rows)
                {
                    DependenciesListBox.Items.Add(row["DEPENDENCY"]?.ToString());
                }
            });

            Logger.Info("View details loaded: {Schema}.{View}", _schema, _viewName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading view details");
            MessageBox.Show($"Error loading view details: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Replace ? placeholders in SQL with quoted values
    /// </summary>
    private static string ReplacePlaceholders(string sql, params string[] values)
    {
        var result = sql;
        foreach (var value in values)
        {
            var idx = result.IndexOf('?');
            if (idx >= 0)
            {
                result = result.Remove(idx, 1).Insert(idx, $"'{value}'");
            }
        }
        return result;
    }

    private void CopyDefinition_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(DefinitionTextBox.Text);
            MessageBox.Show("View definition copied to clipboard!", "Success", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy to clipboard");
            MessageBox.Show($"Failed to copy: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
