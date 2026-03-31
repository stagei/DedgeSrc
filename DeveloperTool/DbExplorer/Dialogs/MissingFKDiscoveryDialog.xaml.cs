using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;
using Microsoft.Win32;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

/// <summary>
/// Dialog for Missing FK Discovery feature.
/// Allows users to select tables, configure options, and start batch job.
/// </summary>
public partial class MissingFKDiscoveryDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly IConnectionManager _connectionManager;
    private readonly MissingFKSqlTranslationService _sqlTranslationService;
    private readonly MissingFKMetadataService _metadataService;
    private readonly MissingFKIgnoreService _ignoreService;
    private readonly MissingFKIgnoreHistoryService _ignoreHistoryService;
    private readonly MissingFKJobStatusService _jobStatusService;
    private readonly MissingFKSearchHistoryService _searchHistoryService;
    private readonly string _connectionProfile;
    
    private List<string> _availableSchemas = new();
    private List<TableSelectionItem> _allTables = new();
    private List<TableSelectionItem> _selectedTables = new();
    private string _outputFolder = string.Empty;
    private string _ignoreJsonPath = string.Empty;
    private string _ignoreFilesFolder = string.Empty;
    private string _jobId = string.Empty;
    private Process? _runningJobProcess;
    private FileSystemWatcher? _statusFileWatcher;
    private FileSystemWatcher? _logFileWatcher;
    private Timer? _statusPollTimer;
    private Timer? _logPollTimer;
    private MissingFKIgnoreModel _currentIgnoreModel = new();
    private ObservableCollection<MissingFKIgnoreColumn> _ignoreColumnsCollection = new();
    
    public MissingFKDiscoveryDialog(IConnectionManager connectionManager, string connectionProfile)
    {
        Logger.Debug("MissingFKDiscoveryDialog constructor started");
        
        try
        {
            InitializeComponent();
            Logger.Debug("InitializeComponent completed");
            
            _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));
            _connectionProfile = connectionProfile ?? throw new ArgumentNullException(nameof(connectionProfile));
            Logger.Debug("Connection manager and profile set: {Profile}", _connectionProfile);
            
            // Initialize services
            Logger.Debug("Initializing services...");
            var sqlMermaidService = new SqlMermaidIntegrationService();
            Logger.Debug("SqlMermaidIntegrationService created");
            
            _sqlTranslationService = new MissingFKSqlTranslationService(sqlMermaidService);
            Logger.Debug("MissingFKSqlTranslationService created");
            
            _metadataService = new MissingFKMetadataService(_sqlTranslationService, _connectionManager);
            Logger.Debug("MissingFKMetadataService created");
            
            _ignoreService = new MissingFKIgnoreService();
            Logger.Debug("MissingFKIgnoreService created");
            
            _ignoreHistoryService = new MissingFKIgnoreHistoryService();
            Logger.Debug("MissingFKIgnoreHistoryService created");
            
            _jobStatusService = new MissingFKJobStatusService();
            Logger.Debug("MissingFKJobStatusService created");
            
            _searchHistoryService = new MissingFKSearchHistoryService();
            Logger.Debug("MissingFKSearchHistoryService created");
            
            // Set default output folder to user's data folder MissingFK/Projects
            // Note: The actual project subfolder will be created when starting a job
            _outputFolder = UserDataFolderHelper.GetMissingFKProjectsFolder();
            Logger.Debug("Output base folder path: {Path}", _outputFolder);
            
            OutputFolderTextBox.Text = _outputFolder;
            Logger.Debug("Output folder textbox set");
            
            // Create dedicated folder for ignore patterns
            _ignoreFilesFolder = UserDataFolderHelper.GetMissingFKIgnorePatternsFolder();
            Logger.Info("Ignore patterns folder: {Path}", _ignoreFilesFolder);
            
            // Initialize ignore model summary
            Logger.Debug("Updating ignore rules summary...");
            UpdateIgnoreRulesSummary();
            Logger.Debug("Ignore rules summary updated");
            
            Loaded += MissingFKDiscoveryDialog_Loaded;
            Closing += MissingFKDiscoveryDialog_Closing;
            Activated += MissingFKDiscoveryDialog_Activated;
            MainTabControl.SelectionChanged += MainTabControl_SelectionChanged;
            
            Logger.Info("MissingFKDiscoveryDialog constructor completed successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Exception in MissingFKDiscoveryDialog constructor");
            throw;
        }
    }
    
    private void MissingFKDiscoveryDialog_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        StopJobStatusMonitoring();
        StopLogFileMonitoring();
    }

    /// <summary>
    /// When dialog is activated (e.g. user switches back), re-check if job is still running.
    /// Re-enables Start Batch Job button if job ended or PID was reused.
    /// </summary>
    private void MissingFKDiscoveryDialog_Activated(object? sender, EventArgs e)
    {
        if (!StartBatchJobButton.IsEnabled && _jobStatusService.GetRunningJobIfActive() == null)
        {
            Logger.Info("Job no longer running on dialog activation, re-enabling Start Batch Job button");
            OnJobCompleted();
        }
    }

    private async void MissingFKDiscoveryDialog_Loaded(object sender, RoutedEventArgs e)
    {
        Logger.Debug("MissingFKDiscoveryDialog_Loaded event started");
        
        try
        {
            Logger.Info("Loading schemas for Missing FK Discovery");
            ShowLoading("Loading schemas from database...");
            
            // Apply UI styles
            Logger.Debug("Applying UI styles");
            UIStyleService.ApplyStyles(this);
            
            // Only load schemas initially, not tables
            Logger.Debug("Calling LoadSchemasAsync");
            await LoadSchemasAsync();
            Logger.Debug("LoadSchemasAsync completed, populating schema combobox");
            
            PopulateSchemaComboBox();
            Logger.Debug("PopulateSchemaComboBox completed");
            
            HideLoading();
            StatusText.Text = "Ready - Please select a schema to load tables";
            TablesList.ItemsSource = new List<TableSelectionItem>(); // Empty list until schema selected
            
            // Check if a job is already running and update button state accordingly
            CheckExistingJobLock();

            Logger.Info("MissingFKDiscoveryDialog loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load schemas in MissingFKDiscoveryDialog_Loaded");
            HideLoading();
            MessageBox.Show(
                $"An error occurred:\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }
    
    private Storyboard? _spinnerStoryboard;

    private void ShowLoading(string message)
    {
        LoadingText.Text = message;
        LoadingOverlay.Visibility = Visibility.Visible;
        StartSpinnerAnimation();
    }
    
    private void HideLoading()
    {
        StopSpinnerAnimation();
        LoadingOverlay.Visibility = Visibility.Collapsed;
    }

    private void StartSpinnerAnimation()
    {
        try
        {
            _spinnerStoryboard = new Storyboard();
            var animation = new DoubleAnimation
            {
                From = 0,
                To = 360,
                Duration = TimeSpan.FromSeconds(1),
                RepeatBehavior = RepeatBehavior.Forever
            };
            Storyboard.SetTarget(animation, SpinnerRotateTransform);
            Storyboard.SetTargetProperty(animation, new PropertyPath(System.Windows.Media.RotateTransform.AngleProperty));
            _spinnerStoryboard.Children.Add(animation);
            _spinnerStoryboard.Begin();
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Failed to start spinner animation");
        }
    }

    private void StopSpinnerAnimation()
    {
        try
        {
            _spinnerStoryboard?.Stop();
            _spinnerStoryboard = null;
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Failed to stop spinner animation");
        }
    }

    /// <summary>
    /// Check if a job is already running and update UI accordingly.
    /// Also provides option to clear stale locks.
    /// </summary>
    private void CheckExistingJobLock()
    {
        try
        {
            // Clean up old status files first
            _jobStatusService.CleanupOldStatusFiles();
            
            // Check if a job is running using PID-based approach
            var runningJob = _jobStatusService.GetRunningJobIfActive();
            if (runningJob != null)
            {
                var jobAge = DateTime.UtcNow - runningJob.StartedAtUtc;
                
                // Job is actually running - disable button and attach to process
                StartBatchJobButton.IsEnabled = false;
                StartBatchJobButton.Content = "Job Running...";
                StatusText.Text = $"A job is running (PID: {runningJob.ProcessId}, started {jobAge.TotalMinutes:F0} minutes ago)";
                Logger.Info("Existing job detected - PID: {Pid}, JobId: {JobId}, Age: {Age} minutes", 
                    runningJob.ProcessId, runningJob.JobId, jobAge.TotalMinutes);
                
                // Update job ID and output folder for monitoring
                _jobId = runningJob.JobId;
                _outputFolder = runningJob.ProjectFolder;
                OutputFolderTextBox.Text = _outputFolder;
                
                // Attach to the running process to detect when it completes
                AttachToRunningJobProcess(runningJob.ProcessId);
                
                // Start log file monitoring and status polling (so we re-enable button when job ends or PID reused)
                StartLogFileMonitoring(_outputFolder);
                StartJobStatusMonitoring(_jobId, _outputFolder);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to check existing job");
        }
    }

    /// <summary>
    /// Attach to a running job process to detect when it completes.
    /// </summary>
    private void AttachToRunningJobProcess(int processId)
    {
        try
        {
            _runningJobProcess = Process.GetProcessById(processId);
            _runningJobProcess.EnableRaisingEvents = true;
            _runningJobProcess.Exited += OnJobProcessExited;
            
            Logger.Info("Attached to running job process - PID: {Pid}", processId);
            JobStatusText.Text = $"Job running (PID: {processId}) - Monitoring...";
            JobStatusText.Foreground = System.Windows.Media.Brushes.Green;
        }
        catch (ArgumentException)
        {
            // Process no longer exists - clean up
            Logger.Info("Job process no longer exists (PID: {Pid}), clearing status", processId);
            _jobStatusService.ClearRunningJob();
            OnJobCompleted();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to attach to running job process");
        }
    }
    
    /// <summary>
    /// Called when the job process exits. Immediately re-enables the start button.
    /// </summary>
    private void OnJobProcessExited(object? sender, EventArgs e)
    {
        Logger.Info("Job process exited");
        
        Dispatcher.Invoke(() =>
        {
            // Clear the running job file
            _jobStatusService.ClearRunningJob();
            
            // Re-enable the start button
            OnJobCompleted();
            
            // Use log notification line for balloon message when available; fallback to results file
            var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
            if (File.Exists(logPath))
            {
                var logContent = File.ReadAllText(logPath);
                var (success, message) = ParseLogNotificationLine(logContent);
                ShowJobCompletionNotification(success, message);
            }
            else
            {
                var resultsPath = Path.Combine(_outputFolder, "missing_fk_results.json");
                if (File.Exists(resultsPath))
                    ShowJobCompletionNotification(true, "Missing FK Discovery job completed successfully.");
            }
        });
    }
    
    /// <summary>
    /// Called when a job completes (successfully or not). Re-enables UI.
    /// </summary>
    private void OnJobCompleted()
    {
        StartBatchJobButton.IsEnabled = true;
        StartBatchJobButton.Content = "Start Batch Job";
        JobStatusText.Text = "Job completed";
        JobStatusText.Foreground = System.Windows.Media.Brushes.Green;
        ViewJobLogButton.IsEnabled = true;
        
        // Update log one final time and parse notification line for status
        var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
        if (File.Exists(logPath))
        {
            LoadLogFileContent(logPath);
            var content = File.ReadAllText(logPath);
            var (_, statusMessage) = ParseLogNotificationLine(content);
            JobProgressStatusText.Text = string.IsNullOrEmpty(statusMessage) ? "Job completed" : statusMessage;
        }
        else
        {
            JobProgressStatusText.Text = "Job completed";
        }
        
        StopJobStatusMonitoring();
        StopLogFileMonitoring();
        
        _runningJobProcess = null;
    }
    
    private void MainTabControl_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MainTabControl.SelectedItem == JobProgressTab && !string.IsNullOrEmpty(_outputFolder))
        {
            var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
            LoadLogFileContent(logPath);
        }
    }
    
    /// <summary>
    /// Load only schemas (not tables) for initial population.
    /// </summary>
    private async Task LoadSchemasAsync()
    {
        Logger.Debug("Loading schemas");
        
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = provider == "POSTGRESQL" ? "18" : "12.1";
        
        // Use MetadataHandler to get SQL for listing schemas
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        var schemasSql = metadataHandler.GetQuery(provider, version, "GetSchemasStatement");
        var schemasResult = await _connectionManager.ExecuteQueryAsync(schemasSql);
        
        var schemas = new List<string>();
        foreach (DataRow schemaRow in schemasResult.Rows)
        {
            var schema = schemaRow["SCHEMANAME"]?.ToString()?.Trim() ?? string.Empty;
            if (!string.IsNullOrEmpty(schema) && !schema.StartsWith("SYS", StringComparison.OrdinalIgnoreCase))
            {
                schemas.Add(schema);
            }
        }
        
        // Store schemas for later use
        _availableSchemas = schemas.OrderBy(s => s).ToList();
        
        Logger.Info("Loaded {Count} schemas", _availableSchemas.Count);
    }
    
    /// <summary>
    /// Load tables for a specific schema.
    /// </summary>
    private async Task LoadTablesForSchemaAsync(string schema)
    {
        Logger.Debug("Loading tables for schema: {Schema}", schema);
        
        if (string.IsNullOrEmpty(schema) || schema == "All")
        {
            _allTables.Clear();
            RefreshTableList();
            return;
        }
        
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = provider == "POSTGRESQL" ? "18" : "12.1";
        
        // Use MetadataHandler to get SQL for listing tables
        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
        var sql = metadataHandler.GetQuery(provider, version, "GetTablesForSchema");
        
        // Get tables for this schema
        var tablesSql = ReplaceParameters(sql, schema);
        var tablesResult = await _connectionManager.ExecuteQueryAsync(tablesSql);
        
        _allTables.Clear();
        foreach (DataRow row in tablesResult.Rows)
        {
            var tableName = row["TABNAME"]?.ToString()?.Trim() ?? string.Empty;
            if (!string.IsNullOrEmpty(tableName))
            {
                _allTables.Add(new TableSelectionItem
                {
                    Schema = schema,
                    TableName = tableName,
                    IsSelected = false
                });
            }
        }
        
        Logger.Info("Loaded {Count} tables from schema {Schema}", _allTables.Count, schema);
        RefreshTableList();
        StatusText.Text = $"Ready - {_allTables.Count} tables loaded from schema {schema}";
    }
    
    private void PopulateSchemaComboBox()
    {
        SchemaComboBox.Items.Clear();
        SchemaComboBox.Items.Add("All");
        foreach (var schema in _availableSchemas)
        {
            SchemaComboBox.Items.Add(schema);
        }
        SchemaComboBox.SelectedIndex = 0;
    }
    
    private async void RefreshTableList()
    {
        var searchText = SearchTextBox.Text?.Trim() ?? string.Empty;
        var selectedSchema = SchemaComboBox.SelectedItem?.ToString() ?? "All";
        var searchType = (SearchTypeComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "TableName";
        var patternType = (PatternTypeComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "Standard";
        
        List<TableSelectionItem> filtered;
        
        if (string.IsNullOrEmpty(searchText))
        {
            // No search - show all tables in selected schema
            filtered = _allTables.Where(t =>
                selectedSchema == "All" || t.Schema == selectedSchema
            ).ToList();
        }
        else if (searchType == "ColumnName")
        {
            // Search by column name - need to query database
            filtered = await SearchTablesByColumnNameAsync(searchText, selectedSchema, patternType);
        }
        else
        {
            // Search by table name
            if (patternType == "Regex")
            {
                try
                {
                    var regex = new System.Text.RegularExpressions.Regex(searchText, 
                        System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                    filtered = _allTables.Where(t =>
                        (regex.IsMatch(t.TableName) || regex.IsMatch(t.Schema)) &&
                        (selectedSchema == "All" || t.Schema == selectedSchema)
                    ).ToList();
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, "Invalid regex pattern: {Pattern}", searchText);
                    MessageBox.Show($"Invalid regex pattern: {ex.Message}", "Regex Error",
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    filtered = _allTables.Where(t =>
                        selectedSchema == "All" || t.Schema == selectedSchema
                    ).ToList();
                }
            }
            else
            {
                // Standard search
                var searchLower = searchText.ToLowerInvariant();
                filtered = _allTables.Where(t =>
                    (t.TableName.ToLowerInvariant().Contains(searchLower) || t.Schema.ToLowerInvariant().Contains(searchLower)) &&
                    (selectedSchema == "All" || t.Schema == selectedSchema)
                ).ToList();
            }
        }
        
        TablesList.ItemsSource = filtered;
        
        // Enable/disable "Add All from Search" button based on whether search is active
        AddAllFromSearchButton.IsEnabled = !string.IsNullOrWhiteSpace(searchText) && filtered.Count > 0;
        
        // Auto-save search pattern to history (include schema when not "All")
        if (!string.IsNullOrWhiteSpace(searchText))
        {
            try
            {
                var schemaForHistory = (selectedSchema == "All" || string.IsNullOrWhiteSpace(selectedSchema)) ? null : selectedSchema;
                _searchHistoryService.SaveSearchPattern(searchText, searchType, patternType, schemaForHistory);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to save search pattern to history");
            }
        }
        
        UpdateSelectionCounts();
    }
    
    private async Task<List<TableSelectionItem>> SearchTablesByColumnNameAsync(string searchPattern, string selectedSchema, string patternType)
    {
        try
        {
            Logger.Debug("Searching tables by column name: {Pattern}, Schema: {Schema}, Type: {Type}", 
                searchPattern, selectedSchema, patternType);
            
            var matchingTables = new HashSet<TableSelectionItem>();
            var schemasToSearch = selectedSchema == "All" 
                ? _availableSchemas 
                : new List<string> { selectedSchema };
            
            foreach (var schema in schemasToSearch)
            {
                // Get all tables in this schema
                var schemaTables = _allTables.Where(t => t.Schema == schema).ToList();
                
                foreach (var table in schemaTables)
                {
                    try
                    {
                        // Get columns for this table
                        var sqlTemplate = await _sqlTranslationService.GetTranslatedStatementAsync(_connectionManager, "GetTableColumnsForMissingFK");
                        // Replace parameters - need to handle multiple ? placeholders
                        var parts = sqlTemplate.Split('?');
                        if (parts.Length >= 3)
                        {
                            var sql = $"{parts[0]}'{schema}'{parts[1]}'{table.TableName}'{parts[2]}";
                            if (parts.Length > 3)
                                sql += string.Join("", parts.Skip(3));
                            
                            var columnsResult = await _connectionManager.ExecuteQueryAsync(sql);
                            
                            var columnNames = new List<string>();
                            
                            foreach (DataRow row in columnsResult.Rows)
                            {
                                var colName = row["COLUMN_NAME"]?.ToString()?.Trim() ?? 
                                             row["COLNAME"]?.ToString()?.Trim() ?? string.Empty;
                                if (!string.IsNullOrEmpty(colName))
                                    columnNames.Add(colName);
                            }
                            
                            // Check if any column matches the pattern
                            bool matches = false;
                            if (patternType == "Regex")
                            {
                                try
                                {
                                    var regex = new System.Text.RegularExpressions.Regex(searchPattern, 
                                        System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                                    matches = columnNames.Any(col => regex.IsMatch(col));
                                }
                                catch
                                {
                                    // Invalid regex - skip this table
                                    continue;
                                }
                            }
                            else
                            {
                                var patternLower = searchPattern.ToLowerInvariant();
                                matches = columnNames.Any(col => col.ToLowerInvariant().Contains(patternLower));
                            }
                            
                            if (matches)
                            {
                                matchingTables.Add(table);
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Logger.Debug(ex, "Failed to get columns for {Schema}.{Table}", schema, table.TableName);
                        // Continue with next table
                    }
                }
            }
            
            Logger.Info("Found {Count} tables matching column name pattern '{Pattern}'", matchingTables.Count, searchPattern);
            return matchingTables.ToList();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to search tables by column name");
            MessageBox.Show($"Failed to search by column name:\n{ex.Message}", "Search Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return _allTables.Where(t => selectedSchema == "All" || t.Schema == selectedSchema).ToList();
        }
    }
    
    private void UpdateSelectionCounts()
    {
        var selected = _allTables.Where(t => t.IsSelected).ToList();
        LeftSelectionCountText.Text = $"Available: {_allTables.Count} | Selected: {selected.Count}";
        
        _selectedTables = selected;
        SelectedTablesList.ItemsSource = _selectedTables.Select(t => new TableReference
        {
            Schema = t.Schema,
            Name = t.TableName
        }).ToList();
    }
    
    private async void SearchTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshTableList();
    }
    
    private void SearchTypeComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        // Guard against event firing during InitializeComponent before controls are ready
        if (SearchTextBox == null || SearchTypeComboBox == null)
        {
            Logger.Debug("SearchTypeComboBox_SelectionChanged called before controls initialized - ignoring");
            return;
        }
        
        // Update placeholder text based on search type
        var searchType = (SearchTypeComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "TableName";
        var placeholderText = searchType == "ColumnName" 
            ? "Enter column name pattern..." 
            : "Enter table name pattern...";
        
        // Update placeholder - ModernWpf ControlHelper is an attached property set in XAML
        // We can't easily change it programmatically, so we'll just update the tooltip
        // The XAML already has a default placeholder, and users will see the tooltip on hover
        SearchTextBox.ToolTip = placeholderText;
        Logger.Debug("Search type changed to: {SearchType}", searchType);
        
        // Refresh search if there's already text
        if (!string.IsNullOrWhiteSpace(SearchTextBox.Text))
        {
            RefreshTableList();
        }
    }
    
    private void SearchHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var history = _searchHistoryService.GetHistory();
            if (history.Count == 0)
            {
                MessageBox.Show("No previous search patterns found.", "No History",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            // Create selection dialog (30% wider by default so Item text is not truncated)
            var dialog = new Window
            {
                Title = "Select Previous Search Pattern",
                Width = 780,
                MinWidth = 500,
                Height = 400,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = this
            };

            var listBox = new ListBox
            {
                Margin = new Thickness(10),
                DisplayMemberPath = "Display"
            };

            var displayItems = history.Select(h => new
            {
                Display = string.IsNullOrWhiteSpace(h.Schema)
                    ? $"{h.Pattern} ({h.SearchType}, {h.PatternType}) - {h.SavedAt:yyyy-MM-dd HH:mm}"
                    : $"{h.Pattern} ({h.Schema}, {h.SearchType}, {h.PatternType}) - {h.SavedAt:yyyy-MM-dd HH:mm}",
                Item = h
            }).ToList();
            listBox.ItemsSource = displayItems;

            void ApplySelectedItem()
            {
                if (listBox.SelectedItem == null) return;
                var selected = ((dynamic)listBox.SelectedItem).Item;
                SearchTextBox.Text = selected.Pattern;

                // Set schema if stored
                if (!string.IsNullOrWhiteSpace(selected.Schema) && SchemaComboBox.Items.Cast<object>().Any(s => s?.ToString() == selected.Schema))
                {
                    SchemaComboBox.SelectedItem = SchemaComboBox.Items.Cast<object>().First(s => s?.ToString() == selected.Schema);
                }

                // Set search type
                var searchTypeItem = SearchTypeComboBox.Items.Cast<ComboBoxItem>()
                    .FirstOrDefault(item => item.Tag?.ToString() == selected.SearchType);
                if (searchTypeItem != null)
                    SearchTypeComboBox.SelectedItem = searchTypeItem;

                // Set pattern type
                var patternTypeItem = PatternTypeComboBox.Items.Cast<ComboBoxItem>()
                    .FirstOrDefault(item => item.Tag?.ToString() == selected.PatternType);
                if (patternTypeItem != null)
                    PatternTypeComboBox.SelectedItem = patternTypeItem;

                dialog.DialogResult = true;
                dialog.Close();
            }

            listBox.MouseDoubleClick += (s, args) =>
            {
                if (listBox.SelectedItem != null)
                    ApplySelectedItem();
            };

            var okButton = new Button
            {
                Content = "Load",
                Width = 75,
                Height = 25,
                Margin = new Thickness(5),
                IsDefault = true
            };
            okButton.Click += (s, args) => ApplySelectedItem();

            var cancelButton = new Button
            {
                Content = "Cancel",
                Width = 75,
                Height = 25,
                Margin = new Thickness(5),
                IsCancel = true
            };
            cancelButton.Click += (s, args) => { dialog.DialogResult = false; dialog.Close(); };

            var buttonPanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(10)
            };
            buttonPanel.Children.Add(okButton);
            buttonPanel.Children.Add(cancelButton);

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetRow(listBox, 0);
            Grid.SetRow(buttonPanel, 1);
            grid.Children.Add(listBox);
            grid.Children.Add(buttonPanel);

            dialog.Content = grid;
            listBox.Focus();

            if (dialog.ShowDialog() == true)
                RefreshTableList();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show search history");
            MessageBox.Show($"Failed to load search history:\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    
    private async void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selectedSchema = SchemaComboBox.SelectedItem?.ToString() ?? "All";
        
        if (selectedSchema == "All")
        {
            _allTables.Clear();
            TablesList.ItemsSource = new List<TableSelectionItem>();
            StatusText.Text = "Please select a specific schema to load tables";
            UpdateSelectionCounts();
        }
        else
        {
            try
            {
                ShowLoading($"Loading tables from schema {selectedSchema}...");
                await LoadTablesForSchemaAsync(selectedSchema);
                HideLoading();
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to load tables for schema: {Schema}", selectedSchema);
                HideLoading();
                MessageBox.Show(
                    $"Failed to load tables from schema {selectedSchema}:\n{ex.Message}",
                    "Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }
    }
    
    private void AddSelected_Click(object sender, RoutedEventArgs e)
    {
        var selected = _allTables.Where(t => t.IsSelected).ToList();
        foreach (var table in selected)
        {
            if (!_selectedTables.Contains(table))
            {
                _selectedTables.Add(table);
            }
        }
        UpdateSelectionCounts();
    }
    
    private void AddAllInSchema_Click(object sender, RoutedEventArgs e)
    {
        var selectedSchema = SchemaComboBox.SelectedItem?.ToString() ?? "All";
        if (selectedSchema == "All")
        {
            foreach (var table in _allTables)
            {
                if (!_selectedTables.Contains(table))
                {
                    _selectedTables.Add(table);
                }
            }
        }
        else
        {
            foreach (var table in _allTables.Where(t => t.Schema == selectedSchema))
            {
                if (!_selectedTables.Contains(table))
                {
                    _selectedTables.Add(table);
                }
            }
        }
        UpdateSelectionCounts();
    }
    
    private async void AddAllFromSearch_Click(object sender, RoutedEventArgs e)
    {
        var searchText = SearchTextBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(searchText))
        {
            MessageBox.Show("Please enter a search term first.", "No Search Term",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        // Get currently filtered tables (from RefreshTableList result)
        var filteredTables = TablesList.ItemsSource as IEnumerable<TableSelectionItem> ?? 
                            Enumerable.Empty<TableSelectionItem>();
        var matchingTables = filteredTables.ToList();
        
        if (matchingTables.Count == 0)
        {
            MessageBox.Show($"No tables found matching '{SearchTextBox.Text}'.", "No Matches",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        var addedCount = 0;
        foreach (var table in matchingTables)
        {
            // Mark as selected in _allTables (this is what UpdateSelectionCounts uses)
            if (!table.IsSelected)
            {
                table.IsSelected = true;
                addedCount++;
            }
        }
        
        // Refresh the table list to show checkboxes as checked
        RefreshTableList();
        UpdateSelectionCounts();
        
        Logger.Info("Added {AddedCount} tables from search '{SearchText}' (total matching: {TotalCount})", 
            addedCount, searchText, matchingTables.Count);
        
        StatusText.Text = $"Added {addedCount} table(s) matching '{SearchTextBox.Text}'";
    }
    
    
    private void RemoveSelected_Click(object sender, RoutedEventArgs e)
    {
        var selected = _allTables.Where(t => t.IsSelected).ToList();
        foreach (var table in selected)
        {
            _selectedTables.Remove(table);
            table.IsSelected = false;
        }
        RefreshTableList();
        UpdateSelectionCounts();
    }
    
    private async void FollowFK_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            FollowFKButton.IsEnabled = false;
            ShowLoading("Following outgoing foreign keys...");
            Logger.Debug("Following outgoing foreign keys...");
            
            var selected = _selectedTables.ToList();
            if (selected.Count == 0)
            {
                MessageBox.Show("Please select at least one table first.", "No Selection",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            
            Logger.Debug("Following foreign keys from {Count} selected tables", selected.Count);
            
            var relatedTables = new HashSet<string>();
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1";
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            
            foreach (var table in selected)
            {
                Logger.Debug("Querying outgoing FKs for {Schema}.{Table}", table.Schema, table.TableName);
                
                var fkQuery = metadataHandler.GetQuery(provider, version, "GetForeignKeysForTable");
                fkQuery = ReplaceParameters(fkQuery, table.Schema, table.TableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(fkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    // GetForeignKeysForTable returns REF_SCHEMA and REF_TABLE columns
                    var refSchema = row["REF_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var refTable = row["REF_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{refSchema}.{refTable}";
                    
                    Logger.Debug("FK result row: REF_SCHEMA={RefSchema}, REF_TABLE={RefTable}", refSchema, refTable);
                    
                    if (!string.IsNullOrEmpty(refSchema) && !string.IsNullOrEmpty(refTable) &&
                        !relatedTables.Contains(key) && !selected.Any(t => t.FullName == key))
                    {
                        relatedTables.Add(key);
                        Logger.Debug("Found related table via FK: {Schema}.{Table}", refSchema, refTable);
                    }
                }
            }
            
            // Add related tables to selection
            var addedCount = 0;
            foreach (var relatedKey in relatedTables)
            {
                var parts = relatedKey.Split('.');
                if (parts.Length != 2) continue;
                
                var table = _allTables.FirstOrDefault(t => t.Schema == parts[0].Trim() && t.TableName == parts[1].Trim());
                if (table != null && !_selectedTables.Contains(table))
                {
                    _selectedTables.Add(table);
                    addedCount++;
                    Logger.Info("Added table to selection via FK: {Table}", relatedKey);
                }
            }
            
            UpdateSelectionCounts();
            
            if (addedCount > 0)
            {
                Logger.Info("Added {Count} table(s) via foreign key relationships", addedCount);
                StatusText.Text = $"Added {addedCount} table(s) via outgoing foreign keys";
            }
            else
            {
                StatusText.Text = "No additional tables found via outgoing foreign keys";
            }
            
            Logger.Info("FK navigation complete - Added {Count} tables", addedCount);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to follow foreign keys");
            MessageBox.Show($"Error following foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            HideLoading();
            FollowFKButton.IsEnabled = true;
        }
    }
    
    private async void FollowIncomingFK_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            FollowIncomingFKButton.IsEnabled = false;
            ShowLoading("Following incoming foreign keys...");
            Logger.Debug("Following incoming foreign keys...");
            
            var selected = _selectedTables.ToList();
            if (selected.Count == 0)
            {
                MessageBox.Show("Please select at least one table first.", "No Selection",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            
            Logger.Debug("Following incoming foreign keys for {Count} selected tables", selected.Count);
            
            var relatedTables = new HashSet<string>();
            var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1";
            var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
            
            foreach (var table in selected)
            {
                Logger.Debug("Querying incoming FKs for {Schema}.{Table}", table.Schema, table.TableName);
                
                var incomingFkQuery = metadataHandler.GetQuery(provider, version, "GetIncomingForeignKeys");
                incomingFkQuery = ReplaceParameters(incomingFkQuery, table.Schema, table.TableName);
                var fkResults = await _connectionManager.ExecuteQueryAsync(incomingFkQuery);
                
                foreach (DataRow row in fkResults.Rows)
                {
                    var fromSchema = row["REFERENCING_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
                    var fromTable = row["REFERENCING_TABLE"]?.ToString()?.Trim() ?? string.Empty;
                    var key = $"{fromSchema}.{fromTable}";
                    
                    if (!string.IsNullOrEmpty(fromSchema) && !string.IsNullOrEmpty(fromTable) &&
                        !relatedTables.Contains(key) && !selected.Any(t => t.FullName == key))
                    {
                        relatedTables.Add(key);
                        Logger.Debug("Found table with incoming FK: {Schema}.{Table}", fromSchema, fromTable);
                    }
                }
            }
            
            // Add related tables to selection
            var addedCount = 0;
            foreach (var relatedKey in relatedTables)
            {
                var parts = relatedKey.Split('.');
                if (parts.Length != 2) continue;
                
                var table = _allTables.FirstOrDefault(t => t.Schema == parts[0].Trim() && t.TableName == parts[1].Trim());
                if (table != null && !_selectedTables.Contains(table))
                {
                    _selectedTables.Add(table);
                    addedCount++;
                    Logger.Info("Added table to selection via incoming FK: {Table}", relatedKey);
                }
            }
            
            UpdateSelectionCounts();
            
            if (addedCount > 0)
            {
                Logger.Info("Added {Count} table(s) via incoming foreign key relationships", addedCount);
                StatusText.Text = $"Added {addedCount} table(s) via incoming foreign keys";
            }
            else
            {
                StatusText.Text = "No additional tables found via incoming foreign keys";
            }
            
            Logger.Info("Incoming FK navigation complete - Added {Count} tables", addedCount);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to follow incoming foreign keys");
            MessageBox.Show($"Error following incoming foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            HideLoading();
            FollowIncomingFKButton.IsEnabled = true;
        }
    }
    
    private void ClearSelection_Click(object sender, RoutedEventArgs e)
    {
        _selectedTables.Clear();
        foreach (var table in _allTables)
        {
            table.IsSelected = false;
        }
        RefreshTableList();
        UpdateSelectionCounts();
    }
    
    private void BrowseOutputFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            SelectedPath = _outputFolder,
            Description = "Select output folder for Missing FK Discovery"
        };
        
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            _outputFolder = dialog.SelectedPath;
            OutputFolderTextBox.Text = _outputFolder;
        }
    }
    
    private void BrowseIgnoreJson_Click(object sender, RoutedEventArgs e)
    {
        // Ensure ignore files folder exists
        if (string.IsNullOrEmpty(_ignoreFilesFolder))
        {
            _ignoreFilesFolder = UserDataFolderHelper.GetMissingFKIgnorePatternsFolder();
        }
        
        var dialog = new OpenFileDialog
        {
            Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
            Title = "Select Ignore JSON File",
            InitialDirectory = _ignoreFilesFolder,
            RestoreDirectory = true
        };
        
        if (dialog.ShowDialog() == true)
        {
            _ignoreJsonPath = dialog.FileName;
            IgnoreJsonTextBox.Text = _ignoreJsonPath;
            Logger.Info("Selected ignore JSON file: {Path}", _ignoreJsonPath);
        }
    }
    
    /// <summary>
    /// Generate input JSON for the Missing FK Discovery job.
    /// </summary>
    /// <param name="showSuccessMessage">Whether to show a success message box</param>
    /// <returns>Tuple of (success, errorMessage)</returns>
    private async Task<(bool Success, string? ErrorMessage)> GenerateInputJsonAsync(bool showSuccessMessage = false)
    {
        try
        {
            if (_selectedTables.Count == 0)
            {
                return (false, "Please select at least one table.");
            }
            
            ShowLoading("Generating input JSON...");
            
            // Generate job ID
            _jobId = $"{DateTime.UtcNow:yyyy-MM-ddTHH-mm-ssZ}_{Guid.NewGuid():N}";
            
            // Collect metadata for selected tables
            var tableRefs = _selectedTables.Select(t => new TableReference
            {
                Schema = t.Schema,
                Name = t.TableName
            }).ToList();
            
            Logger.Info("Collecting metadata for {Count} tables", tableRefs.Count);
            var tablesMetadata = await _metadataService.CollectTableMetadataAsync(tableRefs);
            
            // Create project-specific folder with timestamp and table names
            var schema = _selectedTables.FirstOrDefault()?.Schema ?? "UNKNOWN";
            var tableNames = _selectedTables.Select(t => t.TableName);
            _outputFolder = UserDataFolderHelper.CreateProjectFolder(schema, tableNames);
            OutputFolderTextBox.Text = _outputFolder;
            Logger.Info("Created project folder: {Path}", _outputFolder);
            
            // Create input model
            var inputModel = new MissingFKInputModel
            {
                JobId = _jobId,
                GeneratedAtUtc = DateTime.UtcNow,
                ConnectionProfile = _connectionProfile,
                Provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2",
                ProviderVersion = "12.1", // TODO: Get actual version from connection
                Options = new MissingFKOptions
                {
                    MinRowCount = int.TryParse(MinRowCountTextBox.Text, out var minRow) ? minRow : 100,
                    MinMatchRatio = double.TryParse(MinMatchRatioTextBox.Text, out var minMatch) ? minMatch : 0.95,
                    StrongMatchRatio = 0.99,
                    MaxParallelTables = int.TryParse(MaxParallelTablesTextBox.Text, out var maxPar) ? maxPar : 4,
                    ExportFormat = "csv",
                    IncludeNullsInMatch = false
                },
                SelectedTables = tableRefs,
                Tables = tablesMetadata
            };
            
            // Save input JSON to project folder
            var inputPath = Path.Combine(_outputFolder, "missing_fk_input.json");
            var options = new JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            };
            
            var json = JsonSerializer.Serialize(inputModel, options);
            await File.WriteAllTextAsync(inputPath, json, Encoding.UTF8);
            
            Logger.Info("Input JSON generated in project folder: {Path}", inputPath);
            StatusText.Text = $"Input JSON generated: {inputPath}";
            StartBatchJobButton.IsEnabled = true;
            
            if (showSuccessMessage)
            {
                MessageBox.Show($"Input JSON generated successfully:\n{inputPath}\n\nProject folder:\n{_outputFolder}", "Success",
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
            
            return (true, null);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate input JSON");
            return (false, $"Failed to generate input JSON:\n{ex.Message}");
        }
        finally
        {
            HideLoading();
        }
    }
    
    private async void StartBatchJob_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            // Disable button immediately to prevent multiple clicks
            StartBatchJobButton.IsEnabled = false;
            
            // Auto-generate input JSON if it doesn't exist
            var inputPath = Path.Combine(_outputFolder, "missing_fk_input.json");
            if (string.IsNullOrEmpty(_outputFolder) || !File.Exists(inputPath))
            {
                Logger.Info("Input JSON not found, auto-generating...");
                var (success, errorMessage) = await GenerateInputJsonAsync(showSuccessMessage: false);
                
                if (!success)
                {
                    StartBatchJobButton.IsEnabled = true; // Re-enable if validation fails
                    MessageBox.Show(errorMessage ?? "Failed to generate input JSON.", "Generation Failed",
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }
                
                // Update input path after generation
                inputPath = Path.Combine(_outputFolder, "missing_fk_input.json");
            }
            
            // Save ignore JSON if configured
            if (_currentIgnoreModel.IgnoreColumns.Count > 0 || 
                _currentIgnoreModel.IgnoreColumnPatterns.Count > 0 || 
                _currentIgnoreModel.IgnoreDataTypes.Count > 0)
            {
                // Save to ignore JSON file
                if (string.IsNullOrEmpty(_ignoreJsonPath))
                {
                    _ignoreJsonPath = Path.Combine(_outputFolder, "missing_fk_ignore.json");
                }
                
                var ignoreJson = JsonSerializer.Serialize(_currentIgnoreModel, new JsonSerializerOptions
                {
                    WriteIndented = true
                });
                File.WriteAllText(_ignoreJsonPath, ignoreJson, Encoding.UTF8);
                IgnoreJsonTextBox.Text = _ignoreJsonPath;
            }
            
            // Check if another job is already running (PID-based check)
            var existingJob = _jobStatusService.GetRunningJobIfActive();
            if (existingJob != null)
            {
                StartBatchJobButton.IsEnabled = false; // Keep disabled
                AttachToRunningJobProcess(existingJob.ProcessId);
                MessageBox.Show(
                    $"A Missing FK Discovery job is already running (PID: {existingJob.ProcessId}).\n\n" +
                    "Please wait for it to complete. The button will be re-enabled automatically.",
                    "Job Already Running",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            // Defensive: ensure we have valid folder and job id (set by auto-generate or previous generate)
            var outFolder = _outputFolder ?? string.Empty;
            var jobId = _jobId ?? string.Empty;
            if (string.IsNullOrEmpty(outFolder) || string.IsNullOrEmpty(jobId))
            {
                StartBatchJobButton.IsEnabled = true;
                MessageBox.Show("Output folder or job ID is missing. Please generate input (e.g. add tables and generate) or select an existing project folder.", "Start Job",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            // Log ignore rules being used
            var ignoreRulesInfo = "No ignore rules";
            if (!string.IsNullOrEmpty(_ignoreJsonPath) && File.Exists(_ignoreJsonPath))
            {
                try
                {
                    var ignoreJson = File.ReadAllText(_ignoreJsonPath);
                    var ignoreModel = JsonSerializer.Deserialize<MissingFKIgnoreModel>(ignoreJson);
                    if (ignoreModel != null)
                    {
                        var ruleCount = ignoreModel.IgnoreTables.Count + 
                                       ignoreModel.IgnoreColumns.Count + 
                                       ignoreModel.IgnoreColumnPatterns.Count + 
                                       ignoreModel.IgnoreDataTypes.Count;
                        ignoreRulesInfo = $"Using {ruleCount} ignore rule(s) from {Path.GetFileName(_ignoreJsonPath)}";
                        Logger.Info("Ignore rules loaded: {TableRules} tables, {ColumnRules} columns, {PatternRules} patterns, {DataTypeRules} data types",
                            ignoreModel.IgnoreTables.Count, ignoreModel.IgnoreColumns.Count,
                            ignoreModel.IgnoreColumnPatterns.Count, ignoreModel.IgnoreDataTypes.Count);
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, "Failed to parse ignore JSON for info display");
                }
            }
            
            // Build command line arguments
            var args = new List<string>
            {
                "-profile", _connectionProfile,
                "-command", "missing-fk-scan",
                "-input", inputPath,
                "-out", outFolder
            };
            
            if (!string.IsNullOrEmpty(_ignoreJsonPath) && File.Exists(_ignoreJsonPath))
            {
                args.Add("-ignore");
                args.Add(_ignoreJsonPath);
            }
            
            // Get executable path (prefer Environment.ProcessPath for .NET 6+; avoids NRE with single-file or hosted)
            var exePath = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exePath))
            {
                exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
            }
            if (string.IsNullOrEmpty(exePath))
            {
                try
                {
                    exePath = Process.GetCurrentProcess().MainModule?.FileName;
                }
                catch (InvalidOperationException)
                {
                    // MainModule can throw in some hosted scenarios
                }
                exePath = exePath ?? "DbExplorer.exe";
            }

            Logger.Info("Starting detached batch job: {Exe} {Args}", exePath, string.Join(" ", args));

            var processInfo = new ProcessStartInfo
            {
                FileName = exePath,
                Arguments = string.Join(" ", args.Select(a => $"\"{a}\"")),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            
            _runningJobProcess = Process.Start(processInfo);
            if (_runningJobProcess != null)
            {
                Logger.Info("Batch job started with PID: {Pid}", _runningJobProcess.Id);
                
                // Persist for rest of method
                _jobId = jobId;
                _outputFolder = outFolder;

                // Save running job info (PID + exe path so we can verify PID wasn't reused)
                _jobStatusService.SaveRunningJob(_runningJobProcess.Id, jobId, outFolder, exePath);

                // Attach to process exit event for immediate notification
                _runningJobProcess.EnableRaisingEvents = true;
                _runningJobProcess.Exited += OnJobProcessExited;

                // Show clear indication that job started
                var ignoreInfo = string.IsNullOrEmpty(_ignoreJsonPath)
                    ? "No ignore rules"
                    : $"Ignore rules: {Path.GetFileName(_ignoreJsonPath)}";

                StatusText.Text = $"✓ Batch job STARTED - Job ID: {jobId}";
                JobStatusText.Text = $"Job running (PID: {_runningJobProcess.Id}) - {ignoreInfo}";
                JobStatusText.Foreground = System.Windows.Media.Brushes.Green;

                // Show notification
                MessageBox.Show(
                    $"Missing FK Discovery batch job has been started!\n\n" +
                    $"Job ID: {jobId}\n" +
                    $"Process ID: {_runningJobProcess.Id}\n" +
                    $"{ignoreInfo}\n\n" +
                    $"The job is running in the background. You can monitor progress using the 'View Job Log' button.\n" +
                    $"The button will be re-enabled immediately when the job completes.",
                    "Job Started",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                
                // Tray balloon: job started
                try
                {
                    var notificationService = new NotificationService();
                    notificationService.ShowInfo("Missing FK Discovery", $"Job started. PID: {_runningJobProcess.Id}. Output: {outFolder}");
                }
                catch (Exception exNotif)
                {
                    Logger.Warn(exNotif, "Failed to show tray notification for job start");
                }
                
                // Start log file monitoring and status polling (so we re-enable button when job ends or PID reused)
                StartLogFileMonitoring(outFolder);
                StartJobStatusMonitoring(jobId, outFolder);
                MainTabControl.SelectedItem = JobProgressTab;

                // Update UI - disable button to prevent multiple starts
                StartBatchJobButton.IsEnabled = false;
                StartBatchJobButton.Content = "Job Running...";
                ViewJobLogButton.IsEnabled = true;
                
                Logger.Info("Job started and PID file saved - PID: {Pid}", _runningJobProcess.Id);
            }
            else
            {
                _jobStatusService.ClearRunningJob();
                throw new InvalidOperationException("Failed to start batch job process");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to start batch job");
            _jobStatusService.ReleaseJobLock(_outputFolder);
            MessageBox.Show($"Failed to start batch job:\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void OpenOutputFolder_Click(object sender, RoutedEventArgs e)
    {
        if (Directory.Exists(_outputFolder))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = _outputFolder,
                UseShellExecute = true
            });
        }
        else
        {
            MessageBox.Show("Output folder does not exist.", "Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    
    private void OpenJobLog_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_outputFolder))
        {
            MessageBox.Show("No job has been started yet.", "No Job",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
        if (File.Exists(logPath))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = logPath,
                UseShellExecute = true
            });
        }
        else
        {
            MessageBox.Show($"Job log not found:\n{logPath}", "Log Not Found",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    
    private void EditIgnoreRules_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dialog = new MissingFKIgnoreRulesDialog(_currentIgnoreModel)
            {
                Owner = this
            };
            
            if (dialog.ShowDialog() == true)
            {
                _currentIgnoreModel = dialog.IgnoreModel;
                UpdateIgnoreRulesSummary();
                
                // Update ignore JSON path if needed
                if (!string.IsNullOrEmpty(_ignoreJsonPath))
                {
                    var ignoreJson = JsonSerializer.Serialize(_currentIgnoreModel, new JsonSerializerOptions
                    {
                        WriteIndented = true
                    });
                    File.WriteAllText(_ignoreJsonPath, ignoreJson, Encoding.UTF8);
                }
                
                Logger.Info("Ignore rules updated from editor dialog");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open ignore rules editor");
            MessageBox.Show($"Failed to open ignore rules editor:\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void UpdateIgnoreRulesSummary()
    {
        var parts = new List<string>();
        if (_currentIgnoreModel.IgnoreColumns.Count > 0)
            parts.Add($"{_currentIgnoreModel.IgnoreColumns.Count} column(s)");
        if (_currentIgnoreModel.IgnoreColumnPatterns.Count > 0)
            parts.Add($"{_currentIgnoreModel.IgnoreColumnPatterns.Count} pattern(s)");
        if (_currentIgnoreModel.IgnoreDataTypes.Count > 0)
            parts.Add($"{_currentIgnoreModel.IgnoreDataTypes.Count} data type(s)");
        
        if (parts.Count > 0)
        {
            IgnoreRulesSummaryText.Text = string.Join(", ", parts);
            IgnoreRulesSummaryText.FontStyle = FontStyles.Normal;
            IgnoreRulesSummaryText.Foreground = System.Windows.Media.Brushes.White;
        }
        else
        {
            IgnoreRulesSummaryText.Text = "No ignore rules configured";
            IgnoreRulesSummaryText.FontStyle = FontStyles.Italic;
            IgnoreRulesSummaryText.Foreground = System.Windows.Media.Brushes.Gray;
        }
    }
    
    // Old methods removed - functionality moved to MissingFKIgnoreRulesDialog
    
    private void ViewJobLog_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_outputFolder))
        {
            MessageBox.Show("No job has been started yet.", "No Job",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        
        var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
        if (!File.Exists(logPath))
        {
            MessageBox.Show($"Job log not found:\n{logPath}", "Log Not Found",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        
        var logViewer = new MissingFKJobLogViewerDialog(logPath, _jobId ?? Path.GetFileName(_outputFolder));
        logViewer.Owner = this;
        logViewer.Show();
    }
    
    private void StartJobStatusMonitoring(string jobId, string outputFolder)
    {
        try
        {
            Logger.Debug("Starting job status monitoring for job: {JobId}", jobId);
            
            // Create FileSystemWatcher for status file
            _statusFileWatcher = new FileSystemWatcher(outputFolder)
            {
                Filter = $"missing_fk_status_{jobId}.json",
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.CreationTime | NotifyFilters.Size
            };
            
            _statusFileWatcher.Created += OnStatusFileChanged;
            _statusFileWatcher.Changed += OnStatusFileChanged;
            _statusFileWatcher.Deleted += OnStatusFileDeleted;
            _statusFileWatcher.EnableRaisingEvents = true;
            
            // Also start polling timer as fallback (every 2 seconds)
            _statusPollTimer = new Timer(CheckJobStatus, null, TimeSpan.Zero, TimeSpan.FromSeconds(2));
            
            Logger.Info("Job status monitoring started for job: {JobId}", jobId);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to start job status monitoring");
        }
    }
    
    private void StopJobStatusMonitoring()
    {
        try
        {
            if (_statusFileWatcher != null)
            {
                _statusFileWatcher.EnableRaisingEvents = false;
                _statusFileWatcher.Dispose();
                _statusFileWatcher = null;
            }
            
            if (_statusPollTimer != null)
            {
                _statusPollTimer.Dispose();
                _statusPollTimer = null;
            }
            
            Logger.Debug("Job status monitoring stopped");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error stopping job status monitoring");
        }
    }
    
    private void StartLogFileMonitoring(string outputFolder)
    {
        try
        {
            var logPath = MissingFKJobStatusService.GetLogFilePath(outputFolder);
            var logFileName = Path.GetFileName(logPath);
            
            Logger.Debug("Starting log file monitoring, path: {Path}", logPath);
            
            // Create FileSystemWatcher for log file (static name: missing_fk_job.log)
            _logFileWatcher = new FileSystemWatcher(outputFolder)
            {
                Filter = logFileName,
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size
            };
            
            _logFileWatcher.Changed += OnLogFileChanged;
            _logFileWatcher.EnableRaisingEvents = true;
            
            // Always load once so user sees either content or "Log file not found. Waiting for job to start..."
            LoadLogFileContent(logPath);
            
            // Poll every 1 second; LoadLogFileContent only runs when Job Progress tab is selected (tab-aware)
            _logPollTimer = new Timer(_ =>
            {
                Dispatcher.Invoke(() =>
                {
                    if (MainTabControl.SelectedItem == JobProgressTab)
                        LoadLogFileContent(logPath);
                });
            }, null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
            
            Logger.Info("Log file monitoring started, path: {Path}", logPath);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to start log file monitoring");
        }
    }
    
    private void StopLogFileMonitoring()
    {
        try
        {
            if (_logFileWatcher != null)
            {
                _logFileWatcher.EnableRaisingEvents = false;
                _logFileWatcher.Dispose();
                _logFileWatcher = null;
            }
            
            if (_logPollTimer != null)
            {
                _logPollTimer.Dispose();
                _logPollTimer = null;
            }
            
            Logger.Debug("Log file monitoring stopped");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error stopping log file monitoring");
        }
    }
    
    private void OnLogFileChanged(object sender, FileSystemEventArgs e)
    {
        try
        {
            // Small delay to ensure file write is complete; only refresh when user is on Job Progress tab
            Task.Delay(100).ContinueWith(_ =>
            {
                Dispatcher.Invoke(() =>
                {
                    if (MainTabControl.SelectedItem == JobProgressTab)
                        LoadLogFileContent(e.FullPath);
                });
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error handling log file change");
        }
    }
    
    /// <summary>
    /// Parse the [MISSING_FK_JOB] notification line from log content. Returns (success, message for display/balloon).
    /// </summary>
    private static (bool success, string message) ParseLogNotificationLine(string logContent)
    {
        if (string.IsNullOrWhiteSpace(logContent)) return (true, "Job completed.");
        var idx = logContent.LastIndexOf("[MISSING_FK_JOB]", StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return (true, "Job completed.");
        var line = logContent.Substring(idx);
        var firstNewLine = line.IndexOf('\n');
        if (firstNewLine > 0) line = line.Substring(0, firstNewLine);
        line = line.Trim();
        var success = line.IndexOf("STATUS=SUCCESS", StringComparison.OrdinalIgnoreCase) >= 0;
        var message = new StringBuilder();
        if (success)
        {
            message.Append("Completed.");
            var candMatch = System.Text.RegularExpressions.Regex.Match(line, @"CANDIDATES=(\d+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            var durMatch = System.Text.RegularExpressions.Regex.Match(line, @"DURATION=([^\s]+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (candMatch.Success) message.Append($" {candMatch.Groups[1].Value} candidates.");
            if (durMatch.Success) message.Append($" Duration: {durMatch.Groups[1].Value}");
        }
        else
        {
            var msgMatch = System.Text.RegularExpressions.Regex.Match(line, @"MESSAGE=([^\s]+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            message.Append(msgMatch.Success ? msgMatch.Groups[1].Value.Replace("_", " ") : "Job completed with errors. Check the log for details.");
        }
        return (success, message.ToString().Trim());
    }
    
    private void LoadLogFileContent(string logPath)
    {
        try
        {
            if (!File.Exists(logPath))
            {
                JobLogTextBox.Text = "Log file not found. Waiting for job to start...";
                return;
            }
            
            // Read file with retry logic (file might be locked)
            string content = string.Empty;
            for (int i = 0; i < 3; i++)
            {
                try
                {
                    content = File.ReadAllText(logPath, Encoding.UTF8);
                    break;
                }
                catch (IOException)
                {
                    if (i < 2) Thread.Sleep(100);
                    else content = "Unable to read log file (file may be locked)";
                }
            }
            
            JobLogTextBox.Text = content;
            
            // Auto-scroll to bottom
            JobLogTextBox.CaretIndex = JobLogTextBox.Text.Length;
            JobLogTextBox.ScrollToEnd();
            
            // Update status text: use parsed notification line if present, else last log line
            var (_, statusMessage) = ParseLogNotificationLine(content);
            if (!string.IsNullOrEmpty(statusMessage))
            {
                JobProgressStatusText.Text = statusMessage;
            }
            else
            {
                var lines = content.Split('\n');
                var lastLine = lines.LastOrDefault(l => !string.IsNullOrWhiteSpace(l));
                if (!string.IsNullOrEmpty(lastLine))
                    JobProgressStatusText.Text = $"Job running... Last update: {lastLine.Trim()}";
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading log file content");
            JobLogTextBox.Text = $"Error reading log file: {ex.Message}";
        }
    }
    
    private void RefreshJobLog_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_outputFolder)) return;
        
        var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
        LoadLogFileContent(logPath);
    }
    
    private void ClearJobLog_Click(object sender, RoutedEventArgs e)
    {
        JobLogTextBox.Clear();
        JobProgressStatusText.Text = "Log cleared. Waiting for updates...";
    }
    
    private void OnStatusFileChanged(object sender, FileSystemEventArgs e)
    {
        Dispatcher.Invoke(() => CheckJobStatus(null));
    }
    
    private void OnStatusFileDeleted(object sender, FileSystemEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            Logger.Info("Status file deleted - job completed");
            JobStatusText.Text = "Job completed successfully";
            JobStatusText.Foreground = System.Windows.Media.Brushes.Green;
            StartBatchJobButton.IsEnabled = true;
            StartBatchJobButton.Content = "Start Batch Job";
            ViewJobLogButton.IsEnabled = true; // Keep enabled so user can view final log
            
            // Show completion notification
            ShowJobCompletionNotification(true, "Missing FK Discovery job completed successfully.");
            
            // Update log one final time and parse notification for status
            var logPath = MissingFKJobStatusService.GetLogFilePath(_outputFolder);
            if (File.Exists(logPath))
            {
                LoadLogFileContent(logPath);
                var content = File.ReadAllText(logPath);
                var (_, statusMessage) = ParseLogNotificationLine(content);
                JobProgressStatusText.Text = string.IsNullOrEmpty(statusMessage) ? "Job completed successfully" : statusMessage;
            }
            else
            {
                JobProgressStatusText.Text = "Job completed successfully";
            }
            
            StopJobStatusMonitoring();
            StopLogFileMonitoring();
        });
    }
    
    private void CheckJobStatus(object? state)
    {
        try
        {
            // With PID-based tracking, we mainly rely on process.Exited event
            // This timer is a fallback to check if process is still running
            if (_runningJobProcess != null && _runningJobProcess.HasExited)
            {
                Dispatcher.Invoke(() => OnJobCompleted());
                return;
            }

            // Re-enable Start button if we think job is running but it no longer is (PID reused or stale state)
            Dispatcher.Invoke(() =>
            {
                if (!StartBatchJobButton.IsEnabled && _jobStatusService.GetRunningJobIfActive() == null)
                {
                    Logger.Info("Job no longer running (PID reused or ended), re-enabling Start Batch Job button");
                    OnJobCompleted();
                }
            });
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error checking job status");
        }
    }
    
    private void ShowJobCompletionNotification(bool success, string message)
    {
        var title = success ? "Job Completed" : "Job Failed";
        var details = $"{message}\n\nJob ID: {_jobId}\nOutput folder: {_outputFolder}";
        
        // Use NotificationService to create tray notification
        var notificationService = new NotificationService();
        notificationService.ShowJobCompletion("Missing FK Discovery", success, details);
        
        // Also show MessageBox as fallback if tray icon is not running
        var icon = success ? MessageBoxImage.Information : MessageBoxImage.Error;
        MessageBox.Show(
            details,
            title,
            MessageBoxButton.OK,
            icon);
    }
    
    private string ReplaceParameters(string sql, params string[] values)
    {
        var result = sql;
        foreach (var value in values)
        {
            var index = result.IndexOf('?');
            if (index >= 0)
            {
                var quotedValue = $"'{value.Replace("'", "''")}'";
                result = result.Substring(0, index) + quotedValue + result.Substring(index + 1);
            }
        }
        return result;
    }
}
