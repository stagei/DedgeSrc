using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class PackagePropertiesDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly PackageInfo _package;
    private readonly List<PackageStatement> _statements = new();
    private readonly MetadataHandler? _metadataHandler;

    // Event to communicate with parent window
    public event EventHandler<string>? SqlTextRequested;

    public PackagePropertiesDialog(IConnectionManager connectionManager, PackageInfo package)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _package = package;
        _metadataHandler = App.MetadataHandler;

        Logger.Debug("PackagePropertiesDialog opened for: {Schema}.{Package}", package.PackageSchema, package.PackageName);

        PackageNameText.Text = package.PackageName;
        PackageInfoText.Text = $"Schema: {package.PackageSchema} • Full Name: {package.PackageSchema}.{package.PackageName}";

        // Wire up selection changed event for buttons
        StatementsGrid.SelectionChanged += (s, e) =>
        {
            var hasSelection = StatementsGrid.SelectedItem != null;
            ViewStatementButton.IsEnabled = hasSelection;
            AddToEditorButton.IsEnabled = hasSelection;
        };

        // Apply all UI styles from the unified style service
        this.Loaded += (s, e) => UIStyleService.ApplyStyles(this);

        LoadPackageDetails();
        _ = LoadStatementsAsync();
        _ = LoadDependenciesAsync();
    }
    
    /// <summary>
    /// Activates a specific tab by name for automated testing and direct navigation
    /// </summary>
    public void ActivateTab(string? tabName)
    {
        if (string.IsNullOrEmpty(tabName))
            return;
            
        Logger.Debug("Activating tab: {Tab}", tabName);
        
        var tab = tabName.ToLowerInvariant() switch
        {
            "properties" or "props" => PropertiesTab,
            "statements" or "sql-statements" or "sql" => StatementsTab,
            "objectsused" or "dependencies" or "deps" => ObjectsUsedTab,
            _ => null
        };
        
        if (tab != null)
        {
            DetailsTabControl.SelectedItem = tab;
            Logger.Info("Activated tab: {Tab}", tabName);
        }
        else
        {
            Logger.Warn("Unknown tab name: {Tab}", tabName);
        }
    }

    private async void LoadPackageDetails()
    {
        try
        {
            var sql = _metadataHandler?.GetStatement("GetPackageProperties") 
                ?? @"SELECT 
                    TRIM(PKGSCHEMA) AS PackageSchema, 
                    TRIM(PKGNAME) AS PackageName, 
                    TRIM(BOUNDBY) AS BoundBy, 
                    TRIM(DEFINER) AS Definer, 
                    LASTUSED AS LastUsed, 
                    CREATE_TIME AS CreatedDate, 
                    VALID AS IsValid, 
                    TRIM(ISOLATION) AS IsolationLevel, 
                    TRIM(BLOCKING) AS Blocking, 
                    TRIM(SQLWARN) AS SqlWarnings, 
                    TRIM(FUNCPATH) AS FunctionPath, 
                    TRIM(REMARKS) AS Remarks,
                    LAST_BIND_TIME AS LastBindTime,
                    TRIM(UNIQUE_ID) AS UniqueId
                FROM SYSCAT.PACKAGES 
                WHERE TRIM(PKGSCHEMA) = ? AND TRIM(PKGNAME) = ?";

            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@pkgschema", _package.PackageSchema));
            command.Parameters.Add(_connectionManager.CreateParameter("@pkgname", _package.PackageName));

            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                PackageNameValue.Text = reader.IsDBNull(1) ? _package.PackageName : reader.GetString(1);
                PackageSchemaValue.Text = reader.IsDBNull(0) ? _package.PackageSchema : reader.GetString(0);
                BoundByValue.Text = reader.IsDBNull(2) ? _package.BoundBy : reader.GetString(2);
                OwnerValue.Text = reader.IsDBNull(3) ? _package.Owner : reader.GetString(3);
                IsolationValue.Text = reader.IsDBNull(7) ? _package.Isolation : reader.GetString(7);
                ValidValue.Text = reader.IsDBNull(6) ? "N/A" : reader.GetString(6);
                LastUsedValue.Text = reader.IsDBNull(4) ? "Never" : reader.GetDateTime(4).ToString("yyyy-MM-dd HH:mm:ss");
                CreateTimeValue.Text = reader.IsDBNull(5) ? (_package.CreateTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "N/A") : reader.GetDateTime(5).ToString("yyyy-MM-dd HH:mm:ss");
                LastBindTimeValue.Text = reader.IsDBNull(12) ? "N/A" : reader.GetDateTime(12).ToString("yyyy-MM-dd HH:mm:ss");
                UniqueIdValue.Text = reader.IsDBNull(13) ? "N/A" : reader.GetString(13);
                RemarksValue.Text = reader.IsDBNull(11) ? (string.IsNullOrEmpty(_package.Remarks) ? "No remarks" : _package.Remarks) : reader.GetString(11);
            }
            else
            {
                // Fallback to package info if query fails
                PackageNameValue.Text = _package.PackageName;
                PackageSchemaValue.Text = _package.PackageSchema;
                BoundByValue.Text = _package.BoundBy;
                OwnerValue.Text = _package.Owner;
                IsolationValue.Text = _package.Isolation;
                CreateTimeValue.Text = _package.CreateTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "N/A";
                RemarksValue.Text = string.IsNullOrEmpty(_package.Remarks) ? "No remarks" : _package.Remarks;
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load package details");
            // Fallback to package info
            PackageNameValue.Text = _package.PackageName;
            PackageSchemaValue.Text = _package.PackageSchema;
            BoundByValue.Text = _package.BoundBy;
            OwnerValue.Text = _package.Owner;
            IsolationValue.Text = _package.Isolation;
            CreateTimeValue.Text = _package.CreateTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "N/A";
            RemarksValue.Text = string.IsNullOrEmpty(_package.Remarks) ? "No remarks" : _package.Remarks;
        }
    }

    private async Task LoadStatementsAsync()
    {
        Logger.Info("Loading SQL statements for package: {Schema}.{Package}", _package.PackageSchema, _package.PackageName);

        try
        {
            var sql = _metadataHandler?.GetStatement("GetPackageStatements") 
                ?? @"SELECT 
                    TRIM(S.STMTNO) AS StmtNo,
                    TRIM(S.SECTNO) AS SectionNo,
                    TRIM(S.SEQNO) AS SeqNo,
                    TRIM(S.TEXT) AS StatementText
                FROM SYSCAT.STATEMENTS S
                JOIN SYSCAT.PACKAGES P ON S.PKGSCHEMA = P.PKGSCHEMA AND S.PKGNAME = P.PKGNAME
                WHERE TRIM(S.PKGSCHEMA) = ? AND TRIM(S.PKGNAME) = ?
                ORDER BY S.STMTNO, S.SECTNO, S.SEQNO";

            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@pkgschema", _package.PackageSchema));
            command.Parameters.Add(_connectionManager.CreateParameter("@pkgname", _package.PackageName));

            using var reader = await command.ExecuteReaderAsync();

            var statementGroups = new Dictionary<string, List<string>>();

            while (await reader.ReadAsync())
            {
                var stmtNo = reader.GetString(0);
                var sectNo = reader.GetString(1);
                var seqNo = reader.GetString(2);
                var text = reader.IsDBNull(3) ? string.Empty : reader.GetString(3);

                var key = $"{stmtNo}:{sectNo}";

                if (!statementGroups.ContainsKey(key))
                {
                    statementGroups[key] = new List<string>();
                }

                statementGroups[key].Add(text);
            }

            // Convert to PackageStatement objects
            foreach (var kvp in statementGroups.OrderBy(k => k.Key))
            {
                var parts = kvp.Key.Split(':');
                var stmtNo = parts[0];
                var sectNo = parts[1];
                var fullText = string.Join("", kvp.Value);

                // Determine statement type from the SQL text
                var stmtType = DetermineStatementType(fullText);

                // Create preview (first 100 characters)
                var preview = fullText.Length > 100 ? fullText.Substring(0, 100) + "..." : fullText;

                _statements.Add(new PackageStatement
                {
                    StmtNo = stmtNo,
                    SectionNumber = sectNo,
                    StmtType = stmtType,
                    TextPreview = preview.Replace('\n', ' ').Replace('\r', ' ').Trim(),
                    FullText = fullText
                });
            }

            Dispatcher.Invoke(() =>
            {
                StatementsGrid.ItemsSource = _statements;
                StatementCountText.Text = _statements.Count.ToString();
            });

            Logger.Info("Loaded {Count} SQL statements", _statements.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load package statements");
            Dispatcher.Invoke(() =>
            {
                StatementCountText.Text = "Error";
                MessageBox.Show($"Error loading package statements:\n\n{ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            });
        }
    }

    private string DetermineStatementType(string sql)
    {
        var upperSql = sql.TrimStart().ToUpperInvariant();

        if (upperSql.StartsWith("SELECT")) return "SELECT";
        if (upperSql.StartsWith("INSERT")) return "INSERT";
        if (upperSql.StartsWith("UPDATE")) return "UPDATE";
        if (upperSql.StartsWith("DELETE")) return "DELETE";
        if (upperSql.StartsWith("CALL")) return "CALL";
        if (upperSql.StartsWith("MERGE")) return "MERGE";
        if (upperSql.StartsWith("CREATE")) return "CREATE";
        if (upperSql.StartsWith("ALTER")) return "ALTER";
        if (upperSql.StartsWith("DROP")) return "DROP";
        if (upperSql.StartsWith("GRANT")) return "GRANT";
        if (upperSql.StartsWith("REVOKE")) return "REVOKE";

        return "OTHER";
    }

    private void ViewFullStatement_Click(object sender, RoutedEventArgs e)
    {
        if (StatementsGrid.SelectedItem is PackageStatement statement)
        {
            Logger.Debug("Viewing full statement: Stmt {StmtNo}, Section {Section}", statement.StmtNo, statement.SectionNumber);

            var viewerDialog = new SqlStatementViewerDialog(statement.FullText, 
                $"Statement {statement.StmtNo} - Section {statement.SectionNumber}")
            {
                Owner = this
            };

            if (viewerDialog.ShowDialog() == true && viewerDialog.AddToEditor)
            {
                SqlTextRequested?.Invoke(this, statement.FullText);
                Logger.Info("Statement added to editor from viewer dialog");
            }
        }
    }

    private void AddToEditor_Click(object sender, RoutedEventArgs e)
    {
        if (StatementsGrid.SelectedItem is PackageStatement statement)
        {
            Logger.Info("Adding statement to editor: Stmt {StmtNo}, Section {Section}", statement.StmtNo, statement.SectionNumber);
            SqlTextRequested?.Invoke(this, statement.FullText);
            MessageBox.Show("Statement added to SQL editor", "Success", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private void StatementsGrid_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        ViewFullStatement_Click(sender, new RoutedEventArgs());
    }
    
    /// <summary>
    /// Load package dependencies using PackageDependencyAnalyzer
    /// </summary>
    private async Task LoadDependenciesAsync()
    {
        Logger.Info("Loading dependencies for package: {Schema}.{Package}", _package.PackageSchema, _package.PackageName);
        
        try
        {
            TablesUsedCount.Text = "⏳ Analyzing dependencies...";
            ViewsUsedCount.Text = "⏳ Analyzing dependencies...";
            ProceduresCalledCount.Text = "⏳ Analyzing dependencies...";
            FunctionsCalledCount.Text = "⏳ Analyzing dependencies...";
            
            var analyzer = new PackageDependencyAnalyzer(_metadataHandler);
            var dependencies = await analyzer.AnalyzeDependenciesAsync(
                _connectionManager,
                _package.PackageSchema,
                _package.PackageName);
            
            // Populate Tables Used
            var tablesData = dependencies.TablesUsed.Select(t => new DependencyItem
            {
                Schema = t.Schema,
                Name = t.Name,
                UsageCount = t.UsageCount,
                StatementsText = string.Join(", ", t.StatementsUsedIn.Take(10).Select(s => $"Stmt {s}")),
                VerifiedText = t.Verified ? "✅ Yes" : "❌ No",
                ObjectType = "Table"
            }).ToList();
            
            TablesUsedGrid.ItemsSource = tablesData;
            TablesUsedCount.Text = $"📋 {tablesData.Count} table(s) used";
            
            // Populate Views Used
            var viewsData = dependencies.ViewsUsed.Select(v => new DependencyItem
            {
                Schema = v.Schema,
                Name = v.Name,
                UsageCount = v.UsageCount,
                StatementsText = string.Join(", ", v.StatementsUsedIn.Take(10).Select(s => $"Stmt {s}")),
                VerifiedText = v.Verified ? "✅ Yes" : "❌ No",
                ObjectType = "View"
            }).ToList();
            
            ViewsUsedGrid.ItemsSource = viewsData;
            ViewsUsedCount.Text = $"👁️ {viewsData.Count} view(s) used";
            
            // Populate Procedures Called
            var proceduresData = dependencies.ProceduresCalled.Select(p => new DependencyItem
            {
                Schema = p.Schema,
                Name = p.Name,
                UsageCount = p.UsageCount,
                StatementsText = string.Join(", ", p.StatementsUsedIn.Take(10).Select(s => $"Stmt {s}")),
                VerifiedText = p.Verified ? "✅ Yes" : "❌ No",
                ObjectType = "Procedure"
            }).ToList();
            
            ProceduresCalledGrid.ItemsSource = proceduresData;
            ProceduresCalledCount.Text = $"⚙️ {proceduresData.Count} procedure(s) called";
            
            // Populate Functions Called
            var functionsData = dependencies.FunctionsCalled.Select(f => new DependencyItem
            {
                Schema = f.Schema,
                Name = f.Name,
                UsageCount = f.UsageCount,
                StatementsText = string.Join(", ", f.StatementsUsedIn.Take(10).Select(s => $"Stmt {s}")),
                VerifiedText = f.Verified ? "✅ Yes" : "❌ No",
                ObjectType = "Function"
            }).ToList();
            
            FunctionsCalledGrid.ItemsSource = functionsData;
            FunctionsCalledCount.Text = $"🔧 {functionsData.Count} function(s) called";
            
            Logger.Info("Dependencies loaded successfully: {Tables} tables, {Views} views, {Procs} procedures, {Funcs} functions",
                       tablesData.Count, viewsData.Count, proceduresData.Count, functionsData.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load package dependencies");
            TablesUsedCount.Text = "❌ Error loading dependencies";
            ViewsUsedCount.Text = "❌ Error loading dependencies";
            ProceduresCalledCount.Text = "❌ Error loading dependencies";
            FunctionsCalledCount.Text = "❌ Error loading dependencies";
            MessageBox.Show($"Failed to load dependencies: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Handle double-click on dependency item - open property form for that object
    /// </summary>
    private void DependencyItem_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is DataGrid grid && grid.SelectedItem is DependencyItem item)
        {
            Logger.Info("Opening property form for {Type}: {Schema}.{Name}", item.ObjectType, item.Schema, item.Name);
            
            try
            {
                Window? dialog = null;
                var fullName = $"{item.Schema}.{item.Name}";
                
                switch (item.ObjectType)
                {
                    case "Table":
                        dialog = new TableDetailsDialog(_connectionManager, fullName);
                        break;
                    case "View":
                        var viewParts = fullName.Split('.');
                        if (viewParts.Length == 2)
                        {
                            dialog = new ViewDetailsDialog(_connectionManager, viewParts[0], viewParts[1]);
                        }
                        break;
                    case "Procedure":
                        var procObj = new DatabaseObject
                        {
                            Name = item.Name,
                            SchemaName = item.Schema,
                            FullName = fullName,
                            Type = ObjectType.Procedures
                        };
                        dialog = new ObjectDetailsDialog(_connectionManager, procObj, null);
                        break;
                    case "Function":
                        var funcObj = new DatabaseObject
                        {
                            Name = item.Name,
                            SchemaName = item.Schema,
                            FullName = fullName,
                            Type = ObjectType.Functions
                        };
                        dialog = new ObjectDetailsDialog(_connectionManager, funcObj, null);
                        break;
                }
                
                if (dialog != null)
                {
                    dialog.Owner = this;
                    dialog.ShowDialog();
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to open property form for {Type}: {Schema}.{Name}", item.ObjectType, item.Schema, item.Name);
                MessageBox.Show($"Failed to open property form:\n\n{ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

/// <summary>
/// Model for package SQL statements
/// </summary>
public class PackageStatement
{
    public string StmtNo { get; set; } = string.Empty;
    public string SectionNumber { get; set; } = string.Empty;
    public string StmtType { get; set; } = string.Empty;
    public string TextPreview { get; set; } = string.Empty;
    public string FullText { get; set; } = string.Empty;
}

/// <summary>
/// Model for dependency items with clickable links
/// </summary>
public class DependencyItem
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int UsageCount { get; set; }
    public string StatementsText { get; set; } = string.Empty;
    public string VerifiedText { get; set; } = string.Empty;
    public string ObjectType { get; set; } = string.Empty;
}
