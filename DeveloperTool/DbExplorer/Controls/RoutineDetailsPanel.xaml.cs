using System;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Controls;

/// <summary>
/// UserControl for displaying procedure/function details - can be embedded in dialogs or tabs
/// </summary>
public partial class RoutineDetailsPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;
    private readonly string _schema;
    private readonly string _routineName;
    private readonly string _routineType; // "P" for procedure, "F" for function

    public RoutineDetailsPanel(IConnectionManager connectionManager, string schema, string routineName, string routineType = "P")
    {
        InitializeComponent();
        _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));
        _metadataHandler = App.MetadataHandler;
        _schema = schema?.Trim() ?? "";
        _routineName = routineName?.Trim() ?? "";
        _routineType = routineType;

        var typeLabel = routineType == "F" ? "Function" : "Procedure";
        RoutineNameText.Text = $"{typeLabel}: {_routineName}";
        RoutineInfoText.Text = $"Schema: {_schema} • Full Name: {_schema}.{_routineName}";

        this.Loaded += async (s, e) =>
        {
            UIStyleService.ApplyStyles(this);
            await LoadRoutineDetailsAsync();
        };
    }

    private async Task LoadRoutineDetailsAsync()
    {
        try
        {
            if (_metadataHandler == null)
            {
                throw new InvalidOperationException("MetadataHandler not initialized");
            }
            
            // Load source code - use required statement from JSON config
            var srcSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineSource");
            var srcSql = ReplacePlaceholders(srcSqlTemplate, _schema, _routineName, _routineType);
            var srcResult = await _connectionManager.ExecuteQueryAsync(srcSql);
            if (srcResult.Rows.Count > 0)
            {
                Dispatcher.Invoke(() =>
                {
                    SourceCodeTextBox.Text = srcResult.Rows[0][0]?.ToString() ?? "Source code not available";
                });
            }
            else
            {
                Dispatcher.Invoke(() => SourceCodeTextBox.Text = "-- Source code not available for this routine");
            }

            // Load parameters - use required statement from JSON config
            var paramSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineParameters_Display");
            var paramSql = ReplacePlaceholders(paramSqlTemplate, _schema, _routineName);
            var paramResult = await _connectionManager.ExecuteQueryAsync(paramSql);
            Dispatcher.Invoke(() => ParametersGrid.ItemsSource = paramResult.DefaultView);

            // Load properties - use required statement from JSON config
            var propSqlTemplate = _metadataHandler.GetRequiredStatement("GetRoutineProperties");
            var propSql = ReplacePlaceholders(propSqlTemplate, _schema, _routineName, _routineType);
            var propResult = await _connectionManager.ExecuteQueryAsync(propSql);
            if (propResult.Rows.Count > 0)
            {
                var row = propResult.Rows[0];
                Dispatcher.Invoke(() =>
                {
                    LanguageText.Text = row["LANGUAGE"]?.ToString()?.Trim() ?? "-";
                    ParamCountText.Text = row["PARM_COUNT"]?.ToString() ?? "-";
                    OwnerText.Text = row["OWNER"]?.ToString()?.Trim() ?? "-";
                    CreatedText.Text = row["CREATE_TIME"] != DBNull.Value ? Convert.ToDateTime(row["CREATE_TIME"]).ToString("yyyy-MM-dd HH:mm:ss") : "-";
                    ValidText.Text = row["VALID"]?.ToString() == "Y" ? "Yes" : "No";
                    RemarksText.Text = row["REMARKS"]?.ToString()?.Trim() ?? "-";
                });
            }

            Logger.Info("Routine details loaded: {Schema}.{Routine}", _schema, _routineName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading routine details");
            MessageBox.Show($"Error loading routine details: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
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

    private void CopySource_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(SourceCodeTextBox.Text);
            MessageBox.Show("Source code copied to clipboard!", "Success", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy to clipboard");
            MessageBox.Show($"Failed to copy: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
