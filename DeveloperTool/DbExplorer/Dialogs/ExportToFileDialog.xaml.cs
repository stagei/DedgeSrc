using System.Data;
using System.IO;
using System.Windows;
using Microsoft.Win32;
using NLog;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ExportToFileDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DataTable _dataTable;
    private readonly ExportService _exportService;
    private string? _selectedFilePath;

    public ExportToFileDialog(DataTable dataTable)
    {
        InitializeComponent();
        Logger.Debug("ExportToFileDialog initialized with {RowCount} rows", dataTable.Rows.Count);

        _dataTable = dataTable;
        _exportService = new ExportService();

        RowCountInfo.Text = $"Ready to export {dataTable.Rows.Count:N0} rows to file";
        
        // Enable headers checkbox only for CSV/TSV (default is CSV, so enabled by default)
        UpdateHeadersCheckBoxState();
    }

    private void FormatRadio_Changed(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Export format changed");
        UpdateHeadersCheckBoxState();
        UpdateFileExtension();
    }

    private void UpdateHeadersCheckBoxState()
    {
        // Headers option only applies to CSV and TSV formats
        bool isCsvOrTsv = CsvRadio?.IsChecked == true || TsvRadio?.IsChecked == true;
        
        if (IncludeHeadersCheckBox != null)
        {
            IncludeHeadersCheckBox.IsEnabled = isCsvOrTsv;
            Logger.Debug("Headers checkbox enabled: {Enabled} (CSV/TSV: {IsCsvOrTsv})", 
                IncludeHeadersCheckBox.IsEnabled, isCsvOrTsv);
        }
    }

    private void UpdateFileExtension()
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
            return;

        var directory = Path.GetDirectoryName(_selectedFilePath);
        var fileNameWithoutExt = Path.GetFileNameWithoutExtension(_selectedFilePath);
        
        string newExtension = GetCurrentFormatExtension();
        _selectedFilePath = Path.Combine(directory ?? "", fileNameWithoutExt + newExtension);
        FilePathTextBox.Text = _selectedFilePath;
        
        Logger.Debug("File extension updated to: {Extension}", newExtension);
    }

    private string GetCurrentFormatExtension()
    {
        if (CsvRadio?.IsChecked == true) return ".csv";
        if (TsvRadio?.IsChecked == true) return ".tsv";
        if (JsonRadio?.IsChecked == true) return ".json";
        if (XmlRadio?.IsChecked == true) return ".xml";
        return ".csv";
    }

    private string GetCurrentFormat()
    {
        if (CsvRadio?.IsChecked == true) return "CSV";
        if (TsvRadio?.IsChecked == true) return "TSV";
        if (JsonRadio?.IsChecked == true) return "JSON";
        if (XmlRadio?.IsChecked == true) return "XML";
        return "CSV";
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Browse button clicked");

        var saveFileDialog = new SaveFileDialog
        {
            Filter = "CSV Files (*.csv)|*.csv|TSV Files (*.tsv)|*.tsv|JSON Files (*.json)|*.json|XML Files (*.xml)|*.xml",
            DefaultExt = GetCurrentFormatExtension(),
            FileName = $"export_{DateTime.Now:yyyyMMdd_HHmmss}"
        };

        // Set filter index based on selected format
        if (CsvRadio?.IsChecked == true) saveFileDialog.FilterIndex = 1;
        else if (TsvRadio?.IsChecked == true) saveFileDialog.FilterIndex = 2;
        else if (JsonRadio?.IsChecked == true) saveFileDialog.FilterIndex = 3;
        else if (XmlRadio?.IsChecked == true) saveFileDialog.FilterIndex = 4;

        if (saveFileDialog.ShowDialog() == true)
        {
            _selectedFilePath = saveFileDialog.FileName;
            FilePathTextBox.Text = _selectedFilePath;
            FilePathTextBox.Foreground = System.Windows.Media.Brushes.White;
            Logger.Info("File path selected: {FilePath}", _selectedFilePath);
        }
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Starting file export");

        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            MessageBox.Show("Please select a file location first.", "No File Selected",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            // Disable buttons during export
            ExportButton.IsEnabled = false;
            CancelButton.IsEnabled = false;
            BrowseButton.IsEnabled = false;
            ProgressPanel.Visibility = Visibility.Visible;

            // Determine selected format
            string format = GetCurrentFormat();
            Logger.Debug("Export format: {Format}", format);

            // Get header option
            bool includeHeaders = IncludeHeadersCheckBox.IsChecked == true;
            Logger.Debug("Include headers: {IncludeHeaders}", includeHeaders);

            // Create progress reporter
            var progress = new Progress<int>(percent =>
            {
                ProgressBar.Value = percent;
                ProgressPercentage.Text = $"{percent}%";
                ProgressText.Text = $"Processing {percent}%...";
            });

            // Export to file
            switch (format)
            {
                case "CSV":
                    var csvString = await _exportService.ExportToCsvStringAsync(_dataTable, includeHeaders, progress);
                    await File.WriteAllTextAsync(_selectedFilePath, csvString);
                    break;
                case "TSV":
                    var tsvString = await _exportService.ExportToTsvStringAsync(_dataTable, includeHeaders, progress);
                    await File.WriteAllTextAsync(_selectedFilePath, tsvString);
                    break;
                case "JSON":
                    var jsonString = await _exportService.ExportToJsonStringAsync(_dataTable, progress);
                    await File.WriteAllTextAsync(_selectedFilePath, jsonString);
                    break;
                case "XML":
                    var xmlString = await _exportService.ExportToXmlStringAsync(_dataTable, progress);
                    await File.WriteAllTextAsync(_selectedFilePath, xmlString);
                    break;
                default:
                    var defaultString = await _exportService.ExportToCsvStringAsync(_dataTable, includeHeaders, progress);
                    await File.WriteAllTextAsync(_selectedFilePath, defaultString);
                    break;
            }

            Logger.Info("Successfully exported {RowCount} rows to file: {FilePath}", 
                _dataTable.Rows.Count, _selectedFilePath);

            MessageBox.Show(
                $"Successfully exported {_dataTable.Rows.Count:N0} rows to:\n\n{_selectedFilePath}",
                "Export Successful",
                MessageBoxButton.OK,
                MessageBoxImage.Information);

            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to file");

            MessageBox.Show(
                $"Failed to export to file:\n\n{ex.Message}",
                "Export Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);

            // Re-enable buttons on error
            ExportButton.IsEnabled = true;
            CancelButton.IsEnabled = true;
            BrowseButton.IsEnabled = true;
            ProgressPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Export to file cancelled by user");
        DialogResult = false;
        Close();
    }
}

