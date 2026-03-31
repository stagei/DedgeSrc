using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ModernWpf;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Unified service for applying consistent UI styling across all windows and dialogs.
/// This is the single source of truth for all UI styling in the application.
/// Supports built-in themes (Dark, Light) and user custom themes.
/// </summary>
public static class UIStyleService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly string UserThemesDirectory = UserDataFolderHelper.EnsureSubFolder("Themes");
    private static AppTheme? _currentTheme;
    
    /// <summary>
    /// Application icon path (pack URI format)
    /// </summary>
    public const string ApplicationIconPath = "pack://application:,,,/Resources/dEdge.ico";
    
    /// <summary>
    /// Cached application icon for performance
    /// </summary>
    private static BitmapImage? _applicationIcon;

    /// <summary>
    /// Event raised when theme changes
    /// </summary>
    public static event EventHandler? ThemeChanged;
    
    /// <summary>
    /// Get the application icon as a BitmapImage
    /// </summary>
    public static BitmapImage GetApplicationIcon()
    {
        if (_applicationIcon == null)
        {
            try
            {
                var iconUri = new Uri(ApplicationIconPath, UriKind.Absolute);
                _applicationIcon = new BitmapImage(iconUri);
                _applicationIcon.Freeze(); // Freeze for thread safety
                Logger.Debug("Application icon loaded from: {Path}", ApplicationIconPath);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to load application icon from: {Path}", ApplicationIconPath);
                // Try loading from file system as fallback
                try
                {
                    var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "dEdge.ico");
                    if (File.Exists(iconPath))
                    {
                        _applicationIcon = new BitmapImage(new Uri(iconPath, UriKind.Absolute));
                        _applicationIcon.Freeze();
                        Logger.Info("Application icon loaded from file system: {Path}", iconPath);
                    }
                    else
                    {
                        _applicationIcon = new BitmapImage(); // Return empty to avoid null
                    }
                }
                catch
                {
                    _applicationIcon = new BitmapImage(); // Return empty to avoid null
                }
            }
        }
        return _applicationIcon;
    }

    #region Public API

    /// <summary>
    /// Apply all UI styles to a window/dialog. Call this in the Loaded event.
    /// </summary>
    public static void ApplyStyles(Window window)
    {
        if (window == null)
        {
            Logger.Warn("ApplyStyles called with null window");
            return;
        }

        // Apply the application icon if not already set
        ApplyWindowIcon(window);
        
        ApplyStylesToElement(window, window.GetType().Name);
    }
    
    /// <summary>
    /// Apply the application icon to a window
    /// </summary>
    public static void ApplyWindowIcon(Window window)
    {
        if (window == null) return;
        
        try
        {
            // Always set the icon to ensure it's loaded correctly
            var icon = GetApplicationIcon();
            if (icon != null && icon.PixelWidth > 0)
            {
                window.Icon = icon;
                Logger.Debug("Applied application icon to window: {Window}", window.GetType().Name);
            }
            else
            {
                Logger.Warn("Icon is null or invalid, trying file system path");
                // Try loading from file system directly
                var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "dEdge.ico");
                if (File.Exists(iconPath))
                {
                    var fileIcon = new BitmapImage(new Uri(iconPath, UriKind.Absolute));
                    fileIcon.Freeze();
                    window.Icon = fileIcon;
                    Logger.Info("Loaded icon from file system: {Path}", iconPath);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to apply icon to window: {Window}", window.GetType().Name);
        }
    }

    /// <summary>
    /// Apply all UI styles to a UserControl. Call this in the Loaded event.
    /// </summary>
    public static void ApplyStyles(UserControl control)
    {
        if (control == null)
        {
            Logger.Warn("ApplyStyles called with null control");
            return;
        }

        ApplyStylesToElement(control, control.GetType().Name);
    }

    /// <summary>
    /// Apply all UI styles to any FrameworkElement (Window, UserControl, etc.)
    /// </summary>
    public static void ApplyStyles(FrameworkElement element)
    {
        if (element == null)
        {
            Logger.Warn("ApplyStyles called with null element");
            return;
        }

        ApplyStylesToElement(element, element.GetType().Name);
    }

    private static void ApplyStylesToElement(DependencyObject element, string elementName)
    {
        try
        {
            var preferences = GetPreferences();
            if (preferences == null)
            {
                Logger.Warn("Cannot apply styles - preferences not available");
                return;
            }

            Logger.Debug("Applying UI styles to: {Name}", elementName);

            // Apply styles to all DataGrids
            ApplyDataGridStyles(element, preferences);

            // Apply styles to all TreeViews
            ApplyTreeViewStyles(element, preferences);

            // Apply styles to all ListBoxes
            ApplyListBoxStyles(element, preferences);

            Logger.Debug("UI styles applied successfully to: {Name}", elementName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error applying UI styles to: {Name}", elementName);
        }
    }

    #endregion

    #region Theme Management

    /// <summary>
    /// Get the current active theme
    /// </summary>
    public static AppTheme GetCurrentTheme()
    {
        if (_currentTheme != null)
            return _currentTheme;

        // Load theme based on preferences
        var preferences = GetPreferences();
        var themeName = preferences?.ActiveThemeName ?? "Dark";
        
        _currentTheme = LoadTheme(themeName) ?? CreateDefaultDarkTheme();
        return _currentTheme;
    }

    /// <summary>
    /// Get list of all available themes (built-in + custom)
    /// </summary>
    public static List<AppTheme> GetAvailableThemes()
    {
        var themes = new List<AppTheme>
        {
            CreateDefaultDarkTheme(),
            CreateDefaultLightTheme()
        };

        // Load user custom themes
        try
        {
            EnsureThemesDirectoryExists();
            if (Directory.Exists(UserThemesDirectory))
            {
                foreach (var file in Directory.GetFiles(UserThemesDirectory, "*.theme.json"))
                {
                    var theme = LoadThemeFromFile(file);
                    if (theme != null && !theme.IsBuiltIn)
                    {
                        themes.Add(theme);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading custom themes");
        }

        return themes;
    }

    /// <summary>
    /// Apply a theme by name
    /// </summary>
    public static void ApplyTheme(string themeName)
    {
        Logger.Info("Applying theme: {Name}", themeName);

        var theme = LoadTheme(themeName);
        if (theme == null)
        {
            Logger.Warn("Theme not found: {Name}, falling back to Dark", themeName);
            theme = CreateDefaultDarkTheme();
        }

        ApplyTheme(theme);
    }

    /// <summary>
    /// Apply a specific theme
    /// </summary>
    public static void ApplyTheme(AppTheme theme)
    {
        if (theme == null) return;

        Logger.Info("Applying theme: {Name} (BaseTheme: {Base})", theme.Name, theme.BaseTheme);

        _currentTheme = theme;

        // Determine base theme (Light or Dark)
        var baseTheme = theme.BaseTheme?.ToLowerInvariant() == "light"
            ? ModernWpf.ApplicationTheme.Light
            : ModernWpf.ApplicationTheme.Dark;

        // Update preferences with theme values
        var preferences = GetPreferences();
        if (preferences != null)
        {
            preferences.ActiveThemeName = theme.Name;
            preferences.DefaultTheme = theme.BaseTheme; // IMPORTANT: Update DefaultTheme for RefreshAllStyles

            // Apply grid settings
            preferences.GridBackgroundColor = theme.Grid.BackgroundColor;
            preferences.GridForegroundColor = theme.Grid.ForegroundColor;
            preferences.GridSelectedBackgroundColor = theme.Grid.SelectedBackgroundColor;
            preferences.GridSelectedForegroundColor = theme.Grid.SelectedForegroundColor;
            preferences.GridFontSize = theme.Grid.FontSize;
            preferences.GridFontFamily = theme.Grid.FontFamily;
            preferences.GridCellHeight = theme.Grid.CellHeight;

            // Apply editor settings
            preferences.EditorBackgroundColor = theme.Editor.BackgroundColor;
            preferences.EditorForegroundColor = theme.Editor.ForegroundColor;
            preferences.EditorLineNumberColor = theme.Editor.LineNumberColor;
            preferences.EditorCurrentLineColor = theme.Editor.CurrentLineColor;
            preferences.FontFamily = theme.Editor.FontFamily;
            preferences.FontSize = theme.Editor.FontSize;

            // Apply UI settings
            preferences.UIFontSize = theme.UI.ObjectBrowserFontSize;

            // Save preferences
            App.PreferencesService?.SavePreferences();
        }

        // Apply ModernWpf base theme at application level
        Logger.Debug("Setting ModernWpf ApplicationTheme to: {Theme}", baseTheme);
        ModernWpf.ThemeManager.Current.ApplicationTheme = baseTheme;

        // Force immediate theme application to all windows
        Application.Current.Dispatcher.Invoke(() =>
        {
            var windowList = new List<Window>(Application.Current.Windows.Cast<Window>());
            foreach (var window in windowList)
            {
                try
                {
                    // Set theme on each window explicitly
                    var elementTheme = baseTheme == ModernWpf.ApplicationTheme.Light 
                        ? ModernWpf.ElementTheme.Light 
                        : ModernWpf.ElementTheme.Dark;
                    ModernWpf.ThemeManager.SetRequestedTheme(window, elementTheme);
                    
                    Logger.Debug("Applied theme {Theme} to window: {Window}", elementTheme, window.GetType().Name);
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Error applying theme to window: {Window}", window.GetType().Name);
                }
            }
        });

        // Refresh all windows with custom styles (DataGrids, etc.)
        RefreshAllStyles();

        // Raise event
        ThemeChanged?.Invoke(null, EventArgs.Empty);

        Logger.Info("Theme applied successfully: {Name}", theme.Name);
    }

    /// <summary>
    /// Save current preferences as a custom theme
    /// </summary>
    public static bool SaveAsCustomTheme(string themeName, string description = "")
    {
        if (string.IsNullOrWhiteSpace(themeName))
        {
            Logger.Warn("Cannot save theme with empty name");
            return false;
        }

        // Don't allow overwriting built-in themes
        if (themeName.Equals("Dark", StringComparison.OrdinalIgnoreCase) ||
            themeName.Equals("Light", StringComparison.OrdinalIgnoreCase))
        {
            Logger.Warn("Cannot overwrite built-in theme: {Name}", themeName);
            return false;
        }

        try
        {
            var preferences = GetPreferences();
            if (preferences == null) return false;

            var theme = new AppTheme
            {
                Name = themeName,
                Description = description,
                BaseTheme = preferences.DefaultTheme,
                IsBuiltIn = false,
                Editor = new EditorTheme
                {
                    FontFamily = preferences.FontFamily,
                    FontSize = preferences.FontSize,
                    TabSize = preferences.TabSize,
                    BackgroundColor = preferences.EditorBackgroundColor,
                    ForegroundColor = preferences.EditorForegroundColor,
                    LineNumberColor = preferences.EditorLineNumberColor,
                    CurrentLineColor = preferences.EditorCurrentLineColor
                },
                Grid = new GridTheme
                {
                    FontFamily = preferences.GridFontFamily,
                    FontSize = preferences.GridFontSize,
                    CellHeight = preferences.GridCellHeight,
                    BackgroundColor = preferences.GridBackgroundColor,
                    ForegroundColor = preferences.GridForegroundColor,
                    SelectedBackgroundColor = preferences.GridSelectedBackgroundColor,
                    SelectedForegroundColor = preferences.GridSelectedForegroundColor
                },
                UI = new UITheme
                {
                    ObjectBrowserFontSize = preferences.UIFontSize,
                    DialogFontSize = preferences.UIFontSize,
                    PropertyWindowFontSize = preferences.UIFontSize
                }
            };

            EnsureThemesDirectoryExists();
            var filePath = Path.Combine(UserThemesDirectory, $"{themeName}.theme.json");
            var json = JsonSerializer.Serialize(theme, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(filePath, json);

            Logger.Info("Custom theme saved: {Name} -> {Path}", themeName, filePath);
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error saving custom theme: {Name}", themeName);
            return false;
        }
    }

    /// <summary>
    /// Delete a custom theme
    /// </summary>
    public static bool DeleteCustomTheme(string themeName)
    {
        // Don't allow deleting built-in themes
        if (themeName.Equals("Dark", StringComparison.OrdinalIgnoreCase) ||
            themeName.Equals("Light", StringComparison.OrdinalIgnoreCase))
        {
            Logger.Warn("Cannot delete built-in theme: {Name}", themeName);
            return false;
        }

        try
        {
            var filePath = Path.Combine(UserThemesDirectory, $"{themeName}.theme.json");
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                Logger.Info("Custom theme deleted: {Name}", themeName);
                return true;
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error deleting custom theme: {Name}", themeName);
        }

        return false;
    }

    private static AppTheme? LoadTheme(string themeName)
    {
        // Check built-in themes first
        if (themeName.Equals("Dark", StringComparison.OrdinalIgnoreCase))
            return CreateDefaultDarkTheme();
        if (themeName.Equals("Light", StringComparison.OrdinalIgnoreCase))
            return CreateDefaultLightTheme();

        // Try to load custom theme
        var filePath = Path.Combine(UserThemesDirectory, $"{themeName}.theme.json");
        return LoadThemeFromFile(filePath);
    }

    private static AppTheme? LoadThemeFromFile(string filePath)
    {
        try
        {
            if (!File.Exists(filePath)) return null;

            var json = File.ReadAllText(filePath);
            return JsonSerializer.Deserialize<AppTheme>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading theme file: {File}", filePath);
            return null;
        }
    }

    private static AppTheme CreateDefaultDarkTheme()
    {
        return new AppTheme
        {
            Name = "Dark",
            Description = "Built-in dark theme optimized for low-light environments",
            BaseTheme = "Dark",
            IsBuiltIn = true,
            Editor = new EditorTheme
            {
                FontFamily = "Consolas",
                FontSize = 14,
                TabSize = 4,
                BackgroundColor = "#1E1E1E",
                ForegroundColor = "#D4D4D4",
                LineNumberColor = "#858585",
                SelectionColor = "#264F78",
                CurrentLineColor = "#2D2D30"
            },
            Grid = new GridTheme
            {
                FontFamily = "Segoe UI",
                FontSize = 12,
                CellHeight = 25,
                BackgroundColor = "#2D2D2D",
                ForegroundColor = "#E0E0E0",
                SelectedBackgroundColor = "#0078D4",
                SelectedForegroundColor = "#FFFFFF",
                HeaderBackgroundColor = "#252526",
                HeaderForegroundColor = "#CCCCCC",
                AlternateRowColor = "#323232"
            },
            UI = new UITheme
            {
                ObjectBrowserFontSize = 12,
                DialogFontSize = 14,
                MenuFontSize = 12,
                StatusBarFontSize = 11,
                PropertyWindowFontSize = 12,
                WindowBackgroundColor = "#1E1E1E",
                WindowForegroundColor = "#E0E0E0",
                ButtonBackgroundColor = "#0E639C",
                ButtonForegroundColor = "#FFFFFF"
            }
        };
    }

    private static AppTheme CreateDefaultLightTheme()
    {
        return new AppTheme
        {
            Name = "Light",
            Description = "Built-in light theme for bright environments",
            BaseTheme = "Light",
            IsBuiltIn = true,
            Editor = new EditorTheme
            {
                FontFamily = "Consolas",
                FontSize = 14,
                TabSize = 4,
                BackgroundColor = "#FFFFFF",
                ForegroundColor = "#000000",
                LineNumberColor = "#2B91AF",
                SelectionColor = "#ADD6FF",
                CurrentLineColor = "#F0F0F0"
            },
            Grid = new GridTheme
            {
                FontFamily = "Segoe UI",
                FontSize = 12,
                CellHeight = 25,
                BackgroundColor = "#FFFFFF",
                ForegroundColor = "#000000",
                SelectedBackgroundColor = "#0078D4",
                SelectedForegroundColor = "#FFFFFF",
                HeaderBackgroundColor = "#F0F0F0",
                HeaderForegroundColor = "#000000",
                AlternateRowColor = "#F8F8F8"
            },
            UI = new UITheme
            {
                ObjectBrowserFontSize = 12,
                DialogFontSize = 14,
                MenuFontSize = 12,
                StatusBarFontSize = 11,
                PropertyWindowFontSize = 12,
                WindowBackgroundColor = "#FFFFFF",
                WindowForegroundColor = "#000000",
                ButtonBackgroundColor = "#0078D4",
                ButtonForegroundColor = "#FFFFFF"
            }
        };
    }

    private static void EnsureThemesDirectoryExists()
    {
        if (!Directory.Exists(UserThemesDirectory))
        {
            Directory.CreateDirectory(UserThemesDirectory);
            Logger.Debug("Created user themes directory: {Dir}", UserThemesDirectory);
        }
    }

    /// <summary>
    /// Apply styles to a specific DataGrid control
    /// </summary>
    public static void ApplyDataGridStyle(DataGrid grid)
    {
        var preferences = GetPreferences();
        if (preferences != null && grid != null)
        {
            ApplyDataGridStyleInternal(grid, preferences);
        }
    }

    /// <summary>
    /// Refresh all styles in the entire application (call after preferences change)
    /// </summary>
    public static void RefreshAllStyles()
    {
        Logger.Info("Refreshing all UI styles in application");

        try
        {
            var preferences = GetPreferences();
            if (preferences == null)
            {
                Logger.Warn("Cannot refresh styles - preferences not available");
                return;
            }

            // Apply ModernWpf theme to all windows first
            var baseTheme = preferences.DefaultTheme?.ToLowerInvariant() == "light"
                ? ModernWpf.ApplicationTheme.Light
                : ModernWpf.ApplicationTheme.Dark;
            
            Logger.Debug("Setting ModernWpf base theme to: {Theme}", baseTheme);
            ModernWpf.ThemeManager.Current.ApplicationTheme = baseTheme;

            // Refresh all windows - apply theme and force visual update
            var windowList = new List<Window>(Application.Current.Windows.Cast<Window>());
            foreach (var window in windowList)
            {
                try
                {
                    Logger.Debug("Refreshing window: {Name}", window.GetType().Name);
                    
                    // Force ModernWpf theme on window
                    ModernWpf.ThemeManager.SetRequestedTheme(
                        window,
                        baseTheme == ModernWpf.ApplicationTheme.Light 
                            ? ModernWpf.ElementTheme.Light 
                            : ModernWpf.ElementTheme.Dark);
                    
                    // Apply UIStyleService styles
                    ApplyStyles(window);
                    
                    // Find and refresh all UserControls
                    RefreshUserControlsInWindow(window);
                    
                    // Force visual refresh
                    ForceWindowRefresh(window);
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Error refreshing window: {Name}", window.GetType().Name);
                }
            }

            Logger.Info("UI styles refreshed for all windows and controls");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error refreshing all UI styles");
        }
    }

    /// <summary>
    /// Force a visual refresh of the window and all its children
    /// </summary>
    private static void ForceWindowRefresh(Window window)
    {
        try
        {
            // Update layout
            window.UpdateLayout();
            
            // Force visual refresh of all visual children
            ForceVisualRefresh(window);
            
            Logger.Trace("Window visual refresh forced: {Name}", window.GetType().Name);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error forcing window refresh");
        }
    }

    /// <summary>
    /// Recursively force visual refresh of all visual children
    /// </summary>
    private static void ForceVisualRefresh(DependencyObject obj)
    {
        if (obj == null) return;

        try
        {
            // Update layout for this element
            if (obj is FrameworkElement fe)
            {
                fe.InvalidateVisual();
                fe.UpdateLayout();
            }

            // Recursively update all children
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(obj); i++)
            {
                var child = VisualTreeHelper.GetChild(obj, i);
                ForceVisualRefresh(child);
            }
        }
        catch (Exception ex)
        {
            Logger.Trace(ex, "Error during visual refresh");
        }
    }

    /// <summary>
    /// Refresh all UserControls within a window
    /// </summary>
    private static void RefreshUserControlsInWindow(DependencyObject parent)
    {
        try
        {
            var userControls = FindVisualChildren<System.Windows.Controls.UserControl>(parent);
            foreach (var control in userControls)
            {
                ApplyStyles(control);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error refreshing UserControls in window");
        }
    }

    #endregion

    #region DataGrid Styling

    private static void ApplyDataGridStyles(DependencyObject parent, UserPreferences preferences)
    {
        var grids = FindVisualChildren<DataGrid>(parent);
        var count = 0;

        foreach (var grid in grids)
        {
            ApplyDataGridStyleInternal(grid, preferences);
            count++;
        }

        Logger.Debug("Applied styles to {Count} DataGrids", count);
    }

    private static void ApplyDataGridStyleInternal(DataGrid grid, UserPreferences preferences)
    {
        if (grid == null) return;

        try
        {
            // Parse colors
            var backgroundColor = ParseColor(preferences.GridBackgroundColor, Colors.Transparent);
            var foregroundColor = ParseColor(preferences.GridForegroundColor, Colors.White);
            var selectedBackground = ParseColor(preferences.GridSelectedBackgroundColor, Colors.Blue);
            var selectedForeground = ParseColor(preferences.GridSelectedForegroundColor, Colors.White);

            // Basic grid properties
            grid.Background = new SolidColorBrush(backgroundColor);
            grid.Foreground = new SolidColorBrush(foregroundColor);
            grid.FontSize = preferences.GridFontSize;
            grid.FontFamily = new FontFamily(preferences.GridFontFamily);
            grid.RowHeight = preferences.GridCellHeight;

            // Create row style with proper foreground inheritance
            var rowStyle = new Style(typeof(DataGridRow));
            rowStyle.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(backgroundColor)));
            rowStyle.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(foregroundColor)));

            // Selected row trigger
            var selectedTrigger = new Trigger
            {
                Property = DataGridRow.IsSelectedProperty,
                Value = true
            };
            selectedTrigger.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(selectedBackground)));
            selectedTrigger.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(selectedForeground)));
            rowStyle.Triggers.Add(selectedTrigger);

            // Hover trigger
            var hoverColor = LightenColor(backgroundColor, 15);
            var hoverTrigger = new Trigger
            {
                Property = UIElement.IsMouseOverProperty,
                Value = true
            };
            hoverTrigger.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(hoverColor)));
            rowStyle.Triggers.Add(hoverTrigger);

            grid.RowStyle = rowStyle;

            // Create cell style to ensure text is visible
            var cellStyle = new Style(typeof(DataGridCell));
            cellStyle.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(foregroundColor)));
            cellStyle.Setters.Add(new Setter(Control.BorderBrushProperty, Brushes.Transparent));
            cellStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(4, 2, 4, 2)));

            // Cell selected trigger
            var cellSelectedTrigger = new Trigger
            {
                Property = DataGridCell.IsSelectedProperty,
                Value = true
            };
            cellSelectedTrigger.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(selectedForeground)));
            cellSelectedTrigger.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(selectedBackground)));
            cellStyle.Triggers.Add(cellSelectedTrigger);

            grid.CellStyle = cellStyle;

            // Header style
            var headerBackground = DarkenColor(backgroundColor, 20);
            var headerStyle = new Style(typeof(DataGridColumnHeader));
            headerStyle.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(headerBackground)));
            headerStyle.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(foregroundColor)));
            headerStyle.Setters.Add(new Setter(Control.FontSizeProperty, (double)preferences.GridFontSize));
            headerStyle.Setters.Add(new Setter(Control.FontFamilyProperty, new FontFamily(preferences.GridFontFamily)));
            headerStyle.Setters.Add(new Setter(Control.FontWeightProperty, FontWeights.SemiBold));
            headerStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(8, 6, 8, 6)));
            headerStyle.Setters.Add(new Setter(Control.BorderBrushProperty, new SolidColorBrush(DarkenColor(backgroundColor, 10))));
            headerStyle.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0, 0, 1, 1)));

            grid.ColumnHeaderStyle = headerStyle;

            // Style text columns to ensure proper foreground color
            ApplyColumnElementStyles(grid, foregroundColor, selectedForeground, preferences);
            
            // Refresh column widths to adapt to new font size
            RefreshDataGridColumnWidths(grid, preferences);

            Logger.Trace("DataGrid styled: {Name}, FontSize: {FontSize}, CellHeight: {CellHeight}", 
                grid.Name ?? "unnamed", preferences.GridFontSize, preferences.GridCellHeight);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error styling DataGrid: {Name}", grid.Name);
        }
    }

    /// <summary>
    /// Refresh column widths to adapt to new font sizes
    /// </summary>
    private static void RefreshDataGridColumnWidths(DataGrid grid, UserPreferences preferences)
    {
        try
        {
            if (grid.Columns == null || grid.Columns.Count == 0)
                return;

            // Calculate a scale factor based on font size relative to default (12)
            var scaleFactor = preferences.GridFontSize / 12.0;
            
            foreach (var column in grid.Columns)
            {
                // Store current width mode
                var currentWidth = column.Width;
                
                // Set MinWidth based on font size to ensure content fits
                column.MinWidth = Math.Max(30, preferences.GridFontSize * 3);
                
                if (currentWidth.IsSizeToCells || currentWidth.IsSizeToHeader)
                {
                    // Force recalculation by toggling width mode
                    column.Width = DataGridLength.Auto;
                    column.Width = currentWidth;
                }
                else if (currentWidth.IsAuto || currentWidth.IsStar)
                {
                    // For auto/star columns, force recalculation
                    var originalWidth = column.Width;
                    column.Width = DataGridLength.Auto;
                    
                    // Use dispatcher to set back after layout pass
                    grid.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        try
                        {
                            column.Width = originalWidth;
                        }
                        catch { /* Ignore errors during async update */ }
                    }), System.Windows.Threading.DispatcherPriority.Loaded);
                }
                // For absolute widths, just leave them - they typically don't need scaling
            }
            
            // Force grid to update its layout
            grid.UpdateLayout();
            
            Logger.Trace("Column widths refreshed for grid: {Name}, ScaleFactor: {Scale:F2}", 
                grid.Name, scaleFactor);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error refreshing column widths for grid: {Name}", grid.Name);
        }
    }

    /// <summary>
    /// Apply element styles to DataGrid columns to ensure text is visible
    /// </summary>
    private static void ApplyColumnElementStyles(DataGrid grid, Color foreground, Color selectedForeground, UserPreferences preferences)
    {
        foreach (var column in grid.Columns)
        {
            if (column is DataGridTextColumn textColumn)
            {
                // Create element style for the TextBlock in cells
                var elementStyle = new Style(typeof(TextBlock));
                elementStyle.Setters.Add(new Setter(TextBlock.ForegroundProperty, new SolidColorBrush(foreground)));
                elementStyle.Setters.Add(new Setter(TextBlock.PaddingProperty, new Thickness(4, 2, 4, 2)));
                elementStyle.Setters.Add(new Setter(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center));

                textColumn.ElementStyle = elementStyle;
            }
            else if (column is DataGridTemplateColumn templateColumn)
            {
                // Template columns should inherit from parent, but we can set default style
                // This is handled by the cell style we already set
            }
        }
    }

    #endregion

    #region TreeView Styling

    private static void ApplyTreeViewStyles(DependencyObject parent, UserPreferences preferences)
    {
        var treeViews = FindVisualChildren<TreeView>(parent);

        foreach (var treeView in treeViews)
        {
            ApplyTreeViewStyleInternal(treeView, preferences);
        }
    }

    private static void ApplyTreeViewStyleInternal(TreeView treeView, UserPreferences preferences)
    {
        if (treeView == null) return;

        try
        {
            treeView.FontSize = preferences.UIFontSize;
            treeView.FontFamily = new FontFamily(preferences.GridFontFamily);

            Logger.Trace("TreeView styled: {Name}", treeView.Name ?? "unnamed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error styling TreeView: {Name}", treeView.Name);
        }
    }

    #endregion

    #region ListBox Styling

    private static void ApplyListBoxStyles(DependencyObject parent, UserPreferences preferences)
    {
        var listBoxes = FindVisualChildren<ListBox>(parent);

        foreach (var listBox in listBoxes)
        {
            ApplyListBoxStyleInternal(listBox, preferences);
        }
    }

    private static void ApplyListBoxStyleInternal(ListBox listBox, UserPreferences preferences)
    {
        if (listBox == null) return;

        try
        {
            var foregroundColor = ParseColor(preferences.GridForegroundColor, Colors.White);
            var backgroundColor = ParseColor(preferences.GridBackgroundColor, Colors.Transparent);

            listBox.FontSize = preferences.UIFontSize;
            listBox.FontFamily = new FontFamily(preferences.GridFontFamily);
            listBox.Foreground = new SolidColorBrush(foregroundColor);

            Logger.Trace("ListBox styled: {Name}", listBox.Name ?? "unnamed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error styling ListBox: {Name}", listBox.Name);
        }
    }

    #endregion

    #region Helper Methods

    private static UserPreferences? GetPreferences()
    {
        return App.PreferencesService?.Preferences;
    }

    private static Color ParseColor(string hexColor, Color defaultColor)
    {
        if (string.IsNullOrWhiteSpace(hexColor))
            return defaultColor;

        try
        {
            var cleanHex = hexColor.TrimStart('#');

            if (cleanHex.Length == 6)
            {
                var r = Convert.ToByte(cleanHex.Substring(0, 2), 16);
                var g = Convert.ToByte(cleanHex.Substring(2, 2), 16);
                var b = Convert.ToByte(cleanHex.Substring(4, 2), 16);
                return Color.FromRgb(r, g, b);
            }

            if (cleanHex.Length == 8)
            {
                var a = Convert.ToByte(cleanHex.Substring(0, 2), 16);
                var r = Convert.ToByte(cleanHex.Substring(2, 2), 16);
                var g = Convert.ToByte(cleanHex.Substring(4, 2), 16);
                var b = Convert.ToByte(cleanHex.Substring(6, 2), 16);
                return Color.FromArgb(a, r, g, b);
            }
        }
        catch
        {
            // Ignore parsing errors
        }

        return defaultColor;
    }

    private static Color LightenColor(Color color, int amount)
    {
        return Color.FromArgb(
            color.A,
            (byte)Math.Min(255, color.R + amount),
            (byte)Math.Min(255, color.G + amount),
            (byte)Math.Min(255, color.B + amount));
    }

    private static Color DarkenColor(Color color, int amount)
    {
        return Color.FromArgb(
            color.A,
            (byte)Math.Max(0, color.R - amount),
            (byte)Math.Max(0, color.G - amount),
            (byte)Math.Max(0, color.B - amount));
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject depObj) where T : DependencyObject
    {
        if (depObj == null) yield break;

        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(depObj); i++)
        {
            var child = VisualTreeHelper.GetChild(depObj, i);

            if (child is T t)
            {
                yield return t;
            }

            foreach (var childOfChild in FindVisualChildren<T>(child))
            {
                yield return childOfChild;
            }
        }
    }

    #endregion
}
