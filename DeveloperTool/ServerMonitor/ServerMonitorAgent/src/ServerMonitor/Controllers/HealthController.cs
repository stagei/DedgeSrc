using System.Diagnostics;
using System.Reflection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;
using ServerMonitor.Core.Utilities;

namespace ServerMonitor.Controllers;

/// <summary>
/// Simple health check endpoint for quick availability verification
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class HealthController : ControllerBase
{
    private readonly GlobalSnapshotService _snapshotService;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    
    public HealthController(GlobalSnapshotService snapshotService, IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _snapshotService = snapshotService;
        _config = config;
    }

    /// <summary>
    /// Simple liveness check - returns true if API is up and running
    /// </summary>
    /// <remarks>
    /// Use this endpoint for quick health checks from monitoring tools or scripts.
    /// No authentication required, minimal overhead.
    /// 
    /// Example: GET http://localhost:8999/api/Health/IsAlive
    /// Returns: true
    /// </remarks>
    /// <returns>true if API is alive</returns>
    [HttpGet("IsAlive")]
    [ProducesResponseType(typeof(bool), 200)]
    public IActionResult IsAlive()
    {
        return Ok(true);
    }
    
    /// <summary>
    /// Returns the current version of the ServerMonitor agent
    /// </summary>
    /// <remarks>
    /// Use this endpoint to get the installed agent version for display or comparison.
    /// 
    /// Example: GET http://localhost:8999/api/Health/CurrentVersion
    /// Returns: { "version": "1.0.14", "productName": "ServerMonitor", "machineName": "SERVER01" }
    /// </remarks>
    /// <returns>Version information object</returns>
    [HttpGet("CurrentVersion")]
    [ProducesResponseType(typeof(VersionInfo), 200)]
    public IActionResult CurrentVersion()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var version = assembly.GetName().Version;
        var informationalVersion = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        
        // Use informational version if available (contains semantic version), otherwise use assembly version
        var versionString = informationalVersion?.Split('+')[0] ?? version?.ToString(3) ?? "unknown";
        
        var versionInfo = new VersionInfo
        {
            Version = versionString,
            ProductName = assembly.GetCustomAttribute<AssemblyProductAttribute>()?.Product ?? "ServerMonitor",
            MachineName = Environment.MachineName
        };
        
        return Ok(versionInfo);
    }

    /// <summary>
    /// Returns the current memory usage of ServerMonitor.exe process
    /// </summary>
    /// <remarks>
    /// Use this endpoint to monitor the memory footprint of the ServerMonitor agent.
    /// 
    /// Example: GET http://localhost:8999/api/Health/Memory
    /// Returns: { "workingSetMB": 150.5, "privateMemoryMB": 120.3, "gcTotalMemoryMB": 85.2 }
    /// </remarks>
    /// <returns>Memory usage information in MB</returns>
    [HttpGet("Memory")]
    [ProducesResponseType(typeof(MemoryInfo), 200)]
    public IActionResult GetMemory()
    {
        var process = Process.GetCurrentProcess();
        var memoryInfo = new MemoryInfo
        {
            WorkingSetMB = process.WorkingSet64 / (1024.0 * 1024.0),
            PrivateMemoryMB = process.PrivateMemorySize64 / (1024.0 * 1024.0),
            GcTotalMemoryMB = GC.GetTotalMemory(false) / (1024.0 * 1024.0),
            MachineName = Environment.MachineName,
            Timestamp = DateTime.UtcNow
        };
        
        return Ok(memoryInfo);
    }
    
    /// <summary>
    /// Returns the estimated size of the in-memory snapshot data
    /// </summary>
    /// <remarks>
    /// Use this endpoint to monitor how much memory the snapshot data is consuming.
    /// 
    /// Example: GET http://localhost:8999/api/Health/SnapshotSize
    /// Returns: { "estimatedSizeMB": 12.5, "alertCount": 150, "eventCount": 1200 }
    /// </remarks>
    /// <returns>Snapshot size information in MB</returns>
    [HttpGet("SnapshotSize")]
    [ProducesResponseType(typeof(SnapshotSizeInfo), 200)]
    public IActionResult GetSnapshotSize()
    {
        var snapshot = _snapshotService.GetCurrentSnapshot();
        var sizeInfo = _snapshotService.GetSnapshotSizeInfo();
        
        return Ok(sizeInfo);
    }
    
    /// <summary>
    /// Returns the current log file path as a UNC path
    /// </summary>
    /// <remarks>
    /// Use this endpoint to get the UNC path to the current log file for remote access.
    /// The path is converted from local (e.g., E:\opt\data\...) to UNC (e.g., \\server\opt\data\...).
    /// 
    /// Example: GET http://localhost:8999/api/Health/LogFile
    /// Returns: { "localPath": "E:\opt\data\ServerMonitor\ServerMonitor_2026-01-19.log", 
    ///            "uncPath": "\\p-no1fkmprd-db\opt\data\ServerMonitor\ServerMonitor_2026-01-19.log" }
    /// </remarks>
    /// <returns>Log file path information</returns>
    [HttpGet("LogFile")]
    [ProducesResponseType(typeof(LogFileInfo), 200)]
    public IActionResult GetLogFile()
    {
        var logging = _config.CurrentValue.Logging;
        var logDirectory = logging.LogDirectory;
        var appName = logging.AppName;
        var machineName = Environment.MachineName;
        var machineNameLower = machineName.ToLowerInvariant();
        
        // Build today's log file name (matches NLog pattern: AppName_machinename_yyyy-MM-dd.log)
        var logFileName = $"{appName}_{machineNameLower}_{DateTime.Now:yyyy-MM-dd}.log";
        var localPath = Path.Combine(logDirectory, logFileName);
        
        var uncPath = PathHelper.ToUncPath(localPath, machineName);
        
        return Ok(new LogFileInfo
        {
            LocalPath = localPath,
            UncPath = uncPath,
            MachineName = machineName,
            Exists = System.IO.File.Exists(localPath)
        });
    }
}

