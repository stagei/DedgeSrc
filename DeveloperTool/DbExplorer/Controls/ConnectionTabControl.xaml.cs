using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Xml;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.Highlighting.Xshd;
using ICSharpCode.AvalonEdit.CodeCompletion;
using Microsoft.Extensions.Configuration;
using NLog;
using DbExplorer.Data;
using DbExplorer.Dialogs;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class ConnectionTabControl : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly DatabaseConnection _connection;
    private readonly SqlFormatterService _formatterService;
    private readonly QueryHistoryService _queryHistoryService;
    private readonly ExportService _exportService;
    private readonly PreferencesService _preferencesService;
    private readonly SqlSafetyValidatorService _safetyValidator;
    private ObjectBrowserService? _objectBrowserService;
    private UserAccessLevel _userAccessLevel = UserAccessLevel.Standard;
    private readonly IntellisenseService _intellisenseService;
    private IntelliSenseManager? _newIntelliSenseManager; // New IntelliSense system
    private CompletionWindow? _completionWindow;
    
    // Pagination state
    private string _lastExecutedSql = string.Empty;
    private int _currentPage = 1;
    private int _currentOffset = 0;
    
    // Cell copy state (Issue #1 fix)
    private DataGridCellInfo? _lastClickedCell;
    private System.Windows.Point _lastRightClickPosition;

    /// <summary>
    /// Public property to access the connection manager for monitoring and management
    /// </summary>
    public IConnectionManager ConnectionManager => _connectionManager;
    
    /// <summary>
    /// Public property to access the connection information (database-agnostic)
    /// </summary>
    public DatabaseConnection Connection => _connection;

    public ConnectionTabControl(DatabaseConnection connection)
    {
        InitializeComponent();
        Logger.Debug($"ConnectionTabControl initializing for {connection.GetDisplayName()}");

        _connection = connection;
        _connectionManager = ConnectionManagerFactory.CreateConnectionManager(connection);
        _formatterService = new SqlFormatterService();
        _queryHistoryService = new QueryHistoryService();
        _exportService = new ExportService();
        _preferencesService = new PreferencesService();
        _safetyValidator = new SqlSafetyValidatorService();
        // Get provider from connection (default to DB2 for backward compatibility)
        var provider = connection.ProviderType?.ToUpperInvariant() ?? "DB2";
        var version = "12.1"; // TODO: Detect version from connection
        _intellisenseService = new IntellisenseService(provider, version);

        InitializeSqlEditor();
        RegisterKeyboardShortcuts();
        RegisterResultsGridEvents();
        RegisterObjectBrowserKeyboardShortcuts();
        RegisterDragDropHandlers();
        InitializeObjectBrowserAutoGrow();
        ApplyGridPreferences();
        _ = ConnectToDatabase();
        
        Logger.Debug($"Pagination enabled with max rows: {_preferencesService.Preferences.MaxRowsPerQuery}");
    }
    
    private ObjectBrowserSettings? _objectBrowserSettings;
    private DateTime _lastAutoGrowUpdate = DateTime.MinValue;
    
    /// <summary>
    /// Apply grid preferences from user settings to Results Grid and Object Browser
    /// </summary>
    public void ApplyGridPreferences()
    {
        if (_preferencesService != null)
        {
            // Reload preferences to get latest values
            _preferencesService.Reload();

            // Apply all UI styles to this control
            UIStyleService.ApplyStyles(this);
            
            // Explicitly refresh the ResultsGrid with new font and row height
            RefreshResultsGridSizing();
            
            // Apply spacing to all existing TreeViewItems
            ApplyTreeViewSpacingToAll(DatabaseTreeView);
            
            // Apply editor theme
            ApplyEditorTheme();
            
            Logger.Debug("Grid preferences applied - FontSize: {0}, CellHeight: {1}, Spacing: {2}", 
                _preferencesService.Preferences.GridFontSize,
                _preferencesService.Preferences.GridCellHeight,
                GetTreeViewItemSpacing());
        }
    }
    
    /// <summary>
    /// Explicitly refresh the ResultsGrid sizing (font, row height, column widths)
    /// </summary>
    private void RefreshResultsGridSizing()
    {
        try
        {
            var prefs = _preferencesService?.Preferences;
            if (prefs == null) return;
            
            // Apply font size and row height to the grid
            ResultsGrid.FontSize = prefs.GridFontSize;
            ResultsGrid.RowHeight = prefs.GridCellHeight;
            
            // Create a cell style that explicitly sets font size for cell content
            var cellStyle = new Style(typeof(DataGridCell));
            cellStyle.Setters.Add(new Setter(Control.FontSizeProperty, (double)prefs.GridFontSize));
            cellStyle.Setters.Add(new Setter(Control.FontFamilyProperty, new System.Windows.Media.FontFamily(prefs.GridFontFamily)));
            ResultsGrid.CellStyle = cellStyle;
            
            // Force the grid to re-generate columns by rebinding the data source
            // The AutoGeneratingColumn event handler will apply the correct font styles
            if (ResultsGrid.ItemsSource != null)
            {
                var currentSource = ResultsGrid.ItemsSource;
                ResultsGrid.Columns.Clear();
                ResultsGrid.ItemsSource = null;
                ResultsGrid.ItemsSource = currentSource;
            }
            
            // Use dispatcher to set SizeToCells after columns are regenerated
            Dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    foreach (var column in ResultsGrid.Columns)
                    {
                        column.Width = new DataGridLength(1, DataGridLengthUnitType.SizeToCells);
                    }
                    ResultsGrid.UpdateLayout();
                }
                catch { /* Ignore errors */ }
            }), System.Windows.Threading.DispatcherPriority.Loaded);
            
            Logger.Debug("ResultsGrid sizing refreshed - FontSize: {0}, RowHeight: {1}",
                prefs.GridFontSize, prefs.GridCellHeight);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error refreshing ResultsGrid sizing");
        }
    }

    /// <summary>
    /// Apply editor theme colors from preferences
    /// </summary>
    private void ApplyEditorTheme()
    {
        try
        {
            var prefs = _preferencesService?.Preferences;
            if (prefs == null) return;

            // Convert hex colors to brushes
            var bgColor = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(prefs.EditorBackgroundColor);
            var fgColor = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(prefs.EditorForegroundColor);
            var lineNumColor = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(prefs.EditorLineNumberColor);
            var currentLineColor = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(prefs.EditorCurrentLineColor);

            // Apply background and foreground
            SqlEditor.Background = new System.Windows.Media.SolidColorBrush(bgColor);
            SqlEditor.Foreground = new System.Windows.Media.SolidColorBrush(fgColor);

            // Apply line number color
            SqlEditor.LineNumbersForeground = new System.Windows.Media.SolidColorBrush(lineNumColor);

            // Apply current line highlight
            SqlEditor.TextArea.TextView.CurrentLineBackground = new System.Windows.Media.SolidColorBrush(currentLineColor);
            SqlEditor.TextArea.TextView.CurrentLineBorder = new System.Windows.Media.Pen(
                new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(40, 255, 255, 255)), 1);

            // Apply font settings
            SqlEditor.FontFamily = new System.Windows.Media.FontFamily(prefs.FontFamily);
            SqlEditor.FontSize = prefs.FontSize;

            Logger.Debug("Editor theme applied - Background: {0}, Foreground: {1}", 
                prefs.EditorBackgroundColor, prefs.EditorForegroundColor);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to apply editor theme");
        }
    }
    
    #region Object Browser Font Helpers
    
    /// <summary>
    /// Get configured font size for object browser from preferences (default 12)
    /// </summary>
    private double GetTreeViewFontSize()
    {
        return _preferencesService?.Preferences.GridFontSize > 0 
            ? _preferencesService.Preferences.GridFontSize 
            : 12;
    }
    
    /// <summary>
    /// Get configured font family for object browser from preferences (default Segoe UI)
    /// </summary>
    private System.Windows.Media.FontFamily GetTreeViewFontFamily()
    {
        var fontName = !string.IsNullOrWhiteSpace(_preferencesService?.Preferences.GridFontFamily) 
            ? _preferencesService.Preferences.GridFontFamily 
            : "Segoe UI";
        return new System.Windows.Media.FontFamily(fontName);
    }
    
    /// <summary>
    /// Get configured TreeView item vertical spacing from preferences (default 2)
    /// </summary>
    private int GetTreeViewItemSpacing()
    {
        return _preferencesService?.Preferences.TreeViewItemSpacing ?? 2;
    }
    
    /// <summary>
    /// Apply font and spacing settings to a TreeViewItem
    /// </summary>
    private void ApplyTreeViewItemFont(TreeViewItem item)
    {
        item.FontSize = GetTreeViewFontSize();
        item.FontFamily = GetTreeViewFontFamily();
        var spacing = GetTreeViewItemSpacing();
        item.Margin = new Thickness(0, spacing / 2.0, 0, spacing / 2.0);
    }
    
    /// <summary>
    /// Apply TreeView spacing to all items recursively
    /// </summary>
    private void ApplyTreeViewSpacingToAll(ItemsControl parent)
    {
        var spacing = GetTreeViewItemSpacing();
        var fontSize = GetTreeViewFontSize();
        var fontFamily = GetTreeViewFontFamily();
        
        foreach (var item in parent.Items)
        {
            if (item is TreeViewItem tvi)
            {
                tvi.FontSize = fontSize;
                tvi.FontFamily = fontFamily;
                tvi.Margin = new Thickness(0, spacing / 2.0, 0, spacing / 2.0);
                
                if (tvi.Items.Count > 0)
                {
                    ApplyTreeViewSpacingToAll(tvi);
                }
            }
        }
    }
    
    #endregion
    
    /// <summary>
    /// Initialize auto-grow width for object browser
    /// </summary>
    private void InitializeObjectBrowserAutoGrow()
    {
        try
        {
            var configuration = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                .Build();
            
            var config = configuration.Get<AppSettings>();
            _objectBrowserSettings = config?.ObjectBrowser;
            
            // Check user preference override
            var preferences = App.PreferencesService?.Preferences;
            bool userDisabledAutoResize = preferences?.DisableObjectBrowserAutoResize == true;
            
            if (_objectBrowserSettings?.AutoGrowWidth == true && !userDisabledAutoResize)
            {
                Logger.Debug("Object browser auto-grow enabled (Min: {Min}px, Max: {Max}px)", 
                    _objectBrowserSettings.MinWidth, _objectBrowserSettings.MaxWidth);
                
                DatabaseTreeView.Loaded += (s, e) =>
                {
                    // Use Dispatcher to ensure UI is fully rendered before measuring
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        AutoAdjustObjectBrowserWidth();
                    }), System.Windows.Threading.DispatcherPriority.Loaded);
                };
                
                // Use a throttled approach to avoid excessive layout updates
                DatabaseTreeView.SizeChanged += (s, e) =>
                {
                    if ((DateTime.Now - _lastAutoGrowUpdate).TotalMilliseconds > 500)
                    {
                        AutoAdjustObjectBrowserWidth();
                        _lastAutoGrowUpdate = DateTime.Now;
                    }
                };
                
                // Hook into TreeView item expansion to auto-resize
                DatabaseTreeView.AddHandler(TreeViewItem.ExpandedEvent, new RoutedEventHandler(OnTreeViewItemExpanded));
                DatabaseTreeView.AddHandler(TreeViewItem.CollapsedEvent, new RoutedEventHandler(OnTreeViewItemCollapsed));
            }
            else
            {
                Logger.Debug("Object browser auto-grow disabled (app setting: {AppSetting}, user override: {UserOverride})", 
                    _objectBrowserSettings?.AutoGrowWidth, userDisabledAutoResize);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize object browser auto-grow");
        }
    }
    
    /// <summary>
    /// Handle TreeViewItem expansion to trigger auto-resize
    /// </summary>
    private void OnTreeViewItemExpanded(object sender, RoutedEventArgs e)
    {
        // Force layout update first, then measure after all rendering is complete
        DatabaseTreeView.UpdateLayout();
        
        // Use ContextIdle priority - this runs only when the UI is completely idle after all rendering
        Dispatcher.BeginInvoke(new Action(() =>
        {
            // Force another layout pass to ensure children are fully rendered
            DatabaseTreeView.UpdateLayout();
            AutoAdjustObjectBrowserWidth();
        }), System.Windows.Threading.DispatcherPriority.ContextIdle);
    }
    
    /// <summary>
    /// Handle TreeViewItem collapse to trigger auto-resize
    /// </summary>
    private void OnTreeViewItemCollapsed(object sender, RoutedEventArgs e)
    {
        // Force layout update first, then measure after all rendering is complete
        DatabaseTreeView.UpdateLayout();
        
        // Use ContextIdle priority - this runs only when the UI is completely idle after all rendering
        Dispatcher.BeginInvoke(new Action(() =>
        {
            DatabaseTreeView.UpdateLayout();
            AutoAdjustObjectBrowserWidth();
        }), System.Windows.Threading.DispatcherPriority.ContextIdle);
    }
    
    /// <summary>
    /// Auto-adjust object browser column width to fit content
    /// </summary>
    private void AutoAdjustObjectBrowserWidth()
    {
        try
        {
            if (_objectBrowserSettings?.AutoGrowWidth != true)
                return;
            
            double maxWidth = _objectBrowserSettings.MaxWidth;
            double minWidth = _objectBrowserSettings.MinWidth;
            
            // Calculate the widest item in the tree
            double maxItemWidth = CalculateTreeViewMaxWidth(DatabaseTreeView);
            
            // Add padding for scrollbar and margins (35px)
            maxItemWidth += 35;
            
            // Clamp to min/max bounds
            double newWidth = Math.Max(minWidth, Math.Min(maxWidth, maxItemWidth));
            
            // Only update if significantly different to avoid constant layout updates
            if (Math.Abs(ObjectBrowserColumn.Width.Value - newWidth) > 10)
            {
                ObjectBrowserColumn.Width = new GridLength(newWidth);
                Logger.Debug($"Object browser width auto-adjusted to {newWidth:F0}px (content width: {maxItemWidth:F0}px)");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to auto-adjust object browser width");
        }
    }
    
    /// <summary>
    /// Calculate maximum width of items in TreeView
    /// </summary>
    private double CalculateTreeViewMaxWidth(TreeView treeView)
    {
        double maxWidth = 0;
        
        foreach (var item in treeView.Items)
        {
            if (item is TreeViewItem treeViewItem)
            {
                double itemWidth = MeasureTreeViewItemWidth(treeViewItem, 0);
                maxWidth = Math.Max(maxWidth, itemWidth);
            }
        }
        
        return maxWidth;
    }
    
    /// <summary>
    /// Measure width of a TreeViewItem including its indentation
    /// </summary>
    private double MeasureTreeViewItemWidth(TreeViewItem item, int depth)
    {
        double maxWidth = 0;
        
        // Measure current item
        if (item.Header is string headerText)
        {
            var formattedText = new FormattedText(
                headerText,
                System.Globalization.CultureInfo.CurrentCulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI"),
                12,
                System.Windows.Media.Brushes.Black,
                VisualTreeHelper.GetDpi(item).PixelsPerDip);
            
            // Add indentation (19px per level is WPF default)
            double itemWidth = formattedText.Width + (depth * 19) + 40; // 40px for icon/padding
            maxWidth = Math.Max(maxWidth, itemWidth);
        }
        else if (item.Header is StackPanel panel)
        {
            // Estimate width for StackPanel headers
            double itemWidth = 200 + (depth * 19); // Rough estimate
            maxWidth = Math.Max(maxWidth, itemWidth);
        }
        
        // Measure children if expanded
        if (item.IsExpanded)
        {
            foreach (var child in item.Items)
            {
                if (child is TreeViewItem childItem)
                {
                    double childWidth = MeasureTreeViewItemWidth(childItem, depth + 1);
                    maxWidth = Math.Max(maxWidth, childWidth);
                }
            }
        }
        
        return maxWidth;
    }
    
    /// <summary>
    /// Set SQL editor text (used when opening DDL in new tab)
    /// </summary>
    public void SetSqlEditorText(string text)
    {
        SqlEditor.Text = text;
        Logger.Debug("SQL editor text set programmatically");
    }
    
    /// <summary>
    /// Register keyboard shortcuts for object browser
    /// </summary>
    private void RegisterObjectBrowserKeyboardShortcuts()
    {
        Logger.Debug("Registering object browser keyboard shortcuts");
        
        // Ctrl+F to focus search box
        var focusSearchCommand = new RoutedCommand();
        focusSearchCommand.InputGestures.Add(new KeyGesture(Key.F, ModifierKeys.Control));
        CommandBindings.Add(new CommandBinding(focusSearchCommand, (s, e) =>
        {
            ObjectSearchBox.Focus();
            ObjectSearchBox.SelectAll();
            Logger.Debug("Object search box focused via Ctrl+F");
        }));
        
        // F5 to refresh object browser
        DatabaseTreeView.KeyDown += (s, e) =>
        {
            if (e.Key == Key.F5)
            {
                RefreshObjectBrowser_Click(s, e);
                e.Handled = true;
            }
        };
        
        // Enter to expand/collapse selected node
        DatabaseTreeView.KeyDown += (s, e) =>
        {
            if (e.Key == Key.Enter && DatabaseTreeView.SelectedItem is TreeViewItem item)
            {
                item.IsExpanded = !item.IsExpanded;
                e.Handled = true;
            }
        };
        
        // Ctrl+C to copy selected object name
        DatabaseTreeView.KeyDown += (s, e) =>
        {
            if (e.Key == Key.C && e.KeyboardDevice.Modifiers == ModifierKeys.Control)
            {
                if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is DatabaseObject obj)
                {
                    Clipboard.SetText(obj.FullName);
                    ObjectBrowserStatusText.Text = $"Copied: {obj.FullName}";
                    Logger.Debug("Copied object name: {Name}", obj.FullName);
                    e.Handled = true;
                }
            }
        };
    }
    
    /// <summary>
    /// Register drag-and-drop handlers for object browser
    /// </summary>
    private void RegisterDragDropHandlers()
    {
        Logger.Debug("Registering drag-and-drop handlers for object browser");
        
        // Enable drop on SQL editor
        SqlEditor.AllowDrop = true;
        SqlEditor.Drop += SqlEditor_Drop;
        SqlEditor.DragOver += SqlEditor_DragOver;
    }
    
    /// <summary>
    /// Handle mouse move to initiate drag operation
    /// </summary>
    private void ObjectNode_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed && sender is TreeViewItem item && item.Tag is DatabaseObject obj)
        {
            Logger.Debug("Initiating drag operation for object: {Name}", obj.FullName);
            
            // Create drag data
            var dragData = new DataObject();
            dragData.SetText(obj.FullName);
            dragData.SetData("DatabaseObject", obj);
            
            // Start drag operation
            DragDrop.DoDragDrop(item, dragData, DragDropEffects.Copy);
        }
    }
    
    /// <summary>
    /// Handle drag over SQL editor
    /// </summary>
    private void SqlEditor_DragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.Text) || e.Data.GetDataPresent("DatabaseObject"))
        {
            e.Effects = DragDropEffects.Copy;
        }
        else
        {
            e.Effects = DragDropEffects.None;
        }
        e.Handled = true;
    }
    
    /// <summary>
    /// Handle drop on SQL editor
    /// </summary>
    private void SqlEditor_Drop(object sender, DragEventArgs e)
    {
        try
        {
            if (e.Data.GetData("DatabaseObject") is DatabaseObject obj)
            {
                Logger.Debug("Dropped database object: {Name}", obj.FullName);

                // Requirement: drag/drop should insert the object name at the current caret position.
                InsertTextAtCursor(obj.FullName);
                ObjectBrowserStatusText.Text = $"Inserted: {obj.FullName}";
            }
            else if (e.Data.GetData("PackageInfo") is PackageInfo pkg)
            {
                var fullName = $"{pkg.PackageSchema}.{pkg.PackageName}";
                Logger.Debug("Dropped package: {Name}", fullName);
                InsertTextAtCursor(fullName);
                ObjectBrowserStatusText.Text = $"Inserted: {fullName}";
            }
            else if (e.Data.GetData("TablespaceInfo") is TablespaceInfo ts)
            {
                Logger.Debug("Dropped tablespace: {Name}", ts.TablespaceName);
                InsertTextAtCursor(ts.TablespaceName);
                ObjectBrowserStatusText.Text = $"Inserted: {ts.TablespaceName}";
            }
            else if (e.Data.GetDataPresent(DataFormats.Text))
            {
                var text = e.Data.GetData(DataFormats.Text) as string;
                if (!string.IsNullOrEmpty(text))
                {
                    InsertTextAtCursor(text);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to handle drop operation");
            ObjectBrowserStatusText.Text = "Failed to insert object";
        }
    }
    
    /// <summary>
    /// Register results grid event handlers (Issue #1 fix)
    /// </summary>
    private void RegisterResultsGridEvents()
    {
        Logger.Debug("Registering ResultsGrid event handlers");
        
        // Capture cell info on right-click before context menu opens
        ResultsGrid.PreviewMouseRightButtonDown += ResultsGrid_PreviewMouseRightButtonDown;
        
        // Handle auto-generated columns to apply font styles
        ResultsGrid.AutoGeneratingColumn += ResultsGrid_AutoGeneratingColumn;
    }
    
    /// <summary>
    /// Apply font styles to auto-generated columns
    /// </summary>
    private void ResultsGrid_AutoGeneratingColumn(object? sender, DataGridAutoGeneratingColumnEventArgs e)
    {
        try
        {
            var prefs = _preferencesService?.Preferences;
            if (prefs == null) return;
            
            // Apply font styles to text columns
            if (e.Column is DataGridTextColumn textColumn)
            {
                var elementStyle = new Style(typeof(System.Windows.Controls.TextBlock));
                elementStyle.Setters.Add(new Setter(System.Windows.Controls.TextBlock.FontSizeProperty, (double)prefs.GridFontSize));
                elementStyle.Setters.Add(new Setter(System.Windows.Controls.TextBlock.FontFamilyProperty, new System.Windows.Media.FontFamily(prefs.GridFontFamily)));
                textColumn.ElementStyle = elementStyle;
            }
            
            // Set minimum width based on font size
            e.Column.MinWidth = Math.Max(30, prefs.GridFontSize * 3);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error applying style to auto-generated column: {0}", e.Column.Header);
        }
    }
    
    /// <summary>
    /// Capture clicked cell before context menu opens (Issue #1 fix)
    /// </summary>
    private void ResultsGrid_PreviewMouseRightButtonDown(object sender, MouseButtonEventArgs e)
    {
        Logger.Debug("Right-click detected on results grid");
        
        try
        {
            // Get the clicked element
            var dep = (DependencyObject)e.OriginalSource;
            
            // Walk up the visual tree to find DataGridCell
            while (dep != null && !(dep is DataGridCell))
            {
                dep = System.Windows.Media.VisualTreeHelper.GetParent(dep);
            }
            
            if (dep is DataGridCell cell)
            {
                _lastClickedCell = new DataGridCellInfo(cell);
                _lastRightClickPosition = e.GetPosition(ResultsGrid);
                
                var rowIndex = ResultsGrid.Items.IndexOf(cell.DataContext);
                Logger.Debug("Captured cell info - Column: {Column}, Row: {Row}", 
                    cell.Column?.Header, rowIndex);
            }
            else
            {
                Logger.Debug("Right-click not on a DataGridCell");
                _lastClickedCell = null;
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error capturing cell info on right-click");
            _lastClickedCell = null;
        }
    }

    private void RegisterKeyboardShortcuts()
    {
        Logger.Debug("Registering editor keyboard shortcuts");

        SqlEditor.PreviewKeyDown += (s, e) =>
        {
            // F5 - Execute Query
            if (e.Key == Key.F5)
            {
                e.Handled = true;
                _ = ExecuteQuery();
            }
            // Ctrl+Enter - Execute Current Statement
            else if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
            {
                e.Handled = true;
                _ = ExecuteCurrentStatement();
            }
            // Ctrl+Shift+F - Format SQL
            else if (e.Key == Key.F && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control 
                     && (Keyboard.Modifiers & ModifierKeys.Shift) == ModifierKeys.Shift)
            {
                e.Handled = true;
                FormatSql();
            }
            // Ctrl+S - Save Script
            else if (e.Key == Key.S && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
            {
                e.Handled = true;
                SaveScript();
            }
            // Ctrl+O - Open Script
            else if (e.Key == Key.O && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
            {
                e.Handled = true;
                OpenScript();
            }
            // Ctrl+Shift+C - Commit Transaction
            else if (e.Key == Key.C && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control && (Keyboard.Modifiers & ModifierKeys.Shift) == ModifierKeys.Shift)
            {
                e.Handled = true;
                _ = CommitTransaction();
            }
            // Ctrl+Shift+R - Rollback Transaction
            else if (e.Key == Key.R && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control && (Keyboard.Modifiers & ModifierKeys.Shift) == ModifierKeys.Shift)
            {
                e.Handled = true;
                _ = RollbackTransaction();
            }
        };
    }

    private void InitializeSqlEditor()
    {
        Logger.Debug("Initializing SQL Editor");

        try
        {
            // Load custom DB2 SQL syntax highlighting (moved to SyntaxHighlighting subfolder)
            var xshdPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "SyntaxHighlighting", "DB2SQL.xshd");
            
            if (File.Exists(xshdPath))
            {
                using var reader = new XmlTextReader(xshdPath);
                var definition = HighlightingLoader.Load(reader, HighlightingManager.Instance);
                SqlEditor.SyntaxHighlighting = definition;
                Logger.Debug("DB2 SQL syntax highlighting loaded from: {Path}", xshdPath);
            }
            else
            {
                Logger.Warn($"Syntax highlighting file not found: {xshdPath}");
                // Try legacy path for backward compatibility
                var legacyPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "DB2SQL.xshd");
                if (File.Exists(legacyPath))
                {
                    using var reader = new XmlTextReader(legacyPath);
                    var definition = HighlightingLoader.Load(reader, HighlightingManager.Instance);
                    SqlEditor.SyntaxHighlighting = definition;
                    Logger.Debug("DB2 SQL syntax highlighting loaded from legacy path: {Path}", legacyPath);
                }
                else
                {
                    // Use SQL as fallback
                    SqlEditor.SyntaxHighlighting = HighlightingManager.Instance.GetDefinition("SQL");
                    Logger.Warn("Using default SQL syntax highlighting as fallback");
                }
            }

            // Set editor options
            SqlEditor.Options.EnableHyperlinks = false;
            SqlEditor.Options.EnableEmailHyperlinks = false;
            SqlEditor.Options.ShowTabs = true;
            SqlEditor.Options.ShowSpaces = false;

            // Apply editor theme colors
            ApplyEditorTheme();

            // Set initial SQL
            SqlEditor.Text = "-- Enter your SQL query here\nSELECT * FROM YOUR_TABLE;";

            // Register intellisense events
            SqlEditor.TextArea.TextEntering += TextEditor_TextEntering;
            SqlEditor.TextArea.TextEntered += TextEditor_TextEntered;
            SqlEditor.TextArea.KeyDown += TextEditor_KeyDown;

            Logger.Info("SQL Editor initialized successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize SQL Editor");
        }
    }
    
    /// <summary>
    /// Handle text entering (before character is inserted)
    /// </summary>
    private void TextEditor_TextEntering(object? sender, TextCompositionEventArgs e)
    {
        if (e.Text.Length > 0 && _completionWindow != null)
        {
            // Insert the completion if Enter/Tab is pressed
            if (!char.IsLetterOrDigit(e.Text[0]) && e.Text[0] != '_')
            {
                _completionWindow.CompletionList.RequestInsertion(e);
            }
        }
    }
    
    /// <summary>
    /// Handle text entered (after character is inserted)
    /// </summary>
    private void TextEditor_TextEntered(object? sender, TextCompositionEventArgs e)
    {
        // Handle period entry - remove duplicate periods
        if (e.Text == ".")
        {
            var caretOffset = SqlEditor.CaretOffset;
            
            // Check if there's a double period (previous character is also a period)
            // Caret is now AFTER the newly typed period, so check 2 chars back
            if (caretOffset >= 2)
            {
                var twoCharsBack = SqlEditor.Document.GetText(caretOffset - 2, 1);
                if (twoCharsBack == ".")
                {
                    // Remove the duplicate period (the one we just typed)
                    Logger.Debug("Removing duplicate period at position {Position}", caretOffset);
                    SqlEditor.Document.Remove(caretOffset - 1, 1);
                    // Don't show completion window since we're cleaning up
                    return;
                }
            }
            
            // No duplicate - show completion window for schema.table
            ShowCompletionWindow();
            return;
        }
        
        // If completion window is already open, update filtering dynamically
        if (_completionWindow != null)
        {
            // Update the StartOffset and filter the list based on the new word
            UpdateCompletionWindowFilter();
            return;
        }
        
        // Show completion after space (for keywords)
        if (e.Text == " ")
        {
            ShowCompletionWindow();
        }
        // Also show after typing 2+ characters
        else if (char.IsLetter(e.Text[0]))
        {
            var currentWord = GetCurrentWord();
            if (currentWord.Length >= 2)
            {
                ShowCompletionWindow();
            }
        }
    }
    
    /// <summary>
    /// Handle Ctrl+Space to manually trigger intellisense, Ctrl+K for AI SQL edit, and Backspace to re-trigger
    /// </summary>
    private void TextEditor_KeyDown(object? sender, KeyEventArgs e)
    {
        // Ctrl+K - AI SQL edit (Edit selected code)
        if (e.Key == Key.K && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
        {
            var selectedText = SqlEditor.SelectedText?.Trim() ?? "";
            if (!string.IsNullOrEmpty(selectedText))
            {
                e.Handled = true;
                OpenSqlEditWithAiDialog(selectedText);
            }
            return;
        }
        // Ctrl+Space - Force show context-aware IntelliSense
        if (e.Key == Key.Space && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
        {
            e.Handled = true;
            ForceContextAwareCompletion();
        }
        // Backspace - Re-trigger IntelliSense if window was open
        else if (e.Key == Key.Back && _completionWindow != null)
        {
            // Close current window and re-show after backspace is processed
            _completionWindow.Close();
            _completionWindow = null;
            
            // Schedule re-trigger after backspace is processed
            Dispatcher.BeginInvoke(new Action(() =>
            {
                var currentWord = GetCurrentWord();
                if (currentWord.Length > 0)
                {
                    ShowCompletionWindow();
                }
            }), System.Windows.Threading.DispatcherPriority.Background);
        }
    }
    
    /// <summary>
    /// Force context-aware IntelliSense completion (Ctrl+Space)
    /// Analyzes the SQL statement and cursor position to show relevant suggestions
    /// </summary>
    private void ForceContextAwareCompletion()
    {
        try
        {
            Logger.Debug("Ctrl+Space triggered - forcing context-aware completion");
            
            // Close existing window
            if (_completionWindow != null)
            {
                _completionWindow.Close();
                _completionWindow = null;
            }
            
            var text = SqlEditor.Text;
            var caretPosition = SqlEditor.CaretOffset;
            
            // Get the current word at caret position
            var currentWord = GetCurrentWord();
            
            Logger.Debug("Force completion at position {Position}, current word: '{Word}'", 
                caretPosition, currentWord);
            
            // Get context-aware completions from the new IntelliSense manager
            List<ICSharpCode.AvalonEdit.CodeCompletion.ICompletionData>? completions = null;
            
            if (_newIntelliSenseManager != null)
            {
                completions = _newIntelliSenseManager.GetCompletions(text, caretPosition, _connectionManager);
            }
            
            // Fallback to old IntelliSense if no results
            if (completions == null || completions.Count == 0)
            {
                Logger.Debug("No completions from manager, trying fallback");
                var suggestions = _intellisenseService.GetSuggestions(currentWord);
                if (suggestions.Count == 0)
                {
                    Logger.Debug("No suggestions available");
                    return;
                }
                
                _completionWindow = new ICSharpCode.AvalonEdit.CodeCompletion.CompletionWindow(SqlEditor.TextArea);
                _completionWindow.StartOffset = SqlEditor.CaretOffset - currentWord.Length;
                
                foreach (var suggestion in suggestions)
                {
                    _completionWindow.CompletionList.CompletionData.Add(new SqlCompletionData(suggestion));
                }
            }
            else
            {
                // Filter based on current word if there is one
                var filteredCompletions = completions;
                if (!string.IsNullOrWhiteSpace(currentWord))
                {
                    filteredCompletions = completions
                        .Where(c => c.Text.StartsWith(currentWord, StringComparison.OrdinalIgnoreCase))
                        .ToList();
                    
                    // If no prefix matches, try contains
                    if (filteredCompletions.Count == 0)
                    {
                        filteredCompletions = completions
                            .Where(c => c.Text.Contains(currentWord, StringComparison.OrdinalIgnoreCase))
                            .Take(50)
                            .ToList();
                    }
                }
                
                if (filteredCompletions.Count == 0)
                {
                    // Show all completions if no filter matches
                    filteredCompletions = completions.Take(50).ToList();
                }
                
                _completionWindow = new ICSharpCode.AvalonEdit.CodeCompletion.CompletionWindow(SqlEditor.TextArea);
                _completionWindow.StartOffset = SqlEditor.CaretOffset - currentWord.Length;
                
                foreach (var completion in filteredCompletions)
                {
                    _completionWindow.CompletionList.CompletionData.Add(completion);
                }
            }
            
            _completionWindow.Closed += (s, args) => _completionWindow = null;
            _completionWindow.Show();
            
            Logger.Info("Context-aware completion shown with {Count} items", 
                _completionWindow.CompletionList.CompletionData.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show context-aware completion");
        }
    }
    
    /// <summary>
    /// Show intellisense completion window
    /// </summary>
    /// <summary>
    /// Initialize new IntelliSense system
    /// </summary>
    private async Task InitializeIntelliSenseAsync()
    {
        try
        {
            Logger.Debug("Initializing new IntelliSense system");
            
            _newIntelliSenseManager = new IntelliSenseManager();
            
            // Get provider from connection (default to DB2 for backward compatibility)
            var provider = _connection.ProviderType?.ToUpperInvariant() ?? "DB2";
            var dbVersion = "12.1"; // TODO: Detect version from connection
            
            // Register provider-specific IntelliSense (for now only DB2 is implemented)
            if (provider == "DB2")
            {
                _newIntelliSenseManager.RegisterProvider("DB2", new Db2IntelliSenseProvider());
            }
            
            // Initialize provider with metadata
            await _newIntelliSenseManager.SetActiveProviderAsync(provider, dbVersion, _connectionManager);
            
            // Set callback to trigger table/column completion after schema selection
            _newIntelliSenseManager.SetCompletionCallback(() =>
            {
                // Use dispatcher to ensure we're on UI thread and after current completion closes
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    Logger.Debug("Schema completion callback triggered - showing table completions");
                    ShowNewCompletionWindow();
                }), System.Windows.Threading.DispatcherPriority.Background);
            });
            
            Logger.Info("IntelliSense system initialized successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize IntelliSense");
        }
    }
    
    private void ShowCompletionWindow()
    {
        try
        {
            // Use new IntelliSense if available, fallback to old
            if (_newIntelliSenseManager != null)
            {
                ShowNewCompletionWindow();
                return;
            }
            
            var currentWord = GetCurrentWord();
            if (string.IsNullOrWhiteSpace(currentWord))
                return;
            
            Logger.Debug("Showing completion window for: '{Word}'", currentWord);
            
            var suggestions = _intellisenseService.GetSuggestions(currentWord);
            if (suggestions.Count == 0)
            {
                Logger.Debug("No suggestions found for: '{Word}'", currentWord);
                return;
            }
            
            _completionWindow = new CompletionWindow(SqlEditor.TextArea);
            var data = _completionWindow.CompletionList.CompletionData;
            
            foreach (var suggestion in suggestions)
            {
                data.Add(new SqlCompletionData(suggestion));
            }
            
            _completionWindow.Closed += (s, args) => _completionWindow = null;
            _completionWindow.Show();
            
            Logger.Debug("Completion window shown with {Count} suggestions", suggestions.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show completion window");
        }
    }
    
    /// <summary>
    /// Show new IntelliSense completion window
    /// </summary>
    private void ShowNewCompletionWindow()
    {
        try
        {
            // Close existing window first
            if (_completionWindow != null)
            {
                _completionWindow.Close();
                _completionWindow = null;
            }
            
            // Get current word and whether we're after a period (schema.object context)
            var currentWord = GetCurrentWord(out bool isAfterPeriod);
            Logger.Debug("Showing new IntelliSense for word: '{Word}', after period: {AfterPeriod}", currentWord, isAfterPeriod);
            
            var completions = _newIntelliSenseManager?.GetCompletions(
                SqlEditor.Text,
                SqlEditor.CaretOffset,
                _connectionManager);
            
            if (completions == null || completions.Count == 0)
            {
                Logger.Debug("No completions available from provider");
                
                // Fallback to old IntelliSense
                var suggestions = _intellisenseService.GetSuggestions(currentWord);
                if (suggestions.Count == 0)
                {
                    Logger.Debug("No suggestions found");
                return;
            }
            
            _completionWindow = new CompletionWindow(SqlEditor.TextArea);
                _completionWindow.StartOffset = SqlEditor.CaretOffset - currentWord.Length;
            
                foreach (var suggestion in suggestions)
            {
                    _completionWindow.CompletionList.CompletionData.Add(new SqlCompletionData(suggestion));
            }
            
            _completionWindow.Closed += (s, args) => _completionWindow = null;
            _completionWindow.Show();
            
                // Auto-select if only one item - user can just press Enter
                if (suggestions.Count == 1)
                {
                    _completionWindow.CompletionList.SelectedItem = _completionWindow.CompletionList.CompletionData[0];
                    Logger.Debug("Auto-selected single fallback item");
                }
            
                Logger.Debug("Fallback IntelliSense shown with {Count} suggestions", suggestions.Count);
                return;
            }
            
            // Filter completions based on current word
            var filteredCompletions = completions;
            if (!string.IsNullOrWhiteSpace(currentWord))
            {
                filteredCompletions = completions
                    .Where(c => c.Text.StartsWith(currentWord, StringComparison.OrdinalIgnoreCase))
                    .ToList();
                
                // If no prefix matches, try contains
                if (filteredCompletions.Count == 0)
                {
                    filteredCompletions = completions
                        .Where(c => c.Text.Contains(currentWord, StringComparison.OrdinalIgnoreCase))
                        .Take(30)
                        .ToList();
                }
            }
            else
            {
                filteredCompletions = completions.Take(30).ToList();
            }
            
            if (filteredCompletions.Count == 0)
            {
                Logger.Debug("No matching completions after filtering");
                return;
            }
            
            _completionWindow = new CompletionWindow(SqlEditor.TextArea);
            
            // Set the start offset to replace only the current word (not the schema prefix)
            // When we're after a period (schema.object context), only replace what comes after the period
            _completionWindow.StartOffset = SqlEditor.CaretOffset - currentWord.Length;
            
            Logger.Debug("Completion StartOffset: {Offset}, CaretOffset: {Caret}, WordLength: {Len}", 
                _completionWindow.StartOffset, SqlEditor.CaretOffset, currentWord.Length);
            
            foreach (var completion in filteredCompletions)
            {
                // Wire up OnCompleted callback for schema completions to auto-trigger table list
                if (completion is SqlSchemaCompletionData schemaCompletion)
                {
                    schemaCompletion.OnCompleted = () =>
                    {
                        // Schedule showing the next completion window after this one closes
                        Dispatcher.BeginInvoke(new Action(() =>
                        {
                            // Small delay to let the period be inserted
                            System.Threading.Tasks.Task.Delay(50).ContinueWith(_ =>
                            {
                                Dispatcher.Invoke(() => ShowNewCompletionWindow());
                            });
                        }), System.Windows.Threading.DispatcherPriority.Background);
                    };
                }
                
                _completionWindow.CompletionList.CompletionData.Add(completion);
            }
            
            _completionWindow.Closed += (s, args) => _completionWindow = null;
            
            // Add handler to auto-select when filtering reduces to one item
            _completionWindow.CompletionList.ListBox.ItemContainerGenerator.StatusChanged += (s, args) =>
            {
                if (_completionWindow?.CompletionList?.ListBox != null)
                {
                    var listBox = _completionWindow.CompletionList.ListBox;
                    // Check if exactly one item is visible
                    if (listBox.Items.Count == 1 && listBox.SelectedIndex != 0)
                    {
                        listBox.SelectedIndex = 0;
                        Logger.Debug("Auto-selected single remaining completion item during filtering");
                    }
                }
            };
            
            _completionWindow.Show();
            
            // Auto-select if only one item - user can just press Enter
            if (filteredCompletions.Count == 1)
            {
                _completionWindow.CompletionList.SelectedItem = filteredCompletions[0];
                Logger.Debug("Auto-selected single completion item: {Item}", filteredCompletions[0].Text);
            }
            
            Logger.Info("IntelliSense window shown with {Count} completions (afterPeriod: {AfterPeriod})", 
                filteredCompletions.Count, isAfterPeriod);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show IntelliSense completion window");
        }
    }
    
    /// <summary>
    /// Update the completion window filter when user types while window is open
    /// </summary>
    private void UpdateCompletionWindowFilter()
    {
        if (_completionWindow == null)
            return;
            
        try
        {
            var currentWord = GetCurrentWord(out bool isAfterPeriod);
            Logger.Debug("Updating completion filter for word: '{Word}'", currentWord);
            
            // Update StartOffset to match the new word position
            _completionWindow.StartOffset = SqlEditor.CaretOffset - currentWord.Length;
            
            // Get all original completions (we need to re-filter them)
            // Since we can't easily get the original list, we'll regenerate completions
            // This is necessary because AvalonEdit doesn't maintain the original unfiltered list
            var completions = _newIntelliSenseManager?.GetCompletions(
                SqlEditor.Text,
                SqlEditor.CaretOffset,
                _connectionManager);
            
            if (completions == null || completions.Count == 0)
            {
                // Fallback to old IntelliSense
                var suggestions = _intellisenseService.GetSuggestions(currentWord);
                if (suggestions.Count == 0)
                {
                    Logger.Debug("No suggestions found after filtering, closing window");
                    _completionWindow.Close();
                    _completionWindow = null;
                    return;
                }
                
                // Clear and repopulate with filtered suggestions
                _completionWindow.CompletionList.CompletionData.Clear();
                foreach (var suggestion in suggestions)
                {
                    _completionWindow.CompletionList.CompletionData.Add(new SqlCompletionData(suggestion));
                }
                
                Logger.Debug("Updated completion window with {Count} filtered suggestions", suggestions.Count);
                return;
            }
            
            // Filter completions based on current word
            var filteredCompletions = completions;
            if (!string.IsNullOrWhiteSpace(currentWord))
            {
                filteredCompletions = completions
                    .Where(c => c.Text.StartsWith(currentWord, StringComparison.OrdinalIgnoreCase))
                    .ToList();
                
                // If no prefix matches, try contains
                if (filteredCompletions.Count == 0)
                {
                    filteredCompletions = completions
                        .Where(c => c.Text.Contains(currentWord, StringComparison.OrdinalIgnoreCase))
                        .Take(30)
                        .ToList();
                }
            }
            else
            {
                filteredCompletions = completions.Take(30).ToList();
            }
            
            if (filteredCompletions.Count == 0)
            {
                Logger.Debug("No matching completions after filtering, closing window");
                _completionWindow.Close();
                _completionWindow = null;
                return;
            }
            
            // Clear and repopulate with filtered completions
            _completionWindow.CompletionList.CompletionData.Clear();
            foreach (var completion in filteredCompletions)
            {
                // Wire up OnCompleted callback for schema completions
                if (completion is SqlSchemaCompletionData schemaCompletion)
                {
                    schemaCompletion.OnCompleted = () =>
                    {
                        Dispatcher.BeginInvoke(new Action(() =>
                        {
                            System.Threading.Tasks.Task.Delay(50).ContinueWith(_ =>
                            {
                                Dispatcher.Invoke(() => ShowNewCompletionWindow());
                            });
                        }), System.Windows.Threading.DispatcherPriority.Background);
                    };
                }
                
                _completionWindow.CompletionList.CompletionData.Add(completion);
            }
            
            // Auto-select first item if available
            if (filteredCompletions.Count > 0)
            {
                _completionWindow.CompletionList.SelectedItem = filteredCompletions[0];
            }
            
            Logger.Debug("Updated completion window with {Count} filtered completions", filteredCompletions.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to update completion window filter");
        }
    }
    
    /// <summary>
    /// Get the current word being typed at cursor position
    /// </summary>
    private string GetCurrentWord()
    {
        return GetCurrentWord(out _);
    }
    
    /// <summary>
    /// Get the current word being typed at cursor position
    /// Also returns whether we're after a period (schema.object context)
    /// </summary>
    private string GetCurrentWord(out bool isAfterPeriod)
    {
        isAfterPeriod = false;
        var offset = SqlEditor.CaretOffset;
        var text = SqlEditor.Text;
        
        if (offset == 0 || offset > text.Length)
            return string.Empty;
        
        // Check if character before caret is a period
        // e.g., "dbm." <- caret here, we're after period with empty word
        if (offset > 0 && text[offset - 1] == '.')
        {
            isAfterPeriod = true;
            return string.Empty;  // No word yet after the period
        }
        
        // Special handling for * - treat it as a word by itself
        if (offset > 0 && text[offset - 1] == '*')
        {
            return "*";
        }
        
        // Find start of current word (stop at period, space, or start of text)
        var start = offset - 1;
        while (start > 0 && (char.IsLetterOrDigit(text[start]) || text[start] == '_'))
        {
            start--;
        }
        
        // Check if there's a period before the word (schema.tabl context)
        if (start >= 0 && text[start] == '.')
        {
            isAfterPeriod = true;
        }
        
        // If we stopped on a non-word character, move forward
        if (start < offset - 1 && !char.IsLetterOrDigit(text[start]) && text[start] != '_')
        {
            start++;
        }
        
        // Extract word
        var length = offset - start;
        if (length <= 0)
            return string.Empty;
        
        return text.Substring(start, length);
    }

    private async Task ConnectToDatabase()
    {
        Logger.Info($"Connecting to database: {_connection.GetDisplayName()}");
        StatusText.Text = "Connecting...";

        // Get expected connection time from statistics
        var statsService = new ConnectionStatisticsService();
        var expectation = await statsService.GetExpectedConnectionTimeAsync(_connection.Server);
        
        Logger.Debug("Connection expectation: {Expected}ms (HasHistory: {HasHistory}, Total: {Total})", 
            expectation.ExpectedTimeMs, expectation.HasHistory, expectation.TotalConnections);

        // Create connection progress dialog on UI thread
        var progressDialog = new ConnectionProgressDialog(
            _connection.GetDisplayName(), 
            expectation.ExpectedTimeMs,
            expectation.HasHistory)
        {
            Owner = Window.GetWindow(this)
        };

        bool connectionSuccessful = false;
        int connectionTimeMs = 0;
        
        // Start connection in background task
        var connectionTask = Task.Run(async () =>
        {
            try
            {
                progressDialog.UpdateStatus("Establishing connection...");
                progressDialog.UpdateDetail($"Server: {_connection.Server}:{_connection.Port}");
                progressDialog.StartProgress(); // Start progress bar timer
                
                await _connectionManager.OpenAsync(progressDialog.CancellationToken);
                
                progressDialog.UpdateStatus("Connection established successfully!");
                progressDialog.UpdateDetail("Loading database objects...");
                
                // Close dialog on success
                progressDialog.CloseWithSuccess();
                
                return true;
            }
            catch (OperationCanceledException)
            {
                Logger.Warn("Connection cancelled by user");
                progressDialog.UpdateStatus("Connection aborted by user");
                progressDialog.CloseWithFailure();
                return false;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to connect to database");
                progressDialog.UpdateStatus("Connection failed");
                progressDialog.UpdateDetail(ex.Message);
                await Task.Delay(2000); // Show error for 2 seconds
                progressDialog.CloseWithFailure();
                return false;
            }
        });

        // Show dialog synchronously on UI thread (blocks until closed)
        var dialogResult = progressDialog.ShowDialog();
        
        // Wait for connection task to complete
        try
        {
            connectionSuccessful = await connectionTask;
        }
        catch (OperationCanceledException)
        {
            connectionSuccessful = false;
        }

        // Record connection time if successful
        connectionTimeMs = progressDialog.ElapsedTimeMs;
        if (connectionSuccessful)   
        {
            Logger.Info("Connection successful in {Time}ms", connectionTimeMs);
            _ = statsService.RecordConnectionTimeAsync(_connection.Server, connectionTimeMs);
        }

        if (connectionSuccessful)
        {
            StatusText.Text = $"Connected to {_connection.GetDisplayName()}";
            Logger.Info("Database connection established");

            // RBAC: Update access level indicator
            UpdateAccessLevelIndicator();
            
            // Feature #2: Update commit/rollback button visibility
            UpdateTransactionButtonsVisibility();
            
            // Initialize new IntelliSense system
            await InitializeIntelliSenseAsync();

            // Load database objects
            await LoadDatabaseObjectsAsync();
            
            // Load query history for this connection
            RefreshQueryHistory();
            
            // Feature #5: Background metadata collection (non-blocking)
            _ = Task.Run(async () =>
            {
                try
                {
                    Logger.Info("Starting background metadata collection");
                    // Check provider type for metadata collection support
                    var providerType = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
                    if (providerType == "DB2")
                    {
                        var metadataService = MetadataServiceFactory.CreateMetadataService(_connectionManager);
                        await metadataService.CollectMetadataAsync(_connectionManager, _connection.Name ?? _connection.GetDisplayName());
                    }
                    else
                    {
                        Logger.Warn("Metadata collection is not supported for this connection type");
                    }
                    Logger.Info("Background metadata collection completed");
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Background metadata collection failed");
                    // Don't show error to user - non-critical background task
                }
            });
            
            // Feature: Background preload of all object browser data for faster navigation
            _ = Task.Run(async () =>
            {
                try
                {
                    // Subscribe to progress updates
                    _objectBrowserService.PreloadProgressChanged += (s, msg) =>
                    {
                        Dispatcher.BeginInvoke(() =>
                        {
                            ObjectBrowserStatusText.Text = msg;
                        });
                    };
                    
                    await _objectBrowserService.PreloadAllDataAsync();
                    
                    Dispatcher.BeginInvoke(() =>
                    {
                        ObjectBrowserStatusText.Text = "Ready (data preloaded)";
                    });
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Background object browser preload failed");
                }
            });
        }
        else
        {
            StatusText.Text = "Connection failed or aborted";
            
            if (!progressDialog.WasAborted)
            {
                MessageBox.Show($"Failed to connect to {_connection.GetDisplayName()}.\n\nPlease check your connection settings and try again.", 
                    "Connection Error",
                    MessageBoxButton.OK, 
                    MessageBoxImage.Error);
            }
            else
            {
                Logger.Info("Connection aborted by user");
            }
        }
    }

    private async Task LoadDatabaseObjectsAsync()
    {
        Logger.Debug("Loading enhanced object browser with top-level categories");
        ObjectBrowserStatusText.Text = "Loading database objects...";
        
        // Show loading spinner on refresh button
        var wasSpinnerStartedHere = !_spinnerTimer?.IsEnabled ?? true;
        if (wasSpinnerStartedHere)
        {
            StartRefreshSpinner();
        }

        try
        {
            // Initialize ObjectBrowserService
            _objectBrowserService = new ObjectBrowserService(_connectionManager);
            
            // Determine user access level
            _userAccessLevel = await _objectBrowserService.GetUserAccessLevelAsync();
            Logger.Info($"User access level determined: {_userAccessLevel}");
            
            // Update database info header
            DatabaseInfoText.Text = $"🗄️ Database: {_connection.Database}";
            ConnectionInfoText.Text = $"Server: {_connection.Server}:{_connection.Port} | Access: {_userAccessLevel}";
            
            DatabaseTreeView.Items.Clear();
            
            // Add loading indicator
            var loadingNode = new TreeViewItem
            {
                Header = "⏳ Loading categories...",
                IsEnabled = false
            };
            DatabaseTreeView.Items.Add(loadingNode);
            
            // Load top-level categories filtered by access level
            var categories = await _objectBrowserService.GetTopLevelCategoriesAsync(_userAccessLevel);
            Logger.Info($"Loaded {categories.Count} categories for access level {_userAccessLevel}");

            DatabaseTreeView.Items.Clear();

            if (categories.Count == 0)
            {
                var noDataNode = new TreeViewItem
                {
                    Header = "⚠ No categories available",
                    IsEnabled = false
                };
                DatabaseTreeView.Items.Add(noDataNode);
                ObjectBrowserStatusText.Text = "No database objects available";
                return;
            }

            // Add each category as a top-level node
            foreach (var category in categories)
            {
                var categoryNode = new TreeViewItem
                {
                    Header = $"{category.Icon} {category.Name} ({category.Count})",
                    Tag = category
                };
                ApplyTreeViewItemFont(categoryNode);

                // Add placeholder for lazy loading
                if (category.IsLazyLoad && category.Count > 0)
                {
                    categoryNode.Items.Add("Loading...");
                    categoryNode.Expanded += CategoryNode_Expanded;
                }

                DatabaseTreeView.Items.Add(categoryNode);
            }

            ObjectBrowserStatusText.Text = $"Ready - {categories.Count} categories loaded";
            Logger.Debug($"Added {categories.Count} categories to TreeView");
            
            // Trigger auto-grow width adjustment after loading
            AutoAdjustObjectBrowserWidth();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load database objects");
            
            DatabaseTreeView.Items.Clear();
            var errorNode = new TreeViewItem
            {
                Header = $"❌ Error loading schemas: {ex.Message}",
                IsEnabled = false
            };
            DatabaseTreeView.Items.Add(errorNode);
            
            StatusText.Text = "Failed to load database objects";
        }
        finally
        {
            // Stop the spinner if we started it
            StopRefreshSpinner();
        }
    }

    /// <summary>
    /// Handle category node expansion (lazy load children)
    /// </summary>
    private async void CategoryNode_Expanded(object sender, RoutedEventArgs e)
    {
        if (sender is not TreeViewItem categoryNode) return;
        if (categoryNode.Tag is not CategoryNode category) return;
        if (_objectBrowserService == null) return;

        // Check if already loaded
        if (categoryNode.Items.Count == 1 && categoryNode.Items[0] is string)
        {
            Logger.Debug($"Expanding category: {category.Name}");
            categoryNode.Items.Clear();
            ObjectBrowserStatusText.Text = $"Loading {category.Name}...";

            try
            {
                if (category.Type == CategoryType.Schemas)
                {
                    var schemas = await _objectBrowserService.GetAllSchemasAsync();
                    Logger.Debug($"Found {schemas.Count} schemas");

                    foreach (var schemaNode in schemas)
                    {
                        var icon = schemaNode.Type == "SYSTEM" ? ObjectBrowserIcons.SystemSchema : ObjectBrowserIcons.Schema;
                        var schemaType = schemaNode.Type == "SYSTEM" ? "System Schema" : "User Schema";
                        var node = new TreeViewItem
                        {
                            Header = $"{icon} {schemaNode.SchemaName}",
                            Tag = schemaNode,
                            ToolTip = $"Schema: {schemaNode.SchemaName}\nType: {schemaType}"
                        };
                        ApplyTreeViewItemFont(node);

                        // Add placeholder for lazy loading
                        node.Items.Add("Loading...");
                        node.Expanded += SchemaNode_Expanded;
                        // Removed click handler - schemas should expand, not show dialog
                        categoryNode.Items.Add(node);
                    }
                }
                else if (category.Type == CategoryType.Tablespaces)
                {
                    var tablespaces = await _objectBrowserService.GetTablespacesAsync();
                    foreach (var ts in tablespaces)
                    {
                        var node = new TreeViewItem
                        {
                            Header = $"{ObjectBrowserIcons.Tablespaces} {ts.TablespaceName} ({ts.PageSize} bytes)",
                            Tag = ts,
                            ToolTip = $"Tablespace: {ts.TablespaceName}\nType: {ts.TablespaceType}\nPage Size: {ts.PageSize} bytes\nOwner: {ts.Owner}"
                        };
                        ApplyTreeViewItemFont(node);
                        node.PreviewMouseLeftButtonDown += TablespaceNode_Click;
                        node.MouseDoubleClick += TablespaceNode_DoubleClick;
                        node.ContextMenu = CreateTablespaceContextMenu(ts);
                        node.MouseMove += TablespaceNode_MouseMove;
                        categoryNode.Items.Add(node);
                    }
                }
                else if (category.Type == CategoryType.Aliases)
                {
                    // Show all aliases across all schemas
                    var schemas = await _objectBrowserService.GetAllSchemasAsync();
                    foreach (var schemaNode in schemas.Where(s => s.Type != "SYSTEM"))
                    {
                        var aliases = await _objectBrowserService.GetSynonymsAsync(schemaNode.SchemaName);
                        foreach (var alias in aliases)
                        {
                            var node = new TreeViewItem
                            {
                                Header = $"{alias.Icon} {alias.FullName} → {alias.TableSpace}",
                                Tag = alias
                            };
                            ApplyTreeViewItemFont(node);
                            // Behave like other database objects (single click inserts name, double click opens properties)
                            node.PreviewMouseLeftButtonDown += ObjectNode_Click;
                            node.MouseDoubleClick += ObjectNode_DoubleClick;
                            node.ContextMenu = CreateObjectContextMenu(alias);
                            node.MouseMove += ObjectNode_MouseMove;
                            categoryNode.Items.Add(node);
                        }
                    }
                }
                else if (category.Type == CategoryType.Packages)
                {
                    // Show all packages across all schemas
                    var packages = await _objectBrowserService.GetPackagesAsync();
                    foreach (var pkg in packages)
                    {
                        var node = new TreeViewItem
                        {
                            Header = $"{ObjectBrowserIcons.Package} {pkg.PackageSchema}.{pkg.PackageName}",
                            Tag = pkg
                        };
                        ApplyTreeViewItemFont(node);
                        node.MouseDoubleClick += PackageNode_DoubleClick;
                        node.PreviewMouseLeftButtonDown += PackageNode_Click;
                        node.ContextMenu = CreatePackageContextMenu(pkg);
                        node.MouseMove += PackageNode_MouseMove;
                        categoryNode.Items.Add(node);
                    }
                }
                else if (category.Type == CategoryType.UserDefinedTypes)
                {
                    // Show all user-defined types across all schemas
                    var schemas = await _objectBrowserService.GetAllSchemasAsync();
                    foreach (var schemaNode in schemas.Where(s => s.Type != "SYSTEM"))
                    {
                        var types = await _objectBrowserService.GetTypesAsync(schemaNode.SchemaName);
                        foreach (var type in types)
                        {
                            var node = new TreeViewItem
                            {
                                Header = $"{type.Icon} {type.FullName}",
                                Tag = type
                            };
                            ApplyTreeViewItemFont(node);
                            categoryNode.Items.Add(node);
                        }
                    }
                }
                else if (category.Type == CategoryType.Security)
                {
                    // Security category: Roles, Groups, Users
                    var rolesNode = new TreeViewItem { Header = $"{ObjectBrowserIcons.Roles} Roles", Tag = "Roles" };
                    ApplyTreeViewItemFont(rolesNode);
                    rolesNode.Items.Add("Loading...");
                    rolesNode.Expanded += SecuritySubCategoryNode_Expanded;
                    categoryNode.Items.Add(rolesNode);
                    
                    var groupsNode = new TreeViewItem { Header = $"{ObjectBrowserIcons.Groups} Groups", Tag = "Groups" };
                    ApplyTreeViewItemFont(groupsNode);
                    groupsNode.Items.Add("Loading...");
                    groupsNode.Expanded += SecuritySubCategoryNode_Expanded;
                    categoryNode.Items.Add(groupsNode);
                    
                    var usersNode = new TreeViewItem { Header = $"{ObjectBrowserIcons.Users} Users", Tag = "Users" };
                    ApplyTreeViewItemFont(usersNode);
                    usersNode.Items.Add("Loading...");
                    usersNode.Expanded += SecuritySubCategoryNode_Expanded;
                    categoryNode.Items.Add(usersNode);
                }

                if (categoryNode.Items.Count == 0)
                {
                    categoryNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Empty} No items", IsEnabled = false });
                }

                ObjectBrowserStatusText.Text = $"Loaded {categoryNode.Items.Count} items in {category.Name}";
                
                // Trigger auto-grow width adjustment after expanding category
                AutoAdjustObjectBrowserWidth();
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to load category {category.Name}");
                categoryNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Error} Error loading", IsEnabled = false });
                ObjectBrowserStatusText.Text = $"Error loading {category.Name}";
            }
        }
    }

    /// <summary>
    /// Handle schema node expansion (lazy load object types)
    /// </summary>
    private async void SchemaNode_Expanded(object sender, RoutedEventArgs e)
    {
        if (sender is not TreeViewItem schemaTreeNode) return;
        if (schemaTreeNode.Tag is not SchemaNode schemaNode) return;
        if (_objectBrowserService == null) return;

        // Check if already loaded
        if (schemaTreeNode.Items.Count == 1 && schemaTreeNode.Items[0] is string)
        {
            Logger.Debug($"Expanding schema: {schemaNode.SchemaName}");
            schemaTreeNode.Items.Clear();
            ObjectBrowserStatusText.Text = $"Loading objects in {schemaNode.SchemaName}...";

            try
            {
                // Get object counts for this schema
                var objectCounts = await _objectBrowserService.GetSchemaObjectCountsAsync(schemaNode.SchemaName, _userAccessLevel);

                foreach (var kvp in objectCounts)
                {
                    if (kvp.Value == 0) continue; // Skip empty categories

                    var objectType = kvp.Key;
                    var count = kvp.Value;
                    var icon = GetObjectTypeIcon(objectType);
                    var typeName = GetObjectTypeName(objectType);

                    var typeNode = new TreeViewItem
                    {
                        Header = $"{icon} {typeName} ({count})",
                        Tag = new { Schema = schemaNode.SchemaName, ObjectType = objectType }
                    };
                    ApplyTreeViewItemFont(typeNode);

                    // Add placeholder for lazy loading
                    typeNode.Items.Add("Loading...");
                    typeNode.Expanded += ObjectTypeNode_Expanded;
                    schemaTreeNode.Items.Add(typeNode);
                }

                if (schemaTreeNode.Items.Count == 0)
                {
                    schemaTreeNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Empty} No objects", IsEnabled = false });
                }

                ObjectBrowserStatusText.Text = $"Loaded {schemaTreeNode.Items.Count} object types in {schemaNode.SchemaName}";
                
                // Trigger auto-grow width adjustment after expanding schema
                AutoAdjustObjectBrowserWidth();
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to load schema {schemaNode.SchemaName}");
                schemaTreeNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Error} Error loading", IsEnabled = false });
                ObjectBrowserStatusText.Text = $"Error loading {schemaNode.SchemaName}";
            }
        }
    }

    /// <summary>
    /// Handle object type node expansion (load actual objects)
    /// </summary>
    private async void ObjectTypeNode_Expanded(object sender, RoutedEventArgs e)
    {
        if (sender is not TreeViewItem typeNode) return;
        if (_objectBrowserService == null) return;
        
        // Extract schema and objectType from anonymous type stored in Tag
        var tagType = typeNode.Tag?.GetType();
        if (tagType == null) return;
        
        var schemaProperty = tagType.GetProperty("Schema");
        var objectTypeProperty = tagType.GetProperty("ObjectType");
        if (schemaProperty == null || objectTypeProperty == null) return;
        
        string? schema = schemaProperty.GetValue(typeNode.Tag) as string;
        if (schema == null) return;
        
        var objectTypeValue = objectTypeProperty.GetValue(typeNode.Tag);
        if (objectTypeValue is not ObjectType objectType) return;

        // Check if already loaded
        if (typeNode.Items.Count == 1 && typeNode.Items[0] is string)
        {
            Logger.Debug($"Expanding object type: {objectType} in schema {schema}");
            typeNode.Items.Clear();
            ObjectBrowserStatusText.Text = $"Loading {objectType}...";

            try
            {
                // Use cached methods for faster expansion (data preloaded in background)
                List<DatabaseObject> objects = objectType switch
                {
                    ObjectType.Tables => await _objectBrowserService.GetTablesCachedAsync(schema),
                    ObjectType.Views => await _objectBrowserService.GetViewsCachedAsync(schema),
                    ObjectType.Procedures => await _objectBrowserService.GetProceduresCachedAsync(schema),
                    ObjectType.Functions => await _objectBrowserService.GetFunctionsCachedAsync(schema),
                    ObjectType.Indexes => await _objectBrowserService.GetIndexesAsync(schema), // No cache yet
                    ObjectType.Triggers => await _objectBrowserService.GetTriggersCachedAsync(schema),
                    ObjectType.Sequences => await _objectBrowserService.GetSequencesCachedAsync(schema),
                    ObjectType.Synonyms => await _objectBrowserService.GetSynonymsAsync(schema), // No cache yet
                    ObjectType.Types => await _objectBrowserService.GetTypesAsync(schema), // No cache yet
                    ObjectType.Packages => await _objectBrowserService.GetPackagesForSchemaAsync(schema), // No cache yet
                    _ => new List<DatabaseObject>()
                };

                // For large object counts, use optimized creation (defer context menu)
                var count = objects.Count;
                var batchSize = 100;
                
                for (int i = 0; i < count; i++)
                {
                    var obj = objects[i];
                    var objectNode = new TreeViewItem
                    {
                        Header = GetObjectNodeHeader(obj),
                        Tag = obj,
                        AllowDrop = false
                    };
                    ApplyTreeViewItemFont(objectNode);

                    objectNode.MouseDoubleClick += ObjectNode_DoubleClick;
                    objectNode.PreviewMouseLeftButtonDown += ObjectNode_Click;
                    objectNode.MouseMove += ObjectNode_MouseMove;
                    
                    // Defer tooltip creation for performance (create on demand)
                    objectNode.ToolTipOpening += (s, _) => {
                        if (s is TreeViewItem node && node.ToolTip == null && node.Tag is DatabaseObject dbObj)
                            node.ToolTip = CreateObjectTooltip(dbObj);
                    };
                    
                    // Create placeholder context menu that populates on first open
                    var placeholderMenu = new ContextMenu();
                    var capturedObj = obj; // Capture for closure
                    placeholderMenu.Opened += (menuSender, _) => {
                        if (menuSender is ContextMenu menu && menu.Items.Count == 0)
                        {
                            var fullMenu = CreateObjectContextMenu(capturedObj);
                            foreach (var item in fullMenu.Items.OfType<object>().ToList())
                            {
                                fullMenu.Items.Remove(item);
                                menu.Items.Add(item);
                            }
                        }
                    };
                    objectNode.ContextMenu = placeholderMenu;
                    
                    typeNode.Items.Add(objectNode);
                    
                    // Yield to UI thread every batch to keep UI responsive
                    if (count > batchSize && i > 0 && i % batchSize == 0)
                    {
                        ObjectBrowserStatusText.Text = $"Loading {objectType}... {i}/{count}";
                        await Task.Delay(1); // Allow UI to update
                    }
                }

                if (typeNode.Items.Count == 0)
                {
                    typeNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Empty} No items", IsEnabled = false });
                }

                ObjectBrowserStatusText.Text = $"Loaded {typeNode.Items.Count} {objectType}";
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to load {objectType} in schema {schema}");
                typeNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Error} Error loading", IsEnabled = false });
                ObjectBrowserStatusText.Text = $"Error loading {objectType}";
            }
        }
    }

    /// <summary>
    /// Handle security sub-category expansion (Roles, Groups, Users)
    /// </summary>
    private async void SecuritySubCategoryNode_Expanded(object sender, RoutedEventArgs e)
    {
        if (sender is not TreeViewItem subCategoryNode) return;
        if (subCategoryNode.Tag is not string subCategoryType) return;
        if (_objectBrowserService == null) return;

        // Check if already loaded
        if (subCategoryNode.Items.Count == 1 && subCategoryNode.Items[0] is string)
        {
            Logger.Debug($"Expanding security sub-category: {subCategoryType}");
            subCategoryNode.Items.Clear();
            ObjectBrowserStatusText.Text = $"Loading {subCategoryType}...";

            try
            {
                List<SecurityPrincipal> principals = subCategoryType switch
                {
                    "Roles" => await _objectBrowserService.GetRolesAsync(),
                    "Groups" => await _objectBrowserService.GetGroupsAsync(),
                    "Users" => await _objectBrowserService.GetUsersAsync(),
                    _ => new List<SecurityPrincipal>()
                };

                foreach (var principal in principals)
                {
                    var node = new TreeViewItem
                    {
                        Header = $"{principal.Icon} {principal.Name}",
                        Tag = principal
                    };
                    ApplyTreeViewItemFont(node);
                    
                    // Add placeholder for privilege categories
                    node.Items.Add("Loading...");
                    node.Expanded += SecurityPrincipalNode_Expanded;
                    node.PreviewMouseLeftButtonDown += SecurityPrincipalNode_Click;
                    
                    subCategoryNode.Items.Add(node);
                }

                if (subCategoryNode.Items.Count == 0)
                {
                    subCategoryNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Empty} No items", IsEnabled = false });
                }

                ObjectBrowserStatusText.Text = $"Loaded {subCategoryNode.Items.Count} {subCategoryType}";
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to load {subCategoryType}");
                subCategoryNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Error} Error loading", IsEnabled = false });
                ObjectBrowserStatusText.Text = $"Error loading {subCategoryType}";
            }
        }
    }
    
    /// <summary>
    /// Handle security principal expansion (show privilege categories)
    /// </summary>
    private async void SecurityPrincipalNode_Expanded(object sender, RoutedEventArgs e)
    {
        if (sender is not TreeViewItem principalNode) return;
        if (principalNode.Tag is not SecurityPrincipal principal) return;
        if (_objectBrowserService == null) return;

        // Check if already loaded
        if (principalNode.Items.Count == 1 && principalNode.Items[0] is string)
        {
            Logger.Debug($"Expanding security principal: {principal.Name}");
            principalNode.Items.Clear();
            ObjectBrowserStatusText.Text = $"Loading privileges for {principal.Name}...";

            try
            {
                // Get privilege counts for this principal
                Dictionary<PrivilegeCategoryType, int> privilegeCounts = principal.Type switch
                {
                    SecurityPrincipalType.Role => await _objectBrowserService.GetRolePrivilegeCountsAsync(principal.Name),
                    SecurityPrincipalType.Group => await _objectBrowserService.GetGroupPrivilegeCountsAsync(principal.Name),
                    SecurityPrincipalType.User => await _objectBrowserService.GetUserPrivilegeCountsAsync(principal.Name),
                    _ => new Dictionary<PrivilegeCategoryType, int>()
                };

                // Add privilege categories with counts
                foreach (var kvp in privilegeCounts.Where(p => p.Value > 0).OrderByDescending(p => p.Value))
                {
                    var icon = GetPrivilegeCategoryIcon(kvp.Key);
                    var name = GetPrivilegeCategoryName(kvp.Key);
                    
                    var privilegeNode = new TreeViewItem
                    {
                        Header = $"{icon} {name} ({kvp.Value})",
                        Tag = new { Principal = principal, Category = kvp.Key }
                    };
                    ApplyTreeViewItemFont(privilegeNode);
                    
                    principalNode.Items.Add(privilegeNode);
                }

                if (principalNode.Items.Count == 0)
                {
                    principalNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Empty} No privileges", IsEnabled = false });
                }

                ObjectBrowserStatusText.Text = $"Loaded {principalNode.Items.Count} privilege categories";
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to load privileges for {principal.Name}");
                principalNode.Items.Add(new TreeViewItem { Header = $"{ObjectBrowserIcons.Error} Error loading", IsEnabled = false });
                ObjectBrowserStatusText.Text = $"Error loading privileges";
            }
        }
    }
    
    /// <summary>
    /// Get icon for privilege category
    /// </summary>
    private string GetPrivilegeCategoryIcon(PrivilegeCategoryType category)
    {
        return category switch
        {
            PrivilegeCategoryType.Users => ObjectBrowserIcons.Users,
            PrivilegeCategoryType.Tables => ObjectBrowserIcons.TablesPrivileges,
            PrivilegeCategoryType.Views => ObjectBrowserIcons.ViewsPrivileges,
            PrivilegeCategoryType.MQTs => ObjectBrowserIcons.MQTsPrivileges,
            PrivilegeCategoryType.Columns => ObjectBrowserIcons.ColumnsPrivileges,
            PrivilegeCategoryType.Indexes => ObjectBrowserIcons.IndexesPrivileges,
            PrivilegeCategoryType.Functions => ObjectBrowserIcons.FunctionsPrivileges,
            PrivilegeCategoryType.Modules => ObjectBrowserIcons.ModulesPrivileges,
            PrivilegeCategoryType.Packages => ObjectBrowserIcons.PackagesPrivileges,
            PrivilegeCategoryType.Procedures => ObjectBrowserIcons.ProceduresPrivileges,
            PrivilegeCategoryType.Schemas => ObjectBrowserIcons.SchemasPrivileges,
            PrivilegeCategoryType.Sequences => ObjectBrowserIcons.SequencesPrivileges,
            PrivilegeCategoryType.Tablespaces => ObjectBrowserIcons.TablespacesPrivileges,
            PrivilegeCategoryType.Variables => ObjectBrowserIcons.VariablesPrivileges,
            PrivilegeCategoryType.XmlSchemas => ObjectBrowserIcons.XmlSchemasPrivileges,
            _ => "📋"
        };
    }
    
    /// <summary>
    /// Get display name for privilege category
    /// </summary>
    private string GetPrivilegeCategoryName(PrivilegeCategoryType category)
    {
        return category switch
        {
            PrivilegeCategoryType.Users => "Users",
            PrivilegeCategoryType.Tables => "Tables Privileges",
            PrivilegeCategoryType.Views => "Views Privileges",
            PrivilegeCategoryType.MQTs => "MQTs Privileges",
            PrivilegeCategoryType.Columns => "Columns Privileges",
            PrivilegeCategoryType.Indexes => "Indexes Privileges",
            PrivilegeCategoryType.Functions => "Functions Privileges",
            PrivilegeCategoryType.Modules => "Modules Privileges",
            PrivilegeCategoryType.Packages => "Packages Privileges",
            PrivilegeCategoryType.Procedures => "Procedures Privileges",
            PrivilegeCategoryType.Schemas => "Schemas Privileges",
            PrivilegeCategoryType.Sequences => "Sequences Privileges",
            PrivilegeCategoryType.Tablespaces => "Tablespaces Privileges",
            PrivilegeCategoryType.Variables => "Variables Privileges",
            PrivilegeCategoryType.XmlSchemas => "XML Schemas Privileges",
            _ => "Unknown"
        };
    }

    /// <summary>
    /// Helper to get icon for object type
    /// </summary>
    private string GetObjectTypeIcon(ObjectType objectType)
    {
        return objectType switch
        {
            ObjectType.Tables => ObjectBrowserIcons.Table,
            ObjectType.Views => ObjectBrowserIcons.View,
            ObjectType.Procedures => ObjectBrowserIcons.Procedure,
            ObjectType.Functions => ObjectBrowserIcons.Function,
            ObjectType.Indexes => ObjectBrowserIcons.Index,
            ObjectType.Triggers => ObjectBrowserIcons.Trigger,
            ObjectType.Sequences => ObjectBrowserIcons.Sequence,
            ObjectType.Synonyms => ObjectBrowserIcons.Synonym,
            ObjectType.Types => ObjectBrowserIcons.Type,
            ObjectType.Packages => ObjectBrowserIcons.Package,
            _ => "❓"
        };
    }

    /// <summary>
    /// Helper to get display name for object type
    /// </summary>
    private string GetObjectTypeName(ObjectType objectType)
    {
        return objectType switch
        {
            ObjectType.Tables => "Tables",
            ObjectType.Views => "Views",
            ObjectType.Procedures => "Procedures",
            ObjectType.Functions => "Functions",
            ObjectType.Indexes => "Indexes",
            ObjectType.Triggers => "Triggers",
            ObjectType.Sequences => "Sequences",
            ObjectType.Synonyms => "Synonyms",
            ObjectType.Types => "Types",
            ObjectType.Packages => "Packages",
            _ => "Unknown"
        };
    }

    /// <summary>
    /// Get formatted header for object node
    /// </summary>
    private string GetObjectNodeHeader(DatabaseObject obj)
    {
        return obj.Type switch
        {
            ObjectType.Tables => $"{obj.Icon} {obj.Name} {(obj.RowCount.HasValue ? $"[{obj.RowCount:N0} rows]" : "")}",
            ObjectType.Procedures or ObjectType.Functions => $"{obj.Icon} {obj.Name} ({obj.ParameterCount ?? 0} params)",
            _ => $"{obj.Icon} {obj.Name}"
        };
    }
    
    /// <summary>
    /// Create tooltip with metadata for database object
    /// </summary>
    private string CreateObjectTooltip(DatabaseObject obj)
    {
        var tooltip = $"Full Name: {obj.FullName}\n";
        tooltip += $"Type: {obj.Type}\n";
        
        if (!string.IsNullOrEmpty(obj.Owner))
            tooltip += $"Owner: {obj.Owner}\n";
        
        if (obj.CreatedAt.HasValue)
            tooltip += $"Created: {obj.CreatedAt:yyyy-MM-dd HH:mm:ss}\n";
        
        if (obj.RowCount.HasValue)
            tooltip += $"Row Count: {obj.RowCount:N0}\n";
        
        if (obj.ParameterCount.HasValue)
            tooltip += $"Parameters: {obj.ParameterCount}\n";
        
        if (!string.IsNullOrEmpty(obj.TableSpace))
            tooltip += $"Tablespace/Target: {obj.TableSpace}\n";
        
        if (!string.IsNullOrEmpty(obj.Language))
            tooltip += $"Language: {obj.Language}\n";
        
        if (!string.IsNullOrEmpty(obj.Remarks))
            tooltip += $"\nRemarks: {obj.Remarks}";
        
        return tooltip.TrimEnd();
    }

    /// <summary>
    /// Handle double-click on object node - open properties dialog
    /// </summary>
    private void ObjectNode_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is TreeViewItem objectNode && objectNode.Tag is DatabaseObject obj)
        {
            Logger.Debug($"Object double-clicked: {obj.FullName} - opening properties");
            ShowObjectDetails(obj);
            e.Handled = true;
        }
    }
    
    /// <summary>
    /// Handle single-click on object node - select node only (no text insertion)
    /// </summary>
    private void ObjectNode_Click(object sender, MouseButtonEventArgs e)
    {
        // Single click just selects the node - no text insertion
        // Double-click opens properties dialog
        // Use context menu "Copy Name" or drag-drop to insert text
    }
    
    /// <summary>
    /// Insert text at the current cursor position in SQL editor
    /// </summary>
    private void InsertTextAtCursor(string text)
    {
        var cursorPosition = SqlEditor.CaretOffset;
        SqlEditor.Document.Insert(cursorPosition, text);
        SqlEditor.CaretOffset = cursorPosition + text.Length; // Move cursor after inserted text
        SqlEditor.Focus();
        Logger.Debug($"Inserted '{text}' at position {cursorPosition}");
    }
    
    /// <summary>
    /// Handle click on security principal node to show details
    /// </summary>
    private void SecurityPrincipalNode_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is TreeViewItem principalNode && principalNode.Tag is SecurityPrincipal principal)
        {
            // Only handle direct clicks, not expansion/collapse
            if (e.ClickCount == 1)
            {
                Logger.Debug($"Security principal clicked: {principal.Name}");
                ShowSecurityPrincipalDetails(principal);
                e.Handled = true;
            }
        }
    }
    
    /// <summary>
    /// Handle double-click on package node - open properties dialog
    /// </summary>
    private void PackageNode_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is TreeViewItem packageNode && packageNode.Tag is PackageInfo package)
        {
            Logger.Debug($"Package double-clicked: {package.PackageSchema}.{package.PackageName} - opening properties");
            ShowPackageDetails(package);
            e.Handled = true;
        }
    }
    
    /// <summary>
    /// Handle single-click on package node - select node only (no text insertion)
    /// </summary>
    private void PackageNode_Click(object sender, MouseButtonEventArgs e)
    {
        // Single click just selects the node - no text insertion
        // Double-click opens properties dialog
        // Use context menu "Copy Name" or drag-drop to insert text
    }
    
    /// <summary>
    /// Show details dialog for a database object
    /// </summary>
    private void ShowObjectDetails(DatabaseObject obj)
    {
        try
        {
            Logger.Info("Showing details for {Type}: {Name}", obj.Type, obj.FullName);
            
            Window? dialog = obj.Type switch
            {
                ObjectType.Tables => new TableDetailsDialog(_connectionManager, obj.FullName),
                ObjectType.Views or ObjectType.Procedures or ObjectType.Functions or
                ObjectType.Indexes or ObjectType.Triggers or ObjectType.Sequences or
                ObjectType.Synonyms or ObjectType.Types => new ObjectDetailsDialog(_connectionManager, obj, _connection),
                ObjectType.Packages => CreatePackagePropertiesDialog(obj),
                _ => null
            };
            
            if (dialog != null)
            {
                dialog.Owner = Window.GetWindow(this);
                dialog.ShowDialog();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show object details");
            MessageBox.Show($"Failed to show details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Create package properties dialog from DatabaseObject
    /// </summary>
    private Window CreatePackagePropertiesDialog(DatabaseObject obj)
    {
        // Need to fetch full package info from database
        var packageInfo = new PackageInfo
        {
            PackageSchema = obj.SchemaName,
            PackageName = obj.Name,
            Owner = obj.Owner ?? string.Empty,
            CreateTime = obj.CreatedAt,
            Remarks = obj.Remarks
            // BoundBy and Isolation will be fetched by the dialog if needed
        };
        
        var dialog = new PackagePropertiesDialog(_connectionManager, packageInfo);
        
        // Subscribe to SqlTextRequested event
        dialog.SqlTextRequested += (sender, sqlText) =>
        {
            InsertTextAtCursor(sqlText + "\n");
            Logger.Info("Package SQL statement inserted into editor");
        };
        
        return dialog;
    }
    
    /// <summary>
    /// Show details dialog for a security principal
    /// </summary>
    private void ShowSecurityPrincipalDetails(SecurityPrincipal principal)
    {
        try
        {
            Logger.Info("Showing details for {Type}: {Name}", principal.Type, principal.Name);
            
            var dialog = new UserDetailsDialog(_connectionManager, principal);
            dialog.Owner = Window.GetWindow(this);
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show security principal details");
            MessageBox.Show($"Failed to show details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Show details dialog for a package
    /// </summary>
    private void ShowPackageDetails(PackageInfo package)
    {
        try
        {
            Logger.Info("Showing details for package: {Schema}.{Name}", package.PackageSchema, package.PackageName);
            
            var dialog = new PackagePropertiesDialog(_connectionManager, package);
            dialog.Owner = Window.GetWindow(this);
            
            // Subscribe to the SqlTextRequested event to insert SQL into editor
            dialog.SqlTextRequested += (sender, sqlText) =>
            {
                InsertTextAtCursor(sqlText + "\n");
                Logger.Info("Package SQL statement inserted into editor");
            };
            
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show package details");
            MessageBox.Show($"Failed to show details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Handle click on schema node
    /// </summary>
    private void SchemaNode_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is TreeViewItem schemaTreeNode && schemaTreeNode.Tag is SchemaNode schemaNode)
        {
            // Only handle direct clicks, not expansion/collapse
            if (e.ClickCount == 1)
            {
                Logger.Debug($"Schema clicked: {schemaNode.SchemaName}");
                ShowSchemaDetails(schemaNode);
                e.Handled = true;
            }
        }
    }
    
    /// <summary>
    /// Handle click on tablespace node - select node only (no text insertion)
    /// </summary>
    private void TablespaceNode_Click(object sender, MouseButtonEventArgs e)
    {
        // Single click just selects the node - no text insertion
        // Double-click opens properties dialog
        // Use context menu "Copy Name" or drag-drop to insert text
    }

    private void TablespaceNode_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is TreeViewItem tsNode && tsNode.Tag is TablespaceInfo tablespace)
        {
            Logger.Debug("Tablespace double-clicked: {Tablespace} - opening properties", tablespace.TablespaceName);
            ShowTablespaceDetails(tablespace);
            e.Handled = true;
        }
    }

    private void TablespaceNode_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed && sender is TreeViewItem item && item.Tag is TablespaceInfo ts)
        {
            Logger.Debug("Initiating drag operation for tablespace: {Name}", ts.TablespaceName);

            var dragData = new DataObject();
            dragData.SetText(ts.TablespaceName);
            dragData.SetData("TablespaceInfo", ts);

            DragDrop.DoDragDrop(item, dragData, DragDropEffects.Copy);
        }
    }

    private void PackageNode_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed && sender is TreeViewItem item && item.Tag is PackageInfo pkg)
        {
            var fullName = $"{pkg.PackageSchema}.{pkg.PackageName}";
            Logger.Debug("Initiating drag operation for package: {Name}", fullName);

            var dragData = new DataObject();
            dragData.SetText(fullName);
            dragData.SetData("PackageInfo", pkg);

            DragDrop.DoDragDrop(item, dragData, DragDropEffects.Copy);
        }
    }
    
    /// <summary>
    /// Show details for a schema
    /// </summary>
    private void ShowSchemaDetails(SchemaNode schema)
    {
        try
        {
            var message = $"Schema: {schema.SchemaName}\n" +
                         $"Type: {schema.Type}\n";
            
            // Show object counts by type
            if (schema.ObjectTypes.Any())
            {
                message += $"\nObject Types:\n";
                foreach (var objType in schema.ObjectTypes)
                {
                    message += $"  {objType.Icon} {objType.Name}: {objType.Count}\n";
                }
            }
            
            MessageBox.Show(message.TrimEnd(), $"Schema Details - {schema.SchemaName}", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            
            Logger.Info("Showed schema details for: {Schema}", schema.SchemaName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show schema details");
            MessageBox.Show($"Failed to show details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Show details for a tablespace
    /// </summary>
    private void ShowTablespaceDetails(TablespaceInfo tablespace)
    {
        try
        {
            Logger.Info("Showing details for tablespace: {Tablespace}", tablespace.TablespaceName);

            var dialog = new Dialogs.TablespaceDetailsDialog(tablespace, _connectionManager)
            {
                Owner = Window.GetWindow(this)
            };

            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to show tablespace details");
            MessageBox.Show($"Failed to show details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Create context menu for database object
    /// </summary>
    private ContextMenu CreateObjectContextMenu(DatabaseObject obj)
    {
        var contextMenu = new ContextMenu();

        // Properties (always first - for all users) - DDL is now inside Properties dialog
        var propsItem = new MenuItem { Header = "⚙️ Properties..." };
        propsItem.Click += (s, e) => ShowObjectDetails(obj);
        contextMenu.Items.Add(propsItem);
        
        // Open as New Tab - opens object in a new editor tab
        var openTabItem = new MenuItem { Header = "📌 Open as New Tab" };
        openTabItem.Click += async (s, e) => await OpenObjectAsNewTabAsync(obj);
        contextMenu.Items.Add(openTabItem);
        
        contextMenu.Items.Add(new Separator());

        // Browse Data (Tables/Views only)
        if (obj.Type == ObjectType.Tables || obj.Type == ObjectType.Views)
        {
            var browseItem = new MenuItem { Header = "📊 Browse Data (SELECT *)" };
            browseItem.Click += (s, e) =>
            {
                SqlEditor.Text = $"SELECT * FROM {obj.FullName};";
                Execute_Click(s, e);
            };
            contextMenu.Items.Add(browseItem);
            
            var countItem = new MenuItem { Header = "🔢 Count Rows (SELECT COUNT(*))" };
            countItem.Click += (s, e) =>
            {
                SqlEditor.Text = $"SELECT COUNT(*) AS ROW_COUNT FROM {obj.FullName};";
                Execute_Click(s, e);
            };
            contextMenu.Items.Add(countItem);
            
            contextMenu.Items.Add(new Separator());
        }

        // View Definition (Views/Procedures/Functions)
        if (obj.Type == ObjectType.Views || obj.Type == ObjectType.Procedures || obj.Type == ObjectType.Functions)
        {
            var viewDefItem = new MenuItem { Header = "📄 View Source Code..." };
            viewDefItem.Click += async (s, e) =>
            {
                try
                {
                    string? definition = null;
                    if (obj.Type == ObjectType.Views)
                    {
                        // Get view definition using MetadataHandler
                        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                        var sqlTemplate = metadataHandler.GetRequiredStatement("GetViewText");
                        var sql = sqlTemplate.Replace("?", $"'{obj.Name}'");
                        var result = await _connectionManager.ExecuteScalarAsync(sql);
                        definition = result?.ToString() ?? string.Empty;
                    }
                    else if (obj.Type == ObjectType.Procedures || obj.Type == ObjectType.Functions)
                    {
                        // Use required statement from JSON config
                        var metadataHandler = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                        var routineType = obj.Type == ObjectType.Procedures ? "P" : "F";
                        var sqlTemplate = metadataHandler.GetRequiredStatement("GetRoutineSource");
                        var sql = ReplaceSqlPlaceholders(sqlTemplate, obj.SchemaName?.Trim() ?? "", obj.Name?.Trim() ?? "", routineType);
                        var result = await _connectionManager.ExecuteScalarAsync(sql);
                        definition = result?.ToString();
                    }
                    
                    if (!string.IsNullOrEmpty(definition))
                    {
                        SqlEditor.Text = definition;
                    }
                    else
                    {
                        MessageBox.Show("Source code not available.", "Information", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Failed to get source code for {Name}", obj.FullName);
                    MessageBox.Show($"Failed to retrieve source code: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            };
            contextMenu.Items.Add(viewDefItem);
            contextMenu.Items.Add(new Separator());
        }

        // Generate SELECT statement
        if (obj.Type == ObjectType.Tables || obj.Type == ObjectType.Views)
        {
            var generateSelectItem = new MenuItem { Header = "📝 Generate SELECT Statement" };
            generateSelectItem.Click += (s, e) => SqlEditor.AppendText($"\nSELECT * FROM {obj.FullName};\n");
            contextMenu.Items.Add(generateSelectItem);
        }

        // Copy Name
        var copyItem = new MenuItem { Header = "📋 Copy Full Name" };
        copyItem.Click += (s, e) => Clipboard.SetText(obj.FullName);
        contextMenu.Items.Add(copyItem);
        
        // Copy as CSV (for results)
        if (obj.Type == ObjectType.Tables || obj.Type == ObjectType.Views)
        {
            var copySchemaItem = new MenuItem { Header = "📋 Copy Schema Name" };
            copySchemaItem.Click += (s, e) => Clipboard.SetText(obj.SchemaName);
            contextMenu.Items.Add(copySchemaItem);
            
            var copyTableItem = new MenuItem { Header = "📋 Copy Table Name" };
            copyTableItem.Click += (s, e) => Clipboard.SetText(obj.Name);
            contextMenu.Items.Add(copyTableItem);
        }

        return contextMenu;
    }
    
    /// <summary>
    /// Generate CREATE DDL and open in new tab
    /// </summary>
    private async Task GenerateCreateDdlAsync(DatabaseObject obj)
    {
        try
        {
            Logger.Info("Generating CREATE DDL for {Type}: {Name}", obj.Type, obj.FullName);
            
            var ddlService = new DdlGeneratorService(_connectionManager);
            var (createDdl, _) = await ddlService.GenerateDdlAsync(obj);
            
            // Request new tab from MainWindow
            if (Window.GetWindow(this) is MainWindow mainWindow)
            {
                mainWindow.CreateNewTabWithSql(createDdl, $"CREATE {obj.Name}");
            }
            else
            {
                // Fallback: append to current editor
                SqlEditor.AppendText($"\n{createDdl}\n");
            }
            
            Logger.Info("CREATE DDL generated successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate CREATE DDL for {Name}", obj.FullName);
            MessageBox.Show($"Failed to generate CREATE DDL:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Generate DROP DDL and open in new tab
    /// </summary>
    private async Task GenerateDropDdlAsync(DatabaseObject obj)
    {
        try
        {
            Logger.Info("Generating DROP DDL for {Type}: {Name}", obj.Type, obj.FullName);
            
            var ddlService = new DdlGeneratorService(_connectionManager);
            var (_, dropDdl) = await ddlService.GenerateDdlAsync(obj);
            
            // Request new tab from MainWindow
            if (Window.GetWindow(this) is MainWindow mainWindow)
            {
                mainWindow.CreateNewTabWithSql(dropDdl, $"DROP {obj.Name}");
            }
            else
            {
                // Fallback: append to current editor
                SqlEditor.AppendText($"\n{dropDdl}\n");
            }
            
            Logger.Info("DROP DDL generated successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate DROP DDL for {Name}", obj.FullName);
            MessageBox.Show($"Failed to generate DROP DDL:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Open a database object in a new editor tab with appropriate content
    /// </summary>
    private async Task OpenObjectAsNewTabAsync(DatabaseObject obj)
    {
        try
        {
            Logger.Info("Opening {Type} as new tab: {Name}", obj.Type, obj.FullName);
            
            var mainWindow = Window.GetWindow(this) as MainWindow;
            if (mainWindow == null)
            {
                MessageBox.Show("Could not access main window.", "Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            string content;
            string tabTitle;
            
            switch (obj.Type)
            {
                case ObjectType.Tables:
                    // For tables, create a SELECT query
                    content = $"-- Table: {obj.FullName}\n-- Created: {obj.CreatedAt:yyyy-MM-dd}\n-- Owner: {obj.Owner}\n\nSELECT * FROM {obj.FullName} FETCH FIRST 1000 ROWS ONLY;";
                    tabTitle = $"Table: {obj.Name?.Trim()}";
                    break;
                    
                case ObjectType.Views:
                    // For views, get the view definition using MetadataHandler
                    var metadataHandler2 = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                    var viewSqlTemplate = metadataHandler2.GetRequiredStatement("GetViewText");
                    var viewSql = viewSqlTemplate.Replace("?", $"'{obj.Name}'");
                    var viewResult = await _connectionManager.ExecuteScalarAsync(viewSql);
                    var viewDef = viewResult?.ToString() ?? string.Empty;
                    content = !string.IsNullOrEmpty(viewDef)
                        ? $"-- View: {obj.FullName}\n\n{viewDef}"
                        : $"-- View: {obj.FullName}\n\nSELECT * FROM {obj.FullName} FETCH FIRST 1000 ROWS ONLY;";
                    tabTitle = $"View: {obj.Name?.Trim()}";
                    break;
                    
                case ObjectType.Procedures:
                case ObjectType.Functions:
                    // For routines, get the source code using required statement
                    var routineMetadata = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                    var routineType = obj.Type == ObjectType.Procedures ? "P" : "F";
                    var routineSqlTemplate = routineMetadata.GetRequiredStatement("GetRoutineSource");
                    var routineSql = ReplaceSqlPlaceholders(routineSqlTemplate, obj.SchemaName?.Trim() ?? "", obj.Name?.Trim() ?? "", routineType);
                    var routineResult = await _connectionManager.ExecuteScalarAsync(routineSql);
                    var sourceCode = routineResult?.ToString();
                    content = !string.IsNullOrEmpty(sourceCode) 
                        ? $"-- {(obj.Type == ObjectType.Procedures ? "Procedure" : "Function")}: {obj.FullName}\n\n{sourceCode}"
                        : $"-- {(obj.Type == ObjectType.Procedures ? "Procedure" : "Function")}: {obj.FullName}\n-- Source code not available";
                    tabTitle = $"{(obj.Type == ObjectType.Procedures ? "Proc" : "Func")}: {obj.Name?.Trim()}";
                    break;
                    
                case ObjectType.Triggers:
                    // For triggers, get the trigger definition using required statement
                    var triggerMetadata = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                    var triggerSqlTemplate = triggerMetadata.GetRequiredStatement("GetTriggerSource");
                    var triggerSql = ReplaceSqlPlaceholders(triggerSqlTemplate, obj.SchemaName?.Trim() ?? "", obj.Name?.Trim() ?? "");
                    var triggerResult = await _connectionManager.ExecuteScalarAsync(triggerSql);
                    var triggerCode = triggerResult?.ToString();
                    content = !string.IsNullOrEmpty(triggerCode) 
                        ? $"-- Trigger: {obj.FullName}\n\n{triggerCode}"
                        : $"-- Trigger: {obj.FullName}\n-- Source code not available";
                    tabTitle = $"Trigger: {obj.Name?.Trim()}";
                    break;
                    
                case ObjectType.Sequences:
                    // For sequences, show sequence info and usage
                    var seqMetadata = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                    var seqInfoSqlTemplate = seqMetadata.GetRequiredStatement("GetSequenceInfo");
                    var seqInfoSql = ReplaceSqlPlaceholders(seqInfoSqlTemplate, obj.SchemaName?.Trim() ?? "", obj.Name?.Trim() ?? "");
                    content = $"-- Sequence: {obj.FullName}\n\n-- Get current value (without increment):\nSELECT PREVIOUS VALUE FOR {obj.FullName} FROM SYSIBM.SYSDUMMY1;\n\n-- Get next value:\nSELECT NEXT VALUE FOR {obj.FullName} FROM SYSIBM.SYSDUMMY1;\n\n-- Sequence properties:\n{seqInfoSql};";
                    tabTitle = $"Seq: {obj.Name?.Trim()}";
                    break;
                    
                case ObjectType.Indexes:
                    // For indexes, show index definition using required statements
                    var indexMetadata = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                    var indexInfoSqlTemplate = indexMetadata.GetRequiredStatement("GetIndexInfo");
                    var indexColsSqlTemplate = indexMetadata.GetRequiredStatement("GetIndexColumns");
                    var indexInfoSql = ReplaceSqlPlaceholders(indexInfoSqlTemplate, obj.SchemaName?.Trim() ?? "", obj.Name?.Trim() ?? "");
                    var indexColsSql = ReplaceSqlPlaceholders(indexColsSqlTemplate, obj.SchemaName?.Trim() ?? "", obj.Name?.Trim() ?? "");
                    content = $"-- Index: {obj.FullName}\n\n-- Index details:\n{indexInfoSql};\n\n-- Index columns:\n{indexColsSql};";
                    tabTitle = $"Index: {obj.Name?.Trim()}";
                    break;
                    
                default:
                    // For other types, generate DDL
                    var ddlService = new DdlGeneratorService(_connectionManager);
                    var (createDdl, _) = await ddlService.GenerateDdlAsync(obj);
                    content = createDdl;
                    tabTitle = $"{obj.Type}: {obj.Name?.Trim()}";
                    break;
            }
            
            mainWindow.CreateNewTabWithSql(content, tabTitle);
            Logger.Info("Opened {Type} as new tab: {Title}", obj.Type, tabTitle);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open {Type} as new tab: {Name}", obj.Type, obj.FullName);
            MessageBox.Show($"Failed to open as new tab:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Handle search box text changed
    /// </summary>
    private void ObjectSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        var searchText = ObjectSearchBox.Text?.Trim() ?? string.Empty;
        
        if (string.IsNullOrEmpty(searchText))
        {
            // Show all items and reset expansion
            SetTreeViewItemsVisibility(DatabaseTreeView.Items, true);
            ObjectBrowserStatusText.Text = "Ready";
            return;
        }

        Logger.Debug($"Searching objects: {searchText}");
        int visibleCount = 0;

        // Recursive search through all tree nodes
        foreach (TreeViewItem item in DatabaseTreeView.Items)
        {
            if (SearchAndFilterTreeViewItem(item, searchText))
            {
                visibleCount++;
            }
        }

        ObjectBrowserStatusText.Text = visibleCount > 0 
            ? $"Found {visibleCount} matching items" 
            : "No matches found";
    }
    
    /// <summary>
    /// Recursively search and filter tree view items
    /// </summary>
    private bool SearchAndFilterTreeViewItem(TreeViewItem item, string searchText)
    {
        var header = item.Header?.ToString() ?? string.Empty;
        bool matchesSearch = header.Contains(searchText, StringComparison.OrdinalIgnoreCase);
        bool hasVisibleChildren = false;

        // Check if any children match
        if (item.Items.Count > 0 && item.Items[0] is not string)
        {
            foreach (TreeViewItem child in item.Items.OfType<TreeViewItem>())
            {
                if (SearchAndFilterTreeViewItem(child, searchText))
                {
                    hasVisibleChildren = true;
                }
            }
        }

        // Show item if it matches or has visible children
        bool shouldBeVisible = matchesSearch || hasVisibleChildren;
        item.Visibility = shouldBeVisible ? Visibility.Visible : Visibility.Collapsed;

        // Auto-expand if it has matching children
        if (hasVisibleChildren && !matchesSearch)
        {
            item.IsExpanded = true;
        }

        return shouldBeVisible;
    }
    
    /// <summary>
    /// Set visibility for all tree view items
    /// </summary>
    private void SetTreeViewItemsVisibility(ItemCollection items, bool visible)
    {
        foreach (TreeViewItem item in items.OfType<TreeViewItem>())
        {
            item.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
            
            if (item.Items.Count > 0 && item.Items[0] is not string)
            {
                SetTreeViewItemsVisibility(item.Items, visible);
            }
        }
    }

    /// <summary>
    /// Handle refresh button click
    /// </summary>
    private async void RefreshObjectBrowser_Click(object sender, RoutedEventArgs e)
    {
        // Prevent multiple refreshes at once
        if (!RefreshButton.IsEnabled) return;
        
        Logger.Info("Refreshing object browser");
        
        try
        {
            await LoadDatabaseObjectsAsync();
            ObjectBrowserStatusText.Text = "Refresh complete";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh object browser");
            ObjectBrowserStatusText.Text = "Refresh failed";
            MessageBox.Show($"Failed to refresh: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private System.Windows.Threading.DispatcherTimer? _spinnerTimer;
    
    /// <summary>
    /// Start the refresh button loading spinner
    /// </summary>
    private void StartRefreshSpinner()
    {
        RefreshButton.IsEnabled = false;
        RefreshSpinnerOverlay.Visibility = Visibility.Visible;
        
        // Create rotating animation timer
        _spinnerTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(50)
        };
        _spinnerTimer.Tick += (s, e) =>
        {
            SpinnerRotation.Angle = (SpinnerRotation.Angle + 15) % 360;
        };
        _spinnerTimer.Start();
    }
    
    /// <summary>
    /// Stop the refresh button loading spinner
    /// </summary>
    private void StopRefreshSpinner()
    {
        _spinnerTimer?.Stop();
        _spinnerTimer = null;
        RefreshButton.IsEnabled = true;
        RefreshSpinnerOverlay.Visibility = Visibility.Collapsed;
        SpinnerRotation.Angle = 0;
    }

    private void TableNode_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (sender is TreeViewItem tableNode && tableNode.Tag is string fullTableName)
        {
            Logger.Debug($"Table double-clicked: {fullTableName}");
            SqlEditor.AppendText($"SELECT * FROM {fullTableName};\n");
        }
    }
    
    #region TreeView Context Menu Handlers
    
    private void DatabaseTreeView_MouseRightButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        // Get the clicked item
        if (e.OriginalSource is DependencyObject source)
        {
            var treeViewItem = FindParent<TreeViewItem>(source);
            if (treeViewItem != null)
            {
                treeViewItem.IsSelected = true;
                UpdateContextMenuForSelectedItem();
            }
        }
    }
    
    private void DatabaseTreeView_MouseDoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        // Skip if already handled by individual node handlers (ObjectNode_DoubleClick, PackageNode_DoubleClick, etc.)
        if (e.Handled)
            return;
            
        if (DatabaseTreeView.SelectedItem is not TreeViewItem item || item.Tag == null)
            return;

        // Requirement: double-click on any leaf item should open the relevant property dialog
        // This is a fallback for nodes that don't have individual double-click handlers
        if (item.Tag is DatabaseObject obj)
        {
            ShowObjectDetails(obj);
            e.Handled = true;
            return;
        }

        if (item.Tag is PackageInfo pkg)
        {
            ShowPackageDetails(pkg);
            e.Handled = true;
            return;
        }

        if (item.Tag is TablespaceInfo ts)
        {
            ShowTablespaceDetails(ts);
            e.Handled = true;
            return;
        }

        if (item.Tag is SecurityPrincipal principal)
        {
            ShowSecurityPrincipalDetails(principal);
            e.Handled = true;
            return;
        }

        // Legacy: some nodes store full name as string
        if (item.Tag is string fullName)
        {
            if (fullName.Contains('.'))
            {
                ViewTableDetails(fullName);
            }
            else
            {
                InsertTextAtCursor(fullName);
            }

            e.Handled = true;
        }
    }
    
    private void UpdateContextMenuForSelectedItem()
    {
        var selectedItem = DatabaseTreeView.SelectedItem as TreeViewItem;
        if (selectedItem?.Tag == null) return;
        
        // Show/hide menu items based on what's selected
        var isTable = selectedItem.Header?.ToString()?.Contains("📋") == true || 
                      selectedItem.Parent is TreeViewItem parent && parent.Header?.ToString()?.Contains("Tables") == true;
        var isView = selectedItem.Header?.ToString()?.Contains("👁") == true;
        var isProcedure = selectedItem.Header?.ToString()?.Contains("⚙") == true;
        var isFunction = selectedItem.Header?.ToString()?.Contains("ƒ") == true;
        
        ViewPropertiesMenuItem.IsEnabled = true;
        ViewDdlMenuItem.IsEnabled = isTable || isView;
        SelectTopMenuItem.IsEnabled = isTable || isView;
        ViewSampleDataMenuItem.IsEnabled = isTable || isView;
        DeepAnalysisMenuItem.IsEnabled = true;
        CompareMenuItem.IsEnabled = isTable;
    }
    
    private static T? FindParent<T>(DependencyObject child) where T : DependencyObject
    {
        var parent = VisualTreeHelper.GetParent(child);
        while (parent != null && parent is not T)
        {
            parent = VisualTreeHelper.GetParent(parent);
        }
        return parent as T;
    }
    
    private void ContextMenu_ViewProperties_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            ViewTableDetails(fullName);
        }
    }
    
    private void ContextMenu_ViewDdl_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            GenerateDdl(fullName);
        }
    }
    
    private async void GenerateDdl(string fullName)
    {
        try
        {
            Logger.Info("Generating DDL for {FullName}", fullName);
            var parts = fullName.Split('.');
            if (parts.Length != 2)
            {
                MessageBox.Show("Invalid object name format. Expected SCHEMA.NAME", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            var ddlService = new Services.DdlGeneratorService(ConnectionManager);
            var obj = new Models.DatabaseObject 
            { 
                SchemaName = parts[0], 
                Name = parts[1], 
                Type = Models.ObjectType.Tables 
            };
            
            var (createDdl, _) = await ddlService.GenerateDdlAsync(obj);
            
            // Show DDL in a dialog
            var dialog = new Dialogs.SqlStatementViewerDialog(createDdl, $"DDL for {fullName}");
            dialog.Owner = Window.GetWindow(this);
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate DDL for {FullName}", fullName);
            MessageBox.Show($"Failed to generate DDL: {ex.Message}", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void ContextMenu_SelectTop_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            SqlEditor.Text = $"SELECT * FROM {fullName} FETCH FIRST 100 ROWS ONLY";
            Execute_Click(sender, e);
        }
    }
    
    private void ContextMenu_ViewSampleData_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            SelectTopRows(fullName, 100);
        }
    }
    
    private void ContextMenu_DeepAnalysis_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            try
            {
                var targetObjects = new List<string> { fullName };
                var dialog = new Dialogs.DeepAnalysisDialog(ConnectionManager, targetObjects);
                dialog.Owner = Window.GetWindow(this);
                dialog.ShowDialog();
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to open Deep Analysis dialog");
                MessageBox.Show($"Failed to open Deep Analysis: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
    
    private void ContextMenu_Compare_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            try
            {
                var dialog = new Dialogs.DatabaseComparisonDialog(ConnectionManager);
                dialog.Owner = Window.GetWindow(this);
                dialog.ShowDialog();
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to open Database Comparison dialog");
                MessageBox.Show($"Failed to open Database Comparison: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
    
    private void ContextMenu_CopyName_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item)
        {
            var header = item.Header?.ToString() ?? "";
            // Remove emoji prefix
            var name = System.Text.RegularExpressions.Regex.Replace(header, @"^[\p{So}\p{Sc}]\s*", "");
            Clipboard.SetText(name);
        }
    }
    
    private void ContextMenu_CopyFullName_Click(object sender, RoutedEventArgs e)
    {
        if (DatabaseTreeView.SelectedItem is TreeViewItem item && item.Tag is string fullName)
        {
            Clipboard.SetText(fullName);
        }
    }
    
    #endregion

    /// <summary>
    /// Create context menu for table nodes with various options
    /// </summary>
    private ContextMenu CreateTableContextMenu(string fullTableName)
    {
        Logger.Debug("Creating context menu for table: {Table}", fullTableName);
        
        var contextMenu = new ContextMenu();

        // View Table Details
        var detailsMenuItem = new MenuItem
        {
            Header = "📋 View Table Details...",
            FontWeight = FontWeights.Bold
        };
        detailsMenuItem.Click += (s, e) => ViewTableDetails(fullTableName);
        contextMenu.Items.Add(detailsMenuItem);
        
        // Open as New Tab
        var openTabMenuItem = new MenuItem
        {
            Header = "📌 Open as New Tab"
        };
        openTabMenuItem.Click += (s, e) =>
        {
            var parts = fullTableName.Split('.');
            var schema = parts.Length > 1 ? parts[0].Trim() : "";
            var tableName = parts.Length > 1 ? parts[1].Trim() : parts[0].Trim();
            var sql = $"-- Table: {schema.Trim()}.{tableName.Trim()}\n\nSELECT * FROM {schema.Trim()}.{tableName.Trim()} FETCH FIRST 1000 ROWS ONLY;";
            if (Window.GetWindow(this) is MainWindow mainWindow)
            {
                mainWindow.CreateNewTabWithSql(sql, $"Table: {tableName}");
            }
        };
        contextMenu.Items.Add(openTabMenuItem);

        contextMenu.Items.Add(new Separator());

        // SELECT Top 1000
        var selectTopMenuItem = new MenuItem
        {
            Header = "🔍 SELECT Top 1000 Rows"
        };
        selectTopMenuItem.Click += (s, e) => SelectTopRows(fullTableName, 1000);
        contextMenu.Items.Add(selectTopMenuItem);

        // SELECT Top 100
        var selectTop100MenuItem = new MenuItem
        {
            Header = "🔍 SELECT Top 100 Rows"
        };
        selectTop100MenuItem.Click += (s, e) => SelectTopRows(fullTableName, 100);
        contextMenu.Items.Add(selectTop100MenuItem);

        // SELECT All
        var selectAllMenuItem = new MenuItem
        {
            Header = "🔍 SELECT * (All Rows)"
        };
        selectAllMenuItem.Click += (s, e) => SelectAllRows(fullTableName);
        contextMenu.Items.Add(selectAllMenuItem);

        contextMenu.Items.Add(new Separator());

        // View Foreign Keys
        var foreignKeysMenuItem = new MenuItem
        {
            Header = "🔗 View Foreign Keys..."
        };
        foreignKeysMenuItem.Click += (s, e) => ViewForeignKeys(fullTableName);
        contextMenu.Items.Add(foreignKeysMenuItem);

        // View Indexes
        var indexesMenuItem = new MenuItem
        {
            Header = "📊 View Indexes..."
        };
        indexesMenuItem.Click += (s, e) => ViewIndexes(fullTableName);
        contextMenu.Items.Add(indexesMenuItem);

        // View DDL
        var ddlMenuItem = new MenuItem
        {
            Header = "📝 View DDL Script..."
        };
        ddlMenuItem.Click += (s, e) => ViewDDL(fullTableName);
        contextMenu.Items.Add(ddlMenuItem);

        contextMenu.Items.Add(new Separator());

        // Copy Table Name
        var copyNameMenuItem = new MenuItem
        {
            Header = "📄 Copy Table Name"
        };
        copyNameMenuItem.Click += (s, e) => CopyTableName(fullTableName);
        contextMenu.Items.Add(copyNameMenuItem);

        // Copy SELECT Statement
        var copySelectMenuItem = new MenuItem
        {
            Header = "📄 Copy SELECT Statement"
        };
        copySelectMenuItem.Click += (s, e) => CopySelectStatement(fullTableName);
        contextMenu.Items.Add(copySelectMenuItem);

        contextMenu.Items.Add(new Separator());

        // Refresh
        var refreshMenuItem = new MenuItem
        {
            Header = "🔄 Refresh"
        };
        refreshMenuItem.Click += (s, e) => RefreshTable(fullTableName);
        contextMenu.Items.Add(refreshMenuItem);

        return contextMenu;
    }
    
    /// <summary>
    /// Create context menu for package nodes
    /// </summary>
    private ContextMenu CreatePackageContextMenu(PackageInfo package)
    {
        var contextMenu = new ContextMenu();
        
        // Properties
        var propsItem = new MenuItem { Header = "⚙️ Properties...", FontWeight = FontWeights.Bold };
        propsItem.Click += (s, e) => ShowPackageDetails(package);
        contextMenu.Items.Add(propsItem);
        
        // Open as New Tab
        var openTabItem = new MenuItem { Header = "📌 Open as New Tab" };
        openTabItem.Click += async (s, e) =>
        {
            try
            {
                if (Window.GetWindow(this) is MainWindow mainWindow)
                {
                    // Get package statements using required statement
                    var pkgMetadata = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                    var stmtSqlTemplate = pkgMetadata.GetRequiredStatement("GetPackageStatementsWithText");
                    var stmtSql = ReplaceSqlPlaceholders(stmtSqlTemplate, package.PackageSchema?.Trim() ?? "", package.PackageName?.Trim() ?? "");
                    var sb = new System.Text.StringBuilder();
                    sb.AppendLine($"-- Package: {package.PackageSchema?.Trim()}.{package.PackageName?.Trim()}");
                    sb.AppendLine($"-- Created: {package.CreateTime:yyyy-MM-dd HH:mm:ss}");
                    sb.AppendLine($"-- Owner: {package.Owner}");
                    sb.AppendLine();
                    
                    using var cmd = _connectionManager.CreateCommand(stmtSql);
                    using var reader = await cmd.ExecuteReaderAsync();
                    while (await reader.ReadAsync())
                    {
                        var stmtNo = reader.GetInt32(0);
                        var text = reader.IsDBNull(1) ? "" : reader.GetString(1);
                        sb.AppendLine($"-- Statement {stmtNo}:");
                        sb.AppendLine(text);
                        sb.AppendLine();
                    }
                    
                    mainWindow.CreateNewTabWithSql(sb.ToString(), $"Package: {package.PackageName?.Trim()}");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to open package as new tab");
                MessageBox.Show($"Failed to open package as tab: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        };
        contextMenu.Items.Add(openTabItem);
        
        contextMenu.Items.Add(new Separator());
        
        // Copy Name
        var copyItem = new MenuItem { Header = "📋 Copy Full Name" };
        copyItem.Click += (s, e) => Clipboard.SetText($"{package.PackageSchema?.Trim()}.{package.PackageName?.Trim()}");
        contextMenu.Items.Add(copyItem);
        
        return contextMenu;
    }
    
    /// <summary>
    /// Create context menu for tablespace nodes
    /// </summary>
    private ContextMenu CreateTablespaceContextMenu(TablespaceInfo tablespace)
    {
        var contextMenu = new ContextMenu();
        
        // Properties
        var propsItem = new MenuItem { Header = "⚙️ Properties...", FontWeight = FontWeights.Bold };
        propsItem.Click += (s, e) => ShowTablespaceDetails(tablespace);
        contextMenu.Items.Add(propsItem);
        
        // Open as New Tab
        var openTabItem = new MenuItem { Header = "📌 Open as New Tab" };
        openTabItem.Click += (s, e) =>
        {
            if (Window.GetWindow(this) is MainWindow mainWindow)
            {
                // Use required statement for tables in tablespace
                var tsMetadata = App.MetadataHandler ?? throw new InvalidOperationException("MetadataHandler not initialized");
                var tablesSqlTemplate = tsMetadata.GetRequiredStatement("GetTablesInTablespace");
                var tablesSql = tablesSqlTemplate.Replace("?", $"'{tablespace.TablespaceName}'");
                var sql = $"-- Tablespace: {tablespace.TablespaceName}\n-- Type: {tablespace.TablespaceType}\n-- Page Size: {tablespace.PageSize} bytes\n-- Owner: {tablespace.Owner}\n\n-- Tables in this tablespace:\n{tablesSql};";
                mainWindow.CreateNewTabWithSql(sql, $"Tablespace: {tablespace.TablespaceName}");
            }
        };
        contextMenu.Items.Add(openTabItem);
        
        contextMenu.Items.Add(new Separator());
        
        // Copy Name
        var copyItem = new MenuItem { Header = "📋 Copy Name" };
        copyItem.Click += (s, e) => Clipboard.SetText(tablespace.TablespaceName);
        contextMenu.Items.Add(copyItem);
        
        return contextMenu;
    }

    private void ViewTableDetails(string fullTableName)
    {
        Logger.Info("Opening table details dialog for: {Table}", fullTableName);
        
        try
        {
            var dialog = new Dialogs.TableDetailsDialog(_connectionManager, fullTableName)
            {
                Owner = Window.GetWindow(this)
            };

            if (dialog.ShowDialog() == true)
            {
                // Check if user wants to query the table
                if (dialog.ShouldQueryTable)
                {
                    SelectTopRows(fullTableName, _preferencesService.Preferences.MaxRowsPerQuery);
                }
                // Check if user selected a related table to view
                else if (!string.IsNullOrEmpty(dialog.SelectedRelatedTable))
                {
                    ViewTableDetails(dialog.SelectedRelatedTable);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open table details dialog");
            MessageBox.Show($"Error opening table details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void SelectTopRows(string fullTableName, int topRows)
    {
        Logger.Info("Generating SELECT TOP {Count} for table: {Table}", topRows, fullTableName);
        
        var sql = $"SELECT * FROM {fullTableName} FETCH FIRST {topRows} ROWS ONLY";
        SqlEditor.Text = sql;
        SqlEditor.SelectAll();
        SqlEditor.Focus();
        
        StatusText.Text = $"Query generated for {fullTableName}";
    }

    private void SelectAllRows(string fullTableName)
    {
        Logger.Info("Generating SELECT ALL for table: {Table}", fullTableName);
        
        var sql = $"SELECT * FROM {fullTableName}";
        SqlEditor.Text = sql;
        SqlEditor.SelectAll();
        SqlEditor.Focus();
        
        StatusText.Text = $"Query generated for {fullTableName}";
    }
    
    /// <summary>
    /// Loads a SQL script into the editor with optional title.
    /// Used for loading migration scripts from Mermaid diff.
    /// </summary>
    public void LoadScriptIntoEditor(string sqlScript, string? title = null)
    {
        Logger.Info("Loading script into SQL editor - {Length} characters", sqlScript.Length);
        
        // Clear existing content
        SqlEditor.Text = sqlScript;
        SqlEditor.Focus();
        
        // Move cursor to top
        SqlEditor.CaretOffset = 0;
        SqlEditor.ScrollToHome();
        
        // Update status bar
        if (!string.IsNullOrEmpty(title))
        {
            StatusText.Text = $"📝 {title} - REVIEW before executing (F5)";
        }
        else
        {
            StatusText.Text = "📝 Migration script loaded - REVIEW before executing (F5)";
        }
        StatusText.Foreground = new SolidColorBrush(Colors.Orange);
        
        // Highlight the editor to draw attention (light orange background)
        var originalBackground = SqlEditor.Background;
        SqlEditor.Background = new SolidColorBrush(Color.FromArgb(20, 255, 165, 0));
        
        // Reset background after 3 seconds
        var timer = new System.Timers.Timer(3000);
        timer.Elapsed += (s, e) =>
        {
            Dispatcher.Invoke(() =>
            {
                SqlEditor.Background = originalBackground;
                timer.Stop();
                timer.Dispose();
            });
        };
        timer.Start();
        
        Logger.Debug("Script loaded into editor with title: {Title}", title ?? "Migration Script");
    }

    private void ViewForeignKeys(string fullTableName)
    {
        Logger.Info("Opening table details (Foreign Keys tab) for: {Table}", fullTableName);
        
        try
        {
            var dialog = new Dialogs.TableDetailsDialog(_connectionManager, fullTableName)
            {
                Owner = Window.GetWindow(this)
            };
            
            // Switch to Foreign Keys tab after loading
            dialog.Loaded += (s, e) =>
            {
                if (dialog.DetailsTabControl.Items.Count > 1)
                {
                    dialog.DetailsTabControl.SelectedIndex = 1; // Foreign Keys tab
                }
            };
            
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to view foreign keys");
            MessageBox.Show($"Error viewing foreign keys:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ViewIndexes(string fullTableName)
    {
        Logger.Info("Opening table details (Indexes tab) for: {Table}", fullTableName);
        
        try
        {
            var dialog = new Dialogs.TableDetailsDialog(_connectionManager, fullTableName)
            {
                Owner = Window.GetWindow(this)
            };
            
            // Switch to Indexes tab after loading
            dialog.Loaded += (s, e) =>
            {
                if (dialog.DetailsTabControl.Items.Count > 2)
                {
                    dialog.DetailsTabControl.SelectedIndex = 2; // Indexes tab
                }
            };
            
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to view indexes");
            MessageBox.Show($"Error viewing indexes:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ViewDDL(string fullTableName)
    {
        Logger.Info("Opening table details (DDL tab) for: {Table}", fullTableName);
        
        try
        {
            var dialog = new Dialogs.TableDetailsDialog(_connectionManager, fullTableName)
            {
                Owner = Window.GetWindow(this)
            };
            
            // Switch to DDL tab after loading
            dialog.Loaded += (s, e) =>
            {
                if (dialog.DetailsTabControl.Items.Count > 3)
                {
                    dialog.DetailsTabControl.SelectedIndex = 3; // DDL tab
                }
            };
            
            dialog.ShowDialog();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to view DDL");
            MessageBox.Show($"Error viewing DDL:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void CopyTableName(string fullTableName)
    {
        Logger.Debug("Copying table name to clipboard: {Table}", fullTableName);
        
        try
        {
            Clipboard.SetText(fullTableName);
            StatusText.Text = $"Table name copied: {fullTableName}";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy table name");
            MessageBox.Show($"Failed to copy to clipboard:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void CopySelectStatement(string fullTableName)
    {
        Logger.Debug("Copying SELECT statement to clipboard for: {Table}", fullTableName);
        
        try
        {
            var sql = $"SELECT * FROM {fullTableName};";
            Clipboard.SetText(sql);
            StatusText.Text = $"SELECT statement copied";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy SELECT statement");
            MessageBox.Show($"Failed to copy to clipboard:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void RefreshTable(string fullTableName)
    {
        Logger.Info("Refresh requested for table: {Table}", fullTableName);
        
        StatusText.Text = $"Refreshed: {fullTableName}";
        
        // Could reload table details if needed in the future
    }

    private async void Execute_Click(object sender, RoutedEventArgs e)
    {
        await ExecuteQuery();
    }

    private async Task ExecuteQuery()
    {
        await ExecuteSql(SqlEditor.Text);
    }

    private async Task ExecuteCurrentStatement()
    {
        Logger.Debug("Execute current statement requested");

        var sql = GetCurrentStatement();
        if (string.IsNullOrWhiteSpace(sql))
        {
            StatusText.Text = "No SQL statement at cursor";
            return;
        }

        await ExecuteSql(sql);
    }

    private string GetCurrentStatement()
    {
        var text = SqlEditor.Text;
        var caretOffset = SqlEditor.CaretOffset;

        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        // Find statement boundaries (separated by semicolons)
        var statements = text.Split(';');
        var currentPos = 0;

        foreach (var statement in statements)
        {
            currentPos += statement.Length;
            if (caretOffset <= currentPos)
            {
                return statement.Trim();
            }
            currentPos++; // Account for semicolon
        }

        return statements.LastOrDefault()?.Trim() ?? string.Empty;
    }

    private async Task ExecuteSql(string sql, bool resetPagination = true)
    {
        sql = sql?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(sql))
        {
            Logger.Debug("Empty SQL query");
            StatusText.Text = "No SQL to execute";
            return;
        }

        // Validate SQL for dangerous operations (only on new queries, not pagination)
        if (resetPagination && !_safetyValidator.ValidateAndWarn(sql))
        {
            Logger.Info("SQL execution cancelled by user after safety warning");
            StatusText.Text = "Query cancelled - safety check failed";
            return;
        }

        // Reset pagination if this is a new query
        if (resetPagination)
        {
            _currentPage = 1;
            _currentOffset = 0;
            _lastExecutedSql = sql;
            Logger.Debug("Pagination reset to page 1");
        }

        Logger.Info($"Executing SQL (Page {_currentPage}, Offset {_currentOffset}): {sql.Substring(0, Math.Min(50, sql.Length))}...");
        StatusText.Text = "Executing query...";
        ExecuteButton.IsEnabled = false;
        PreviousButton.IsEnabled = false;
        NextButton.IsEnabled = false;

        var stopwatch = Stopwatch.StartNew();

        try
        {
            var maxRows = _preferencesService.Preferences.MaxRowsPerQuery;
            var handleDecimalErrors = _preferencesService.Preferences.HandleDecimalErrorsGracefully;
            
            var dataTable = await _connectionManager.ExecuteQueryAsync(sql, maxRows, _currentOffset, handleDecimalErrors);
            ResultsGrid.ItemsSource = dataTable.DefaultView;

            stopwatch.Stop();
            var elapsed = stopwatch.ElapsedMilliseconds;

            var rowsReturned = dataTable.Rows.Count;
            var rowFrom = _currentOffset + 1;
            var rowTo = _currentOffset + rowsReturned;
            
            RowCountText.Text = $"{rowsReturned} rows (Rows {rowFrom:N0}-{rowTo:N0})";
            ExecutionTimeText.Text = $"Executed in {elapsed}ms";
            StatusText.Text = "Query completed successfully";
            PageInfoText.Text = $"Page {_currentPage}";

            // Enable/disable pagination buttons
            PreviousButton.IsEnabled = _currentPage > 1;
            NextButton.IsEnabled = rowsReturned >= maxRows; // If we got a full page, there might be more
            
            Logger.Debug("Pagination buttons updated - Previous: {PrevEnabled}, Next: {NextEnabled}", 
                PreviousButton.IsEnabled, NextButton.IsEnabled);

            Logger.Info($"Query executed successfully: {rowsReturned} rows in {elapsed}ms (Page {_currentPage})");

            // Save to query history with connection name
            _queryHistoryService.AddQuery(sql, _connection.GetDisplayName(), _connection.Database, true, elapsed, rowsReturned);
            
            // Refresh history display
            RefreshQueryHistory();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Query execution failed");
            stopwatch.Stop();
            var elapsed = stopwatch.ElapsedMilliseconds;

            StatusText.Text = "Query failed";
            RowCountText.Text = "Error - No results";
            ExecutionTimeText.Text = "";
            PageInfoText.Text = "Page -";
            PreviousButton.IsEnabled = false;
            NextButton.IsEnabled = false;

            // Save failed query to history
            _queryHistoryService.AddQuery(sql, _connection.GetDisplayName(), _connection.Database, false, elapsed);
            
            // Refresh history display
            RefreshQueryHistory();

            MessageBox.Show($"Query execution error:\n\n{ex.Message}", "Query Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            ExecuteButton.IsEnabled = true;
        }
    }
    
    private async void Previous_Click(object sender, RoutedEventArgs e)
    {
        if (_currentPage <= 1 || string.IsNullOrEmpty(_lastExecutedSql))
        {
            return;
        }

        Logger.Debug($"Loading previous page (current: {_currentPage})");
        
        _currentPage--;
        _currentOffset = (_currentPage - 1) * _preferencesService.Preferences.MaxRowsPerQuery;
        
        await ExecuteSql(_lastExecutedSql, resetPagination: false);
    }

    private async void Next_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_lastExecutedSql))
        {
            return;
        }

        Logger.Debug($"Loading next page (current: {_currentPage})");
        
        _currentPage++;
        _currentOffset = (_currentPage - 1) * _preferencesService.Preferences.MaxRowsPerQuery;
        
        await ExecuteSql(_lastExecutedSql, resetPagination: false);
    }

    private void Format_Click(object sender, RoutedEventArgs e)
    {
        FormatSql();
    }

    /// <summary>
    /// Format SQL in the editor (public for menu access)
    /// </summary>
    public void FormatSql()
    {
        var sql = SqlEditor.Text;
        if (string.IsNullOrWhiteSpace(sql))
        {
            return;
        }

        Logger.Info("Formatting SQL");

        try
        {
            var formattedSql = _formatterService.FormatSql(sql);
            SqlEditor.Text = formattedSql;
            StatusText.Text = "SQL formatted successfully";
            Logger.Debug("SQL formatting completed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "SQL formatting failed");
            MessageBox.Show($"Formatting error:\n\n{ex.Message}", "Format Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    
    /// <summary>
    /// Show Find dialog (public for menu access)
    /// </summary>
    public void ShowFindDialog()
    {
        // AvalonEdit doesn't have built-in find dialog, use Ctrl+F behavior
        // For now, just select the search box if visible or show message
        MessageBox.Show("Use Ctrl+F in the SQL editor to find text.\n\nThe find panel appears at the top of the editor.", 
            "Find", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    /// <summary>
    /// Show Find and Replace dialog (public for menu access)
    /// </summary>
    public void ShowReplaceDialog()
    {
        MessageBox.Show("Use Ctrl+H in the SQL editor to find and replace text.\n\nThe replace panel appears at the top of the editor.", 
            "Find and Replace", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    /// <summary>
    /// Open AI SQL Edit dialog (Ctrl+K). Replaces selection with LLM result on Accept.
    /// </summary>
    private void OpenSqlEditWithAiDialog(string selectedSql)
    {
        var owner = Window.GetWindow(this);
        var dialog = new SqlEditWithAiDialog(selectedSql, _connectionManager)
        {
            Owner = owner
        };
        if (dialog.ShowDialog() != true || string.IsNullOrEmpty(dialog.ResultNewSql))
            return;
        var start = SqlEditor.SelectionStart;
        var length = SqlEditor.SelectionLength;
        SqlEditor.Document.Replace(start, length, dialog.ResultNewSql);
        Logger.Info("AI SQL edit applied: replaced {Len} chars with {NewLen} chars", length, dialog.ResultNewSql.Length);
    }
    
    /// <summary>
    /// Open SQL file (public for menu access)
    /// </summary>
    public void OpenSqlFile()
    {
        OpenScript();
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Clearing editor and results");
        SqlEditor.Clear();
        ResultsGrid.ItemsSource = null;
        RowCountText.Text = "No results";
        ExecutionTimeText.Text = "";
        StatusText.Text = "Ready";
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Export button clicked");

        if (ResultsGrid.ItemsSource == null)
        {
            MessageBox.Show("No results to export. Execute a query first.", "Export",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var dataView = ResultsGrid.ItemsSource as System.Data.DataView;
        if (dataView == null)
        {
            Logger.Warn("Unable to export: ItemsSource is not a DataView");
            return;
        }

        var dataTable = dataView.Table;
        if (dataTable == null)
        {
            Logger.Warn("Unable to export: DataView.Table is null");
            StatusText.Text = "No data to export";
            MessageBox.Show("No data available to export.", "Export Failed", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        // Show export dialog
        var exportDialog = new ExportToFileDialog(dataTable)
        {
            Owner = Window.GetWindow(this)
        };

        if (exportDialog.ShowDialog() == true)
        {
            StatusText.Text = $"Exported {dataTable.Rows.Count} rows";
            Logger.Info("Export to file completed successfully");
        }
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        OpenScript();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        SaveScript();
    }

    private void OpenScript()
    {
        Logger.Debug("Open script requested");

        var openFileDialog = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "SQL Files (*.sql)|*.sql|Text Files (*.txt)|*.txt|All Files (*.*)|*.*",
            DefaultExt = ".sql",
            Title = "Open SQL Script"
        };

        if (openFileDialog.ShowDialog() == true)
        {
            try
            {
                Logger.Info($"Opening script: {openFileDialog.FileName}");
                // Use UTF-8 encoding to properly handle Norwegian/special characters (ÆØÅ)
                var content = File.ReadAllText(openFileDialog.FileName, System.Text.Encoding.UTF8);
                SqlEditor.Text = content;
                StatusText.Text = $"Loaded: {Path.GetFileName(openFileDialog.FileName)}";
                Logger.Info($"Script loaded successfully: {content.Length} characters");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to open script: {openFileDialog.FileName}");
                MessageBox.Show($"Failed to open script:\n\n{ex.Message}", "Open Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void SaveScript()
    {
        Logger.Debug("Save script requested");

        if (string.IsNullOrWhiteSpace(SqlEditor.Text))
        {
            MessageBox.Show("No SQL to save.", "Save Script",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var saveFileDialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "SQL Files (*.sql)|*.sql|Text Files (*.txt)|*.txt|All Files (*.*)|*.*",
            DefaultExt = ".sql",
            FileName = $"script_{DateTime.Now:yyyyMMdd_HHmmss}.sql",
            Title = "Save SQL Script"
        };

        if (saveFileDialog.ShowDialog() == true)
        {
            try
            {
                Logger.Info($"Saving script: {saveFileDialog.FileName}");
                // Use UTF-8 encoding with BOM to properly save Norwegian/special characters (ÆØÅ)
                File.WriteAllText(saveFileDialog.FileName, SqlEditor.Text, new System.Text.UTF8Encoding(true));
                StatusText.Text = $"Saved: {Path.GetFileName(saveFileDialog.FileName)} (UTF-8)";
                Logger.Info($"Script saved successfully: {SqlEditor.Text.Length} characters (UTF-8 with BOM)");

                MessageBox.Show($"Script saved successfully (UTF-8 encoding):\n{saveFileDialog.FileName}",
                    "Save Complete", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Failed to save script: {saveFileDialog.FileName}");
                MessageBox.Show($"Failed to save script:\n\n{ex.Message}", "Save Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    /// <summary>
    /// Set query text in the editor (used for rerunning queries from history)
    /// </summary>
    public void SetQueryText(string queryText)
    {
        Logger.Debug("Setting query text from external source");
        SqlEditor.Text = queryText;
        SqlEditor.Focus();
    }

    /// <summary>
    /// Refresh query history display
    /// </summary>
    private void RefreshQueryHistory()
    {
        try
        {
            Logger.Debug("Refreshing query history display");
            
            var searchTerm = HistorySearchBox?.Text ?? string.Empty;
            var showAllConnections = ShowAllConnectionsCheckBox?.IsChecked == true;
            
            var connectionFilter = showAllConnections ? null : _connection.GetDisplayName();
            
            var historyItems = _queryHistoryService.SearchHistory(searchTerm, connectionFilter);
            
            var viewModels = historyItems.Select(item =>
            {
                var decryptedSql = _queryHistoryService.GetDecryptedSql(item);
                return Models.QueryHistoryViewModel.FromHistoryItem(item, decryptedSql);
            }).ToList();
            
            QueryHistoryListBox.ItemsSource = viewModels;
            
            Logger.Debug("History refreshed with {Count} items", viewModels.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh query history");
        }
    }

    /// <summary>
    /// Handle search text changed in history
    /// </summary>
    private void HistorySearch_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshQueryHistory();
    }

    /// <summary>
    /// Handle show all connections checkbox changed
    /// </summary>
    private void ShowAllConnections_Changed(object sender, RoutedEventArgs e)
    {
        RefreshQueryHistory();
    }

    /// <summary>
    /// Handle double-click on history item to load query
    /// </summary>
    private void HistoryItem_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (QueryHistoryListBox.SelectedItem is Models.QueryHistoryViewModel viewModel)
        {
            Logger.Info("Loading query from history: {Preview}", viewModel.SqlPreview);
            
            SqlEditor.Text = viewModel.SqlStatement;
            SqlEditor.SelectAll();
            SqlEditor.Focus();
            
            StatusText.Text = $"Query loaded from history ({viewModel.ExecutedAt})";
        }
    }

    /// <summary>
    /// Open dialog to copy results to clipboard in various formats
    /// </summary>
    private void CopyToClipboard_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Copy to clipboard requested");

        if (ResultsGrid.ItemsSource == null)
        {
            MessageBox.Show("No results to copy. Execute a query first.", "Copy to Clipboard",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var dataView = ResultsGrid.ItemsSource as System.Data.DataView;
        if (dataView?.Table == null)
        {
            Logger.Warn("Unable to copy: ItemsSource is not a DataView or Table is null");
            MessageBox.Show("No data available to copy.", "Copy Failed",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            var dialog = new Dialogs.ExportToClipboardDialog(dataView.Table)
            {
                Owner = Window.GetWindow(this)
            };

            if (dialog.ShowDialog() == true)
            {
                StatusText.Text = "Data copied to clipboard";
                Logger.Info("Data successfully copied to clipboard");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open copy to clipboard dialog");
            MessageBox.Show($"Error opening copy dialog:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Copy selected cell value to clipboard (Issue #1 fix - uses cached cell info)
    /// </summary>
    private void CopyCell_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Copy cell requested");

        try
        {
            // Use cached cell info instead of SelectedCells (Issue #1 fix)
            if (_lastClickedCell == null || !_lastClickedCell.HasValue)
            {
                Logger.Warn("No cell clicked - attempting fallback to SelectedCells");
                
                // Fallback to selected cells if no cached cell
            var selectedCells = ResultsGrid.SelectedCells;
            if (selectedCells.Count == 0)
            {
                MessageBox.Show("No cell selected.", "Copy Cell",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

                _lastClickedCell = selectedCells[0];
            }

            var cellInfo = _lastClickedCell.Value;
            var cellValue = cellInfo.Item;
            var columnName = cellInfo.Column?.Header?.ToString() ?? string.Empty;

            Logger.Debug("Copying cell - Column: {Column}, HasValue: {HasValue}", 
                columnName, cellValue != null);

            if (cellValue != null)
            {
                var property = cellValue.GetType().GetProperty(columnName);
                if (property != null)
                {
                    var value = property.GetValue(cellValue)?.ToString() ?? string.Empty;
                    Clipboard.SetText(value);
                    StatusText.Text = $"Cell value copied: {value.Substring(0, Math.Min(30, value.Length))}...";
                    Logger.Info("Cell value copied to clipboard");
                }
                else
                {
                    // Try DataRowView
                    if (cellValue is System.Data.DataRowView rowView)
                    {
                        var value = rowView[columnName]?.ToString() ?? string.Empty;
                        Clipboard.SetText(value);
                        StatusText.Text = $"Cell value copied";
                        Logger.Info("Cell value copied to clipboard");
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy cell");
            MessageBox.Show($"Failed to copy cell:\n\n{ex.Message}", "Copy Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Copy selected row to clipboard as CSV
    /// </summary>
    private void CopyRow_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Copy row requested");

        try
        {
            if (ResultsGrid.SelectedItem == null)
            {
                MessageBox.Show("No row selected.", "Copy Row",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var dataView = ResultsGrid.ItemsSource as System.Data.DataView;
            if (dataView?.Table == null)
            {
                Logger.Warn("Unable to copy row: ItemsSource is not a DataView");
                return;
            }

            var rowView = ResultsGrid.SelectedItem as System.Data.DataRowView;
            if (rowView == null)
            {
                Logger.Warn("Selected item is not a DataRowView");
                return;
            }

            // Build CSV row
            var values = new List<string>();
            foreach (System.Data.DataColumn column in dataView.Table.Columns)
            {
                var value = rowView[column.ColumnName]?.ToString() ?? string.Empty;
                // Escape CSV if needed
                if (value.Contains(',') || value.Contains('"') || value.Contains('\n'))
                {
                    value = $"\"{value.Replace("\"", "\"\"")}\"";
                }
                values.Add(value);
            }

            var csvRow = string.Join(",", values);
            Clipboard.SetText(csvRow);
            StatusText.Text = "Row copied to clipboard as CSV";
            Logger.Info("Row copied to clipboard");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy row");
            MessageBox.Show($"Failed to copy row:\n\n{ex.Message}", "Copy Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Copy selected cells to clipboard with format options
    /// </summary>
    private void CopySelection_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Copy selection requested");

        try
        {
            var selectedCells = ResultsGrid.SelectedCells;
            if (selectedCells.Count == 0)
            {
                MessageBox.Show("No cells selected.", "Copy Selection",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var dataView = ResultsGrid.ItemsSource as System.Data.DataView;
            if (dataView?.Table == null)
            {
                Logger.Warn("Unable to copy selection: ItemsSource is not a DataView");
                return;
            }

            // Group selected cells by row and column
            var selectedRows = new HashSet<int>();
            var selectedColumns = new HashSet<int>();
            
            foreach (var cellInfo in selectedCells)
            {
                var rowItem = cellInfo.Item;
                var rowIndex = dataView.Table.Rows.IndexOf(((System.Data.DataRowView)rowItem).Row);
                var columnIndex = cellInfo.Column.DisplayIndex;
                
                selectedRows.Add(rowIndex);
                selectedColumns.Add(columnIndex);
            }

            Logger.Debug("Selection spans {RowCount} rows and {ColumnCount} columns", 
                selectedRows.Count, selectedColumns.Count);

            // Get sorted list of columns and their names
            var sortedColumns = selectedColumns.OrderBy(c => c).ToList();
            var columnHeaders = sortedColumns
                .Select(colIndex => ResultsGrid.Columns[colIndex].Header?.ToString() ?? $"Column{colIndex}")
                .ToList();

            // Create a DataTable with only the selected data
            var selectionTable = new System.Data.DataTable();
            foreach (var header in columnHeaders)
            {
                selectionTable.Columns.Add(header);
            }

            var sortedRows = selectedRows.OrderBy(r => r).ToList();
            foreach (var rowIndex in sortedRows)
            {
                var sourceRow = dataView.Table.Rows[rowIndex];
                var newRow = selectionTable.NewRow();
                
                for (int i = 0; i < sortedColumns.Count; i++)
                {
                    var colIndex = sortedColumns[i];
                    var columnName = dataView.Table.Columns[colIndex].ColumnName;
                    newRow[i] = sourceRow[columnName];
                }
                
                selectionTable.Rows.Add(newRow);
            }

            // Show copy selection dialog
            var copyDialog = new CopySelectionDialog(selectionTable, columnHeaders)
            {
                Owner = Window.GetWindow(this)
            };

            if (copyDialog.ShowDialog() == true)
            {
                StatusText.Text = $"Copied {sortedRows.Count} row(s) × {sortedColumns.Count} column(s) to clipboard";
                Logger.Info("Selection copied successfully");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy selection");
            MessageBox.Show($"Failed to copy selection:\n\n{ex.Message}", "Copy Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Update access level indicator badge - RBAC
    /// </summary>
    private void UpdateAccessLevelIndicator()
    {
        Logger.Debug("Updating access level indicator");
        
        if (_connection.Permissions == null)
        {
            Logger.Warn("Permissions not determined, hiding access level badge");
            AccessLevelBadge.Visibility = Visibility.Collapsed;
            return;
        }
        
        var permissions = _connection.Permissions;
        
        // Update badge text
        AccessLevelText.Text = permissions.AccessLevelBadge;
        AccessLevelText.ToolTip = permissions.PermissionsTooltip;
        
        // Update badge color
        var color = permissions.BadgeColor switch
        {
            "Green" => System.Windows.Media.Colors.Green,
            "Orange" => System.Windows.Media.Colors.Orange,
            "Red" => System.Windows.Media.Colors.Red,
            _ => System.Windows.Media.Colors.Gray
        };
        
        AccessLevelBadge.Background = new System.Windows.Media.SolidColorBrush(color);
        AccessLevelBadge.Visibility = Visibility.Visible;
        
        Logger.Info("Access level indicator updated: {Badge} ({Color})", 
            permissions.AccessLevelBadge, permissions.BadgeColor);
        
        // Log user permissions for transparency
        Logger.Info("User permissions - DDL: {DDL}, DML: {DML}, Force: {Force}, Stats: {Stats}, CDC: {CDC}, Drop: {Drop}",
            permissions.CanExecuteDDL, permissions.CanExecuteDML, permissions.CanForceDisconnect,
            permissions.CanModifyStatistics, permissions.CanModifyCDC, permissions.CanDropObjects);
    }
    
    private void UpdateTransactionButtonsVisibility()
    {
        var showButtons = !_connection.AutoCommit;
        CommitButton.Visibility = showButtons ? Visibility.Visible : Visibility.Collapsed;
        RollbackButton.Visibility = showButtons ? Visibility.Visible : Visibility.Collapsed;
        Logger.Debug("Transaction buttons visibility: {Visible} (AutoCommit: {AutoCommit})", showButtons, _connection.AutoCommit);
    }
    
    private async Task CommitTransaction()
    {
        try
        {
            await _connectionManager.CommitAsync();
            StatusText.Text = "Transaction committed";
            Logger.Info("Transaction committed successfully");
            MessageBox.Show("Transaction committed successfully.", "Commit", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to commit transaction");
            MessageBox.Show($"Failed to commit:\n\n{ex.Message}", "Commit Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async Task RollbackTransaction()
    {
        try
        {
            await _connectionManager.RollbackAsync();
            StatusText.Text = "Transaction rolled back";
            Logger.Info("Transaction rolled back successfully");
            MessageBox.Show("Transaction rolled back successfully.", "Rollback", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to rollback transaction");
            MessageBox.Show($"Failed to rollback:\n\n{ex.Message}", "Rollback Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void Commit_Click(object sender, RoutedEventArgs e) => await CommitTransaction();
    
    private async void Rollback_Click(object sender, RoutedEventArgs e) => await RollbackTransaction();
    
    /// <summary>
    /// Replace ? placeholders in SQL templates with quoted values
    /// </summary>
    private static string ReplaceSqlPlaceholders(string sql, params string[] values)
    {
        var result = sql;
        foreach (var value in values)
        {
            var idx = result.IndexOf('?');
            if (idx >= 0)
            {
                result = result.Remove(idx, 1).Insert(idx, $"'{value}'");
            }
        }
        return result;
    }

    public void Cleanup()
    {
        Logger.Debug("Cleaning up ConnectionTabControl");
        _connectionManager?.Dispose();
    }
}

