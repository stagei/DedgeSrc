namespace ServerMonitorDashboard.Models;

/// <summary>
/// Configuration for the alert polling feature
/// </summary>
public class AlertPollingConfig
{
    /// <summary>
    /// Whether alert polling is enabled
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// How often to poll servers for alerts (in seconds)
    /// </summary>
    public int PollingIntervalSeconds { get; set; } = 60;

    /// <summary>
    /// Regex patterns for server names to monitor for alerts.
    /// Use [".*"] to monitor all servers.
    /// </summary>
    public List<string> ServerNamePatterns { get; set; } = new() { ".*" };

    /// <summary>
    /// Minimum severity level to include in alerts.
    /// Options: "Critical", "Error", "Warning", "Informational"
    /// </summary>
    public string MinimumSeverity { get; set; } = "Error";

    /// <summary>
    /// Regex patterns to identify production servers.
    /// Example: ["^p-no1"] matches servers starting with "p-no1"
    /// </summary>
    public List<string> ProductionPatterns { get; set; } = new() { "^p-no1" };

    /// <summary>
    /// Default state of the "Production Only" filter in the UI
    /// </summary>
    public bool ShowOnlyProductionDefault { get; set; } = true;

    /// <summary>
    /// Only show servers with errors from today (based on LatestAlertTimestamp)
    /// </summary>
    public bool OnlyShowTodaysErrors { get; set; } = true;
}
