using System.Windows;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

/// <summary>
/// Dialog for AI SQL modification: user enters instruction in English, LLM returns modified SQL;
/// user sees old (red) vs new (green) and can Accept or Reject.
/// </summary>
public partial class SqlEditWithAiDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _originalSelectedSql;
    private readonly IConnectionManager? _connectionManager;
    private readonly SqlEditAiService _sqlEditAiService;
    private string? _newSqlFromLlm;

    /// <summary>
    /// After dialog closes with Accept, caller should read this and replace selection in editor.
    /// </summary>
    public string? ResultNewSql { get; private set; }

    public SqlEditWithAiDialog(string selectedSql, IConnectionManager? connectionManager)
    {
        InitializeComponent();
        _originalSelectedSql = selectedSql ?? string.Empty;
        _connectionManager = connectionManager;
        _sqlEditAiService = new SqlEditAiService(App.MetadataHandler!);

        if (_connectionManager == null)
        {
            InstructionBox.IsEnabled = false;
            EditSelectionButton.IsEnabled = false;
            StatusText.Visibility = Visibility.Visible;
            StatusText.Text = "Connect to a database to use AI SQL edit.";
            Logger.Debug("SqlEditWithAiDialog opened without connection - Edit disabled");
        }
    }

    private async void EditSelection_Click(object sender, RoutedEventArgs e)
    {
        if (_connectionManager == null) return;

        var instruction = InstructionBox.Text?.Trim() ?? "";
        if (string.IsNullOrEmpty(instruction))
        {
            StatusText.Visibility = Visibility.Visible;
            StatusText.Text = "Enter an instruction (e.g. Make sql return the 5 largest tablespaces in GB).";
            return;
        }

        EditSelectionButton.IsEnabled = false;
        StatusText.Visibility = Visibility.Visible;
        StatusText.Text = "Calling Ollama...";

        try
        {
            var model = App.PreferencesService?.Preferences.SqlEditModel;
            var newSql = await _sqlEditAiService.ModifySqlAsync(
                _originalSelectedSql,
                instruction,
                _connectionManager,
                modelOverride: model);

            _newSqlFromLlm = newSql;
            OldSqlBox.Text = _originalSelectedSql;
            NewSqlBox.Text = newSql;
            ResultPanel.Visibility = Visibility.Visible;
            StatusText.Text = "";
            StatusText.Visibility = Visibility.Collapsed;
            RejectButton.Focus();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "SqlEditWithAiDialog Edit failed");
            StatusText.Text = "Error: " + ex.Message;
            _newSqlFromLlm = null;
        }
        finally
        {
            EditSelectionButton.IsEnabled = true;
        }
    }

    private void Reject_Click(object sender, RoutedEventArgs e)
    {
        ResultNewSql = null;
        DialogResult = false;
        Close();
    }

    private void Accept_Click(object sender, RoutedEventArgs e)
    {
        ResultNewSql = _newSqlFromLlm;
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        ResultNewSql = null;
        DialogResult = false;
        Close();
    }
}
