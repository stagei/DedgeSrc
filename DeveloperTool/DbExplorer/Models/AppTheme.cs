using System.Text.Json.Serialization;

namespace DbExplorer.Models;

/// <summary>
/// Comprehensive theme configuration including colors, fonts, and grid settings
/// Can be saved as a custom theme file
/// </summary>
public class AppTheme
{
    /// <summary>
    /// Theme name (e.g., "Dark", "Light", "Custom - Blue")
    /// </summary>
    [JsonPropertyName("name")]
    public string Name { get; set; } = "Custom Theme";

    /// <summary>
    /// Theme description
    /// </summary>
    [JsonPropertyName("description")]
    public string Description { get; set; } = "";

    /// <summary>
    /// Base theme: "Light" or "Dark"
    /// </summary>
    [JsonPropertyName("baseTheme")]
    public string BaseTheme { get; set; } = "Dark";

    /// <summary>
    /// Is this a built-in theme (non-editable)
    /// </summary>
    [JsonPropertyName("isBuiltIn")]
    public bool IsBuiltIn { get; set; } = false;

    // ==================== SQL EDITOR SETTINGS ====================
    
    [JsonPropertyName("editor")]
    public EditorTheme Editor { get; set; } = new();

    // ==================== GRID SETTINGS ====================
    
    [JsonPropertyName("grid")]
    public GridTheme Grid { get; set; } = new();

    // ==================== UI COMPONENT SETTINGS ====================
    
    [JsonPropertyName("ui")]
    public UITheme UI { get; set; } = new();
}

/// <summary>
/// SQL Editor theme settings
/// </summary>
public class EditorTheme
{
    [JsonPropertyName("fontFamily")]
    public string FontFamily { get; set; } = "Consolas";

    [JsonPropertyName("fontSize")]
    public int FontSize { get; set; } = 14;

    [JsonPropertyName("tabSize")]
    public int TabSize { get; set; } = 4;

    [JsonPropertyName("backgroundColor")]
    public string BackgroundColor { get; set; } = "#1E1E1E";

    [JsonPropertyName("foregroundColor")]
    public string ForegroundColor { get; set; } = "#D4D4D4";

    [JsonPropertyName("lineNumberColor")]
    public string LineNumberColor { get; set; } = "#858585";

    [JsonPropertyName("selectionColor")]
    public string SelectionColor { get; set; } = "#264F78";

    [JsonPropertyName("currentLineColor")]
    public string CurrentLineColor { get; set; } = "#282828";
}

/// <summary>
/// DataGrid theme settings
/// </summary>
public class GridTheme
{
    [JsonPropertyName("fontFamily")]
    public string FontFamily { get; set; } = "Segoe UI";

    [JsonPropertyName("fontSize")]
    public int FontSize { get; set; } = 12;

    [JsonPropertyName("cellHeight")]
    public int CellHeight { get; set; } = 25;

    [JsonPropertyName("backgroundColor")]
    public string BackgroundColor { get; set; } = "#2D2D2D";

    [JsonPropertyName("foregroundColor")]
    public string ForegroundColor { get; set; } = "#E0E0E0";

    [JsonPropertyName("selectedBackgroundColor")]
    public string SelectedBackgroundColor { get; set; } = "#0078D4";

    [JsonPropertyName("selectedForegroundColor")]
    public string SelectedForegroundColor { get; set; } = "#FFFFFF";

    [JsonPropertyName("headerBackgroundColor")]
    public string HeaderBackgroundColor { get; set; } = "#252526";

    [JsonPropertyName("headerForegroundColor")]
    public string HeaderForegroundColor { get; set; } = "#CCCCCC";

    [JsonPropertyName("alternateRowColor")]
    public string AlternateRowColor { get; set; } = "#323232";
}

/// <summary>
/// UI component theme settings
/// </summary>
public class UITheme
{
    [JsonPropertyName("objectBrowserFontSize")]
    public int ObjectBrowserFontSize { get; set; } = 12;

    [JsonPropertyName("dialogFontSize")]
    public int DialogFontSize { get; set; } = 14;

    [JsonPropertyName("menuFontSize")]
    public int MenuFontSize { get; set; } = 12;

    [JsonPropertyName("statusBarFontSize")]
    public int StatusBarFontSize { get; set; } = 11;

    [JsonPropertyName("propertyWindowFontSize")]
    public int PropertyWindowFontSize { get; set; } = 12;

    [JsonPropertyName("windowBackgroundColor")]
    public string WindowBackgroundColor { get; set; } = "#1E1E1E";

    [JsonPropertyName("windowForegroundColor")]
    public string WindowForegroundColor { get; set; } = "#E0E0E0";

    [JsonPropertyName("buttonBackgroundColor")]
    public string ButtonBackgroundColor { get; set; } = "#0E639C";

    [JsonPropertyName("buttonForegroundColor")]
    public string ButtonForegroundColor { get; set; } = "#FFFFFF";
}
