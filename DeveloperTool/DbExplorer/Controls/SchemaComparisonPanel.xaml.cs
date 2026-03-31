using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls
{
    /// <summary>
    /// Schema comparison panel for comparing and migrating schemas across databases
    /// </summary>
    public partial class SchemaComparisonPanel : UserControl
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        
        private readonly ConnectionStorageService _connectionStorage;
        private readonly SchemaComparisonService _comparisonService;
        private readonly SchemaMigrationDdlService _ddlService;
        private readonly MetadataHandler _metadataHandler;
        
        private IConnectionManager? _sourceConnection;
        private IConnectionManager? _targetConnection;
        private IConnectionManager? _currentConnection;
        private string? _currentConnectionName;
        private List<SavedConnection> _savedConnections = new();
        
        private SchemaComparisonResult? _comparisonResult;
        private SchemaDifference? _selectedDifference;
        private readonly Dictionary<string, TreeViewItem> _treeItems = new();

        /// <summary>
        /// Event raised when the panel requests to be closed
        /// </summary>
        public event EventHandler? CloseRequested;
        
        /// <summary>
        /// Event raised when scripts should be opened in new tabs
        /// </summary>
        public event EventHandler<MigrationScriptEventArgs>? OpenScriptRequested;

        public SchemaComparisonPanel()
        {
            InitializeComponent();
            
            _connectionStorage = new ConnectionStorageService();
            _comparisonService = new SchemaComparisonService();
            _ddlService = new SchemaMigrationDdlService();
            _metadataHandler = new MetadataHandler();
            
            Loaded += async (s, e) => 
            {
                UIStyleService.ApplyStyles(Window.GetWindow(this));
                await LoadConnectionsAsync();
            };
        }

        /// <summary>
        /// Initialize with current connection as default source
        /// </summary>
        public void SetCurrentConnection(IConnectionManager connection, string connectionName)
        {
            _currentConnection = connection;
            _currentConnectionName = connectionName;
            Logger.Debug("SchemaComparisonPanel initialized with connection: {Name}", connectionName);
        }

        #region Connection Loading

        private async Task LoadConnectionsAsync()
        {
            try
            {
                _savedConnections = _connectionStorage.LoadConnections();
                
                if (_savedConnections.Count == 0)
                {
                    MessageBox.Show(
                        "No saved connections found.\n\nPlease create connections using File → New Connection before using this feature.",
                        "No Saved Connections",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                    return;
                }

                var connectionNames = _savedConnections.Select(c => c.Name).ToList();
                
                // Add current connection if not in list
                if (_currentConnection != null && !string.IsNullOrEmpty(_currentConnectionName))
                {
                    var matchingName = connectionNames.FirstOrDefault(n => 
                        n.Equals(_currentConnectionName, StringComparison.OrdinalIgnoreCase));
                    
                    if (matchingName == null)
                    {
                        connectionNames.Insert(0, _currentConnectionName);
                    }
                }

                SourceConnectionComboBox.ItemsSource = connectionNames;
                TargetConnectionComboBox.ItemsSource = connectionNames;

                // Pre-select current connection as source
                if (!string.IsNullOrEmpty(_currentConnectionName))
                {
                    var match = connectionNames.FirstOrDefault(n => 
                        n.Equals(_currentConnectionName, StringComparison.OrdinalIgnoreCase));
                    if (match != null)
                    {
                        SourceConnectionComboBox.SelectedItem = match;
                        _sourceConnection = _currentConnection;
                        
                        if (_sourceConnection != null)
                        {
                            await LoadSchemasForConnectionAsync(_sourceConnection, true);
                        }

                        // Pre-select different connection for target
                        var otherConnections = connectionNames.Where(n => 
                            !n.Equals(_currentConnectionName, StringComparison.OrdinalIgnoreCase)).ToList();
                        if (otherConnections.Count > 0)
                        {
                            TargetConnectionComboBox.SelectedItem = otherConnections[0];
                        }
                    }
                }

                Logger.Info("Loaded {Count} connections", _savedConnections.Count);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error loading connections");
                MessageBox.Show($"Error loading connections: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private async void SourceConnection_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (SourceConnectionComboBox.SelectedItem == null) return;
            
            var connectionName = SourceConnectionComboBox.SelectedItem.ToString()!;
            
            // Use current connection if it matches
            if (connectionName.Equals(_currentConnectionName, StringComparison.OrdinalIgnoreCase) && 
                _currentConnection != null)
            {
                _sourceConnection = _currentConnection;
                await LoadSchemasForConnectionAsync(_sourceConnection, true);
                return;
            }

            await ConnectAndLoadSchemasAsync(connectionName, true);
        }

        private async void TargetConnection_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (TargetConnectionComboBox.SelectedItem == null) return;
            
            var connectionName = TargetConnectionComboBox.SelectedItem.ToString()!;
            
            // Reuse source connection if same profile selected
            var sourceProfile = SourceConnectionComboBox.SelectedItem?.ToString();
            if (connectionName.Equals(sourceProfile, StringComparison.OrdinalIgnoreCase) && _sourceConnection != null)
            {
                _targetConnection = _sourceConnection;
                await LoadSchemasForConnectionAsync(_targetConnection, false);
                return;
            }

            await ConnectAndLoadSchemasAsync(connectionName, false);
        }

        private async Task ConnectAndLoadSchemasAsync(string connectionName, bool isSource)
        {
            var infoText = isSource ? SourceInfoText : TargetInfoText;
            var schemaComboBox = isSource ? SourceSchemaComboBox : TargetSchemaComboBox;
            
            try
            {
                infoText.Text = "Connecting...";
                schemaComboBox.ItemsSource = null;
                
                var connection = _connectionStorage.GetConnection(connectionName);
                if (connection == null)
                {
                    infoText.Text = "Connection not found";
                    return;
                }

                var connectionManager = ConnectionManagerFactory.CreateConnectionManager(connection);
                await connectionManager.OpenAsync();

                if (isSource)
                    _sourceConnection = connectionManager;
                else
                    _targetConnection = connectionManager;

                await LoadSchemasForConnectionAsync(connectionManager, isSource);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error connecting to {Connection}", connectionName);
                infoText.Text = $"Error: {ex.Message}";
            }
        }

        private async Task LoadSchemasForConnectionAsync(IConnectionManager connection, bool isSource)
        {
            var infoText = isSource ? SourceInfoText : TargetInfoText;
            var schemaComboBox = isSource ? SourceSchemaComboBox : TargetSchemaComboBox;
            
            try
            {
                infoText.Text = "Loading schemas...";
                
                var sql = "SELECT TRIM(SCHEMANAME) AS SCHEMANAME FROM SYSCAT.SCHEMATA " +
                          "WHERE SCHEMANAME NOT LIKE 'SYS%' ORDER BY SCHEMANAME";
                var result = await connection.ExecuteQueryAsync(sql);
                
                var schemas = result.Rows.Cast<DataRow>()
                    .Select(r => r["SCHEMANAME"]?.ToString()?.Trim() ?? "")
                    .Where(s => !string.IsNullOrEmpty(s))
                    .ToList();

                schemaComboBox.ItemsSource = schemas;
                infoText.Text = $"Connected - {schemas.Count} schemas";

                if (schemas.Count == 1)
                    schemaComboBox.SelectedIndex = 0;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error loading schemas");
                infoText.Text = $"Error: {ex.Message}";
            }
        }

        #endregion

        #region Comparison

        private async void Compare_Click(object sender, RoutedEventArgs e)
        {
            if (_sourceConnection == null || _targetConnection == null)
            {
                MessageBox.Show("Please select both source and target connections.", "Missing Connection",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            var sourceSchema = SourceSchemaComboBox.SelectedItem?.ToString();
            var targetSchema = TargetSchemaComboBox.SelectedItem?.ToString();

            if (string.IsNullOrEmpty(sourceSchema) || string.IsNullOrEmpty(targetSchema))
            {
                MessageBox.Show("Please select both source and target schemas.", "Missing Schema",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            try
            {
                CompareButton.IsEnabled = false;
                ProgressBar.Visibility = Visibility.Visible;
                ProgressText.Visibility = Visibility.Visible;

                var progress = new Progress<string>(status => ProgressText.Text = status);

                _comparisonResult = await _comparisonService.CompareSchemas(
                    _sourceConnection, sourceSchema,
                    _targetConnection, targetSchema,
                    progress);

                PopulateDifferenceTree();
                UpdateSummary();

                ResultsGrid.Visibility = Visibility.Visible;
                ActionBar.Visibility = Visibility.Visible;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error comparing schemas");
                MessageBox.Show($"Error comparing schemas: {ex.Message}", "Comparison Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                CompareButton.IsEnabled = true;
                ProgressBar.Visibility = Visibility.Collapsed;
                ProgressText.Visibility = Visibility.Collapsed;
            }
        }

        private void PopulateDifferenceTree()
        {
            DifferenceTreeView.Items.Clear();
            _treeItems.Clear();

            if (_comparisonResult == null) return;

            var hideIdentical = ShowOnlyDifferences.IsChecked == true;
            var searchFilter = SearchBox.Text?.Trim().ToLowerInvariant() ?? "";

            // Group by object type
            var objectTypeOrder = new[]
            {
                SchemaObjectType.Table,
                SchemaObjectType.Column,
                SchemaObjectType.View,
                SchemaObjectType.Index,
                SchemaObjectType.PrimaryKey,
                SchemaObjectType.UniqueConstraint,
                SchemaObjectType.ForeignKey,
                SchemaObjectType.CheckConstraint,
                SchemaObjectType.Trigger,
                SchemaObjectType.Sequence,
                SchemaObjectType.Procedure,
                SchemaObjectType.Function
            };

            foreach (var objectType in objectTypeOrder)
            {
                if (!_comparisonResult.DifferencesByType.TryGetValue(objectType, out var differences))
                    continue;

                var filteredDiffs = differences
                    .Where(d => !hideIdentical || d.DifferenceType != Models.DifferenceType.Identical)
                    .Where(d => string.IsNullOrEmpty(searchFilter) || 
                               d.DisplayName.ToLowerInvariant().Contains(searchFilter))
                    .ToList();

                if (filteredDiffs.Count == 0) continue;

                var typeNode = new TreeViewItem
                {
                    Header = CreateTypeHeader(objectType, filteredDiffs),
                    Tag = objectType,
                    IsExpanded = true
                };

                // Group by difference type
                var byDiffType = filteredDiffs.GroupBy(d => d.DifferenceType)
                    .OrderBy(g => g.Key);

                foreach (var group in byDiffType)
                {
                    var diffTypeNode = new TreeViewItem
                    {
                        Header = CreateDiffTypeHeader(group.Key, group.Count()),
                        Tag = group.Key,
                        IsExpanded = true
                    };

                    foreach (var diff in group.OrderBy(d => d.DisplayName))
                    {
                        var itemNode = new TreeViewItem
                        {
                            Header = CreateDifferenceHeader(diff),
                            Tag = diff
                        };
                        _treeItems[diff.Id] = itemNode;
                        diffTypeNode.Items.Add(itemNode);
                    }

                    typeNode.Items.Add(diffTypeNode);
                }

                DifferenceTreeView.Items.Add(typeNode);
            }
        }

        private StackPanel CreateTypeHeader(SchemaObjectType type, List<SchemaDifference> diffs)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            var icon = GetObjectTypeIcon(type);
            panel.Children.Add(new TextBlock { Text = icon, Margin = new Thickness(0, 0, 5, 0) });
            panel.Children.Add(new TextBlock { Text = $"{type}s", FontWeight = FontWeights.SemiBold });
            panel.Children.Add(new TextBlock 
            { 
                Text = $" ({diffs.Count})", 
                Foreground = Brushes.Gray 
            });
            return panel;
        }

        private StackPanel CreateDiffTypeHeader(DbExplorer.Models.DifferenceType type, int count)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            var (icon, color) = GetDiffTypeIconAndColor(type);
            panel.Children.Add(new TextBlock { Text = icon, Margin = new Thickness(0, 0, 5, 0) });
            panel.Children.Add(new TextBlock { Text = type.ToString(), Foreground = color });
            panel.Children.Add(new TextBlock { Text = $" ({count})", Foreground = Brushes.Gray });
            return panel;
        }

        private StackPanel CreateDifferenceHeader(SchemaDifference diff)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            
            // Checkbox for selection
            var checkBox = new CheckBox
            {
                IsChecked = diff.IsSelected,
                Margin = new Thickness(0, 0, 5, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            checkBox.Checked += (s, e) => { diff.IsSelected = true; UpdateSelectionCount(); };
            checkBox.Unchecked += (s, e) => { diff.IsSelected = false; UpdateSelectionCount(); };
            panel.Children.Add(checkBox);

            // Merge direction indicator
            if (diff.MergeDirection != MergeDirection.None)
            {
                var dirText = diff.MergeDirection switch
                {
                    MergeDirection.SourceToTarget => "→",
                    MergeDirection.TargetToSource => "←",
                    MergeDirection.Both => "⇄",
                    _ => ""
                };
                panel.Children.Add(new TextBlock 
                { 
                    Text = dirText, 
                    Foreground = Brushes.DodgerBlue,
                    FontWeight = FontWeights.Bold,
                    Margin = new Thickness(0, 0, 5, 0)
                });
            }

            // Object name
            panel.Children.Add(new TextBlock { Text = diff.DisplayName });

            // Property count for modified items
            if (diff.DifferenceType == DbExplorer.Models.DifferenceType.Modified && diff.PropertyDifferences.Count > 0)
            {
                panel.Children.Add(new TextBlock 
                { 
                    Text = $" ({diff.PropertyDifferences.Count} props)", 
                    Foreground = Brushes.Orange,
                    FontSize = 10
                });
            }

            return panel;
        }

        private string GetObjectTypeIcon(SchemaObjectType type)
        {
            return type switch
            {
                SchemaObjectType.Table => "📋",
                SchemaObjectType.View => "👁",
                SchemaObjectType.Column => "📊",
                SchemaObjectType.Index => "🔍",
                SchemaObjectType.PrimaryKey => "🔑",
                SchemaObjectType.UniqueConstraint => "✨",
                SchemaObjectType.ForeignKey => "🔗",
                SchemaObjectType.CheckConstraint => "✓",
                SchemaObjectType.Trigger => "⚡",
                SchemaObjectType.Sequence => "🔢",
                SchemaObjectType.Procedure => "⚙",
                SchemaObjectType.Function => "ƒ",
                _ => "📄"
            };
        }

        private (string Icon, Brush Color) GetDiffTypeIconAndColor(DbExplorer.Models.DifferenceType type)
        {
            return type switch
            {
                DbExplorer.Models.DifferenceType.OnlyInSource => ("➕", Brushes.LimeGreen),
                DbExplorer.Models.DifferenceType.OnlyInTarget => ("➖", Brushes.OrangeRed),
                DbExplorer.Models.DifferenceType.Modified => ("⚠", Brushes.Orange),
                DbExplorer.Models.DifferenceType.Identical => ("✓", Brushes.Gray),
                _ => ("?", Brushes.Gray)
            };
        }

        private void UpdateSummary()
        {
            if (_comparisonResult == null) return;

            var summary = _comparisonResult.Summary;
            SummaryText.Text = $"Differences: {summary.OnlyInSourceCount} only in source, " +
                              $"{summary.OnlyInTargetCount} only in target, " +
                              $"{summary.ModifiedCount} modified";
        }

        private void UpdateSelectionCount()
        {
            if (_comparisonResult == null) return;

            var selected = _comparisonResult.GetAllDifferences().Count(d => d.IsSelected);
            var withDirection = _comparisonResult.GetAllDifferences()
                .Count(d => d.IsSelected && d.MergeDirection != MergeDirection.None);
            
            SelectionCountText.Text = $"{selected} items selected ({withDirection} with merge direction)";
            GenerateScriptsButton.IsEnabled = withDirection > 0;
        }

        #endregion

        #region Tree Events

        private void DifferenceTreeView_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
        {
            if (e.NewValue is TreeViewItem item && item.Tag is SchemaDifference diff)
            {
                _selectedDifference = diff;
                ShowDifferenceDetails(diff);
                MergeDirectionPanel.Visibility = Visibility.Visible;
            }
            else
            {
                _selectedDifference = null;
                MergeDirectionPanel.Visibility = Visibility.Collapsed;
                SelectedItemTitle.Text = "Select an item to view details";
            }
        }

        private void ShowDifferenceDetails(SchemaDifference diff)
        {
            SelectedItemTitle.Text = $"{diff.ObjectType}: {diff.FullName}";
            
            // Properties tab
            PropertiesGrid.ItemsSource = diff.PropertyDifferences;
            PropertiesHeader.Text = diff.PropertyDifferences.Count > 0 
                ? $"Property differences ({diff.PropertyDifferences.Count}):"
                : "No property differences";

            // Source code tab
            var sourceObj = diff.SourceObject;
            var targetObj = diff.TargetObject;
            
            SourceCodeEditor.Text = sourceObj?.SourceCode ?? "(not available)";
            TargetCodeEditor.Text = targetObj?.SourceCode ?? "(not available)";
            
            // Show source code tab if there's code to compare
            SourceCodeTab.Visibility = (sourceObj?.SourceCode != null || targetObj?.SourceCode != null) 
                ? Visibility.Visible : Visibility.Collapsed;

            // DDL preview
            GenerateDdlPreview(diff);
        }

        private void GenerateDdlPreview(SchemaDifference diff)
        {
            if (_comparisonResult == null) return;

            try
            {
                // Generate preview DDL for this single item
                var tempDiff = new SchemaDifference
                {
                    Id = diff.Id,
                    ObjectType = diff.ObjectType,
                    DifferenceType = diff.DifferenceType,
                    SourceObject = diff.SourceObject,
                    TargetObject = diff.TargetObject,
                    PropertyDifferences = diff.PropertyDifferences,
                    IsSelected = true,
                    MergeDirection = MergeDirection.SourceToTarget
                };

                var scripts = _ddlService.GenerateMigrationScripts(_comparisonResult, new[] { tempDiff });
                DdlPreviewEditor.Text = scripts.FirstOrDefault()?.GetFullScript() ?? "-- No DDL generated";
            }
            catch (Exception ex)
            {
                DdlPreviewEditor.Text = $"-- Error generating DDL: {ex.Message}";
            }
        }

        private void Filter_Changed(object sender, RoutedEventArgs e)
        {
            PopulateDifferenceTree();
        }

        private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            PopulateDifferenceTree();
        }

        #endregion

        #region Merge Direction

        private void MergeToTarget_Click(object sender, RoutedEventArgs e)
        {
            SetMergeDirection(MergeDirection.SourceToTarget);
        }

        private void MergeToSource_Click(object sender, RoutedEventArgs e)
        {
            SetMergeDirection(MergeDirection.TargetToSource);
        }

        private void MergeBoth_Click(object sender, RoutedEventArgs e)
        {
            SetMergeDirection(MergeDirection.Both);
        }

        private void SetMergeDirection(MergeDirection direction)
        {
            if (_selectedDifference == null) return;

            _selectedDifference.MergeDirection = direction;
            _selectedDifference.IsSelected = true;

            // Refresh tree item
            if (_treeItems.TryGetValue(_selectedDifference.Id, out var item))
            {
                item.Header = CreateDifferenceHeader(_selectedDifference);
            }

            UpdateSelectionCount();
            GenerateDdlPreview(_selectedDifference);
        }

        private void SelectAll_Click(object sender, RoutedEventArgs e)
        {
            if (_comparisonResult == null) return;

            foreach (var diff in _comparisonResult.GetAllDifferences())
            {
                if (diff.DifferenceType != Models.DifferenceType.Identical)
                {
                    diff.IsSelected = true;
                    if (diff.MergeDirection == MergeDirection.None)
                        diff.MergeDirection = MergeDirection.SourceToTarget;
                }
            }
            PopulateDifferenceTree();
            UpdateSelectionCount();
        }

        private void ClearSelection_Click(object sender, RoutedEventArgs e)
        {
            if (_comparisonResult == null) return;

            foreach (var diff in _comparisonResult.GetAllDifferences())
            {
                diff.IsSelected = false;
                diff.MergeDirection = MergeDirection.None;
            }
            PopulateDifferenceTree();
            UpdateSelectionCount();
        }

        #endregion

        #region Script Generation

        private void GenerateScripts_Click(object sender, RoutedEventArgs e)
        {
            if (_comparisonResult == null) return;

            var selectedDiffs = _comparisonResult.GetSelectedDifferences().ToList();
            if (selectedDiffs.Count == 0)
            {
                MessageBox.Show("Please select items and set merge directions.", "No Items Selected",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            try
            {
                var scripts = _ddlService.GenerateMigrationScripts(_comparisonResult, selectedDiffs);

                if (scripts.Count == 0)
                {
                    MessageBox.Show("No scripts generated.", "No Scripts",
                        MessageBoxButton.OK, MessageBoxImage.Information);
                    return;
                }

                // Get connection managers for scripts
                foreach (var script in scripts)
                {
                    var connectionManager = script.Direction == MergeDirection.SourceToTarget
                        ? _targetConnection
                        : _sourceConnection;

                    if (connectionManager != null)
                    {
                        OpenScriptRequested?.Invoke(this, new MigrationScriptEventArgs
                        {
                            Script = script,
                            ConnectionManager = connectionManager
                        });
                    }
                }

                // Close panel after generating scripts
                CloseRequested?.Invoke(this, EventArgs.Empty);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error generating scripts");
                MessageBox.Show($"Error generating scripts: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CopyDdl_Click(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrEmpty(DdlPreviewEditor.Text))
            {
                Clipboard.SetText(DdlPreviewEditor.Text);
                MessageBox.Show("DDL copied to clipboard.", "Copied", 
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            // Cleanup connections that we created (not the current connection)
            if (_sourceConnection != null && _sourceConnection != _currentConnection)
            {
                _sourceConnection.Dispose();
            }
            if (_targetConnection != null && _targetConnection != _currentConnection && _targetConnection != _sourceConnection)
            {
                _targetConnection.Dispose();
            }

            CloseRequested?.Invoke(this, EventArgs.Empty);
        }

        #endregion
    }

    /// <summary>
    /// Event args for script generation
    /// </summary>
    public class MigrationScriptEventArgs : EventArgs
    {
        public MigrationScript Script { get; set; } = new();
        public IConnectionManager ConnectionManager { get; set; } = null!;
    }
}
