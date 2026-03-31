using NLog;
using System.Windows;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ViewDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;
    private readonly string _schema;
    private readonly string _viewName;

    public ViewDetailsDialog(IConnectionManager connectionManager, string schema, string viewName)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _metadataHandler = App.MetadataHandler;
        _schema = schema?.Trim() ?? "";
        _viewName = viewName?.Trim() ?? "";

        ViewNameText.Text = _viewName;
        ViewInfoText.Text = $"{_schema}.{_viewName}";

        Loaded += async (s, e) => 
        {
            // Apply all UI styles from the unified style service
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
            
            // Load view definition - use required statement
            var defSqlTemplate = _metadataHandler.GetRequiredStatement("GetViewDefinition");
            var defSql = ReplacePlaceholders(defSqlTemplate, _schema, _viewName);
            var defResult = await _connectionManager.ExecuteQueryAsync(defSql);
            if (defResult.Rows.Count > 0)
            {
                DefinitionTextBox.Text = defResult.Rows[0][0]?.ToString() ?? "No definition found";
            }

            // Load columns - use required statement
            var colSqlTemplate = _metadataHandler.GetRequiredStatement("GetViewColumns_Display");
            var colSql = ReplacePlaceholders(colSqlTemplate, _schema, _viewName);
            var colResult = await _connectionManager.ExecuteQueryAsync(colSql);
            ColumnsGrid.ItemsSource = colResult.DefaultView;

            // Load dependencies - use required statement
            var depSqlTemplate = _metadataHandler.GetRequiredStatement("GetViewDependencies");
            var depSql = ReplacePlaceholders(depSqlTemplate, _schema, _viewName);
            var depResult = await _connectionManager.ExecuteQueryAsync(depSql);
            foreach (System.Data.DataRow row in depResult.Rows)
            {
                DependenciesListBox.Items.Add(row["DEPENDENCY"]?.ToString());
            }

            Logger.Info("View details loaded: {Schema}.{View}", _schema, _viewName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading view details");
            MessageBox.Show($"Error loading view details: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
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

    private void ExportContext_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("AI Export functionality requires AI provider configuration", "Export Context", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void RefreshAnalysis_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("AI Analysis requires AI provider configuration (Ollama/OpenAI/Claude)", "Refresh Analysis", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
    
    private void DockAsTab_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Docking ViewDetailsDialog as tab: {Schema}.{View}", _schema, _viewName);
        
        try
        {
            if (System.Windows.Application.Current.MainWindow is MainWindow mainWindow)
            {
                mainWindow.CreateTabWithViewDetails(_connectionManager, _schema, _viewName);
                Close();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to dock as tab");
            MessageBox.Show($"Failed to dock as tab: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}

