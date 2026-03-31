using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ModernWpf;
using ModernWpf.Controls.Primitives;

namespace DbExplorer.Services;

/// <summary>
/// Helper for creating properly themed popup windows with ModernWpf styling
/// </summary>
public static class ThemedWindowHelper
{
    /// <summary>
    /// Apply modern theme styling to a window
    /// </summary>
    public static void ApplyTheme(Window window)
    {
        // Apply ModernWpf window style
        WindowHelper.SetUseModernWindowStyle(window, true);
        
        // Ensure the window follows the current application theme
        var currentTheme = ModernWpf.ThemeManager.Current.ActualApplicationTheme;
        if (currentTheme == ApplicationTheme.Dark)
        {
            ModernWpf.ThemeManager.SetRequestedTheme(window, ElementTheme.Dark);
        }
        else
        {
            ModernWpf.ThemeManager.SetRequestedTheme(window, ElementTheme.Light);
        }
    }
    
    /// <summary>
    /// Create a themed window with content
    /// </summary>
    public static Window CreateThemedWindow(string title, object content, double width = 700, double height = 500, Window? owner = null)
    {
        var window = new Window
        {
            Title = title,
            Width = width,
            Height = height,
            Content = content,
            WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
            Owner = owner
        };
        
        ApplyTheme(window);
        return window;
    }
    
    /// <summary>
    /// Create a themed window with a read-only TextBox for displaying scripts/text
    /// </summary>
    public static Window CreateScriptWindow(string title, string script, double width = 700, double height = 500, Window? owner = null)
    {
        var textBox = new TextBox
        {
            Text = script,
            IsReadOnly = true,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 12,
            Margin = new Thickness(10),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.NoWrap
        };
        
        return CreateThemedWindow(title, textBox, width, height, owner);
    }
}
