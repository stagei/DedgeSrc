namespace DbExplorer.Models;

/// <summary>
/// Application settings loaded from appsettings.json
/// </summary>
public class AppSettings
{
    public ApplicationSettings Application { get; set; } = new();
    public EditorSettings Editor { get; set; } = new();
    public DatabaseSettings Database { get; set; } = new();
    public LoggingSettings Logging { get; set; } = new();
    public ConnectionStringsSettings ConnectionStrings { get; set; } = new();
    public FeatureSettings Features { get; set; } = new();
    public ObjectBrowserSettings ObjectBrowser { get; set; } = new();
}

public class ApplicationSettings
{
    public string Version { get; set; } = "1.0.0";
    public string Environment { get; set; } = "Development";
    public bool EnableTelemetry { get; set; } = false;
    public bool CheckForUpdates { get; set; } = false;
    public string Framework { get; set; } = "net10.0-windows";
}

public class EditorSettings
{
    public string DefaultTheme { get; set; } = "Dark";
    public string FontFamily { get; set; } = "Consolas";
    public int FontSize { get; set; } = 14;
    public bool ShowLineNumbers { get; set; } = true;
    public bool AutoFormatOnSave { get; set; } = false;
    public int TabSize { get; set; } = 4;
    public bool EnableAutoComplete { get; set; } = true;
    public int IndentSize { get; set; } = 4;
}

public class DatabaseSettings
{
    public int DefaultCommandTimeout { get; set; } = 30;
    public int MaxConnectionPoolSize { get; set; } = 100;
    public bool SaveConnectionHistory { get; set; } = true;
    public bool EnableQueryHistory { get; set; } = true;
    public int MaxQueryHistoryItems { get; set; } = 100;
}

public class LoggingSettings
{
    public bool UseNLog { get; set; } = true;
    public string ConfigFile { get; set; } = "nlog.config";
    public string LogPath { get; set; } = "Logs";
    public int MaxLogFileSizeMB { get; set; } = 10;
    public int RetainDays { get; set; } = 30;
    public string MinimumLevel { get; set; } = "Info";
}

public class ConnectionStringsSettings
{
    public List<string> SavedConnections { get; set; } = new();
}

public class FeatureSettings
{
    public bool EnableDarkMode { get; set; } = true;
    public bool EnableMultipleTabs { get; set; } = true;
    public bool EnableSqlFormatter { get; set; } = true;
    public bool EnableDatabaseBrowser { get; set; } = true;
    public bool EnableExport { get; set; } = true;
}

public class ObjectBrowserSettings
{
    public bool AutoGrowWidth { get; set; } = true;
    public int InitialWidth { get; set; } = 250;
    public int MinWidth { get; set; } = 150;
    public int MaxWidth { get; set; } = 800;
}

