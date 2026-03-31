using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Helper service for applying consistent grid styling across all DataGrids in the application
/// </summary>
public static class GridStyleHelper
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// Apply grid preferences to all DataGrids in a window/dialog
    /// </summary>
    public static void ApplyGridStylesToWindow(Window window, UserPreferences preferences)
    {
        if (window == null)
        {
            Logger.Warn("Attempted to apply grid styles to null window");
            return;
        }

        try
        {
            Logger.Debug("Applying grid styles to all DataGrids in window: {Name}", window.GetType().Name);
            var grids = FindVisualChildren<DataGrid>(window);
            var count = 0;
            
            foreach (var grid in grids)
            {
                ApplyGridStyle(grid, preferences);
                count++;
            }
            
            Logger.Debug("Applied styles to {Count} DataGrids in window", count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error applying grid styles to window");
        }
    }

    /// <summary>
    /// Apply grid preferences to a DataGrid control
    /// </summary>
    public static void ApplyGridStyle(DataGrid grid, UserPreferences preferences)
    {
        if (grid == null)
        {
            Logger.Warn("Attempted to apply grid style to null DataGrid");
            return;
        }

        try
        {
            Logger.Debug("Applying grid style to DataGrid: {Name}, FontSize: {FontSize}, CellHeight: {CellHeight}", 
                grid.Name, preferences.GridFontSize, preferences.GridCellHeight);

            // Background color
            if (TryParseColor(preferences.GridBackgroundColor, out var backgroundColor))
            {
                grid.Background = new SolidColorBrush(backgroundColor);
            }

            // Foreground color
            if (TryParseColor(preferences.GridForegroundColor, out var foregroundColor))
            {
                grid.Foreground = new SolidColorBrush(foregroundColor);
            }

            // Font settings
            grid.FontSize = (double)preferences.GridFontSize;
            grid.FontFamily = new FontFamily(preferences.GridFontFamily);

            // Row height
            grid.RowHeight = (double)preferences.GridCellHeight;
            
            // Refresh column widths to adapt to new font size
            RefreshColumnWidths(grid, preferences);

            // Create or update style for selected rows
            var style = new Style(typeof(DataGridRow));
            
            // Default row style
            var defaultSetter = new Setter(Control.BackgroundProperty, new SolidColorBrush(backgroundColor));
            style.Setters.Add(defaultSetter);

            // Selected row style
            var selectedTrigger = new Trigger
            {
                Property = DataGridRow.IsSelectedProperty,
                Value = true
            };

            if (TryParseColor(preferences.GridSelectedBackgroundColor, out var selectedBackgroundColor))
            {
                selectedTrigger.Setters.Add(new Setter(Control.BackgroundProperty, 
                    new SolidColorBrush(selectedBackgroundColor)));
            }

            if (TryParseColor(preferences.GridSelectedForegroundColor, out var selectedForegroundColor))
            {
                selectedTrigger.Setters.Add(new Setter(Control.ForegroundProperty, 
                    new SolidColorBrush(selectedForegroundColor)));
            }

            style.Triggers.Add(selectedTrigger);

            // Mouse over style (slightly lighter than background)
            var mouseOverTrigger = new Trigger
            {
                Property = UIElement.IsMouseOverProperty,
                Value = true
            };

            if (TryParseColor(preferences.GridBackgroundColor, out var hoverBackgroundColor))
            {
                // Lighten the background color slightly for hover
                var hoverColor = Color.FromArgb(
                    hoverBackgroundColor.A,
                    (byte)Math.Min(255, hoverBackgroundColor.R + 10),
                    (byte)Math.Min(255, hoverBackgroundColor.G + 10),
                    (byte)Math.Min(255, hoverBackgroundColor.B + 10));
                mouseOverTrigger.Setters.Add(new Setter(Control.BackgroundProperty, 
                    new SolidColorBrush(hoverColor)));
            }

            style.Triggers.Add(mouseOverTrigger);

            grid.RowStyle = style;

            // Also style the header
            var headerStyle = new Style(typeof(DataGridColumnHeader));
            if (TryParseColor(preferences.GridBackgroundColor, out var headerBackgroundColor))
            {
                // Make header slightly darker
                var headerColor = Color.FromArgb(
                    headerBackgroundColor.A,
                    (byte)Math.Max(0, headerBackgroundColor.R - 20),
                    (byte)Math.Max(0, headerBackgroundColor.G - 20),
                    (byte)Math.Max(0, headerBackgroundColor.B - 20));
                headerStyle.Setters.Add(new Setter(Control.BackgroundProperty, 
                    new SolidColorBrush(headerColor)));
            }

            if (TryParseColor(preferences.GridForegroundColor, out var headerForegroundColor))
            {
                headerStyle.Setters.Add(new Setter(Control.ForegroundProperty, 
                    new SolidColorBrush(headerForegroundColor)));
            }

            headerStyle.Setters.Add(new Setter(Control.FontSizeProperty, (double)preferences.GridFontSize));
            headerStyle.Setters.Add(new Setter(Control.FontFamilyProperty, new FontFamily(preferences.GridFontFamily)));

            grid.ColumnHeaderStyle = headerStyle;

            Logger.Debug("Grid style applied successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error applying grid style to DataGrid: {Name}", grid.Name);
        }
    }

    /// <summary>
    /// Refresh all DataGrid controls in the application with current preferences
    /// </summary>
    public static void RefreshAllGrids(UserPreferences preferences)
    {
        Logger.Info("Refreshing all DataGrid controls in the application");
        
        try
        {
            var mainWindow = Application.Current.MainWindow;
            if (mainWindow == null)
            {
                Logger.Warn("MainWindow is null, cannot refresh grids");
                return;
            }

            // Find all DataGrid controls in the visual tree
            var grids = FindVisualChildren<DataGrid>(mainWindow);
            var count = 0;
            
            foreach (var grid in grids)
            {
                ApplyGridStyle(grid, preferences);
                count++;
            }
            
            Logger.Info("Refreshed {Count} DataGrid controls", count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error refreshing all grids");
        }
    }

    /// <summary>
    /// Refresh column widths to adapt to new font sizes
    /// This forces columns to recalculate their widths based on content
    /// </summary>
    private static void RefreshColumnWidths(DataGrid grid, UserPreferences preferences)
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
                    // For auto/star columns, temporarily set to auto to force recalculation
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
            
            Logger.Debug("Column widths refreshed for grid: {Name}, ScaleFactor: {Scale:F2}", 
                grid.Name, scaleFactor);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error refreshing column widths for grid: {Name}", grid.Name);
        }
    }

    /// <summary>
    /// Find all children of a specific type in the visual tree
    /// </summary>
    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject depObj) where T : DependencyObject
    {
        if (depObj == null) yield break;

        for (int i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(depObj); i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(depObj, i);

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

    /// <summary>
    /// Try to parse a hex color string to a Color object
    /// </summary>
    private static bool TryParseColor(string hexColor, out Color color)
    {
        color = Colors.White;

        if (string.IsNullOrWhiteSpace(hexColor))
            return false;

        try
        {
            // Remove # if present
            var cleanHex = hexColor.TrimStart('#');

            // Handle 6-digit hex
            if (cleanHex.Length == 6)
            {
                var r = Convert.ToByte(cleanHex.Substring(0, 2), 16);
                var g = Convert.ToByte(cleanHex.Substring(2, 2), 16);
                var b = Convert.ToByte(cleanHex.Substring(4, 2), 16);
                color = Color.FromRgb(r, g, b);
                return true;
            }

            // Handle 8-digit hex (with alpha)
            if (cleanHex.Length == 8)
            {
                var a = Convert.ToByte(cleanHex.Substring(0, 2), 16);
                var r = Convert.ToByte(cleanHex.Substring(2, 2), 16);
                var g = Convert.ToByte(cleanHex.Substring(4, 2), 16);
                var b = Convert.ToByte(cleanHex.Substring(6, 2), 16);
                color = Color.FromArgb(a, r, g, b);
                return true;
            }

            return false;
        }
        catch
        {
            return false;
        }
    }
}
