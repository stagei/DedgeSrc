using System;

namespace DbExplorer.Models;

/// <summary>
/// Represents active database session information.
/// Uses database-agnostic property names for multi-provider support.
/// </summary>
public class SessionInfo
{
    public int AgentId { get; set; }
    public string DatabaseName { get; set; } = string.Empty;
    public string AuthorizationId { get; set; } = string.Empty;
    public string ClientName { get; set; } = string.Empty;
    public string ApplicationName { get; set; } = string.Empty;
    public string ApplicationId { get; set; } = string.Empty;
    public DateTime? ConnectTime { get; set; }
    public string Status { get; set; } = string.Empty;
    
    /// <summary>
    /// Duration of connection
    /// </summary>
    public TimeSpan? ConnectionDuration
    {
        get
        {
            if (!ConnectTime.HasValue)
                return null;
            
            return DateTime.Now - ConnectTime.Value;
        }
    }
    
    /// <summary>
    /// Friendly duration string
    /// </summary>
    public string DurationText
    {
        get
        {
            if (!ConnectionDuration.HasValue)
                return "Unknown";
            
            var duration = ConnectionDuration.Value;
            
            if (duration.TotalDays >= 1)
                return $"{(int)duration.TotalDays}d {duration.Hours}h";
            if (duration.TotalHours >= 1)
                return $"{(int)duration.TotalHours}h {duration.Minutes}m";
            if (duration.TotalMinutes >= 1)
                return $"{(int)duration.TotalMinutes}m {duration.Seconds}s";
            
            return $"{(int)duration.TotalSeconds}s";
        }
    }
}

/// <summary>
/// Filter for session monitoring
/// </summary>
public class SessionMonitorFilter
{
    public string? UserFilter { get; set; } = "*";
    public string? ApplicationFilter { get; set; } = "*";
    public bool ShowOnlyActive { get; set; } = true;
}

