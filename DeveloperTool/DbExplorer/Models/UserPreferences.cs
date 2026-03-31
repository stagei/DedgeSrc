using System;
using System.IO;
using System.Text.Json.Serialization;

namespace DbExplorer.Models
{
    /// <summary>
    /// User preferences stored in preferences.json
    /// </summary>
    public class UserPreferences
    {
        /// <summary>
        /// Default user data folder path (Documents\DbExplorer)
        /// </summary>
        private static readonly string DefaultUserDataFolder = 
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "DbExplorer");

        /// <summary>
        /// User data folder for all user-specific files (connections, history, Missing FK projects, etc.)
        /// Default: Documents\DbExplorer
        /// </summary>
        [JsonPropertyName("userDataFolder")]
        public string UserDataFolder { get; set; } = DefaultUserDataFolder;

        /// <summary>
        /// Gets the default user data folder path
        /// </summary>
        public static string GetDefaultUserDataFolder() => DefaultUserDataFolder;

        /// <summary>
        /// Maximum number of rows to fetch per query (default: 1000)
        /// </summary>
        [JsonPropertyName("maxRowsPerQuery")]
        public int MaxRowsPerQuery { get; set; } = 1000;

        /// <summary>
        /// Default theme (System, Dark, or Light)
        /// </summary>
        [JsonPropertyName("defaultTheme")]
        public string DefaultTheme { get; set; } = "Dark";

        /// <summary>
        /// SQL editor font family
        /// </summary>
        [JsonPropertyName("fontFamily")]
        public string FontFamily { get; set; } = "Consolas";

        /// <summary>
        /// SQL editor font size
        /// </summary>
        [JsonPropertyName("fontSize")]
        public int FontSize { get; set; } = 14;

        /// <summary>
        /// Tab size in spaces
        /// </summary>
        [JsonPropertyName("tabSize")]
        public int TabSize { get; set; } = 4;

        /// <summary>
        /// Auto-format SQL on execute
        /// </summary>
        [JsonPropertyName("autoFormatOnExecute")]
        public bool AutoFormatOnExecute { get; set; } = false;

        /// <summary>
        /// Command timeout in seconds (default: 30, 0 = no timeout)
        /// </summary>
        [JsonPropertyName("commandTimeout")]
        public int CommandTimeout { get; set; } = 30;

        /// <summary>
        /// Handle DB2Decimal errors gracefully
        /// </summary>
        [JsonPropertyName("handleDecimalErrorsGracefully")]
        public bool HandleDecimalErrorsGracefully { get; set; } = true;

        /// <summary>
        /// Auto-refresh database objects on connection
        /// </summary>
        [JsonPropertyName("autoRefreshObjectsOnConnect")]
        public bool AutoRefreshObjectsOnConnect { get; set; } = true;

        /// <summary>
        /// Log level (Debug, Info, Warn, Error)
        /// </summary>
        [JsonPropertyName("logLevel")]
        public string LogLevel { get; set; } = "Info";

        /// <summary>
        /// Grid background color (hex format, e.g., "#2D2D2D" for dark, "#FFFFFF" for light)
        /// </summary>
        [JsonPropertyName("gridBackgroundColor")]
        public string GridBackgroundColor { get; set; } = "#2D2D2D";

        /// <summary>
        /// Grid foreground (text) color (hex format, e.g., "#E0E0E0" for dark, "#000000" for light)
        /// </summary>
        [JsonPropertyName("gridForegroundColor")]
        public string GridForegroundColor { get; set; } = "#E0E0E0";

        /// <summary>
        /// Grid selected row background color (hex format, e.g., "#0078D4")
        /// </summary>
        [JsonPropertyName("gridSelectedBackgroundColor")]
        public string GridSelectedBackgroundColor { get; set; } = "#0078D4";

        /// <summary>
        /// Grid selected row foreground (text) color (hex format, e.g., "#FFFFFF")
        /// </summary>
        [JsonPropertyName("gridSelectedForegroundColor")]
        public string GridSelectedForegroundColor { get; set; } = "#FFFFFF";

        /// <summary>
        /// Grid font size (default: 12)
        /// </summary>
        [JsonPropertyName("gridFontSize")]
        public int GridFontSize { get; set; } = 12;

