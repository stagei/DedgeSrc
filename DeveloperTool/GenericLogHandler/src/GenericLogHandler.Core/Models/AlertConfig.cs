namespace GenericLogHandler.Core.Models;

/// <summary>
/// Configuration for alert triggers (stored as JSON in SavedFilter.AlertConfig)
/// </summary>
public class AlertConfig
{
    /// <summary>
    /// Type of action to take: "webhook", "script", "servermonitor", "email"
    /// </summary>
    public string Type { get; set; } = "webhook";

    /// <summary>
    /// URL for webhook or path for script
    /// </summary>
    public string Endpoint { get; set; } = string.Empty;

    /// <summary>
    /// HTTP method for webhook (POST, GET)
    /// </summary>
    public string Method { get; set; } = "POST";

    /// <summary>
    /// Additional HTTP headers for webhook
    /// </summary>
    public Dictionary<string, string> Headers { get; set; } = new();

    /// <summary>
    /// Template for request body with placeholders like {{matchCount}}, {{filterName}}, {{entries}}
    /// </summary>
    public string BodyTemplate { get; set; } = string.Empty;

    /// <summary>
    /// Minimum number of matching records to trigger the alert
    /// </summary>
    public int ThresholdCount { get; set; } = 1;

    /// <summary>
    /// Cooldown period in minutes before the same alert can trigger again
    /// </summary>
    public int CooldownMinutes { get; set; } = 15;

    /// <summary>
    /// Whether to include matching log entries in the alert payload
    /// </summary>
    public bool IncludeEntries { get; set; } = true;

    /// <summary>
    /// Maximum number of entries to include in the alert payload
    /// </summary>
    public int MaxEntriesToInclude { get; set; } = 10;

    /// <summary>
    /// Time window in minutes to search for new entries (0 = since last evaluation)
    /// </summary>
    public int TimeWindowMinutes { get; set; } = 0;

    /// <summary>
    /// Whether the alert is currently active
    /// </summary>
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Optional: Script arguments for script type
    /// </summary>
    public List<string> ScriptArguments { get; set; } = new();

    /// <summary>
    /// Optional: Email recipients for email type
    /// </summary>
    public List<string> EmailRecipients { get; set; } = new();

    /// <summary>
    /// Optional: Email subject template for email type
    /// </summary>
    public string EmailSubject { get; set; } = "Log Handler Alert: {{filterName}}";

    /// <summary>
    /// Optional: ServerMonitor alert severity for servermonitor type
    /// </summary>
    public string ServerMonitorSeverity { get; set; } = "Warning";
}
