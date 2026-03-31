using System.Data;
using System.IO;
using System.Security;
using System.Text;
using System.Xml;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for exporting query results to various formats
/// </summary>
public class ExportService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// Export DataTable to CSV file
    /// </summary>
    public async Task ExportToCsvAsync(DataTable dataTable, string filePath)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to CSV: {filePath}");

        try
        {
            var csv = new StringBuilder();

            // Write header
            var columnNames = dataTable.Columns.Cast<DataColumn>()
                .Select(column => EscapeCsvField(column.ColumnName));
            csv.AppendLine(string.Join(",", columnNames));

            // Write rows
            foreach (DataRow row in dataTable.Rows)
            {
                var fields = row.ItemArray.Select(field => 
                {
                    var value = field?.ToString() ?? string.Empty;
                    return EscapeCsvField(value.Trim()); // Trim all string fields
                });
                csv.AppendLine(string.Join(",", fields));
            }

            await File.WriteAllTextAsync(filePath, csv.ToString(), Encoding.UTF8);

            Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to CSV");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to CSV");
            throw new Exception($"Failed to export to CSV: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to TSV (Tab-Separated Values) file
    /// </summary>
    public async Task ExportToTsvAsync(DataTable dataTable, string filePath)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to TSV: {filePath}");

        try
        {
            var tsv = new StringBuilder();

            // Write header
            var columnNames = dataTable.Columns.Cast<DataColumn>()
                .Select(column => column.ColumnName);
            tsv.AppendLine(string.Join("\t", columnNames));

            // Write rows
            foreach (DataRow row in dataTable.Rows)
            {
                var fields = row.ItemArray.Select(field => 
                {
                    var value = field?.ToString() ?? string.Empty;
                    return value.Trim(); // Trim all string fields
                });
                tsv.AppendLine(string.Join("\t", fields));
            }

            await File.WriteAllTextAsync(filePath, tsv.ToString(), Encoding.UTF8);

            Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to TSV");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to TSV");
            throw new Exception($"Failed to export to TSV: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to JSON file
    /// </summary>
    public async Task ExportToJsonAsync(DataTable dataTable, string filePath)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to JSON: {filePath}");

        try
        {
            var list = new List<Dictionary<string, object?>>();

            foreach (DataRow row in dataTable.Rows)
            {
                var dict = new Dictionary<string, object?>();
                foreach (DataColumn column in dataTable.Columns)
                {
                    var value = row[column];
                    // Trim string values
                    if (value is string strValue)
                    {
                        dict[column.ColumnName] = strValue.Trim();
                    }
                    else
                    {
                        dict[column.ColumnName] = value;
                    }
                }
                list.Add(dict);
            }

            var json = System.Text.Json.JsonSerializer.Serialize(list, new System.Text.Json.JsonSerializerOptions
            {
                WriteIndented = true
            });

            await File.WriteAllTextAsync(filePath, json, Encoding.UTF8);

            Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to JSON");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to JSON");
            throw new Exception($"Failed to export to JSON: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to SQL INSERT statements
    /// </summary>
    public async Task ExportToSqlAsync(DataTable dataTable, string tableName, string filePath)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to SQL: {filePath}");

        try
        {
            var sql = new StringBuilder();

            foreach (DataRow row in dataTable.Rows)
            {
                var columnNames = string.Join(", ", 
                    dataTable.Columns.Cast<DataColumn>().Select(c => c.ColumnName));

                var values = string.Join(", ", 
                    row.ItemArray.Select(v => FormatSqlValue(v)));

                sql.AppendLine($"INSERT INTO {tableName} ({columnNames}) VALUES ({values});");
            }

            await File.WriteAllTextAsync(filePath, sql.ToString(), Encoding.UTF8);

            Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to SQL");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to SQL");
            throw new Exception($"Failed to export to SQL: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export only column headers as CSV string (no data rows)
    /// </summary>
    /// <param name="dataTable">DataTable to get headers from</param>
    /// <returns>Comma-separated column headers</returns>
    public string ExportHeadersOnlyCsv(DataTable dataTable)
    {
        Logger.Info("Exporting headers only as CSV");
        Logger.Debug("Column count: {Count}", dataTable.Columns.Count);

        var columnNames = dataTable.Columns.Cast<DataColumn>()
            .Select(column => EscapeCsvField(column.ColumnName));
        
        var result = string.Join(",", columnNames);
        Logger.Info("Headers only CSV export complete: {Length} characters", result.Length);
        return result;
    }

    /// <summary>
    /// Export only column headers as TSV string (no data rows)
    /// </summary>
    /// <param name="dataTable">DataTable to get headers from</param>
    /// <returns>Tab-separated column headers</returns>
    public string ExportHeadersOnlyTsv(DataTable dataTable)
    {
        Logger.Info("Exporting headers only as TSV");
        Logger.Debug("Column count: {Count}", dataTable.Columns.Count);

        var columnNames = dataTable.Columns.Cast<DataColumn>()
            .Select(column => column.ColumnName);
        
        var result = string.Join("\t", columnNames);
        Logger.Info("Headers only TSV export complete: {Length} characters", result.Length);
        return result;
    }

    /// <summary>
    /// Escape CSV field (handle commas, quotes, newlines)
    /// </summary>
    private string EscapeCsvField(string field)
    {
        if (field.Contains(',') || field.Contains('"') || field.Contains('\n') || field.Contains('\r'))
        {
            return $"\"{field.Replace("\"", "\"\"")}\"";
        }
        return field;
    }

    /// <summary>
    /// Format value for SQL INSERT statement
    /// </summary>
    private string FormatSqlValue(object? value)
    {
        if (value == null || value == DBNull.Value)
        {
            return "NULL";
        }

        if (value is string strValue)
        {
            return $"'{strValue.Trim().Replace("'", "''")}'"; // Trim string values
        }
        
        if (value is DateTime)
        {
            return $"'{value.ToString()?.Replace("'", "''")}'";
        }

        return value.ToString() ?? "NULL";
    }

    /// <summary>
    /// Export DataTable to CSV string (for clipboard)
    /// </summary>
    /// <param name="dataTable">DataTable to export</param>
    /// <param name="includeHeaders">Whether to include column headers as first row</param>
    /// <param name="progress">Progress reporter</param>
    public async Task<string> ExportToCsvStringAsync(DataTable dataTable, bool includeHeaders = true, IProgress<int>? progress = null)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to CSV string (includeHeaders: {includeHeaders})");
        Logger.Debug("Starting CSV string export with progress reporting");

        try
        {
            return await Task.Run(() =>
            {
                var csv = new StringBuilder();
                var totalRows = dataTable.Rows.Count;

                // Write header if requested
                if (includeHeaders)
                {
                    var columnNames = dataTable.Columns.Cast<DataColumn>()
                        .Select(column => EscapeCsvField(column.ColumnName));
                    csv.AppendLine(string.Join(",", columnNames));
                    Logger.Debug("CSV headers included");
                }
                else
                {
                    Logger.Debug("CSV headers excluded");
                }

                // Write rows with progress
                int processedRows = 0;
                foreach (DataRow row in dataTable.Rows)
                {
                    var fields = row.ItemArray.Select(field =>
                        EscapeCsvField(field?.ToString() ?? string.Empty));
                    csv.AppendLine(string.Join(",", fields));

                    processedRows++;
                    if (progress != null && processedRows % 100 == 0)
                    {
                        var percent = (int)((processedRows / (double)totalRows) * 100);
                        progress.Report(percent);
                    }
                }

                progress?.Report(100);
                Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to CSV string");
                return csv.ToString();
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to CSV string");
            throw new Exception($"Failed to export to CSV: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to TSV string (for clipboard)
    /// </summary>
    /// <param name="dataTable">DataTable to export</param>
    /// <param name="includeHeaders">Whether to include column headers as first row</param>
    /// <param name="progress">Progress reporter</param>
    public async Task<string> ExportToTsvStringAsync(DataTable dataTable, bool includeHeaders = true, IProgress<int>? progress = null)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to TSV string (includeHeaders: {includeHeaders})");
        Logger.Debug("Starting TSV string export with progress reporting");

        try
        {
            return await Task.Run(() =>
            {
                var tsv = new StringBuilder();
                var totalRows = dataTable.Rows.Count;

                // Write header if requested
                if (includeHeaders)
                {
                    var columnNames = dataTable.Columns.Cast<DataColumn>()
                        .Select(column => column.ColumnName);
                    tsv.AppendLine(string.Join("\t", columnNames));
                    Logger.Debug("TSV headers included");
                }
                else
                {
                    Logger.Debug("TSV headers excluded");
                }

                // Write rows with progress
                int processedRows = 0;
                foreach (DataRow row in dataTable.Rows)
                {
                    var fields = row.ItemArray.Select(field => field?.ToString() ?? string.Empty);
                    tsv.AppendLine(string.Join("\t", fields));

                    processedRows++;
                    if (progress != null && processedRows % 100 == 0)
                    {
                        var percent = (int)((processedRows / (double)totalRows) * 100);
                        progress.Report(percent);
                    }
                }

                progress?.Report(100);
                Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to TSV string");
                return tsv.ToString();
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to TSV string");
            throw new Exception($"Failed to export to TSV: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to JSON string (for clipboard)
    /// </summary>
    public async Task<string> ExportToJsonStringAsync(DataTable dataTable, IProgress<int>? progress = null)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to JSON string");
        Logger.Debug("Starting JSON string export with progress reporting");

        try
        {
            return await Task.Run(() =>
            {
                var list = new List<Dictionary<string, object?>>();
                var totalRows = dataTable.Rows.Count;
                int processedRows = 0;

                foreach (DataRow row in dataTable.Rows)
                {
                    var dict = new Dictionary<string, object?>();
                    foreach (DataColumn column in dataTable.Columns)
                    {
                        var value = row[column];
                        dict[column.ColumnName] = value == DBNull.Value ? null : value;
                    }
                    list.Add(dict);

                    processedRows++;
                    if (progress != null && processedRows % 100 == 0)
                    {
                        var percent = (int)((processedRows / (double)totalRows) * 100);
                        progress.Report(percent);
                    }
                }

                progress?.Report(100);

                var json = System.Text.Json.JsonSerializer.Serialize(list, new System.Text.Json.JsonSerializerOptions
                {
                    WriteIndented = true
                });

                Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to JSON string");
                return json;
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to JSON string");
            throw new Exception($"Failed to export to JSON: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to XML string (for clipboard)
    /// </summary>
    public async Task<string> ExportToXmlStringAsync(DataTable dataTable, IProgress<int>? progress = null)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to XML string");
        Logger.Debug("Starting XML string export with progress reporting");

        try
        {
            return await Task.Run(() =>
            {
                var xml = new StringBuilder();
                var totalRows = dataTable.Rows.Count;
                int processedRows = 0;

                xml.AppendLine("<?xml version=\"1.0\" encoding=\"utf-8\"?>");
                xml.AppendLine("<ResultSet>");

                foreach (DataRow row in dataTable.Rows)
                {
                    xml.AppendLine("  <Row>");

                    foreach (DataColumn column in dataTable.Columns)
                    {
                        var value = row[column];
                        var xmlValue = value == DBNull.Value ? "" : SecurityElement.Escape(value.ToString() ?? "");
                        xml.AppendLine($"    <{SanitizeXmlElementName(column.ColumnName)}>{xmlValue}</{SanitizeXmlElementName(column.ColumnName)}>");
                    }

                    xml.AppendLine("  </Row>");

                    processedRows++;
                    if (progress != null && processedRows % 100 == 0)
                    {
                        var percent = (int)((processedRows / (double)totalRows) * 100);
                        progress.Report(percent);
                    }
                }

                xml.AppendLine("</ResultSet>");

                progress?.Report(100);
                Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to XML string");
                return xml.ToString();
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to XML string");
            throw new Exception($"Failed to export to XML: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Export DataTable to XML file
    /// </summary>
    public async Task ExportToXmlAsync(DataTable dataTable, string filePath)
    {
        Logger.Info($"Exporting {dataTable.Rows.Count} rows to XML: {filePath}");

        try
        {
            var xmlString = await ExportToXmlStringAsync(dataTable);
            await File.WriteAllTextAsync(filePath, xmlString, Encoding.UTF8);

            Logger.Info($"Successfully exported {dataTable.Rows.Count} rows to XML file");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export to XML file");
            throw new Exception($"Failed to export to XML: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Sanitize column names for use as XML element names
    /// </summary>
    private string SanitizeXmlElementName(string name)
    {
        // Replace invalid XML element name characters
        var sanitized = name.Replace(" ", "_")
            .Replace(".", "_")
            .Replace("-", "_")
            .Replace("(", "")
            .Replace(")", "")
            .Replace("[", "")
            .Replace("]", "");

        // Ensure it doesn't start with a number
        if (char.IsDigit(sanitized[0]))
        {
            sanitized = "_" + sanitized;
        }

        return sanitized;
    }
}

