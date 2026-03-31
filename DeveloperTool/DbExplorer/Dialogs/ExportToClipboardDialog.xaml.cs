using System.Data;
using System.Windows;
using NLog;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ExportToClipboardDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DataTable _dataTable;
    private readonly ExportService _exportService;

    public ExportToClipboardDialog(DataTable dataTable)
    {
        InitializeComponent();
        Logger.Debug("ExportToClipboardDialog initialized with {RowCount} rows", dataTable.Rows.Count);

        _dataTable = dataTable;
        _exportService = new ExportService();

        RowCountInfo.Text = $"Ready to export {dataTable.Rows.Count:N0} rows to clipboard";
        
        // Enable headers checkbox only for CSV/TSV (default is CSV, so enabled by default)
        UpdateHeadersCheckBoxState();
    }

    private void FormatRadio_Changed(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Export format changed");
        UpdateHeadersCheckBoxState();
    }

    private void HeadersOnly_Changed(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Headers only checkbox changed");
        
        // If headers only is checked, disable the "Include Headers" checkbox
        if (HeadersOnlyCheckBox != null && IncludeHeadersCheckBox != null)
        {
            if (HeadersOnlyCheckBox.IsChecked == true)
            {
                IncludeHeadersCheckBox.IsEnabled = false;
                IncludeHeadersCheckBox.IsChecked = true; // Force to true when headers only
                Logger.Debug("Headers only mode enabled - Include Headers checkbox disabled");
            }
            else
            {
                UpdateHeadersCheckBoxState();
                Logger.Debug("Headers only mode disabled - Include Headers checkbox enabled");
            }
        }
    }

    private void UpdateHeadersCheckBoxState()
    {
        // Headers option only applies to CSV and TSV formats
        bool isCsvOrTsv = CsvRadio?.IsChecked == true || TsvRadio?.IsChecked == true;
        
        if (HeadersOnlyCheckBox != null)
        {
            HeadersOnlyCheckBox.IsEnabled = isCsvOrTsv;
            Logger.Debug("Headers only checkbox enabled: {Enabled} (CSV/TSV: {IsCsvOrTsv})", 
                HeadersOnlyCheckBox.IsEnabled, isCsvOrTsv);
        }
        
        if (IncludeHeadersCheckBox != null)
        {
            // Disable if headers only is checked or if not CSV/TSV
            bool headersOnly = HeadersOnlyCheckBox?.IsChecked == true;
            IncludeHeadersCheckBox.IsEnabled = isCsvOrTsv && !headersOnly;
            Logger.Debug("Include headers checkbox enabled: {Enabled} (CSV/TSV: {IsCsvOrTsv}, HeadersOnly: {HeadersOnly})", 
                IncludeHeadersCheckBox.IsEnabled, isCsvOrTsv, headersOnly);
        }
    }

    private async void Copy_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Starting clipboard export");

        try
        {
            // Disable buttons during export
            CopyButton.IsEnabled = false;
            CancelButton.IsEnabled = false;
            ProgressPanel.Visibility = Visibility.Visible;

            // Determine selected format
            string format;
            if (CsvRadio.IsChecked == true)
            {
                format = "CSV";
                Logger.Debug("Export format: CSV");
            }
            else if (TsvRadio.IsChecked == true)
            {
                format = "TSV";
                Logger.Debug("Export format: TSV");
            }
            else if (JsonRadio.IsChecked == true)
            {
                format = "JSON";
                Logger.Debug("Export format: JSON");
            }
            else if (XmlRadio.IsChecked == true)
            {
                format = "XML";
                Logger.Debug("Export format: XML");
            }
            else
            {
                format = "CSV"; // Default
                Logger.Debug("Export format: CSV (default)");
            }

            // Create progress reporter
            var progress = new Progress<int>(percent =>
            {
                ProgressBar.Value = percent;
                ProgressPercentage.Text = $"{percent}%";
                ProgressText.Text = $"Processing {percent}%...";
            });

            // Get header options
            bool headersOnly = HeadersOnlyCheckBox.IsChecked == true;
            bool includeHeaders = IncludeHeadersCheckBox.IsChecked == true;
            Logger.Debug("Headers only: {HeadersOnly}, Include headers: {IncludeHeaders}", headersOnly, includeHeaders);

            // Export to clipboard
            string result;
            switch (format)
            {
                case "CSV":
                    if (headersOnly)
                    {
                        result = _exportService.ExportHeadersOnlyCsv(_dataTable);
                    }
                    else
                    {
                        result = await _exportService.ExportToCsvStringAsync(_dataTable, includeHeaders, progress);
                    }
                    break;
                case "TSV":
                    if (headersOnly)
                    {
                        result = _exportService.ExportHeadersOnlyTsv(_dataTable);
                    }
                    else
                    {
                        result = await _exportService.ExportToTsvStringAsync(_dataTable, includeHeaders, progress);
                    }
                    break;
                case "JSON":
                    result = await _exportService.ExportToJsonStringAsync(_dataTable, progress);
                    break;
                case "XML":
                    result = await _exportService.ExportToXmlStringAsync(_dataTable, progress);
                    break;
                default:
                    if (headersOnly)
                    {
                        result = _exportService.ExportHeadersOnlyCsv(_dataTable);
                    }
                    else
                    {
                        result = await _exportService.ExportToCsvStringAsync(_dataTable, includeHeaders, progress);
                    }
                    break;
            }

            // Copy to clipboard
            Logger.Debug("Copying result to clipboard ({Length} characters)", result.Length);
            Clipboard.SetText(result);

            Logger.Info("Successfully exported {RowCount} rows to clipboard as {Format}", 
                _dataTable.Rows.Count, format);

            MessageBox.Show(
                $"Successfully copied {_dataTable.Rows.Count:N0} rows to clipboard as {format}!\n\n" +
                $"Size: {result.Length:N0} characters",
                "Copy Successful",
                MessageBoxButton.OK,
                MessageBoxImage.Information);

            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to clipboard");

            MessageBox.Show(
                $"Failed to copy to clipboard:\n\n{ex.Message}",
                "Copy Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);

            // Re-enable buttons on error
            CopyButton.IsEnabled = true;
            CancelButton.IsEnabled = true;
            ProgressPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Export to clipboard cancelled by user");
        DialogResult = false;
        Close();
    }
}









