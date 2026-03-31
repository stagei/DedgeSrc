using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Dialogs;

public partial class TablespaceDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly TablespaceInfo _tablespace;
    private readonly IConnectionManager _connectionManager;

    public TablespaceDetailsDialog(TablespaceInfo tablespace, IConnectionManager connectionManager)
    {
        InitializeComponent();
        _tablespace = tablespace ?? throw new ArgumentNullException(nameof(tablespace));
        _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));

        Logger.Debug("TablespaceDetailsDialog opened for: {Tablespace}", _tablespace.TablespaceName);

        Title = $"Tablespace Details - {_tablespace.TablespaceName}";

        TablespaceNameText.Text = _tablespace.TablespaceName;
        TablespaceInfoText.Text = $"Type: {_tablespace.TablespaceType} • Page size: {_tablespace.PageSize?.ToString() ?? "N/A"} • Owner: {_tablespace.Owner}";

        TablespaceNameValue.Text = _tablespace.TablespaceName;
        TablespaceTypeValue.Text = _tablespace.TablespaceType;
        DataTypeValue.Text = _tablespace.DataType;
        PageSizeValue.Text = _tablespace.PageSize?.ToString() ?? "N/A";
        OwnerValue.Text = _tablespace.Owner;
        CreateTimeValue.Text = _tablespace.CreateTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "N/A";
        RemarksValue.Text = string.IsNullOrWhiteSpace(_tablespace.Remarks) ? "No remarks" : _tablespace.Remarks;

        // Apply all UI styles and load data asynchronously
        Loaded += async (s, e) =>
        {
            Services.UIStyleService.ApplyStyles(this);
            await LoadDataAsync();
        };
    }

    private async Task LoadDataAsync()
    {
        await LoadTablesAsync();
        await LoadIndexesAsync();
    }

    private async Task LoadTablesAsync()
    {
        try
        {
            TablesCountText.Text = "Loading tables...";
            Logger.Debug("Loading tables for tablespace: {Tablespace}", _tablespace.TablespaceName);

            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            var sqlTemplate = metadataHandler.GetRequiredStatement("GetTablesInTablespace");
            var sql = sqlTemplate.Replace("?", $"'{_tablespace.TablespaceName}'");

            var result = await _connectionManager.ExecuteQueryAsync(sql);
            
            var tables = new List<TablespaceTableItem>();
            foreach (System.Data.DataRow row in result.Rows)
            {
                tables.Add(new TablespaceTableItem
                {
                    Schema = row["TABSCHEMA"]?.ToString()?.Trim() ?? "",
                    TableName = row["TABNAME"]?.ToString()?.Trim() ?? "",
                    TableType = row["TYPE"]?.ToString()?.Trim() ?? "",
                    RowCount = row["ROW_COUNT"] != DBNull.Value ? Convert.ToInt64(row["ROW_COUNT"]) : 0
                });
            }

            TablesDataGrid.ItemsSource = tables;
            TablesCountText.Text = $"{tables.Count} table(s) in this tablespace";
            Logger.Info("Loaded {Count} tables for tablespace {Tablespace}", tables.Count, _tablespace.TablespaceName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load tables for tablespace: {Tablespace}", _tablespace.TablespaceName);
            TablesCountText.Text = $"Error loading tables: {ex.Message}";
            MessageBox.Show($"Failed to load tables:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task LoadIndexesAsync()
    {
        try
        {
            IndexesCountText.Text = "Loading indexes...";
            Logger.Debug("Loading indexes for tablespace: {Tablespace}", _tablespace.TablespaceName);

            // Query to get indexes in tablespace
            var sql = $@"
                SELECT TRIM(INDSCHEMA) AS INDSCHEMA, 
                       TRIM(INDNAME) AS INDNAME, 
                       TRIM(TABSCHEMA) AS TABSCHEMA, 
                       TRIM(TABNAME) AS TABNAME,
                       TRIM(INDEXTYPE) AS INDEXTYPE
                FROM SYSCAT.INDEXES 
                WHERE TRIM(TBSPACE) = '{_tablespace.TablespaceName}'
                ORDER BY INDSCHEMA, INDNAME";

            var result = await _connectionManager.ExecuteQueryAsync(sql);
            
            var indexes = new List<TablespaceIndexItem>();
            foreach (System.Data.DataRow row in result.Rows)
            {
                indexes.Add(new TablespaceIndexItem
                {
                    Schema = row["INDSCHEMA"]?.ToString()?.Trim() ?? "",
                    IndexName = row["INDNAME"]?.ToString()?.Trim() ?? "",
                    TableSchema = row["TABSCHEMA"]?.ToString()?.Trim() ?? "",
                    TableName = row["TABNAME"]?.ToString()?.Trim() ?? "",
                    IndexType = row["INDEXTYPE"]?.ToString()?.Trim() ?? ""
                });
            }

            IndexesDataGrid.ItemsSource = indexes;
            IndexesCountText.Text = $"{indexes.Count} index(es) in this tablespace";
            Logger.Info("Loaded {Count} indexes for tablespace {Tablespace}", indexes.Count, _tablespace.TablespaceName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load indexes for tablespace: {Tablespace}", _tablespace.TablespaceName);
            IndexesCountText.Text = $"Error loading indexes: {ex.Message}";
            MessageBox.Show($"Failed to load indexes:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void TableLink_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Hyperlink hyperlink && hyperlink.Tag is TablespaceTableItem tableItem)
        {
            OpenTableProperties(tableItem.Schema, tableItem.TableName);
        }
    }

    private void TablesDataGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (TablesDataGrid.SelectedItem is TablespaceTableItem tableItem)
        {
            OpenTableProperties(tableItem.Schema, tableItem.TableName);
        }
    }

    private void IndexTableLink_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Hyperlink hyperlink && hyperlink.Tag is TablespaceIndexItem indexItem)
        {
            OpenTableProperties(indexItem.TableSchema, indexItem.TableName);
        }
    }

    private void IndexesDataGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (IndexesDataGrid.SelectedItem is TablespaceIndexItem indexItem)
        {
            OpenTableProperties(indexItem.TableSchema, indexItem.TableName);
        }
    }

    private void OpenTableProperties(string schema, string tableName)
    {
        try
        {
            // Trim both parts before concatenation
            var trimmedSchema = schema?.Trim() ?? string.Empty;
            var trimmedTableName = tableName?.Trim() ?? string.Empty;
            
            Logger.Info("Opening table properties for: {Schema}.{Table}", trimmedSchema, trimmedTableName);
            
            var fullTableName = $"{trimmedSchema}.{trimmedTableName}";
            var dialog = new TableDetailsDialog(_connectionManager, fullTableName);
            dialog.Owner = this;
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open table properties for {Schema}.{Table}", schema, tableName);
            MessageBox.Show($"Failed to open table properties:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

/// <summary>
/// Model for table items in the tablespace
/// </summary>
public class TablespaceTableItem
{
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string TableType { get; set; } = string.Empty;
    public long RowCount { get; set; }
    public string FullName => $"{Schema.Trim()}.{TableName.Trim()}";
}

/// <summary>
/// Model for index items in the tablespace
/// </summary>
public class TablespaceIndexItem
{
    public string Schema { get; set; } = string.Empty;
    public string IndexName { get; set; } = string.Empty;
    public string TableSchema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string IndexType { get; set; } = string.Empty;
    public string TableFullName => $"{TableSchema.Trim()}.{TableName.Trim()}";
}