/// <summary>
/// Version information response model
/// </summary>
public class VersionInfo
{
    /// <summary>
    /// The semantic version of the ServerMonitor agent (e.g., "1.0.14")
    /// </summary>
    public string Version { get; set; } = "unknown";
    
    /// <summary>
    /// The product name
    /// </summary>
    public string ProductName { get; set; } = "ServerMonitor";
    
    /// <summary>
    /// The machine name where the agent is running
    /// </summary>
    public string MachineName { get; set; } = "";
}

/// <summary>
/// Memory usage information for the ServerMonitor process
/// </summary>
public class MemoryInfo
{
    /// <summary>
    /// Working set memory in MB (physical memory currently in use)
    /// </summary>
    public double WorkingSetMB { get; set; }
    
    /// <summary>
    /// Private memory in MB (memory allocated exclusively to this process)
    /// </summary>
    public double PrivateMemoryMB { get; set; }
    
    /// <summary>
    /// GC managed heap memory in MB
    /// </summary>
    public double GcTotalMemoryMB { get; set; }
    
    /// <summary>
    /// Machine name
    /// </summary>
    public string MachineName { get; set; } = "";
    
    /// <summary>
    /// Timestamp of the measurement
    /// </summary>
    public DateTime Timestamp { get; set; }
}

/// <summary>
/// Log file path information
/// </summary>
public class LogFileInfo
{
    /// <summary>
    /// Local file path on the server
    /// </summary>
    public string LocalPath { get; set; } = "";
    
    /// <summary>
    /// UNC path for remote access (e.g., \\server\opt\data\...)
    /// </summary>
    public string UncPath { get; set; } = "";
    
    /// <summary>
    /// Machine name where the log file is located
    /// </summary>
    public string MachineName { get; set; } = "";
    
    /// <summary>
    /// Whether the log file currently exists
    /// </summary>
    public bool Exists { get; set; }
}
