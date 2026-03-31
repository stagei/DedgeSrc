using NLog;
using System.Windows;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class DeepAnalysisDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly List<string> _targetObjects;

    public DeepAnalysisDialog(IConnectionManager connectionManager, List<string> targetObjects)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _targetObjects = targetObjects;

        TargetInfoText.Text = $"Analyzing: {string.Join(", ", targetObjects)}";

        Loaded += async (s, e) => 
        {
            // Apply all UI styles from the unified style service
            UIStyleService.ApplyStyles(this);
            await LoadAnalysisAsync();
        };
    }

    private async Task LoadAnalysisAsync()
    {
        try
        {
            Logger.Info("Loading deep analysis for objects: {Objects}", string.Join(", ", _targetObjects));

            // Placeholder implementation - would use DeepAnalysisService
            CommentsTextBox.Text = "Comments would be extracted from SYSCAT.REMARKS here.";
            
            // Sample profiling data (placeholder)
            var sampleProfiling = new List<dynamic>
            {
                new { Column = "ID", DistinctCount = 0, NullCount = 0, DataType = "INTEGER" },
                new { Column = "NAME", DistinctCount = 0, NullCount = 0, DataType = "VARCHAR" }
            };
            ProfilingGrid.ItemsSource = sampleProfiling;

            RelationshipsListBox.Items.Add("Relationships would be extracted from SYSCAT.REFERENCES here");

            Logger.Debug("Deep analysis loaded (placeholder implementation)");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading deep analysis");
            MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ExportMarkdown_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("Export to Markdown requires AiExportService configuration", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void OpenInCursor_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("Open in Cursor requires ExternalEditorService configuration", "Open in Editor", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

