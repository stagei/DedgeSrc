using NLog;
using System.Windows;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class FunctionDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;
    private readonly string _schema;
    private readonly string _functionName;

    public FunctionDetailsDialog(IConnectionManager connectionManager, string schema, string functionName)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _metadataHandler = App.MetadataHandler;
        _schema = schema?.Trim() ?? "";
        _functionName = functionName?.Trim() ?? "";

        FunctionNameText.Text = _functionName;
        FunctionInfoText.Text = $"{_schema}.{_functionName}";

        Loaded += async (s, e) => 
        {
            // Apply all UI styles from the unified style service
            UIStyleService.ApplyStyles(this);
            await LoadFunctionDetailsAsync();
        };
    }

    private async Task LoadFunctionDetailsAsync()
    {
        try
        {
            if (_metadataHandler == null)
            {
                throw new InvalidOperationException("MetadataHandler not initialized");
            }
            
            // Load source code - use required statement (SYSCAT.ROUTINES)
            var sourceSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineSource");
            var sourceSql = ReplacePlaceholders(sourceSqlTemplate, _schema, _functionName, "F");
            var sourceResult = await _connectionManager.ExecuteQueryAsync(sourceSql);
            if (sourceResult.Rows.Count > 0)
            {
                SourceCodeTextBox.Text = sourceResult.Rows[0][0]?.ToString() ?? "Source code not available";
            }

            // Load parameters - use required statement (SYSCAT.ROUTINEPARMS)
            var paramSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineParameters_Display");
            var paramSql = ReplacePlaceholders(paramSqlTemplate, _schema, _functionName);
            var paramResult = await _connectionManager.ExecuteQueryAsync(paramSql);
            ParametersGrid.ItemsSource = paramResult.DefaultView;

            Logger.Info("Function details loaded: {Schema}.{Function}", _schema, _functionName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading function details");
            MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
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
        MessageBox.Show("AI Export requires configuration", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void AnalyzeCode_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("AI Code Analysis requires provider configuration", "Analyze", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
    
    private void DockAsTab_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Docking FunctionDetailsDialog as tab: {Schema}.{Function}", _schema, _functionName);
        
        try
        {
            if (System.Windows.Application.Current.MainWindow is MainWindow mainWindow)
            {
                mainWindow.CreateTabWithRoutineDetails(_connectionManager, _schema, _functionName, "F");
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