        /// <summary>
        /// Grid font family name (default: "Segoe UI")
        /// </summary>
        [JsonPropertyName("gridFontFamily")]
        public string GridFontFamily { get; set; } = "Segoe UI";

        /// <summary>
        /// Grid cell height in pixels (default: 25)
        /// </summary>
        [JsonPropertyName("gridCellHeight")]
        public int GridCellHeight { get; set; } = 25;

        /// <summary>
        /// TreeView item vertical spacing in pixels (default: 2)
        /// </summary>
        [JsonPropertyName("treeViewItemSpacing")]
        public int TreeViewItemSpacing { get; set; } = 2;

        /// <summary>
        /// TreeView horizontal indent per level in pixels (default: 19)
        /// </summary>
        [JsonPropertyName("treeViewIndent")]
        public int TreeViewIndent { get; set; } = 19;

        /// <summary>
        /// Global UI font size for all controls (default: 12)
        /// </summary>
        [JsonPropertyName("uiFontSize")]
        public int UIFontSize { get; set; } = 12;

        /// <summary>
        /// SQL Editor background color (hex format, dark mode default: "#1E1E1E")
        /// </summary>
        [JsonPropertyName("editorBackgroundColor")]
        public string EditorBackgroundColor { get; set; } = "#1E1E1E";

        /// <summary>
        /// SQL Editor foreground/text color (hex format, dark mode default: "#D4D4D4")
        /// </summary>
        [JsonPropertyName("editorForegroundColor")]
        public string EditorForegroundColor { get; set; } = "#D4D4D4";

        /// <summary>
        /// SQL Editor line number color (hex format)
        /// </summary>
        [JsonPropertyName("editorLineNumberColor")]
        public string EditorLineNumberColor { get; set; } = "#858585";

        /// <summary>
        /// SQL Editor current line highlight color (hex format)
        /// </summary>
        [JsonPropertyName("editorCurrentLineColor")]
        public string EditorCurrentLineColor { get; set; } = "#2D2D30";

        /// <summary>
        /// Auto-dock tool windows as tabs instead of floating windows (default: false - tools open undocked)
        /// </summary>
        [JsonPropertyName("autoDockTools")]
        public bool AutoDockTools { get; set; } = false;

        /// <summary>
        /// Currently active theme name (e.g., "Dark", "Light", or custom theme name)
        /// </summary>
        [JsonPropertyName("activeThemeName")]
        public string ActiveThemeName { get; set; } = "Dark";

        /// <summary>
        /// Whether user is using custom overrides on top of the base theme
        /// </summary>
        [JsonPropertyName("useCustomOverrides")]
        public bool UseCustomOverrides { get; set; } = false;

        /// <summary>
        /// Disable auto-adjust of Object Browser width on tree expansion (default: false = auto-adjust enabled)
        /// </summary>
        [JsonPropertyName("disableObjectBrowserAutoResize")]
        public bool DisableObjectBrowserAutoResize { get; set; } = false;

        /// <summary>
        /// Start DbExplorer when Windows starts (default: true)
        /// </summary>
        [JsonPropertyName("startupEnabled")]
        public bool StartupEnabled { get; set; } = true;

        /// <summary>
        /// Show system tray icon (default: true)
        /// </summary>
        [JsonPropertyName("showTrayIcon")]
        public bool ShowTrayIcon { get; set; } = true;

        /// <summary>
        /// Allow using Ollama for AI SQL editing (Ctrl+K). Set after user consent.
        /// </summary>
        [JsonPropertyName("allowOllamaForSqlEdit")]
        public bool AllowOllamaForSqlEdit { get; set; } = false;

        /// <summary>
        /// Whether the "Use Ollama for AI SQL edit?" consent has been shown once.
        /// </summary>
        [JsonPropertyName("ollamaSqlEditAskedOnce")]
        public bool OllamaSqlEditAskedOnce { get; set; } = false;

        /// <summary>
        /// Ollama model name for SQL edit (e.g. defog-llama3-sqlcoder-8b or sqlcoder).
        /// </summary>
        [JsonPropertyName("sqlEditModel")]
        public string SqlEditModel { get; set; } = "defog-llama3-sqlcoder-8b";
    }
}

