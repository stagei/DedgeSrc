using NLog;
using System.Windows;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ProcedureDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;
    private readonly string _schema;
    private readonly string _procedureName;

    public ProcedureDetailsDialog(IConnectionManager connectionManager, string schema, string procedureName)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _metadataHandler = App.MetadataHandler;
        _schema = schema?.Trim() ?? "";
        _procedureName = procedureName?.Trim() ?? "";

        ProcedureNameText.Text = _procedureName;
        ProcedureInfoText.Text = $"{_schema}.{_procedureName}";

        Loaded += async (s, e) => 
        {
            // Apply all UI styles from the unified style service
            UIStyleService.ApplyStyles(this);
            await LoadProcedureDetailsAsync();
        };
    }

    private async Task LoadProcedureDetailsAsync()
    {
        try
        {
            if (_metadataHandler == null)
            {
                throw new InvalidOperationException("MetadataHandler not initialized");
            }
            
            // Load source code - use required statement (SYSCAT.ROUTINES)
            var sourceSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineSource");
            var sourceSql = ReplacePlaceholders(sourceSqlTemplate, _schema, _procedureName, "P");
            var sourceResult = await _connectionManager.ExecuteQueryAsync(sourceSql);
            if (sourceResult.Rows.Count > 0)
            {
                SourceCodeTextBox.Text = sourceResult.Rows[0][0]?.ToString() ?? "Source code not available";
            }

            // Load parameters - use required statement (SYSCAT.ROUTINEPARMS)
            var paramSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineParameters_Display");
            var paramSql = ReplacePlaceholders(paramSqlTemplate, _schema, _procedureName);
            var paramResult = await _connectionManager.ExecuteQueryAsync(paramSql);
            ParametersGrid.ItemsSource = paramResult.DefaultView;

            Logger.Info("Procedure details loaded: {Schema}.{Procedure}", _schema, _procedureName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading procedure details");
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
        Logger.Info("Docking ProcedureDetailsDialog as tab: {Schema}.{Procedure}", _schema, _procedureName);
        
        try
        {
            if (System.Windows.Application.Current.MainWindow is MainWindow mainWindow)
            {
                mainWindow.CreateTabWithRoutineDetails(_connectionManager, _schema, _procedureName, "P");
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

