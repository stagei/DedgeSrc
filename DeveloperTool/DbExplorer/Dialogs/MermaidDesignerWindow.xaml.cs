using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Text.Json;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;
using NLog;
using DbExplorer.Data;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class MermaidDesignerWindow : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly IConnectionManager _connectionManager;
    private readonly MermaidDiagramGeneratorService _generatorService;
    private readonly SchemaDiffAnalyzerService _diffAnalyzer;
    private readonly DiffBasedDdlGeneratorService _ddlGenerator;
    private readonly SqlMermaidIntegrationService _sqlMermaidService;
    private readonly MermaidBaselineSnapshotService _baselineService;
    private readonly MermaidDiffComparisonService _diffComparisonService;
    private readonly MermaidChangeTracker _changeTracker;
    private string _targetSchema;
    private string? _lastGeneratedMermaid;
    private List<string>? _lastSelectedTables;
    private string? _currentDiffDdl;
    private MermaidPreviewWindow? _previewWindow;
    
    // Public properties for testing automation
    public bool IsDesignerLoaded { get; private set; }
    public string? LastGeneratedMermaid => _lastGeneratedMermaid;
    public List<string>? LastSelectedTables => _lastSelectedTables;
    public string TargetSchema => _targetSchema;
    
    public MermaidDesignerWindow(IConnectionManager connectionManager, string targetSchema)
    {
        InitializeComponent();
        
        _connectionManager = connectionManager;
        _targetSchema = targetSchema;
        _generatorService = new MermaidDiagramGeneratorService();
        _diffAnalyzer = new SchemaDiffAnalyzerService();
        _ddlGenerator = new DiffBasedDdlGeneratorService();
        _sqlMermaidService = new SqlMermaidIntegrationService();
        _baselineService = new MermaidBaselineSnapshotService();
        _diffComparisonService = new MermaidDiffComparisonService(_sqlMermaidService, _baselineService);
        _changeTracker = new MermaidChangeTracker();
        
        // Wire up diff detection event
        _diffComparisonService.DiffDetected += DiffComparisonService_DiffDetected;
        
        // Wire up change tracker events for button enable/disable
        _changeTracker.ChangeStatusChanged += ChangeTracker_ChangeStatusChanged;
        
        Loaded += MermaidDesignerWindow_Loaded;
        Closed += MermaidDesignerWindow_Closed;
    }
    
    private void MermaidDesignerWindow_Closed(object? sender, EventArgs e)
    {
        // Close preview window if open
        _previewWindow?.Close();
        _previewWindow = null;
    }
    
    private async void MermaidDesignerWindow_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            Logger.Info("Initializing Mermaid Designer WebView2 for schema: {Schema}", _targetSchema);
            Logger.Debug("MermaidDesignerWindow_Loaded event fired");
            Logger.Debug("BaseDirectory: {BaseDir}", AppDomain.CurrentDomain.BaseDirectory);
            
            Logger.Debug("Step 1: Ensuring WebView2 runtime");
            await MermaidWebView.EnsureCoreWebView2Async();
            Logger.Info("WebView2 runtime initialized successfully");
            
            Logger.Debug("Step 2: Registering web message handler");
            MermaidWebView.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;
            Logger.Debug("Web message handler registered");
            
            Logger.Debug("Step 3: Locating MermaidDesigner.html");
            var htmlPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "MermaidDesigner.html");
            Logger.Debug("Expected HTML path: {HtmlPath}", htmlPath);
            
            if (!File.Exists(htmlPath))
            {
                Logger.Error("MermaidDesigner.html not found at: {Path}", htmlPath);
                Logger.Debug("Checking if Resources directory exists...");
                
                var resourcesDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources");
                if (Directory.Exists(resourcesDir))
                {
                    Logger.Debug("Resources directory exists. Contents:");
                    var files = Directory.GetFiles(resourcesDir);
                    foreach (var file in files)
                    {
                        Logger.Debug("  - {File}", Path.GetFileName(file));
                    }
                }
                else
                {
                    Logger.Error("Resources directory does not exist: {Dir}", resourcesDir);
                }
                
                MessageBox.Show(
                    $"MermaidDesigner.html not found at:\n{htmlPath}\n\nPlease ensure it exists in Resources folder.",
                    "Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                Close();
                return;
            }
            
            Logger.Info("MermaidDesigner.html found, loading into WebView2");
            Logger.Debug("File size: {Size} bytes", new FileInfo(htmlPath).Length);
            
            Logger.Debug("Step 4: Setting WebView2 source");
            MermaidWebView.Source = new Uri(htmlPath);
            Logger.Debug("WebView2 source set to: {Uri}", htmlPath);
            
            IsDesignerLoaded = true;
            Logger.Info("Mermaid Designer initialized successfully for schema: {Schema}", _targetSchema);
        }
        catch (Exception ex)
        {
            IsDesignerLoaded = false;
            Logger.Error(ex, "Failed to initialize Mermaid Designer");
            Logger.Debug("Exception type: {Type}", ex.GetType().Name);
            Logger.Debug("Exception message: {Message}", ex.Message);
            Logger.Debug("Stack trace: {StackTrace}", ex.StackTrace);
            
            if (ex.InnerException != null)
            {
                Logger.Error(ex.InnerException, "Inner exception details");
            }
            
            MessageBox.Show(
                $"Failed to initialize Mermaid Designer:\n\n{ex.Message}\n\nSee logs for details.",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Close();
        }
    }
    
    #region WPF Toolbar Button Handlers
    
    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Refresh button clicked");
        await MermaidWebView.ExecuteScriptAsync("refreshPreview();");
    }
    
    private async void AutoRefresh_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Auto-Refresh button clicked");
        await MermaidWebView.ExecuteScriptAsync("autoRefresh();");
    }
    
    private async void LoadFromDB_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Load from DB button clicked (WPF)");
        await HandleGenerateFromDB();
    }
    
    private async void ShowDiff_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Show Diff button clicked");
        await MermaidWebView.ExecuteScriptAsync("showDiff();");
    }
    
    private async void GenerateDDL_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Generate DDL button clicked");
        await MermaidWebView.ExecuteScriptAsync("generateDDL();");
    }
    
    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Export button clicked");
        await MermaidWebView.ExecuteScriptAsync("exportDiagram();");
    }
    
    private async void MermaidToSql_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Mermaid to SQL button clicked");
        await MermaidWebView.ExecuteScriptAsync("generateSqlFromMermaid();");
    }
    
    private async void TranslateSql_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Translate SQL button clicked");
        await MermaidWebView.ExecuteScriptAsync("translateSql();");
    }
    
    private async void AdvancedMigration_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Advanced Migration button clicked");
        await MermaidWebView.ExecuteScriptAsync("advancedMigration();");
    }
    
    private void Help_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Help button clicked");
        MessageBox.Show(
            "Mermaid ER Diagram Designer\n\n" +
            "• Load from DB: Select tables to generate an ER diagram\n" +
            "• Add Tables: Add more tables to existing diagram\n" +
            "• Show Diff: Compare current diagram with baseline (enabled when changes detected)\n" +
            "• Generate DDL: Create ALTER statements from changes\n" +
            "• Preview Window: Open diagram preview in separate window\n\n" +
            "Change Tracking:\n" +
            "• Each table's Mermaid code is tracked with a hash\n" +
            "• Diff buttons enable when changes are detected\n" +
            "• Buttons disable when you revert changes\n\n" +
            "Click on table names in the preview to view properties.\n\n" +
            "Powered by SqlMermaidErdTools",
            "Mermaid Designer Help",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
    
    private void OpenPreviewWindow_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Open Preview Window button clicked");
        
        if (_previewWindow != null && _previewWindow.IsVisible)
        {
            // Bring existing window to front
            _previewWindow.Activate();
            return;
        }
        
        // Create new preview window
        _previewWindow = new MermaidPreviewWindow();
        _previewWindow.SetConnectionInfo(_connectionManager.ConnectionInfo.Name);
        _previewWindow.PreviewWindowClosed += (s, args) => _previewWindow = null;
        _previewWindow.Show();
        
        // If we have a diagram, send it to preview
        if (!string.IsNullOrEmpty(_lastGeneratedMermaid))
        {
            _previewWindow.UpdatePreview(_lastGeneratedMermaid, _lastSelectedTables?.Count ?? 0);
        }
        
        Logger.Info("Preview window opened");
    }
    
    private async void AddMoreTables_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Add More Tables button clicked");
        
        try
        {
            var dialog = new TableSelectionWithFKNavigationDialog(_connectionManager, _targetSchema);
            
            // Pre-select already included tables
            // This would need enhancement in the dialog to support pre-selection
            
            if (dialog.ShowDialog() != true)
            {
                Logger.Debug("User cancelled table selection");
                return;
            }
            
            var newTables = dialog.SelectedTables
                .Where(t => _lastSelectedTables == null || !_lastSelectedTables.Contains(t))
                .ToList();
            
            if (newTables.Count == 0)
            {
                MessageBox.Show("No new tables selected.", "Info", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            
            Logger.Info("Adding {Count} new tables to diagram", newTables.Count);
            
            // Add new tables to selection
            _lastSelectedTables ??= new List<string>();
            _lastSelectedTables.AddRange(newTables);
            
            // Regenerate diagram with all tables
            var mermaid = await _generatorService.GenerateMermaidDiagramAsync(_connectionManager, _lastSelectedTables);
            _lastGeneratedMermaid = mermaid;
            
            // Update change tracker with new tables
            _changeTracker.AddNewTables(mermaid, newTables);
            
            // Update editor
            var escapedMermaid = EscapeForJavaScript(mermaid);
            await MermaidWebView.ExecuteScriptAsync($"setEditorContent(`{escapedMermaid}`);");
            
            // Update preview window if open
            _previewWindow?.UpdatePreview(mermaid, _lastSelectedTables.Count);
            
            // Update status
            UpdateStatusBar();
            
            Logger.Info("Added {Count} new tables - Total: {Total} tables", newTables.Count, _lastSelectedTables.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to add more tables");
            MessageBox.Show($"Failed to add tables: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Handler for change tracker status changes.
    /// Enables/disables Show Diff and Generate DDL buttons based on detected changes.
    /// </summary>
    private void ChangeTracker_ChangeStatusChanged(object? sender, MermaidChangeEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            Logger.Debug("Change status updated: HasChanges={HasChanges}, Changed={Changed}, New={New}, Removed={Removed}",
                e.HasChanges, e.ChangedTableCount, e.NewTableCount, e.RemovedTableCount);
            
            // Enable/disable diff buttons based on change status
            ShowDiffButton.IsEnabled = e.HasChanges;
            GenerateDDLButton.IsEnabled = e.HasChanges;
            
            // Update change count in status bar
            var totalChanges = e.ChangedTableCount + e.NewTableCount + e.RemovedTableCount;
            ChangeCountStatus.Content = $"Changes: {totalChanges}";
            
            if (e.HasChanges)
            {
                StatusText.Content = $"⚠️ {totalChanges} change(s) detected - Use 'Show Diff' or 'Generate DDL'";
            }
            else if (_lastSelectedTables?.Count > 0)
            {
                StatusText.Content = $"✓ No changes - {_lastSelectedTables.Count} tables in diagram";
            }
        });
    }
    
    private void UpdateStatusBar()
    {
        try
        {
            TableCountStatus.Content = $"Tables: {_lastSelectedTables?.Count ?? 0}";
            
            if (_changeTracker != null)
            {
                var changeStatus = _changeTracker.GetChangeStatus();
                ChangeCountStatus.Content = $"Changes: {changeStatus?.ChangedTableCount ?? 0 + changeStatus?.NewTableCount ?? 0 + changeStatus?.RemovedTableCount ?? 0}";
            }
            else
            {
                ChangeCountStatus.Content = "Changes: 0";
            }
        }
        catch (Exception ex)
        {
            Logger.Debug("UpdateStatusBar error: {Message}", ex.Message);
            // Don't throw - just set defaults
            TableCountStatus.Content = "Tables: ?";
            ChangeCountStatus.Content = "Changes: ?";
        }
    }
    
    #endregion
    
    private async void CoreWebView2_WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            Logger.Debug("WebMessage received from JavaScript");
            var json = e.WebMessageAsJson;
            Logger.Debug("WebMessage JSON: {Json}", json?.Substring(0, Math.Min(200, json?.Length ?? 0)));
            
            if (string.IsNullOrEmpty(json))
            {
                Logger.Warn("WebMessage JSON is null or empty");
                return;
            }
            
            var message = JsonSerializer.Deserialize<WebMessage>(json);
            
            if (message == null)
            {
                Logger.Warn("WebMessage deserialized to null");
                return;
            }
            
            Logger.Info("Processing web message action: {Action}", message.Action);
            Logger.Debug("Message details - Action: {Action}, TableName: {Table}, Diagram length: {DiagramLen}, Original length: {OrigLen}, Edited length: {EditLen}",
                message.Action, message.TableName, message.Diagram?.Length ?? 0, message.Original?.Length ?? 0, message.Edited?.Length ?? 0);
            
            switch (message.Action)
            {
                case "generateFromDB":
                    Logger.Debug("Handling generateFromDB action");
                    await HandleGenerateFromDB();
                    break;
                    
                case "analyzeDiff":
                    Logger.Debug("Handling analyzeDiff action");
                    await HandleAnalyzeDiff(message.Original, message.Edited);
                    break;
                    
                case "generateDDL":
                    Logger.Debug("Handling generateDDL action");
                    await HandleGenerateDDL(message.Original, message.Edited);
                    break;
                    
                case "exportDiagram":
                    Logger.Debug("Handling exportDiagram action");
                    HandleExportDiagram(message.Diagram);
                    break;
                    
                case "openTableProperties":
                    Logger.Debug("Handling openTableProperties action for table: {Table}", message.TableName);
                    HandleOpenTableProperties(message.TableName);
                    break;
                    
                case "generateSqlFromMermaid":
                    Logger.Debug("Handling generateSqlFromMermaid action");
                    await HandleGenerateSqlFromMermaid(message.Diagram, message.Dialect);
                    break;
                    
                case "translateSqlDialect":
                    Logger.Debug("Handling translateSqlDialect action");
                    await HandleTranslateSqlDialect(message.SourceSql, message.SourceDialect, message.TargetDialect);
                    break;
                    
                case "generateMigrationAdvanced":
                    Logger.Debug("Handling generateMigrationAdvanced action");
                    await HandleGenerateMigrationAdvanced(message.Original, message.Edited, message.Dialect);
                    break;
                    
                case "editorContentChanged":
                    Logger.Debug("Handling editorContentChanged action - triggering diff check");
                    if (!string.IsNullOrEmpty(message.Diagram))
                    {
                        // Update change tracker with current editor content
                        _changeTracker.UpdateFromEditor(message.Diagram);
                        
                        // Update preview window if open
                        _previewWindow?.UpdatePreview(message.Diagram, _lastSelectedTables?.Count ?? 0);
                        
                        // Also trigger baseline comparison
                        _diffComparisonService.CheckForDifferences(message.Diagram);
                    }
                    break;
                    
                default:
                    Logger.Warn("Unknown web message action: {Action}", message.Action);
                    break;
            }
            
            Logger.Debug("Web message action completed: {Action}", message.Action);
        }
        catch (JsonException jsonEx)
        {
            Logger.Error(jsonEx, "Failed to deserialize web message JSON");
            Logger.Debug("Raw JSON: {Json}", e.WebMessageAsJson);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error handling web message");
            Logger.Debug("Exception type: {Type}", ex.GetType().Name);
            Logger.Debug("Stack trace: {StackTrace}", ex.StackTrace);
            
            MessageBox.Show(
                $"Error processing web message: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    private async Task HandleGenerateFromDB()
    {
        try
        {
            Logger.Info("========================================");
            Logger.Info("=== HandleGenerateFromDB START ===");
            Logger.Info("========================================");
            Logger.Info("Target schema: {Schema}", _targetSchema);
            Logger.Debug("Connection: {Connection}", _connectionManager.ConnectionInfo.Name);
            Logger.Debug("Step 1: Opening TableSelectionWithFKNavigationDialog");
            
            var dialog = new TableSelectionWithFKNavigationDialog(_connectionManager, _targetSchema);
            Logger.Debug("SchemaTableSelectionDialog created");
            
            var dialogResult = dialog.ShowDialog();
            Logger.Debug("SchemaTableSelectionDialog closed - Result: {Result}", dialogResult);
            
            if (dialogResult != true)
            {
                Logger.Info("User cancelled table selection");
                return;
            }
            
            var selectedTables = dialog.SelectedTables;
            Logger.Info("User selected {Count} tables", selectedTables.Count);
            
            if (selectedTables.Count == 0)
            {
                Logger.Warn("No tables selected by user");
                MessageBox.Show("No tables selected.", "Info", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            
            Logger.Debug("Step 2: Generating Mermaid diagram for {Count} tables", selectedTables.Count);
            foreach (var table in selectedTables)
            {
                Logger.Debug("  - Selected table: {Table}", table);
            }
            
            string mermaid;
            try
            {
                Logger.Debug(">>> Calling _generatorService.GenerateMermaidDiagramAsync...");
                mermaid = await _generatorService.GenerateMermaidDiagramAsync(_connectionManager, selectedTables);
                Logger.Info("Generator returned Mermaid: {Length} characters", mermaid?.Length ?? 0);
            }
            catch (Exception genEx)
            {
                Logger.Error(genEx, "GenerateMermaidDiagramAsync threw exception: {Type} - {Message}", 
                    genEx.GetType().Name, genEx.Message);
                throw;
            }
            
            if (string.IsNullOrEmpty(mermaid))
            {
                Logger.Error("GenerateMermaidDiagramAsync returned NULL or EMPTY!");
                throw new InvalidOperationException("Mermaid generator returned empty result");
            }
            
            Logger.Debug("First 300 chars of returned Mermaid:\n{Preview}", 
                mermaid.Length > 300 ? mermaid.Substring(0, 300) : mermaid);
            
            // CHECK FOR PROBLEMATIC TYPES IMMEDIATELY
            bool hasDecimal = mermaid.Contains("DECIMAL(");
            bool hasVarchar = mermaid.Contains("VARCHAR(");
            bool hasChar = mermaid.Contains("CHAR(");
            
            Logger.Debug("Checking returned Mermaid - DECIMAL(: {D}, VARCHAR(: {V}, CHAR(: {C}", 
                hasDecimal, hasVarchar, hasChar);
            
            // EMERGENCY FIX: Strip types right here if generator failed to do so
            if (hasDecimal || hasVarchar || hasChar)
            {
                Logger.Warn("!!! EMERGENCY: Generator FAILED to strip types - doing it NOW !!!");
                mermaid = EmergencyStripDataTypes(mermaid);
                Logger.Debug("After emergency strip: DECIMAL(: {D}, VARCHAR(: {V}", 
                    mermaid.Contains("DECIMAL("), mermaid.Contains("VARCHAR("));
            }
            
            _lastGeneratedMermaid = mermaid;
            _lastSelectedTables = selectedTables;
            
            // CRITICAL: Capture baseline snapshot
            try
            {
                await _baselineService.CaptureBaselineAsync(_connectionManager, selectedTables, mermaid);
                Logger.Info("Baseline snapshot captured for {Count} tables", selectedTables.Count);
            }
            catch (Exception baselineEx)
            {
                Logger.Error(baselineEx, "Failed to capture baseline - continuing anyway");
            }
            
            // Initialize change tracker with per-table hashing
            try
            {
                _changeTracker.InitializeFromOriginal(mermaid, selectedTables);
                Logger.Info("Change tracker initialized with {Count} tables", selectedTables.Count);
            }
            catch (Exception trackerEx)
            {
                Logger.Error(trackerEx, "Failed to initialize change tracker - continuing anyway");
            }
            
            // Enable Add Tables button after initial load
            AddMoreTablesButton.IsEnabled = true;
            
            // Update status bar safely
            try
            {
                UpdateStatusBar();
            }
            catch (Exception statusEx)
            {
                Logger.Error(statusEx, "Failed to update status bar");
            }
            
            Logger.Debug("Step 3: Injecting diagram into WebView2 editor");
            var escapedMermaid = EscapeForJavaScript(mermaid);
            Logger.Debug("Escaped Mermaid length: {Length}", escapedMermaid.Length);
            
            var script = $"setEditorContent(`{escapedMermaid}`);";
            Logger.Debug("Executing JavaScript: setEditorContent (length: {Length})", script.Length);
            
            await MermaidWebView.ExecuteScriptAsync(script);
            Logger.Debug("JavaScript setEditorContent executed successfully");
            
            // Final validation - check if any problematic types slipped through
            if (mermaid.Contains("DECIMAL(") || mermaid.Contains("VARCHAR(") || mermaid.Contains("CHAR("))
            {
                Logger.Warn("!!! WARNING: Final Mermaid STILL contains parameterized types !!!");
                Logger.Warn("This WILL cause Mermaid parse errors like 'Expecting ATTRIBUTE_WORD, got COMMA'");
                // Find and log problematic lines
                var lines = mermaid.Split('\n');
                for (int i = 0; i < lines.Length; i++)
                {
                    if (System.Text.RegularExpressions.Regex.IsMatch(lines[i], @"\w+\(\d"))
                    {
                        Logger.Warn("Problematic line {Num}: {Line}", i + 1, lines[i].Trim());
                    }
                }
            }
            else
            {
                Logger.Info("✓ Final Mermaid validation passed - no parameterized types detected");
            }
            
            Logger.Info("========================================");
            Logger.Info("=== HandleGenerateFromDB COMPLETE ===");
            Logger.Info("========================================");
            Logger.Info("Result: {Length} chars for {Count} tables", mermaid.Length, selectedTables.Count);
        }
        catch (InvalidOperationException invOpEx)
        {
            Logger.Error(invOpEx, "!!! InvalidOperationException in HandleGenerateFromDB !!!");
            Logger.Debug("Message: {Message}", invOpEx.Message);
            Logger.Debug("Stack: {Stack}", invOpEx.StackTrace);
            if (invOpEx.InnerException != null)
            {
                Logger.Error(invOpEx.InnerException, "Inner exception");
            }
            MessageBox.Show(
                $"Invalid operation: {invOpEx.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        catch (NullReferenceException nullEx)
        {
            Logger.Error(nullEx, "!!! NullReferenceException in HandleGenerateFromDB !!!");
            Logger.Debug("Message: {Message}", nullEx.Message);
            Logger.Debug("Stack: {Stack}", nullEx.StackTrace);
            MessageBox.Show(
                $"Null reference error: {nullEx.Message}\n\nCheck logs for details.",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "!!! Unexpected exception in HandleGenerateFromDB !!!");
            Logger.Debug("Exception type: {Type}", ex.GetType().Name);
            Logger.Debug("Exception message: {Message}", ex.Message);
            Logger.Debug("Stack trace: {StackTrace}", ex.StackTrace);
            
            if (ex.InnerException != null)
            {
                Logger.Error(ex.InnerException, "Inner exception");
                Logger.Debug("Inner type: {Type}, Message: {Msg}", 
                    ex.InnerException.GetType().Name, ex.InnerException.Message);
            }
            
            MessageBox.Show(
                $"Failed to generate diagram:\n\n{ex.Message}\n\nSee logs for details.",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Programmatically generate Mermaid diagram for testing automation.
    /// </summary>
    public async Task<string> GenerateDiagramAutomatedAsync(List<string> tableNames)
    {
        Logger.Info("Automated diagram generation for {Count} tables", tableNames.Count);
        Logger.Debug("Tables requested:");
        foreach (var table in tableNames)
        {
            Logger.Debug("  - {Table}", table);
        }
        
        try
        {
            Logger.Debug("Step 1: Calling MermaidDiagramGeneratorService.GenerateMermaidDiagramAsync");
            var mermaid = await _generatorService.GenerateMermaidDiagramAsync(_connectionManager, tableNames);
            Logger.Info("Diagram generated: {Length} characters", mermaid.Length);
            Logger.Debug("Mermaid preview (first 300 chars): {Preview}", mermaid.Substring(0, Math.Min(300, mermaid.Length)));
            
            _lastGeneratedMermaid = mermaid;
            _lastSelectedTables = tableNames;
            
            Logger.Debug("Step 2: Setting WebView2 editor content");
            await MermaidWebView.ExecuteScriptAsync($"setEditorContent(`{EscapeForJavaScript(mermaid)}`);");
            Logger.Debug("Editor content set successfully");
            
            Logger.Info("Automated diagram generated successfully: {Length} chars", mermaid.Length);
            return mermaid;
        }
        catch (IBM.Data.Db2.DB2Exception db2Ex)
        {
            Logger.Error(db2Ex, "DB2 error during automated diagram generation - SqlState: {SqlState}, ErrorCode: {ErrorCode}", 
                db2Ex.SqlState, db2Ex.ErrorCode);
            Logger.Debug("DB2 Exception details: {Details}", db2Ex.Message);
            throw;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Automated diagram generation failed");
            Logger.Debug("Exception type: {Type}", ex.GetType().Name);
            Logger.Debug("Exception message: {Message}", ex.Message);
            Logger.Debug("Stack trace: {StackTrace}", ex.StackTrace);
            throw;
        }
    }
    
    /// <summary>
    /// Extract data for testing automation.
    /// </summary>
    public object ExtractDataForTesting()
    {
        Logger.Info("Extracting Mermaid Designer data for testing automation");
        Logger.Debug("Target Schema: {Schema}", _targetSchema);
        Logger.Debug("IsDesignerLoaded: {Loaded}", IsDesignerLoaded);
        Logger.Debug("HasDiagram: {HasDiagram}", !string.IsNullOrEmpty(_lastGeneratedMermaid));
        Logger.Debug("MermaidLength: {Length}", _lastGeneratedMermaid?.Length ?? 0);
        Logger.Debug("SelectedTablesCount: {Count}", _lastSelectedTables?.Count ?? 0);
        
        var extractedData = new
        {
            TargetSchema = _targetSchema,
            IsLoaded = IsDesignerLoaded,
            LastGeneratedMermaid = _lastGeneratedMermaid,
            MermaidLength = _lastGeneratedMermaid?.Length ?? 0,
            SelectedTablesCount = _lastSelectedTables?.Count ?? 0,
            SelectedTables = _lastSelectedTables ?? new List<string>(),
            HasDiagram = !string.IsNullOrEmpty(_lastGeneratedMermaid)
        };
        
        Logger.Info("Data extraction complete - Schema: {Schema}, Diagram: {HasDiagram}, Tables: {Count}", 
            _targetSchema, extractedData.HasDiagram, extractedData.SelectedTablesCount);
        
        return extractedData;
    }
    
    private async Task HandleAnalyzeDiff(string? original, string? edited)
    {
        try
        {
            if (string.IsNullOrEmpty(original) || string.IsNullOrEmpty(edited))
            {
                Logger.Warn("Original or edited diagram is empty");
                return;
            }
            
            Logger.Info("Analyzing schema differences");
            
            var diff = _diffAnalyzer.AnalyzeDifferences(original, edited);
            
            var diffJson = JsonSerializer.Serialize(diff, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            
            await MermaidWebView.ExecuteScriptAsync($"displayDiff({diffJson});");
            
            Logger.Info("Diff analysis complete: {Changes} changes", diff.TotalChanges);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to analyze diff");
        }
    }
    
    /// <summary>
    /// ENHANCED: Generates ALTER statements and opens review dialog for safe execution.
    /// Uses SqlMermaidErdTools for migration DDL generation from Mermaid diff.
    /// </summary>
    private async Task HandleGenerateDDL(string? original, string? edited)
    {
        try
        {
            if (string.IsNullOrEmpty(original) || string.IsNullOrEmpty(edited))
            {
                MessageBox.Show(
                    "No changes to analyze.\n\n" +
                    "1. Click 'Show Diff' to capture baseline\n" +
                    "2. Modify the Mermaid diagram\n" +
                    "3. Click 'Show Diff' again to see changes\n" +
                    "4. Click 'Generate DDL' to create ALTER statements",
                    "Info", 
                    MessageBoxButton.OK, 
                    MessageBoxImage.Information);
                return;
            }
            
            Logger.Info("Generating ALTER statements from Mermaid diff using SqlMermaidErdTools");
            
            // Try SqlMermaidErdTools first for advanced migration
            string ddl;
            try
            {
                ddl = await _sqlMermaidService.GenerateMigrationFromMermaidDiffAsync(
                    original,
                    edited,
                    SqlMermaidErdTools.Models.SqlDialect.AnsiSql);
                
                Logger.Info("SqlMermaidErdTools generated migration: {Length} chars", ddl.Length);
            }
            catch (Exception sqlMermaidEx)
            {
                Logger.Warn(sqlMermaidEx, "SqlMermaidErdTools failed, using fallback DiffBasedDdlGenerator");
                
                // Fallback to legacy DiffBasedDdlGenerator
                ddl = await _ddlGenerator.GenerateMigrationScriptsAsync(
                    original,
                    edited,
                    _targetSchema,
                    SqlMermaidErdTools.Models.SqlDialect.AnsiSql);
            }
            
            // Check if migration has content
            if (string.IsNullOrWhiteSpace(ddl) || ddl.Contains("-- No changes detected"))
            {
                MessageBox.Show(
                    "No schema changes detected.\n\n" +
                    "The original and modified diagrams appear to be identical.",
                    "No Changes", 
                    MessageBoxButton.OK, 
                    MessageBoxImage.Information);
                return;
            }
            
            // Parse DDL into individual ALTER statements
            var alterStatements = ParseDdlIntoStatements(ddl);
            
            if (alterStatements.Count == 0)
            {
                MessageBox.Show(
                    "Generated DDL contains no executable statements.",
                    "No Statements",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                return;
            }
            
            Logger.Info("Parsed {Count} ALTER statements from DDL", alterStatements.Count);
            
            // Store diff DDL for opening in editor
            _currentDiffDdl = ddl;
            
            // Open diff script in SQL editor
            await OpenDiffScriptInEditorAsync(ddl);
            
            // Also open ALTER statement review dialog (optional - user can use either)
            var reviewDialog = new AlterStatementReviewDialog(alterStatements, _connectionManager);
            reviewDialog.Owner = this;
            
            var dialogResult = reviewDialog.ShowDialog();
            
            if (dialogResult == true && reviewDialog.StatementsExecuted)
            {
                Logger.Info("User executed {Count} ALTER statements successfully", reviewDialog.ExecutedCount);
                
                // Ask if user wants to reload diagram from DB to see changes
                var reloadResult = MessageBox.Show(
                    $"Successfully executed {reviewDialog.ExecutedCount} statement(s).\n\n" +
                    $"Reload diagram from database to see the changes?",
                    "Reload Diagram?",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);
                
                if (reloadResult == MessageBoxResult.Yes && _lastSelectedTables != null)
                {
                    // Reload diagram from same tables
                    var mermaid = await _generatorService.GenerateMermaidDiagramAsync(
                        _connectionManager,
                        _lastSelectedTables);
                    
                    _lastGeneratedMermaid = mermaid;
                    var escapedMermaid = EscapeForJavaScript(mermaid);
                    await MermaidWebView.ExecuteScriptAsync($"setEditorContent(`{escapedMermaid}`);");
                    
                    Logger.Info("Diagram reloaded from database successfully");
                }
            }
            else
            {
                Logger.Info("User closed ALTER review dialog without executing statements");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate DDL via SqlMermaidErdTools");
            MessageBox.Show(
                $"Failed to generate DDL: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    private void HandleExportDiagram(string? diagram)
    {
        try
        {
            if (string.IsNullOrEmpty(diagram))
            {
                Logger.Warn("Diagram is empty");
                return;
            }
            
            var saveDialog = new SaveFileDialog
            {
                Title = "Export Mermaid Diagram",
                Filter = "Mermaid Files (*.mmd)|*.mmd|Text Files (*.txt)|*.txt|All Files (*.*)|*.*",
                DefaultExt = ".mmd",
                FileName = $"diagram_{DateTime.Now:yyyyMMdd_HHmmss}.mmd"
            };
            
            if (saveDialog.ShowDialog() == true)
            {
                File.WriteAllText(saveDialog.FileName, diagram);
                Logger.Info("Diagram exported to: {File}", saveDialog.FileName);
                MessageBox.Show(
                    $"Diagram exported successfully to:\n{saveDialog.FileName}",
                    "Export Complete",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to export diagram");
            MessageBox.Show(
                $"Failed to export diagram: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    private void HandleOpenTableProperties(string? tableName)
    {
        try
        {
            if (string.IsNullOrEmpty(tableName))
            {
                Logger.Warn("Table name is empty");
                return;
            }
            
            Logger.Info("Opening table properties for: {Table}", tableName);
            
            var fullTableName = tableName.Contains(".") ? tableName : $"{_targetSchema}.{tableName}";
            var dialog = new TableDetailsDialog(_connectionManager, fullTableName);
            dialog.Owner = this;
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open table properties for: {Table}", tableName);
            MessageBox.Show(
                $"Failed to open table properties: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Parse SQL DDL into individual executable statements.
    /// Splits by semicolon and filters out comments.
    /// </summary>
    private List<string> ParseDdlIntoStatements(string ddl)
    {
        var statements = new List<string>();
        
        // Split by semicolon but preserve statements
        var lines = ddl.Split('\n');
        var currentStatement = new StringBuilder();
        
        foreach (var line in lines)
        {
            var trimmedLine = line.Trim();
            
            // Skip comments and empty lines
            if (trimmedLine.StartsWith("--") || string.IsNullOrWhiteSpace(trimmedLine))
            {
                continue;
            }
            
            currentStatement.AppendLine(line);
            
            // If line ends with semicolon, statement is complete
            if (trimmedLine.EndsWith(";"))
            {
                var statement = currentStatement.ToString().Trim();
                
                if (!string.IsNullOrWhiteSpace(statement))
                {
                    statements.Add(statement);
                }
                
                currentStatement.Clear();
            }
        }
        
        // Add any remaining statement
        if (currentStatement.Length > 0)
        {
            var statement = currentStatement.ToString().Trim();
            if (!string.IsNullOrWhiteSpace(statement))
            {
                statements.Add(statement);
            }
        }
        
        return statements;
    }
    
    private string EscapeForJavaScript(string text)
    {
        return text
            .Replace("\\", "\\\\")
            .Replace("`", "\\`")
            .Replace("$", "\\$")
            .Replace("\r", "\\r")
            .Replace("\n", "\\n");
    }
    
    /// <summary>
    /// EMERGENCY fallback to strip data type parameters if all other methods fail.
    /// This is the last line of defense against Mermaid parse errors.
    /// </summary>
    private string EmergencyStripDataTypes(string mermaid)
    {
        Logger.Info("=== EMERGENCY STRIP DATA TYPES ===");
        Logger.Debug("Input length: {Len} chars", mermaid.Length);
        
        var result = mermaid;
        int totalChanges = 0;
        
        // List of all known types that might have parameters
        var knownTypes = new[] { 
            "VARCHAR", "CHAR", "CHARACTER", "NVARCHAR", "NCHAR",
            "DECIMAL", "NUMERIC", "DEC", "NUMBER", "MONEY",
            "INTEGER", "INT", "BIGINT", "SMALLINT", "TINYINT",
            "FLOAT", "DOUBLE", "REAL",
            "TIMESTAMP", "DATETIME", "DATE", "TIME",
            "BLOB", "CLOB", "TEXT", "BINARY", "VARBINARY"
        };
        
        // For each known type, strip any parentheses that follow
        foreach (var typeName in knownTypes)
        {
            // Pattern: TYPE followed by optional whitespace and parentheses with anything inside
            var pattern = $@"\b{typeName}\s*\([^)]*\)";
            var matches = System.Text.RegularExpressions.Regex.Matches(result, pattern, 
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            
            if (matches.Count > 0)
            {
                Logger.Debug("Stripping {Count} instances of {Type}(...)", matches.Count, typeName);
                result = System.Text.RegularExpressions.Regex.Replace(result, pattern, typeName, 
                    System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                totalChanges += matches.Count;
            }
        }
        
        // Also catch any generic WORD(number...) patterns we might have missed
        var genericPattern = @"\b([A-Z_][A-Z0-9_]*)\s*\(\s*\d[^)]*\)";
        var genericMatches = System.Text.RegularExpressions.Regex.Matches(result, genericPattern,
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        if (genericMatches.Count > 0)
        {
            Logger.Debug("Generic pattern found {Count} additional matches", genericMatches.Count);
            result = System.Text.RegularExpressions.Regex.Replace(result, genericPattern, "$1",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            totalChanges += genericMatches.Count;
        }
        
        Logger.Info("Emergency strip complete: {Count} total replacements", totalChanges);
        Logger.Debug("Output length: {Len} chars", result.Length);
        
        return result;
    }
    
    /// <summary>
    /// NEW: Generates SQL DDL from Mermaid ERD using SqlMermaidErdTools.
    /// Supports multiple SQL dialects (ANSI, SQL Server, PostgreSQL, MySQL).
    /// </summary>
    private async Task HandleGenerateSqlFromMermaid(string? mermaidDiagram, string? dialectName)
    {
        try
        {
            if (string.IsNullOrEmpty(mermaidDiagram))
            {
                MessageBox.Show("Mermaid diagram is empty.", "Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            Logger.Info("Generating SQL DDL from Mermaid - Dialect: {Dialect}", dialectName ?? "AnsiSql");
            
            // Parse dialect (default to ANSI SQL)
            var dialect = ParseSqlDialect(dialectName);
            
            // Convert Mermaid to SQL
            var sql = await _sqlMermaidService.ConvertMermaidToSqlAsync(mermaidDiagram, dialect);
            
            // Send result back to JavaScript
            await MermaidWebView.ExecuteScriptAsync($"showGeneratedSql(`{EscapeForJavaScript(sql)}`, '{dialect}');");
            
            Logger.Info("SQL DDL generated successfully - {Length} characters", sql.Length);
            MessageBox.Show(
                $"SQL DDL generated successfully!\n\nDialect: {dialect}\nLength: {sql.Length} characters",
                "Success",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate SQL from Mermaid");
            MessageBox.Show(
                $"Failed to generate SQL DDL:\n\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// NEW: Translates SQL from one dialect to another using SqlMermaidErdTools.
    /// Example: DB2 SQL → PostgreSQL, SQL Server → MySQL, etc.
    /// </summary>
    private async Task HandleTranslateSqlDialect(string? sourceSql, string? sourceDialectName, string? targetDialectName)
    {
        try
        {
            if (string.IsNullOrEmpty(sourceSql))
            {
                MessageBox.Show("Source SQL is empty.", "Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            var sourceDialect = ParseSqlDialect(sourceDialectName);
            var targetDialect = ParseSqlDialect(targetDialectName);
            
            Logger.Info("Translating SQL: {Source} → {Target}", sourceDialect, targetDialect);
            
            // Translate SQL
            var translatedSql = await _sqlMermaidService.TranslateSqlDialectAsync(sourceSql, sourceDialect, targetDialect);
            
            // Send result back to JavaScript
            await MermaidWebView.ExecuteScriptAsync($"showTranslatedSql(`{EscapeForJavaScript(translatedSql)}`, '{sourceDialect}', '{targetDialect}');");
            
            Logger.Info("SQL translation complete - {Length} characters", translatedSql.Length);
            MessageBox.Show(
                $"SQL translation successful!\n\nFrom: {sourceDialect}\nTo: {targetDialect}\nLength: {translatedSql.Length} characters",
                "Success",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to translate SQL");
            MessageBox.Show(
                $"Failed to translate SQL:\n\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// NEW: Generates migration DDL using advanced SqlMermaidErdTools diff algorithm.
    /// Produces ALTER statements for schema changes.
    /// </summary>
    private async Task HandleGenerateMigrationAdvanced(string? beforeMermaid, string? afterMermaid, string? dialectName)
    {
        try
        {
            if (string.IsNullOrEmpty(beforeMermaid) || string.IsNullOrEmpty(afterMermaid))
            {
                MessageBox.Show("Both before and after Mermaid diagrams are required.", "Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            var dialect = ParseSqlDialect(dialectName);
            Logger.Info("Generating advanced migration DDL - Dialect: {Dialect}", dialect);
            
            // Generate migration scripts using SqlMermaidErdTools
            var migrationDdl = await _sqlMermaidService.GenerateMigrationFromMermaidDiffAsync(
                beforeMermaid,
                afterMermaid,
                dialect);
            
            // Send result back to JavaScript
            await MermaidWebView.ExecuteScriptAsync($"showMigrationDdl(`{EscapeForJavaScript(migrationDdl)}`, '{dialect}');");
            
            Logger.Info("Migration DDL generated - {Length} characters", migrationDdl.Length);
            MessageBox.Show(
                $"Migration DDL generated successfully!\n\nDialect: {dialect}\nStatements: {CountSqlStatements(migrationDdl)}",
                "Success",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate migration DDL");
            MessageBox.Show(
                $"Failed to generate migration DDL:\n\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Parses SQL dialect name to SqlDialect enum.
    /// </summary>
    private SqlMermaidErdTools.Models.SqlDialect ParseSqlDialect(string? dialectName)
    {
        if (string.IsNullOrEmpty(dialectName))
            return SqlMermaidErdTools.Models.SqlDialect.AnsiSql;
        
        return dialectName.ToUpperInvariant() switch
        {
            "ANSI" or "ANSISQL" or "SQL" => SqlMermaidErdTools.Models.SqlDialect.AnsiSql,
            "SQLSERVER" or "TSQL" or "MSSQL" => SqlMermaidErdTools.Models.SqlDialect.SqlServer,
            "POSTGRESQL" or "POSTGRES" or "PG" => SqlMermaidErdTools.Models.SqlDialect.PostgreSql,
            "MYSQL" or "MARIADB" => SqlMermaidErdTools.Models.SqlDialect.MySql,
            _ => SqlMermaidErdTools.Models.SqlDialect.AnsiSql
        };
    }
    
    /// <summary>
    /// Counts SQL statements (semicolon-separated).
    /// </summary>
    private int CountSqlStatements(string sql)
    {
        return sql.Split(';', StringSplitOptions.RemoveEmptyEntries).Length;
    }
    
    /// <summary>
    /// Handler for diff detection events from MermaidDiffComparisonService.
    /// </summary>
    private void DiffComparisonService_DiffDetected(object? sender, DiffDetectedEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            if (e.HasChanges)
            {
                Logger.Info("Diff detected: {Message}", e.Message);
                _currentDiffDdl = e.DiffDdl;
                
                // Update status (would need to add status text block to XAML)
                // For now, we'll just log it
                Logger.Debug("Changes detected - {Count} change(s), DDL length: {Length}", 
                    e.ChangeCount, e.DiffDdl?.Length ?? 0);
            }
            else
            {
                Logger.Debug("No changes detected: {Message}", e.Message);
                _currentDiffDdl = null;
            }
        });
    }
    
    /// <summary>
    /// Opens generated diff script in SQL editor with same connection.
    /// Adds encoding header for proper character handling (Norwegian/special chars).
    /// </summary>
    private async Task OpenDiffScriptInEditorAsync(string diffDdl)
    {
        try
        {
            Logger.Info("Opening diff script in SQL editor - {Length} characters", diffDdl.Length);
            
            // Add header with encoding information and warnings
            var scriptWithHeader = new StringBuilder();
            scriptWithHeader.AppendLine("-- =============================================================================");
            scriptWithHeader.AppendLine("-- MIGRATION SCRIPT - Generated from Mermaid ERD Diff");
            scriptWithHeader.AppendLine($"-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            scriptWithHeader.AppendLine($"-- Connection: {_connectionManager.ConnectionInfo.Name}");
            scriptWithHeader.AppendLine("-- ");
            scriptWithHeader.AppendLine("-- ENCODING: UTF-8 (ensure database supports Unicode/CCSID 1208 for special chars)");
            scriptWithHeader.AppendLine("-- WARNING: Review all statements carefully before executing!");
            scriptWithHeader.AppendLine("-- Norwegian chars (ÆØÅ) require proper database CCSID configuration.");
            scriptWithHeader.AppendLine("-- =============================================================================");
            scriptWithHeader.AppendLine();
            scriptWithHeader.Append(diffDdl);
            
            var finalScript = scriptWithHeader.ToString();
            
            // Find or create connection tab with same connection
            var connectionInfo = _connectionManager.ConnectionInfo;
            var connectionTab = FindOrCreateConnectionTab(connectionInfo);
            
            if (connectionTab == null)
            {
                Logger.Error("Could not find or create connection tab");
                MessageBox.Show(
                    "Could not open SQL editor. Please ensure a connection tab is available.",
                    "Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                return;
            }
            
            // Load diff script into SQL editor (with encoding header)
            connectionTab.LoadScriptIntoEditor(finalScript, "Migration Script from Mermaid Diff");
            
            // Switch to the connection tab
            SwitchToConnectionTab(connectionTab);
            
            // Show confirmation
            MessageBox.Show(
                $"Migration script loaded into SQL editor.\n\n" +
                $"Connection: {connectionInfo.Name}\n" +
                $"Script length: {finalScript.Length} characters\n\n" +
                $"⚠️ REVIEW CAREFULLY before executing (F5)",
                "Diff Script Loaded",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            
            Logger.Info("Diff script successfully loaded into SQL editor");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open diff script in editor");
            MessageBox.Show(
                $"Failed to open diff script in editor:\n\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Finds or creates a connection tab for the specified connection.
    /// </summary>
    private Controls.ConnectionTabControl? FindOrCreateConnectionTab(Models.IConnectionInfo connectionInfo)
    {
        // Try to find MainWindow instance
        var mainWindow = Application.Current.Windows.OfType<MainWindow>().FirstOrDefault();
        if (mainWindow == null)
        {
            Logger.Warn("MainWindow not found");
            return null;
        }
        
        // Check if tab already exists for this connection
        foreach (System.Windows.Controls.TabItem tabItem in mainWindow.ConnectionTabs.Items)
        {
            if (tabItem.Content is Controls.ConnectionTabControl tab)
            {
                if (tab.ConnectionManager.ConnectionInfo.Name == connectionInfo.Name)
                {
                    Logger.Debug("Found existing connection tab: {Connection}", connectionInfo.Name);
                    return tab;
                }
            }
        }
        
        // Use the currently selected tab if available
        if (mainWindow.ConnectionTabs.SelectedItem is System.Windows.Controls.TabItem selectedItem &&
            selectedItem.Content is Controls.ConnectionTabControl selectedTab)
        {
            Logger.Info("No exact match found for {Connection}, using currently selected tab", connectionInfo.Name);
            return selectedTab;
        }
        
        // Use the first available tab
        if (mainWindow.ConnectionTabs.Items.Count > 0 &&
            mainWindow.ConnectionTabs.Items[0] is System.Windows.Controls.TabItem firstItem &&
            firstItem.Content is Controls.ConnectionTabControl firstTab)
        {
            Logger.Info("Using first available connection tab");
            return firstTab;
        }
        
        Logger.Warn("No connection tabs available");
        return null;
    }
    
    /// <summary>
    /// Switches to the specified connection tab.
    /// </summary>
    private void SwitchToConnectionTab(Controls.ConnectionTabControl tab)
    {
        var mainWindow = Application.Current.Windows.OfType<MainWindow>().FirstOrDefault();
        if (mainWindow == null) return;
        
        // Find tab item containing this control
        foreach (System.Windows.Controls.TabItem item in mainWindow.ConnectionTabs.Items)
        {
            if (item.Content == tab)
            {
                mainWindow.ConnectionTabs.SelectedItem = item;
                Logger.Debug("Switched to connection tab");
                break;
            }
        }
    }
    
    private class WebMessage
    {
        public string Action { get; set; } = string.Empty;
        public string? Original { get; set; }
        public string? Edited { get; set; }
        public string? Diagram { get; set; }
        public string? TableName { get; set; }
        
        // NEW: Properties for SqlMermaidErdTools features
        public string? Dialect { get; set; }
        public string? SourceSql { get; set; }
        public string? SourceDialect { get; set; }
        public string? TargetDialect { get; set; }
    }
}

