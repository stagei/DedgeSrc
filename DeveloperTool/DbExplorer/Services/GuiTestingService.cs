using NLog;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using DbExplorer.Data;
using DbExplorer.Dialogs;

namespace DbExplorer.Services;

/// <summary>
/// Service for automated GUI form testing
/// Opens dialogs programmatically and extracts their data for validation
/// </summary>
public class GuiTestingService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler _metadataHandler;
    
    public GuiTestingService(MetadataHandler metadataHandler)
    {
        _metadataHandler = metadataHandler;
        Logger.Debug("GuiTestingService initialized");
    }
    
    /// <summary>
    /// Open a dialog, extract its data, and return as dictionary
    /// </summary>
    public async Task<Dictionary<string, object>> TestFormAsync(
        IConnectionManager connectionManager,
        string formName,
        string objectName,
        string? tabName = null)
    {
        Logger.Info("Testing form: {FormName}, Object: {ObjectName}, Tab: {Tab}", formName, objectName, tabName);
        
        try
        {
            return formName.ToLowerInvariant() switch
            {
                "table-details" => await TestTableDetailsAsync(connectionManager, objectName, tabName),
                "object-details" => await TestObjectDetailsAsync(connectionManager, objectName, tabName),
                "package-details" => await TestPackageDetailsAsync(connectionManager, objectName, tabName),
                "user-details" => await TestUserDetailsAsync(connectionManager, objectName, tabName),
                "mermaid-designer" => await TestMermaidDesignerAsync(connectionManager, objectName, tabName),
                _ => throw new ArgumentException($"Unknown form name: {formName}")
            };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to test form: {FormName}", formName);
            return new Dictionary<string, object>
            {
                {"error", ex.Message},
                {"formName", formName},
                {"objectName", objectName},
                {"tabName", tabName ?? "all"}
            };
        }
    }
    
    private async Task<Dictionary<string, object>> TestTableDetailsAsync(
        IConnectionManager connectionManager,
        string objectName,
        string? tabName)
    {
        Logger.Debug("Testing TableDetailsDialog for: {Object}", objectName);
        
        // Parse schema.table
        var parts = objectName.Split('.');
        if (parts.Length != 2)
        {
            throw new ArgumentException($"Object must be in format SCHEMA.TABLE, got: {objectName}");
        }
        
        var schema = parts[0];
        var tableName = parts[1];
        
        // Create dialog on UI thread and extract data
        Dictionary<string, object>? result = null;
        Exception? exception = null;
        
        await Application.Current.Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                Logger.Debug("Creating TableDetailsDialog on UI thread");
                var dialog = new TableDetailsDialog(connectionManager, objectName);
                
                Logger.Debug("Dialog created, waiting for async data loading...");
                await Task.Delay(3000); // Give time for async loading
                
                Logger.Debug("Extracting data from dialog");
                result = ExtractTableDetailsData(dialog, tabName);
                
                Logger.Debug("Data extracted, result is null: {IsNull}", result == null);
                
                dialog.Close();
                Logger.Debug("Dialog closed");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Exception during dialog extraction");
                exception = ex;
            }
        });
        
        if (exception != null)
        {
            return new Dictionary<string, object> { {"error", exception.Message}, {"stackTrace", exception.StackTrace ?? ""} };
        }
        
        Logger.Debug("Returning extracted result");
        return result ?? new Dictionary<string, object> { {"error", "Failed to extract data"} };
    }
    
    private Dictionary<string, object> ExtractTableDetailsData(TableDetailsDialog dialog, string? tabName)
    {
        try
        {
            Logger.Debug("ExtractTableDetailsData called, Tab: {Tab}", tabName ?? "all");
            
            var data = new Dictionary<string, object>
            {
                {"formName", "TableDetailsDialog"},
                {"fullTableName", dialog.Title}, // Dialog title shows table name
                {"extractedAt", DateTime.Now}
            };
            
            Logger.Debug("Base data created, extracting tabs...");
        
        
        // If specific tab requested, extract only that tab
        // Otherwise extract all tabs
        if (string.IsNullOrEmpty(tabName) || tabName == "all")
        {
            data["tabs"] = new Dictionary<string, object>
            {
                {"columns", ExtractDataGridData(dialog.ColumnsGridPublic)},
                {"foreignKeys", ExtractDataGridData(dialog.ForeignKeysGridPublic)},
                {"indexes", ExtractDataGridData(dialog.IndexesGridPublic)},
                {"ddlScript", ExtractTextBoxData(dialog.DDLTextBoxPublic)},
                {"statistics", ExtractStatisticsData(dialog)},
                {"incomingFK", ExtractDataGridData(dialog.IncomingFKGridPublic)},
                {"usedByPackages", ExtractDataGridData(dialog.PackagesGridPublic)},
                {"usedByViews", ExtractDataGridData(dialog.ViewsGridPublic)},
                {"usedByRoutines", ExtractDataGridData(dialog.RoutinesGridPublic)}
            };
        }
        else
        {
            // Extract specific tab
            data["tab"] = tabName;
            data["data"] = tabName switch
            {
                "columns" => ExtractDataGridData(dialog.ColumnsGridPublic),
                "foreign-keys" => ExtractDataGridData(dialog.ForeignKeysGridPublic),
                "indexes" => ExtractDataGridData(dialog.IndexesGridPublic),
                "ddl-script" => ExtractTextBoxData(dialog.DDLTextBoxPublic),
                "statistics" => ExtractStatisticsData(dialog),
                "incoming-fk" => ExtractDataGridData(dialog.IncomingFKGridPublic),
                "used-by-packages" => ExtractDataGridData(dialog.PackagesGridPublic),
                "used-by-views" => ExtractDataGridData(dialog.ViewsGridPublic),
                "used-by-routines" => ExtractDataGridData(dialog.RoutinesGridPublic),
                _ => new { error = $"Unknown tab: {tabName}" }
            };
        }
            
        Logger.Debug("Extraction complete, returning data");
        return data;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to extract TableDetailsDialog data");
            return new Dictionary<string, object>
            {
                {"error", ex.Message},
                {"stackTrace", ex.StackTrace ?? ""}
            };
        }
    }
    
    private object ExtractDataGridData(System.Windows.Controls.DataGrid grid)
    {
        try
        {
            if (grid == null || grid.ItemsSource == null)
            {
                return new { rowCount = 0, rows = Array.Empty<object>() };
            }
            
            var rows = new List<Dictionary<string, object>>();
            
            foreach (var item in grid.ItemsSource)
            {
                if (item is System.Data.DataRowView rowView)
                {
                    var row = new Dictionary<string, object>();
                    foreach (System.Data.DataColumn col in rowView.Row.Table.Columns)
                    {
                        row[col.ColumnName] = rowView[col.ColumnName]?.ToString() ?? "";
                    }
                    rows.Add(row);
                }
            }
            
            return new { rowCount = rows.Count, rows };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to extract DataGrid data");
            return new { error = ex.Message };
        }
    }
    
    private object ExtractTextBoxData(System.Windows.Controls.TextBox textBox)
    {
        try
        {
            if (textBox == null)
            {
                return new { text = "", length = 0 };
            }
            
            var text = textBox.Text ?? "";
            return new { text, length = text.Length, lineCount = text.Split('\n').Length };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to extract TextBox data");
            return new { error = ex.Message };
        }
    }
    
    private object ExtractStatisticsData(TableDetailsDialog dialog)
    {
        try
        {
            return new
            {
                rowCount = dialog.RowCountTextPublic.Text,
                columnCount = dialog.ColumnCountTextPublic.Text,
                fkCount = dialog.FKCountTextPublic.Text,
                indexCount = dialog.IndexCountTextPublic.Text,
                tableType = dialog.TableTypeTextPublic.Text,
                tablespace = dialog.TablespaceTextPublic.Text
            };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to extract statistics data");
            return new { error = ex.Message };
        }
    }
    
    private async Task<Dictionary<string, object>> TestObjectDetailsAsync(
        IConnectionManager connectionManager,
        string objectName,
        string? tabName)
    {
        // TODO: Implement for ObjectDetailsDialog
        Logger.Warn("ObjectDetailsDialog testing not yet implemented");
        return new Dictionary<string, object>
        {
            {"error", "Not yet implemented"},
            {"formName", "ObjectDetailsDialog"},
            {"objectName", objectName}
        };
    }
    
    private async Task<Dictionary<string, object>> TestPackageDetailsAsync(
        IConnectionManager connectionManager,
        string objectName,
        string? tabName)
    {
        // TODO: Implement for PackageDetailsDialog
        Logger.Warn("PackageDetailsDialog testing not yet implemented");
        return new Dictionary<string, object>
        {
            {"error", "Not yet implemented"},
            {"formName", "PackageDetailsDialog"},
            {"objectName", objectName}
        };
    }
    
    private async Task<Dictionary<string, object>> TestUserDetailsAsync(
        IConnectionManager connectionManager,
        string objectName,
        string? tabName)
    {
        // TODO: Implement for UserDetailsDialog
        Logger.Warn("UserDetailsDialog testing not yet implemented");
        return new Dictionary<string, object>
        {
            {"error", "Not yet implemented"},
            {"formName", "UserDetailsDialog"},
            {"objectName", objectName}
        };
    }
    
    /// <summary>
    /// Test Mermaid Designer form
    /// ObjectName is interpreted as schema or "auto" for current connection schema
    /// TabName can be: "generate-from-db", "show-diff", "generate-alter", "export-sql"
    /// </summary>
    private async Task<Dictionary<string, object>> TestMermaidDesignerAsync(
        IConnectionManager connectionManager,
        string objectName,
        string? tabName)
    {
        Logger.Debug("Testing MermaidDesignerWindow for schema: {Schema}, Action: {Action}", objectName, tabName);
        
        // objectName is the target schema (e.g., "INL", "SYSCAT", etc.)
        var targetSchema = objectName;
        
        Dictionary<string, object>? result = null;
        Exception? exception = null;
        
        // Use a TaskCompletionSource to properly await the UI thread operation
        var tcs = new TaskCompletionSource<bool>();
        
        var dispatcherOp = Application.Current.Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                Logger.Debug("Creating MermaidDesignerWindow on UI thread");
                var dialog = new MermaidDesignerWindow(connectionManager, targetSchema);
                
                Logger.Debug("Showing dialog (non-modal for extraction)");
                dialog.Show();
                
                Logger.Debug("Waiting for WebView2 initialization...");
                await Task.Delay(5000); // Give time for WebView2 to load
                
                Logger.Debug("Extracting data from Mermaid Designer");
                result = ExtractMermaidDesignerData(dialog, tabName);
                Logger.Debug("Extraction returned result: {IsNull}", result == null);
                
                // If specific action requested, perform it
                if (!string.IsNullOrEmpty(tabName))
                {
                    var safeResult = result ?? new Dictionary<string, object>
                    {
                        { "formName", "MermaidDesignerWindow" },
                        { "error", "Extraction returned null result" }
                    };
                    await PerformMermaidAction(dialog, tabName, safeResult);
                }
                
                Logger.Debug("Data extracted from Mermaid Designer");
                
                dialog.Close();
                Logger.Debug("MermaidDesignerWindow closed");
                
                tcs.SetResult(true);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Exception during Mermaid Designer extraction");
                exception = ex;
                tcs.SetException(ex);
            }
        });

        // Await dispatcher operation to avoid fire-and-forget warning (CS4014)
        await dispatcherOp.Task.Unwrap();
        
        // Wait for the UI operation to complete
        await tcs.Task;
        
        if (exception != null)
        {
            return new Dictionary<string, object> 
            { 
                {"error", exception.Message}, 
                {"stackTrace", exception.StackTrace ?? ""},
                {"formName", "MermaidDesignerWindow"}
            };
        }
        
        return result ?? new Dictionary<string, object> { {"error", "Failed to extract data"} };
    }
    
    private Dictionary<string, object> ExtractMermaidDesignerData(MermaidDesignerWindow dialog, string? action)
    {
        try
        {
            Logger.Debug("ExtractMermaidDesignerData called, Action: {Action}", action ?? "none");
            
            var data = new Dictionary<string, object>
            {
                {"formName", "MermaidDesignerWindow"},
                {"targetSchema", dialog.TargetSchema},
                {"isDesignerLoaded", dialog.IsDesignerLoaded},
                {"extractedAt", DateTime.Now}
            };
            
            // Extract diagram data if available
            if (dialog.LastGeneratedMermaid != null)
            {
                data["lastGeneratedMermaid"] = new
                {
                    length = dialog.LastGeneratedMermaid.Length,
                    preview = dialog.LastGeneratedMermaid.Substring(0, Math.Min(200, dialog.LastGeneratedMermaid.Length)),
                    lineCount = dialog.LastGeneratedMermaid.Split('\n').Length
                };
            }
            
            // Extract selected tables if available
            if (dialog.LastSelectedTables != null && dialog.LastSelectedTables.Count > 0)
            {
                data["selectedTables"] = new
                {
                    count = dialog.LastSelectedTables.Count,
                    tables = dialog.LastSelectedTables
                };
            }
            
            Logger.Debug("Mermaid Designer data extraction complete");
            return data;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to extract Mermaid Designer data");
            return new Dictionary<string, object>
            {
                {"error", ex.Message},
                {"stackTrace", ex.StackTrace ?? ""}
            };
        }
    }
    
    /// <summary>
    /// Perform automated action on Mermaid Designer for testing
    /// </summary>
    private async Task PerformMermaidAction(MermaidDesignerWindow dialog, string action, Dictionary<string, object> result)
    {
        try
        {
            Logger.Debug("Performing Mermaid action: {Action}", action);
            
            switch (action.ToLowerInvariant())
            {
                case "generate-from-db":
                    // Test loading tables from DB
                    Logger.Debug("Testing generate from DB with sample tables");
                    var testTables = new List<string> { "INL.KUNDEKONTO_TEST", "INL.TRANSREG_TEST" };
                    var mermaid = await dialog.GenerateDiagramAutomatedAsync(testTables);
                    result["generatedMermaid"] = new
                    {
                        length = mermaid.Length,
                        tablesCount = testTables.Count,
                        success = !string.IsNullOrEmpty(mermaid)
                    };
                    Logger.Info("Generated Mermaid diagram via automation: {Length} chars", mermaid.Length);
                    break;
                    
                case "extract-data":
                    // Extract current state
                    var extractedData = dialog.ExtractDataForTesting();
                    result["extracted"] = extractedData;
                    Logger.Info("Extracted Mermaid Designer data for testing");
                    break;
                    
                default:
                    result["actionError"] = $"Unknown action: {action}";
                    Logger.Warn("Unknown Mermaid action requested: {Action}", action);
                    break;
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to perform Mermaid action: {Action}", action);
            result["actionError"] = ex.Message;
        }
    }
}

