namespace ServerMonitor.Core.Models;

/// <summary>
/// Complete IIS snapshot for a server
/// </summary>
public class IisSnapshot
{
    /// <summary>
    /// Whether IIS is installed and the monitor is active on this server
    /// </summary>
    public bool IsActive { get; set; }

    /// <summary>
    /// Reason if not active (e.g. "IIS not installed", "Server name does not match pattern")
    /// </summary>
    public string? InactiveReason { get; set; }

    /// <summary>
    /// IIS version string (e.g. "10.0")
    /// </summary>
    public string? IisVersion { get; set; }

    /// <summary>
    /// Timestamp of data collection
    /// </summary>
    public DateTime CollectedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// All sites configured in IIS
    /// </summary>
    public List<IisSiteInfo> Sites { get; set; } = new();

    /// <summary>
    /// All application pools configured in IIS
    /// </summary>
    public List<IisAppPoolInfo> AppPools { get; set; } = new();

    public int TotalSites => Sites.Count;
    public int RunningSites => Sites.Count(s => s.State == "Started");
    public int StoppedSites => Sites.Count(s => s.State == "Stopped");
    public int TotalAppPools => AppPools.Count;
    public int RunningAppPools => AppPools.Count(p => p.State == "Started");
    public int StoppedAppPools => AppPools.Count(p => p.State == "Stopped");
    public int TotalWorkerProcesses => AppPools.Sum(p => p.WorkerProcesses.Count);

    /// <summary>
    /// Error message if collection failed
    /// </summary>
    public string? Error { get; set; }
}

/// <summary>
/// IIS website information
/// </summary>
public class IisSiteInfo
{
    /// <summary>
    /// Site name (e.g. "Default Web Site")
    /// </summary>
    public string Name { get; init; } = string.Empty;

    /// <summary>
    /// IIS site ID
    /// </summary>
    public long Id { get; init; }

    /// <summary>
    /// Site state: Started, Stopped, Starting, Stopping, Unknown
    /// </summary>
    public string State { get; init; } = "Unknown";

    /// <summary>
    /// Bindings configured on this site (protocol://host:port)
    /// </summary>
    public List<IisBindingInfo> Bindings { get; init; } = new();

    /// <summary>
    /// Physical path of the site root
    /// </summary>
    public string PhysicalPath { get; init; } = string.Empty;

    /// <summary>
    /// UNC path to the site root for remote Dashboard access
    /// </summary>
    public string PhysicalPathUnc { get; init; } = string.Empty;

    /// <summary>
    /// Application pool name used by the site root application
    /// </summary>
    public string AppPoolName { get; init; } = string.Empty;

    /// <summary>
    /// Virtual applications under this site
    /// </summary>
    public List<IisVirtualAppInfo> VirtualApps { get; init; } = new();
}

/// <summary>
/// IIS binding (protocol, host, port)
/// </summary>
public class IisBindingInfo
{
    public string Protocol { get; init; } = "http";
    public string Host { get; init; } = string.Empty;
    public int Port { get; init; } = 80;

    /// <summary>
    /// Raw binding information string
    /// </summary>
    public string BindingInformation { get; init; } = string.Empty;

    public override string ToString() =>
        string.IsNullOrEmpty(Host) ? $"{Protocol}://*:{Port}" : $"{Protocol}://{Host}:{Port}";
}

/// <summary>
/// IIS virtual application under a site
/// </summary>
public class IisVirtualAppInfo
{
    /// <summary>
    /// Virtual path (e.g. "/DedgeAuth", "/DocView")
    /// </summary>
    public string Path { get; init; } = string.Empty;

    /// <summary>
    /// Physical path on disk
    /// </summary>
    public string PhysicalPath { get; init; } = string.Empty;

    /// <summary>
    /// UNC path to the install folder for remote Dashboard access
    /// </summary>
    public string PhysicalPathUnc { get; init; } = string.Empty;

    /// <summary>
    /// Application pool name
    /// </summary>
    public string AppPoolName { get; init; } = string.Empty;

    /// <summary>
    /// Enabled protocols (e.g. "http", "https")
    /// </summary>
    public string EnabledProtocols { get; init; } = "http";

    /// <summary>
    /// Whether this is an ASP.NET Core application (detected via web.config aspNetCore element)
    /// </summary>
    public bool IsAspNetCore { get; init; }

    /// <summary>
    /// The .NET DLL entry point (e.g. "ServerMonitorDashboard.dll"), extracted from web.config
    /// </summary>
    public string? DotNetDll { get; init; }

    /// <summary>
    /// UNC path to the application's log directory, discovered from appsettings.json
    /// </summary>
    public string? LogPath { get; init; }

    /// <summary>
    /// UNC path to the application's output/content directory, discovered from appsettings.json
    /// </summary>
    public string? OutputPath { get; init; }
}

/// <summary>
/// IIS application pool information
/// </summary>
public class IisAppPoolInfo
{
    /// <summary>
    /// Application pool name
    /// </summary>
    public string Name { get; init; } = string.Empty;

    /// <summary>
    /// State: Started, Stopped, Starting, Stopping, Unknown
    /// </summary>
    public string State { get; init; } = "Unknown";

    /// <summary>
    /// Managed runtime version (e.g. "v4.0", "" for No Managed Code)
    /// </summary>
    public string ManagedRuntimeVersion { get; init; } = string.Empty;

    /// <summary>
    /// Pipeline mode: Integrated or Classic
    /// </summary>
    public string PipelineMode { get; init; } = "Integrated";

    /// <summary>
    /// Process model identity type (ApplicationPoolIdentity, LocalSystem, NetworkService, etc.)
    /// </summary>
    public string IdentityType { get; init; } = string.Empty;

    /// <summary>
    /// Custom identity username (if IdentityType is SpecificUser)
    /// </summary>
    public string? IdentityUsername { get; init; }

    /// <summary>
    /// Whether the pool starts automatically
    /// </summary>
    public bool AutoStart { get; init; } = true;

    /// <summary>
    /// Whether 32-bit applications are enabled
    /// </summary>
    public bool Enable32BitAppOnWin64 { get; init; }

    /// <summary>
    /// CPU limit percentage (0 = no limit)
    /// </summary>
    public long CpuLimit { get; init; }

    /// <summary>
    /// Private memory limit in KB for recycling (0 = no limit)
    /// </summary>
    public long PrivateMemoryLimitKB { get; init; }

    /// <summary>
    /// Regular time interval for recycling in minutes (0 = no interval recycling)
    /// </summary>
    public long RecyclingTimeIntervalMinutes { get; init; }

    /// <summary>
    /// Current worker processes running in this pool
    /// </summary>
    public List<IisWorkerProcessInfo> WorkerProcesses { get; init; } = new();
}

/// <summary>
/// IIS worker process information
/// </summary>
public class IisWorkerProcessInfo
{
    /// <summary>
    /// Process ID
    /// </summary>
    public int ProcessId { get; init; }

    /// <summary>
    /// Worker process state: Starting, Running, Stopping, Unknown
    /// </summary>
    public string State { get; init; } = "Unknown";

    /// <summary>
    /// Application pool name this worker process belongs to
    /// </summary>
    public string AppPoolName { get; init; } = string.Empty;

    /// <summary>
    /// Private memory usage in MB
    /// </summary>
    public double PrivateMemoryMB { get; init; }

    /// <summary>
    /// Process start time (approximated from process info)
    /// </summary>
    public DateTime? StartTime { get; init; }
}
