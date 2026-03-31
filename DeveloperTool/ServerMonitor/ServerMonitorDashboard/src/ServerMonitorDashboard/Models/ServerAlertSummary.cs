namespace ServerMonitorDashboard.Models;

/// <summary>
/// Summary of alerts for a single server
/// </summary>
public class ServerAlertSummary
{
    /// <summary>
    /// Server name
    /// </summary>
    public string ServerName { get; set; } = string.Empty;

    /// <summary>
    /// Number of critical alerts
    /// </summary>
    public int CriticalCount { get; set; }

    /// <summary>
    /// Number of error alerts
    /// </summary>
    public int ErrorCount { get; set; }

    /// <summary>
    /// Number of warning alerts
    /// </summary>
    public int WarningCount { get; set; }

    /// <summary>
    /// Number of informational alerts
    /// </summary>
    public int InformationalCount { get; set; }

    /// <summary>
    /// Total alert count
    /// </summary>
    public int TotalCount => CriticalCount + ErrorCount + WarningCount + InformationalCount;

    /// <summary>
    /// Timestamp of the most recent alert
    /// </summary>
    public DateTime? LatestAlertTimestamp { get; set; }

    /// <summary>
    /// When this summary was last updated
    /// </summary>
    public DateTime LastUpdated { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// The highest severity level present (Critical > Warning > Informational)
    /// </summary>
    public string HighestSeverity
    {
        get
        {
            if (CriticalCount > 0) return "Critical";
            if (WarningCount > 0) return "Warning";
            if (InformationalCount > 0) return "Informational";
            return "None";
        }
    }
}

/// <summary>
/// Response model for active alerts API
/// </summary>
public class ActiveAlertsResponse
{
    /// <summary>
    /// List of servers with active alerts
    /// </summary>
    public List<ServerAlertSummary> Servers { get; set; } = new();

    /// <summary>
    /// When the alerts were last polled
    /// </summary>
    public DateTime LastPolled { get; set; }

    /// <summary>
    /// Whether alert polling is enabled
    /// </summary>
    public bool PollingEnabled { get; set; }

    /// <summary>
    /// Polling interval in seconds
    /// </summary>
    public int PollingIntervalSeconds { get; set; }

    /// <summary>
    /// Regex patterns to identify production servers (e.g., "^p-no1")
    /// </summary>
    public List<string> ProductionPatterns { get; set; } = new();

    /// <summary>
    /// Default state of the "Production Only" filter
    /// </summary>
    public bool ShowOnlyProductionDefault { get; set; } = true;

    /// <summary>
    /// Total critical alerts across all servers
    /// </summary>
    public int TotalCritical => Servers.Sum(s => s.CriticalCount);

    /// <summary>
    /// Total warning alerts across all servers
    /// </summary>
    public int TotalWarning => Servers.Sum(s => s.WarningCount);

    /// <summary>
    /// Total informational alerts across all servers
    /// </summary>
    public int TotalInformational => Servers.Sum(s => s.InformationalCount);
}
