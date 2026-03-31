using System.Data;
using System.Windows;
using NLog;

namespace DbExplorer.Dialogs;

public partial class CopySelectionDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly DataTable _selectionData;
    private readonly List<string> _columnHeaders;

    public CopySelectionDialog(DataTable selectionData, List<string> columnHeaders)
    {
        InitializeComponent();
        Logger.Debug("CopySelectionDialog initialized with {RowCount} rows and {ColumnCount} columns", 
            selectionData.Rows.Count, columnHeaders.Count);

        _selectionData = selectionData;
        _columnHeaders = columnHeaders;

        SelectionInfo.Text = $"Selection: {selectionData.Rows.Count} row(s) × {columnHeaders.Count} column(s)";
        
        UpdatePreview();
    }

    private void FormatRadio_Changed(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Format changed");
        UpdatePreview();
    }

    private void UpdatePreview()
    {
        if (PreviewTextBox == null || _selectionData == null)
            return;

        try
        {
            bool includeHeaders = IncludeHeadersCheckBox?.IsChecked == true;
            bool isCsv = CsvRadio?.IsChecked == true;
            string delimiter = isCsv ? "," : "\t";

            var preview = new System.Text.StringBuilder();
            int previewRows = Math.Min(5, _selectionData.Rows.Count);

            // Add headers if requested
            if (includeHeaders)
            {
                if (isCsv)
                {
                    var escapedHeaders = _columnHeaders.Select(h => EscapeCsvField(h));
                    preview.AppendLine(string.Join(delimiter, escapedHeaders));
                }
                else
                {
                    preview.AppendLine(string.Join(delimiter, _columnHeaders));
                }
            }

            // Add data rows (preview only first 5)
            for (int i = 0; i < previewRows; i++)
            {
                var row = _selectionData.Rows[i];
                var values = row.ItemArray.Select(v => v?.ToString() ?? string.Empty);
                
                if (isCsv)
                {
                    values = values.Select(v => EscapeCsvField(v));
                }
                
                preview.AppendLine(string.Join(delimiter, values));
            }

            if (_selectionData.Rows.Count > previewRows)
            {
                preview.AppendLine($"... ({_selectionData.Rows.Count - previewRows} more rows)");
            }

            PreviewTextBox.Text = preview.ToString();
            Logger.Debug("Preview updated ({Length} characters)", preview.Length);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to update preview");
            PreviewTextBox.Text = "Error generating preview";
        }
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Copying selection to clipboard");

        try
        {
            bool includeHeaders = IncludeHeadersCheckBox.IsChecked == true;
            bool isCsv = CsvRadio.IsChecked == true;
            string delimiter = isCsv ? "," : "\t";

            var result = new System.Text.StringBuilder();

            // Add headers if requested
            if (includeHeaders)
            {
                if (isCsv)
                {
                    var escapedHeaders = _columnHeaders.Select(h => EscapeCsvField(h));
                    result.AppendLine(string.Join(delimiter, escapedHeaders));
                }
                else
                {
                    result.AppendLine(string.Join(delimiter, _columnHeaders));
                }
            }

            // Add all data rows
            foreach (DataRow row in _selectionData.Rows)
            {
                var values = row.ItemArray.Select(v => v?.ToString() ?? string.Empty);
                
                if (isCsv)
                {
                    values = values.Select(v => EscapeCsvField(v));
                }
                
                result.AppendLine(string.Join(delimiter, values));
            }

            Clipboard.SetText(result.ToString());
            
            Logger.Info("Successfully copied {RowCount} rows × {ColumnCount} columns to clipboard", 
                _selectionData.Rows.Count, _columnHeaders.Count);

            MessageBox.Show(
                $"Successfully copied selection to clipboard!\n\n" +
                $"Rows: {_selectionData.Rows.Count:N0}\n" +
                $"Columns: {_columnHeaders.Count}\n" +
                $"Format: {(isCsv ? "CSV" : "TSV")}\n" +
                $"Headers included: {(includeHeaders ? "Yes" : "No")}",
                "Copy Successful",
                MessageBoxButton.OK,
                MessageBoxImage.Information);

            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy selection");
            MessageBox.Show($"Failed to copy selection:\n\n{ex.Message}", "Copy Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Copy selection cancelled by user");
        DialogResult = false;
        Close();
    }

    private string EscapeCsvField(string field)
    {
        if (field.Contains(',') || field.Contains('"') || field.Contains('\n') || field.Contains('\r'))
        {
            return $"\"{field.Replace("\"", "\"\"")}\"";
        }
        return field;
    }
}

