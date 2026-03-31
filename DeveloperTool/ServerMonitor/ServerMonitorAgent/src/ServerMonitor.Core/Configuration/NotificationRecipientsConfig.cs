namespace ServerMonitor.Core.Configuration;

/// <summary>
/// Configuration for notification recipients with per-environment, per-person, per-day rules
/// </summary>
public class NotificationRecipientsConfig
{
    public string Version { get; set; } = "1.0";
    public DateTime LastUpdated { get; set; }
    public List<EnvironmentConfig> Environments { get; set; } = new();
    public List<PersonConfig> People { get; set; } = new();
}

/// <summary>
/// Environment configuration with computer name patterns and channel settings
/// </summary>
public class EnvironmentConfig
{
    public string Name { get; set; } = string.Empty;
    
    /// <summary>
    /// Human-readable description of this environment
    /// </summary>
    public string? Description { get; set; }
    
    public List<string> ComputerNamePatterns { get; set; } = new();
    
    /// <summary>
    /// If true, this environment is the fallback when no other pattern matches.
    /// Only one environment should have IsDefault = true.
    /// </summary>
    public bool IsDefault { get; set; }
    
    /// <summary>
    /// Channel enable/disable settings for this environment.
    /// If null, all channels are enabled by default.
    /// </summary>
    public EnvironmentChannelConfig? Channels { get; set; }
}

/// <summary>
/// Channel enable/disable settings per environment
/// </summary>
public class EnvironmentChannelConfig
{
    public bool Sms { get; set; } = true;
    public bool Email { get; set; } = true;
    public bool EventLog { get; set; } = true;
    public bool File { get; set; } = true;
    public bool WkMonitor { get; set; } = true;
    
    /// <summary>
    /// Check if a specific channel type is enabled
    /// </summary>
    public bool IsChannelEnabled(string channelType)
    {
        return channelType?.ToUpperInvariant() switch
        {
            "SMS" => Sms,
            "EMAIL" => Email,
            "EVENTLOG" => EventLog,
            "FILE" => File,
            "WKMONITOR" => WkMonitor,
            _ => true // Unknown channels enabled by default
        };
    }
}

/// <summary>
/// Person configuration with contact info and notification rules
/// </summary>
public class PersonConfig
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public bool Enabled { get; set; } = true;
    public Dictionary<string, Dictionary<string, DayNotificationRule>> Environments { get; set; } = new();
    public List<AbsencePeriod> Absences { get; set; } = new();
}

/// <summary>
/// Notification rules for a specific day
/// </summary>
public class DayNotificationRule
{
    public TimeRange? Email { get; set; }
    public TimeRange? Sms { get; set; }
}

/// <summary>
/// Time range for notifications
/// </summary>
public class TimeRange
{
    public string From { get; set; } = string.Empty;  // Format: "HH:mm" (e.g., "08:00")
    public string To { get; set; } = string.Empty;    // Format: "HH:mm" (e.g., "17:00")
}

/// <summary>
/// Absence period (vacation, etc.)
/// </summary>
public class AbsencePeriod
{
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public string Reason { get; set; } = string.Empty;
    public string? BackupPersonId { get; set; }
}

/// <summary>
/// Recipient information for sending notifications
/// </summary>
public class RecipientInfo
{
    public string PersonId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public bool IsBackup { get; set; }
    public string? OriginalPersonId { get; set; }
}

