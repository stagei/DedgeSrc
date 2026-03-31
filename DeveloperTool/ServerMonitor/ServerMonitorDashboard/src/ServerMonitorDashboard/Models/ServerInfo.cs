namespace ServerMonitorDashboard.Models;

/// <summary>
/// Server status enumeration
/// </summary>
public enum ServerStatus
{
    /// <summary>Server has not been checked yet</summary>
    Unknown,
    /// <summary>Server is currently being checked</summary>
    Checking,
    /// <summary>Server is online and responding</summary>
    Online,
    /// <summary>Server is offline or not responding</summary>
    Offline
}

/// <summary>
/// Server information with current status
/// </summary>
public class ServerInfo
{
    public string Name { get; set; } = string.Empty;
    public string? DisplayName { get; set; }
    public string? Type { get; set; }
    public string? IpAddress { get; set; }
    public bool IsAlive { get; set; }
    
    /// <summary>
    /// Current server status: unknown (yellow), checking (yellow), online (green), offline (magenta)
    /// </summary>
    public ServerStatus Status { get; set; } = ServerStatus.Unknown;
    
    /// <summary>
    /// Status as string for JSON serialization
    /// </summary>
    public string StatusText => Status.ToString().ToLower();
    
    public DateTime? LastChecked { get; set; }
    public string? AgentVersion { get; set; }
    public long? ResponseTimeMs { get; set; }
    public string? Error { get; set; }
}

/// <summary>
/// Response for /api/servers endpoint
/// </summary>
public class ServersResponse
{
    public List<ServerInfo> Servers { get; set; } = new();
    public DateTime LastRefreshed { get; set; }
    public string? CurrentAgentVersion { get; set; }
}
