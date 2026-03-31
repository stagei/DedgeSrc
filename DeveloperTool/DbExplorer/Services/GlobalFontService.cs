using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for applying global font size to all windows and controls
/// </summary>
public static class GlobalFontService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// Apply the global UI font size to the entire application
    /// </summary>
    public static void ApplyGlobalFontSize(int fontSize)
    {
        Logger.Debug("Applying global font size: {FontSize}", fontSize);
        
        // Clamp font size to reasonable bounds
        fontSize = Math.Max(8, Math.Min(24, fontSize));
        
        // Apply to Application resources
        Application.Current.Resources["GlobalFontSize"] = (double)fontSize;
        Application.Current.Resources["GlobalFontSizeSmall"] = (double)(fontSize - 1);
        Application.Current.Resources["GlobalFontSizeLarge"] = (double)(fontSize + 2);
        
        // Apply to all open windows
        foreach (Window window in Application.Current.Windows)
        {
            ApplyFontSizeToWindow(window, fontSize);
        }
        
        Logger.Info("Global font size applied: {FontSize}pt", fontSize);
    }

    /// <summary>
    /// Apply font size to a specific window and all its child controls
    /// </summary>
    public static void ApplyFontSizeToWindow(Window window, int fontSize)
    {
        // Set the window's default font size
        window.FontSize = fontSize;
        
        // Recursively apply to all child controls
        ApplyFontSizeToElement(window, fontSize);
    }

    /// <summary>
    /// Apply font size to a FrameworkElement and all its children
    /// </summary>
    public static void ApplyFontSizeToElement(DependencyObject parent, int fontSize)
    {
        if (parent == null) return;
        
        int childCount = VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < childCount; i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            
            if (child is Control control)
            {
                // Apply font size based on control type
                ApplyFontToControl(control, fontSize);
            }
            
            // Recursively process children
            ApplyFontSizeToElement(child, fontSize);
        }
    }

    /// <summary>
    /// Apply appropriate font size to a specific control
    /// </summary>
    private static void ApplyFontToControl(Control control, int fontSize)
    {
        // Skip certain controls that should maintain their own size
        if (control is TabControl) return;
        if (control is TabItem) return;
        if (control is ScrollViewer) return;
        if (control is Slider) return;
        if (control is ProgressBar) return;
        
        // Apply font size to the control
        control.FontSize = fontSize;
    }

    /// <summary>
    /// Apply all preferences including font sizes, grid styles, and TreeView settings
    /// </summary>
    public static void ApplyAllPreferences(UserPreferences preferences)
    {
        // Apply global UI font size
        ApplyGlobalFontSize(preferences.UIFontSize);
        
        // Apply grid styles
        GridStyleHelper.RefreshAllGrids(preferences);
        
        Logger.Debug("All preferences applied");
    }
}

