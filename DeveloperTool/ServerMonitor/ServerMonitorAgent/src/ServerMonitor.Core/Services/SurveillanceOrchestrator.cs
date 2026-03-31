using System.Diagnostics;
using System.Linq;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Orchestrates all monitoring activities
/// </summary>
public class SurveillanceOrchestrator
{
    private readonly ILogger<SurveillanceOrchestrator> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IEnumerable<IMonitor> _monitors;
    private readonly ISnapshotExporter _snapshotExporter;
    private readonly AlertManager _alertManager;
    private readonly GlobalSnapshotService _globalSnapshot;
    private readonly PerformanceScalingService _scalingService;
    private readonly Dictionary<string, Timer> _monitorTimers = new();
    private Timer? _cleanupTimer;
    private Timer? _selfMonitoringTimer;
    private CancellationTokenSource? _exportCts;
    private readonly SemaphoreSlim _exportSemaphore = new(1, 1); // Prevent concurrent exports
    private Action? _shutdownCallback;
    
    /// <summary>
    /// True when shutting down due to memory threshold. Persisted snapshot must NOT be saved 
    /// (and any existing one must be deleted) to avoid reloading a bloated snapshot on restart.
    /// </summary>
    public bool IsMemoryShutdown { get; private set; }

    public SurveillanceOrchestrator(
        ILogger<SurveillanceOrchestrator> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IEnumerable<IMonitor> monitors,
        ISnapshotExporter snapshotExporter,
        AlertManager alertManager,
        GlobalSnapshotService globalSnapshot,
        PerformanceScalingService scalingService)
    {
        _logger = logger;
        _config = config;
        _monitors = monitors;
        _snapshotExporter = snapshotExporter;
        _alertManager = alertManager;
        _globalSnapshot = globalSnapshot;
        _scalingService = scalingService;

        // Subscribe to configuration changes to restart timers with new intervals
        _config.OnChange(newConfig =>
        {
            _logger.LogInformation("🔄 Configuration changed - restarting monitoring cycles with new intervals");
            RestartMonitoringCycles();
            RestartSnapshotExportTimer();
            RestartCleanupTimer();
        });
    }
    
    /// <summary>
    /// Sets the callback to invoke when graceful shutdown is needed (e.g., memory threshold exceeded)
    /// </summary>
    public void SetShutdownCallback(Action callback)
    {
        _shutdownCallback = callback;
    }

    private void RestartMonitoringCycles()
    {
        _logger.LogInformation("Restarting monitoring cycles with updated intervals");

        // Stop existing timers
        foreach (var timer in _monitorTimers.Values)
        {
            timer?.Dispose();
        }
        _monitorTimers.Clear();

        // Restart with new intervals
        StartMonitoringCycles();
    }

    private void RestartSnapshotExportTimer()
    {
        _logger.LogInformation("Restarting snapshot export timer with updated interval");

        // Cancel existing timer
        _exportCts?.Cancel();
        _exportCts?.Dispose();

        // Restart with new interval
        StartSnapshotExportTimer();
    }

    private void RestartCleanupTimer()
    {
        _logger.LogInformation("Restarting cleanup timer");

        // Stop existing timer
        _cleanupTimer?.Dispose();

        // Restart with new interval
        StartCleanupTimer();
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting Server Health Monitor Check Tool");

        if (!_config.CurrentValue.General.MonitoringEnabled)
        {
            _logger.LogWarning("Monitoring is disabled in configuration");
            return Task.CompletedTask;
        }

        // Start monitoring cycles for each enabled monitor
        StartMonitoringCycles();

        // Start snapshot export timer
        StartSnapshotExportTimer();

        // Start cleanup timer
        StartCleanupTimer();
        
        // Start self-monitoring timer (memory check)
        StartSelfMonitoringTimer();

        _logger.LogInformation("Server Health Monitor Check Tool started successfully");

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Stopping Server Health Monitor Check Tool");

        // Stop all timers
        foreach (var timer in _monitorTimers.Values)
        {
            timer?.Dispose();
        }
        _monitorTimers.Clear();

        _exportCts?.Cancel();
        _exportCts?.Dispose();
        _cleanupTimer?.Dispose();
        _selfMonitoringTimer?.Dispose();

        _logger.LogInformation("Server Health Monitor Check Tool stopped");

        return Task.CompletedTask;
    }

    private void StartMonitoringCycles()
    {
        // Log performance scaling status
        _logger.LogInformation("📊 {ScalingSummary}", _scalingService.GetScalingSummary());
        
        // Stagger monitor startup to avoid CPU spike at startup
        // Each monitor starts with an incremental delay to spread the initial load
        // Base stagger interval is scaled for low-capacity servers
        var baseStaggerSeconds = 3;
        var staggerIntervalSeconds = (int)(_scalingService.StartupDelayMultiplier * baseStaggerSeconds);
        var startupDelaySeconds = 0;
        
        // Get enabled monitors and order by priority (lightweight first)
        var enabledMonitors = _monitors
            .Where(m => m.IsEnabled)
            .OrderBy(m => GetMonitorStartupPriority(m.Category))
            .ToList();
        
        _logger.LogInformation("═══════════════════════════════════════════════════════");
        _logger.LogInformation("Starting {Count} monitors with staggered startup ({Stagger}s intervals{Scaled})", 
            enabledMonitors.Count, staggerIntervalSeconds, 
            _scalingService.IsLowCapacityServer ? $" - scaled x{_scalingService.StartupDelayMultiplier}" : "");
        _logger.LogInformation("Estimated full startup time: {Time}s", 
            enabledMonitors.Count * staggerIntervalSeconds);
        _logger.LogInformation("═══════════════════════════════════════════════════════");
        
        foreach (var monitor in enabledMonitors)
        {
            var interval = GetMonitorInterval(monitor);
            if (interval > 0)
            {
                var initialDelay = TimeSpan.FromSeconds(startupDelaySeconds);
                
                var timer = new Timer(
                    async _ => await RunMonitorCycleAsync(monitor),
                    null,
                    initialDelay,  // Staggered start instead of TimeSpan.Zero
                    TimeSpan.FromSeconds(interval));

                _monitorTimers[monitor.Category] = timer;

                _logger.LogInformation("Scheduled {Category} (delay: {Delay}s, interval: {Interval}s)",
                    monitor.Category, startupDelaySeconds, interval);
                
                startupDelaySeconds += staggerIntervalSeconds;
            }
        }
    }
    
    /// <summary>
    /// Returns startup priority for monitors. Lower values start first.
    /// Lightweight monitors start first to reduce CPU load.
    /// </summary>
    private static int GetMonitorStartupPriority(string category)
    {
        return category switch
        {
            "Uptime" => 1,           // Fast: single WMI query
            "Memory" => 2,           // Fast: single WMI query
            "VirtualMemory" => 3,    // Fast: performance counter
            "Processor" => 4,        // Medium: performance counter with sampling
            "Disk" => 5,             // Medium: multiple drives
            "Network" => 6,          // Medium: ping tests
            "ScheduledTask" => 7,    // Heavy: Task Scheduler enumeration
            "EventLog" => 8,         // Heavy: log parsing
            "WindowsUpdate" => 9,    // Heavy: WMI query can be slow
            "Db2Diag" => 10,         // Heavy: file parsing (conditional)
            "IIS" => 11,             // Medium: IIS ServerManager queries (conditional)
            _ => 50                  // Unknown monitors last
        };
    }

    private int GetMonitorInterval(IMonitor monitor)
    {
        var config = _config.CurrentValue;

        var baseInterval = monitor.Category switch
        {
            "Processor" => config.ProcessorMonitoring.PollingIntervalSeconds,
            "Memory" => config.MemoryMonitoring.PollingIntervalSeconds,
            "VirtualMemory" => config.VirtualMemoryMonitoring.PollingIntervalSeconds,
            "Disk" => Math.Min(config.DiskUsageMonitoring.PollingIntervalSeconds, 
                              config.DiskSpaceMonitoring.PollingIntervalSeconds),
            "Network" => config.NetworkMonitoring.PollingIntervalSeconds,
            "Uptime" => config.UptimeMonitoring.PollingIntervalSeconds,
            "WindowsUpdate" => config.WindowsUpdateMonitoring.PollingIntervalSeconds,
            "EventLog" => config.EventMonitoring.PollingIntervalSeconds,
            "ScheduledTask" => config.ScheduledTaskMonitoring.PollingIntervalSeconds,
            "IIS" => config.IisMonitoring.PollingIntervalSeconds,
            _ => 60
        };
        
        // Apply performance scaling for low-capacity servers
        return _scalingService.ScaleIntervalSeconds(baseInterval);
    }

    private async Task RunMonitorCycleAsync(IMonitor monitor)
    {
        try
        {
            var result = await monitor.CollectAsync();

            if (!result.Success)
            {
                _logger.LogWarning("Monitor {Category} failed: {Error}", 
                    monitor.Category, result.ErrorMessage);
                return;
            }

            // Update global snapshot with new data (sequential, no locks needed)
            UpdateGlobalSnapshot(monitor.Category, result);

            // Process alerts: add to global snapshot + distribute (sequential, simple)
            if (result.Alerts.Count > 0)
            {
                _logger.LogInformation("Monitor {Category} generated {Count} alert(s)", 
                    monitor.Category, result.Alerts.Count);
                
                // Sequential alert processing - no async complexity
                _alertManager.ProcessAlertsSync(result.Alerts);

                // Export snapshot on alert if configured
                if (_config.CurrentValue.ExportSettings.ExportIntervals.OnAlertTrigger)
                {
                    await ExportCurrentSnapshotAsync();
                }
            }

            _logger.LogDebug("Monitor {Category} cycle completed in {Duration}ms", 
                monitor.Category, result.CollectionDurationMs);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running monitor cycle for {Category}", monitor.Category);
        }
    }

    /// <summary>
    /// Updates global snapshot with monitor data
    /// </summary>
    private void UpdateGlobalSnapshot(string category, MonitorResult result)
    {
        if (!result.Success || result.Data == null)
            return;

        switch (category)
        {
            case "Processor":
                _globalSnapshot.UpdateProcessor(result.Data as ProcessorData ?? throw new InvalidCastException());
                break;
            case "Memory":
                _globalSnapshot.UpdateMemory(result.Data as MemoryData ?? throw new InvalidCastException());
                break;
            case "VirtualMemory":
                _globalSnapshot.UpdateVirtualMemory(result.Data as VirtualMemoryData ?? throw new InvalidCastException());
                break;
            case "Disk":
                _globalSnapshot.UpdateDisk(result.Data as DiskData ?? throw new InvalidCastException());
                break;
            case "Network":
                if (result.Data is List<NetworkHostData> networkData)
                    _globalSnapshot.UpdateNetwork(networkData);
                break;
            case "Uptime":
                _globalSnapshot.UpdateUptime(result.Data as UptimeData ?? throw new InvalidCastException());
                break;
            case "WindowsUpdate":
                _globalSnapshot.UpdateWindowsUpdates(result.Data as WindowsUpdateData ?? throw new InvalidCastException());
                break;
            case "EventLog":
                if (result.Data is List<EventData> eventData)
                    _globalSnapshot.UpdateEvents(eventData);
                break;
            case "ScheduledTask":
                if (result.Data is List<ScheduledTaskData> taskData)
                    _globalSnapshot.UpdateScheduledTasks(taskData);
                break;
            case "Db2Diag":
                if (result.Data is Db2DiagData db2Data)
                    _globalSnapshot.UpdateDb2Diagnostics(db2Data);
                break;
            case "Db2Instance":
                if (result.Data is Dictionary<string, object> dict && dict.TryGetValue("Snapshot", out var snapshotObj) && snapshotObj is Db2InstanceSnapshot db2Instance)
                    _globalSnapshot.UpdateDb2Instance(db2Instance);
                break;
            case "IIS":
                if (result.Data is IisSnapshot iisSnapshot)
                    _globalSnapshot.UpdateIis(iisSnapshot);
                break;
        }
    }

    private void StartSnapshotExportTimer()
    {
        _logger.LogInformation("StartSnapshotExportTimer called. Enabled={Enabled}", _config.CurrentValue.ExportSettings.Enabled);
        
        if (!_config.CurrentValue.ExportSettings.Enabled)
        {
            _logger.LogWarning("⚠️ Snapshot export is DISABLED in configuration");
            return;
        }

        // Get export interval from configuration and apply scaling if enabled
        var baseIntervalMinutes = _config.CurrentValue.ExportSettings.ExportIntervals.IntervalMinutes ?? 15;
        var applyScaling = _config.CurrentValue.PerformanceScaling.ApplyToExportIntervals;
        var intervalMinutes = applyScaling 
            ? _scalingService.ScaleIntervalMinutes(baseIntervalMinutes) 
            : baseIntervalMinutes;
        
        // Scale the initial startup delay
        var startupDelaySeconds = (int)_scalingService.ScaleStartupDelay(TimeSpan.FromSeconds(10)).TotalSeconds;
        
        _exportCts = new CancellationTokenSource();
        
        _logger.LogInformation("🚀 Starting snapshot export background task: first export in {StartupDelay}s, then every {Interval} minutes{Scaled}", 
            startupDelaySeconds, intervalMinutes, 
            _scalingService.IsLowCapacityServer && applyScaling ? $" (scaled from {baseIntervalMinutes}min)" : "");
        
        // Use Task-based timer loop WITHOUT passing cancellation token to Task.Run to prevent premature cancellation
        _ = Task.Run(async () =>
        {
            _logger.LogInformation("📢 Export background task STARTED");
            try
            {
                // Wait before first export to let ALL monitors complete their first data collection cycle
                // Delay is scaled for low-capacity servers
                _logger.LogInformation("⏳ Waiting {Delay} seconds for all monitors to collect initial data...", startupDelaySeconds);
                await Task.Delay(TimeSpan.FromSeconds(startupDelaySeconds)).ConfigureAwait(false);
                
                // First export after startup delay
                _logger.LogInformation("⏰ Triggering startup export (after initial delay)...");
                await ExportCurrentSnapshotAsync().ConfigureAwait(false);
                _logger.LogInformation("✅ Startup export complete, next export in {Interval} minutes", intervalMinutes);
                
                while (!_exportCts.Token.IsCancellationRequested)
                {
                    // Wait for next interval (re-read config in case it changed, apply scaling)
                    baseIntervalMinutes = _config.CurrentValue.ExportSettings.ExportIntervals.IntervalMinutes ?? 15;
                    applyScaling = _config.CurrentValue.PerformanceScaling.ApplyToExportIntervals;
                    intervalMinutes = applyScaling 
                        ? _scalingService.ScaleIntervalMinutes(baseIntervalMinutes) 
                        : baseIntervalMinutes;
                    await Task.Delay(TimeSpan.FromMinutes(intervalMinutes)).ConfigureAwait(false);
                    
                    _logger.LogInformation("⏰ Scheduled export timer triggered");
                    await ExportCurrentSnapshotAsync().ConfigureAwait(false);
                    _logger.LogInformation("✅ Scheduled export complete");
                }
                
                _logger.LogInformation("Export timer loop exited (cancellation requested)");
            }
            catch (OperationCanceledException ex)
            {
                _logger.LogWarning(ex, "Snapshot export timer cancelled");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ FATAL ERROR in snapshot export timer loop");
            }
        });
        
        _logger.LogInformation("✅ Export background task launched");
    }

    private void StartCleanupTimer()
    {
        // Get cleanup interval from config and apply scaling if enabled
        var memSettings = _config.CurrentValue.General.MemoryManagement;
        var baseIntervalMinutes = memSettings.CleanupIntervalMinutes;
        var applyScaling = _config.CurrentValue.PerformanceScaling.ApplyToCleanupIntervals;
        var intervalMinutes = applyScaling 
            ? _scalingService.ScaleIntervalMinutes(baseIntervalMinutes) 
            : baseIntervalMinutes;
        
        // Run cleanup based on configured interval (default: every hour, scaled for low-capacity servers)
        _cleanupTimer = new Timer(
            _ => Task.Run(async () => await RunAllCleanupTasksAsync()),
            null,
            TimeSpan.FromMinutes(intervalMinutes), // First cleanup after configured interval
            TimeSpan.FromMinutes(intervalMinutes)); // Repeat at configured interval

        _logger.LogInformation("Started cleanup timer (interval: {Interval} minutes{Scaled})", 
            intervalMinutes, 
            _scalingService.IsLowCapacityServer && applyScaling ? $" - scaled from {baseIntervalMinutes}min" : "");
    }
    
    /// <summary>
    /// Runs all cleanup tasks for memory management and file retention.
    /// This is called periodically by the cleanup timer.
    /// </summary>
    private async Task RunAllCleanupTasksAsync()
    {
        try
        {
            _logger.LogDebug("Running periodic cleanup tasks...");
            
            // 1. Memory cleanup: Alerts, ExternalEvents, tracking dictionaries
            _globalSnapshot.RunPeriodicCleanup();
            _alertManager.RunPeriodicCleanup();
            
            // 2. File cleanup: Old snapshot files
            await _snapshotExporter.CleanupOldSnapshotsAsync();
            
            _logger.LogDebug("Periodic cleanup tasks completed");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error during periodic cleanup - will retry on next cycle");
        }
    }

    private async Task ExportCurrentSnapshotAsync()
    {
        // Run entire export synchronously in background thread to avoid deadlocks
        await Task.Run(() =>
        {
            try
            {
                _logger.LogInformation("📸 Creating snapshot...");
                
                // Collect snapshot (synchronous)
                var snapshot = CollectFullSnapshot();
                
                _logger.LogInformation("💾 Saving files...");
                
                // Export synchronously (avoids all async deadlocks)
                ExportSnapshot(snapshot);
                
                _logger.LogInformation("✅ Snapshot exported successfully");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ Failed to export snapshot");
            }
        });
    }
    
    /// <summary>
    /// Gets current snapshot from global service - ALWAYS available, never null
    /// </summary>
    private SystemSnapshot CollectFullSnapshot()
    {
        _logger.LogDebug("📸 Reading snapshot from GlobalSnapshotService (always available)");
        
        // Simply get the current snapshot - it's always initialized and up-to-date
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        
        _logger.LogInformation("✅ Snapshot retrieved: {ServerName}, {AlertCount} alerts, Uptime: {Uptime:F1} days", 
            snapshot.Metadata.ServerName,
            snapshot.Alerts.Count,
            snapshot.Uptime?.CurrentUptimeDays ?? 0);

        return snapshot;
    }
    
    private void ExportSnapshot(SystemSnapshot snapshot)
    {
        var settings = _config.CurrentValue.ExportSettings;
        
        if (!settings.Enabled)
            return;

        // Get all output directories
        var outputDirs = GetOutputDirectories(settings);
        
        if (outputDirs.Count == 0)
        {
            _logger.LogWarning("No output directories configured for snapshot export");
            return;
        }

        // Generate filename with milliseconds to avoid conflicts
        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmssfff");
        var serverName = snapshot.Metadata.ServerName; // Get from snapshot, not config
        var fileName = $"{serverName}_{timestamp}.json";

        // Serialize snapshot once (reuse for all directories)
        // Use JsonStringEnumConverter to serialize enums as strings (e.g., "critical" instead of 2)
        var jsonOptions = new JsonSerializerOptions 
        { 
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
        };
        var json = JsonSerializer.Serialize(snapshot, jsonOptions);
        var html = GenerateHtml(snapshot);

        // Write to all output directories
        foreach (var outputDir in outputDirs)
        {
            try
            {
                // Ensure output directory exists
                Directory.CreateDirectory(outputDir);

                var filePath = Path.Combine(outputDir, fileName);

                // Write JSON
                File.WriteAllText(filePath, json);
                _logger.LogInformation("JSON saved: {FilePath} ({Size} KB)", filePath, json.Length / 1024);

                // Create HTML
                var htmlPath = Path.ChangeExtension(filePath, ".html");
                File.WriteAllText(htmlPath, html);
                _logger.LogInformation("HTML saved: {HtmlPath}", htmlPath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to export snapshot to {Directory} - continuing with other directories", outputDir);
                // Continue with other directories even if one fails
            }
        }

        // Copy HTML to server share with static filename (legacy behavior)
        try
        {
            var serverShareBase = @"dedge-server\FkAdminWebContent\Server";
            var computerFolder = Path.Combine(serverShareBase, serverName);
            
            if (!Directory.Exists(computerFolder))
                Directory.CreateDirectory(computerFolder);
            
            // Use static filename (no timestamp) for server share
            var serverHtmlPath = Path.Combine(computerFolder, "ServerMonitorReport.html");
            File.WriteAllText(serverHtmlPath, html); // Write directly instead of copying
            
            _logger.LogInformation("HTML copied to server share: {ServerPath}", serverHtmlPath);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to copy HTML to server share");
        }
    }

    /// <summary>
    /// Gets all output directories from configuration.
    /// Combines OutputDirectory (for backward compatibility) and OutputDirectories.
    /// </summary>
    private List<string> GetOutputDirectories(ExportSettings settings)
    {
        var directories = new List<string>();

        // If OutputDirectories is specified, use it (ignore OutputDirectory)
        if (settings.OutputDirectories != null && settings.OutputDirectories.Count > 0)
        {
            directories.AddRange(settings.OutputDirectories);
        }
        // Otherwise, use OutputDirectory for backward compatibility
        else if (!string.IsNullOrWhiteSpace(settings.OutputDirectory))
        {
            directories.Add(settings.OutputDirectory);
        }

        // Expand environment variables and remove duplicates
        return directories
            .Select(d => Environment.ExpandEnvironmentVariables(d))
            .Where(d => !string.IsNullOrWhiteSpace(d))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }
    
    private string GenerateHtml(SystemSnapshot snapshot)
    {
        return $@"<!DOCTYPE html>
<html>
<head>
    <title>Server Snapshot - {snapshot.Metadata.ServerName} - {snapshot.Metadata.Timestamp:yyyy-MM-dd HH:mm:ss}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1400px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
        h1 {{ color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 10px; }}
        h2 {{ color: #4CAF50; margin-top: 30px; }}
        h3 {{ color: #666; margin-top: 20px; }}
        table {{ width: 100%; border-collapse: collapse; margin: 15px 0; }}
        th {{ background: #4CAF50; color: white; padding: 12px; text-align: left; }}
        td {{ padding: 10px; border-bottom: 1px solid #ddd; }}
        tr:nth-child(even) {{ background: #f9f9f9; }}
        .metric {{ display: inline-block; margin: 10px 20px 10px 0; }}
        .metric-label {{ font-weight: bold; color: #666; }}
        .metric-value {{ font-size: 1.2em; color: #333; }}
        .timestamp {{ color: #666; font-size: 0.9em; }}
        .metric-good {{ color: #4CAF50; }}
        .metric-warning {{ color: #F57C00; }}
        .metric-critical {{ color: #D32F2F; }}
        .process-table td {{ font-size: 0.9em; padding: 6px 10px; }}
        .process-table th {{ font-size: 0.9em; padding: 8px 10px; }}
    </style>
</head>
<body>
    <div class='container'>
        <h1>Server Snapshot: {snapshot.Metadata.ServerName}</h1>
        <p class='timestamp'>Generated: {snapshot.Metadata.Timestamp:yyyy-MM-dd HH:mm:ss} UTC | Collection: {snapshot.Metadata.CollectionDurationMs}ms</p>
        
        <h2>Processor</h2>
        <div class='metric'><span class='metric-label'>Overall CPU:</span> <span class='metric-value'>{snapshot.Processor?.OverallUsagePercent:F1}%</span></div>
        <div class='metric'><span class='metric-label'>Cores:</span> <span class='metric-value'>{snapshot.Processor?.PerCoreUsage?.Count ?? 0}</span></div>
        <div class='metric'><span class='metric-label'>1m Avg:</span> <span class='metric-value'>{snapshot.Processor?.Averages?.OneMinute:F1}%</span></div>
        <div class='metric'><span class='metric-label'>5m Avg:</span> <span class='metric-value'>{snapshot.Processor?.Averages?.FiveMinute:F1}%</span></div>
        <div class='metric'><span class='metric-label'>15m Avg:</span> <span class='metric-value'>{snapshot.Processor?.Averages?.FifteenMinute:F1}%</span></div>
        {(snapshot.Processor?.CpuUsageHistory != null && snapshot.Processor.CpuUsageHistory.Count > 0 ? $@"
        <script>
        var cpuUsageHistory = [{string.Join(",", snapshot.Processor.CpuUsageHistory.Select(m => $"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}"))}];
        </script>
        <p style='color: #666; font-size: 0.9em;'>CPU Usage History: {snapshot.Processor.CpuUsageHistory.Count} measurements (last {(int)(DateTime.UtcNow - snapshot.Processor.CpuUsageHistory.First().Timestamp).TotalSeconds} seconds)</p>" : "")}
        
        {(snapshot.Processor?.TopProcesses != null && snapshot.Processor.TopProcesses.Count > 0 ? $@"
        <h3>Top Processes by CPU</h3>
        <table class='process-table'>
            <tr><th>Process</th><th>PID</th><th>CPU %</th><th>Memory (MB)</th><th>Threads</th><th>User</th><th>Service</th></tr>
            {string.Join("", snapshot.Processor.TopProcesses.Select(p => $@"
            <tr>
                <td title='{System.Net.WebUtility.HtmlEncode(p.CommandLine)}'>{System.Net.WebUtility.HtmlEncode(p.Name)}</td>
                <td>{p.Pid}</td>
                <td class='{(p.CpuPercent > 50 ? "metric-critical" : p.CpuPercent > 20 ? "metric-warning" : "")}'>{p.CpuPercent:F1}%</td>
                <td>{p.MemoryMB:N0}</td>
                <td>{p.ThreadCount}</td>
                <td>{System.Net.WebUtility.HtmlEncode(p.UserName)}</td>
                <td>{(string.IsNullOrEmpty(p.ServiceName) ? "-" : System.Net.WebUtility.HtmlEncode(p.ServiceDisplayName ?? p.ServiceName))}</td>
            </tr>"))}
        </table>" : "")}
        
        <h2>Memory</h2>
        <div class='metric'><span class='metric-label'>Used:</span> <span class='metric-value'>{(snapshot.Memory != null ? (snapshot.Memory.TotalGB - snapshot.Memory.AvailableGB) : 0):F1} GB / {snapshot.Memory?.TotalGB:F1} GB</span></div>
        <div class='metric'><span class='metric-label'>Usage:</span> <span class='metric-value'>{snapshot.Memory?.UsedPercent:F1}%</span></div>
        {(snapshot.Memory?.MemoryUsageHistory != null && snapshot.Memory.MemoryUsageHistory.Count > 0 ? $@"
        <script>
        var memoryUsageHistory = [{string.Join(",", snapshot.Memory.MemoryUsageHistory.Select(m => $"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}"))}];
        </script>
        <p style='color: #666; font-size: 0.9em;'>Memory Usage History: {snapshot.Memory.MemoryUsageHistory.Count} measurements (last {(int)(DateTime.UtcNow - snapshot.Memory.MemoryUsageHistory.First().Timestamp).TotalSeconds} seconds)</p>" : "")}
        
        {(snapshot.Memory?.TopProcesses != null && snapshot.Memory.TopProcesses.Count > 0 ? $@"
        <h3>Top Processes by Memory</h3>
        <table class='process-table'>
            <tr><th>Process</th><th>PID</th><th>Memory (MB)</th><th>Private (MB)</th><th>Virtual (MB)</th><th>CPU %</th><th>User</th></tr>
            {string.Join("", snapshot.Memory.TopProcesses.Select(p => $@"
            <tr>
                <td title='{System.Net.WebUtility.HtmlEncode(p.CommandLine)}'>{System.Net.WebUtility.HtmlEncode(p.Name)}</td>
                <td>{p.Pid}</td>
                <td class='{(p.MemoryMB > 1000 ? "metric-warning" : "")}'>{p.MemoryMB:N0}</td>
                <td>{p.PrivateMemoryMB:N0}</td>
                <td>{p.VirtualMemoryMB:N0}</td>
                <td>{p.CpuPercent:F1}%</td>
                <td>{System.Net.WebUtility.HtmlEncode(p.UserName)}</td>
            </tr>"))}
        </table>" : "")}
        
        {(snapshot.VirtualMemory != null ? $@"
        <h2>Virtual Memory</h2>
        <div class='metric'><span class='metric-label'>Used:</span> <span class='metric-value'>{(snapshot.VirtualMemory.TotalGB - snapshot.VirtualMemory.AvailableGB):F1} GB / {snapshot.VirtualMemory.TotalGB:F1} GB</span></div>
        <div class='metric'><span class='metric-label'>Usage:</span> <span class='metric-value'>{snapshot.VirtualMemory.UsedPercent:F1}%</span></div>
        <div class='metric'><span class='metric-label'>Paging Rate:</span> <span class='metric-value'>{snapshot.VirtualMemory.PagingRatePerSec:F1} pages/sec</span></div>
        {(snapshot.VirtualMemory.VirtualMemoryUsageHistory != null && snapshot.VirtualMemory.VirtualMemoryUsageHistory.Count > 0 ? $@"
        <script>
        var virtualMemoryUsageHistory = [{string.Join(",", snapshot.VirtualMemory.VirtualMemoryUsageHistory.Select(m => $"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}"))}];
        </script>
        <p style='color: #666; font-size: 0.9em;'>Virtual Memory Usage History: {snapshot.VirtualMemory.VirtualMemoryUsageHistory.Count} measurements (last {(int)(DateTime.UtcNow - snapshot.VirtualMemory.VirtualMemoryUsageHistory.First().Timestamp).TotalSeconds} seconds)</p>" : "")}" : "")}
        
        <h2>Disks</h2>
        <table>
            <tr><th>Drive</th><th>Total</th><th>Available</th><th>Used%</th><th>File System</th></tr>
            {string.Join("", snapshot.Disks?.Space?.Select(d => $"<tr><td>{d.Drive}</td><td>{d.TotalGB:F1} GB</td><td>{d.AvailableGB:F1} GB</td><td class='{(d.UsedPercent > 90 ? "metric-critical" : d.UsedPercent > 80 ? "metric-warning" : "")}'>{d.UsedPercent:F1}%</td><td>{d.FileSystem}</td></tr>") ?? new[] { "" })}
        </table>
        {(snapshot.Disks?.Usage != null && snapshot.Disks.Usage.Any(d => (d.QueueLengthHistory != null && d.QueueLengthHistory.Count > 0) || (d.ResponseTimeHistory != null && d.ResponseTimeHistory.Count > 0)) ? string.Join("", snapshot.Disks.Usage.Where(d => (d.QueueLengthHistory != null && d.QueueLengthHistory.Count > 0) || (d.ResponseTimeHistory != null && d.ResponseTimeHistory.Count > 0)).Select(d => {
            var driveKey = d.Drive.Replace(":", "").Replace("\\", "_");
            var queueScript = d.QueueLengthHistory != null && d.QueueLengthHistory.Count > 0 ? $@"
        <script>
        var disk_{driveKey}_QueueLengthHistory = [{string.Join(",", d.QueueLengthHistory.Select(m => $"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}"))}];
        </script>
        <p style='color: #666; font-size: 0.9em;'>Disk {d.Drive} Queue Length History: {d.QueueLengthHistory.Count} measurements</p>" : "";
            var responseScript = d.ResponseTimeHistory != null && d.ResponseTimeHistory.Count > 0 ? $@"
        <script>
        var disk_{driveKey}_ResponseTimeHistory = [{string.Join(",", d.ResponseTimeHistory.Select(m => $"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}"))}];
        </script>
        <p style='color: #666; font-size: 0.9em;'>Disk {d.Drive} Response Time History: {d.ResponseTimeHistory.Count} measurements</p>" : "";
            return queueScript + responseScript;
        })) : "")}
        
        {(snapshot.Network != null && snapshot.Network.Count > 0 ? $@"
        <h2>Network</h2>
        <table>
            <tr><th>Host</th><th>Ping (ms)</th><th>Packet Loss %</th><th>DNS (ms)</th><th>Failures</th></tr>
            {string.Join("", snapshot.Network.Select(n => $@"
            <tr>
                <td>{System.Net.WebUtility.HtmlEncode(n.Hostname)}</td>
                <td>{(n.PingMs.HasValue ? $"{n.PingMs.Value:F1}" : "N/A")}</td>
                <td class='{(n.PacketLossPercent > 0 ? "metric-warning" : "")}'>{n.PacketLossPercent:F1}%</td>
                <td>{(n.DnsResolutionMs.HasValue ? $"{n.DnsResolutionMs.Value:F1}" : "N/A")}</td>
                <td class='{(n.ConsecutiveFailures > 0 ? "metric-critical" : "")}'>{n.ConsecutiveFailures}</td>
            </tr>"))}
        </table>" : "")}
        
        <h2>Uptime</h2>
        <div class='metric'><span class='metric-label'>Last Boot:</span> <span class='metric-value'>{snapshot.Uptime?.LastBootTime:yyyy-MM-dd HH:mm}</span></div>
        <div class='metric'><span class='metric-label'>Uptime:</span> <span class='metric-value'>{(snapshot.Uptime != null ? (DateTime.Now - snapshot.Uptime.LastBootTime).TotalDays : 0):F1} days</span></div>
        
        {(snapshot.WindowsUpdates != null ? $@"
        <h2>Windows Updates</h2>
        <div class='metric'><span class='metric-label'>Pending:</span> <span class='metric-value {(snapshot.WindowsUpdates.PendingCount > 0 ? "metric-warning" : "")}'>{snapshot.WindowsUpdates.PendingCount}</span></div>
        <div class='metric'><span class='metric-label'>Security:</span> <span class='metric-value {(snapshot.WindowsUpdates.SecurityUpdates > 0 ? "metric-critical" : "")}'>{snapshot.WindowsUpdates.SecurityUpdates}</span></div>
        <div class='metric'><span class='metric-label'>Critical:</span> <span class='metric-value {(snapshot.WindowsUpdates.CriticalUpdates > 0 ? "metric-critical" : "")}'>{snapshot.WindowsUpdates.CriticalUpdates}</span></div>
        <div class='metric'><span class='metric-label'>Last Install:</span> <span class='metric-value'>{(snapshot.WindowsUpdates.LastInstallDate.HasValue ? snapshot.WindowsUpdates.LastInstallDate.Value.ToString("yyyy-MM-dd") : "Never")}</span></div>" : "")}
        
        {(snapshot.ScheduledTasks != null && snapshot.ScheduledTasks.Count > 0 ? $@"
        <h2>Scheduled Tasks</h2>
        <table>
            <tr><th>Task</th><th>State</th><th>Last Run</th><th>Result</th><th>Next Run</th><th>Run As</th></tr>
            {string.Join("", snapshot.ScheduledTasks.Select(t => $@"
            <tr>
                <td title='{System.Net.WebUtility.HtmlEncode(t.TaskPath)}'>{System.Net.WebUtility.HtmlEncode(t.TaskName)}</td>
                <td class='{(t.State == "Running" ? "metric-good" : t.IsEnabled ? "" : "metric-warning")}'>{t.State}{(t.IsEnabled ? "" : " (Disabled)")}</td>
                <td>{(t.LastRunTime.HasValue ? t.LastRunTime.Value.ToString("yyyy-MM-dd HH:mm") : "Never")}</td>
                <td class='{(t.LastRunResult.HasValue && t.LastRunResult.Value != 0 ? "metric-critical" : "")}'>{(t.LastRunResult.HasValue ? (t.LastRunResult.Value == 0 ? "✓ Success" : $"Exit: {t.LastRunResult.Value}") : "N/A")}</td>
                <td>{(t.NextRunTime.HasValue ? t.NextRunTime.Value.ToString("yyyy-MM-dd HH:mm") : "Not scheduled")}</td>
                <td>{System.Net.WebUtility.HtmlEncode(t.RunAsUser ?? "N/A")}</td>
            </tr>"))}
        </table>" : "")}
        
        {(snapshot.Events != null && snapshot.Events.Count > 0 ? $@"
        <h2>Event Log Summary</h2>
        <table>
            <tr><th>Event ID</th><th>Source</th><th>Level</th><th>Count</th><th>Last Occurrence</th></tr>
            {string.Join("", snapshot.Events.OrderByDescending(e => e.LastOccurrence).Take(20).Select(e => $@"
            <tr>
                <td>{e.EventId}</td>
                <td>{System.Net.WebUtility.HtmlEncode(e.Source)}</td>
                <td class='{(e.Level == "Critical" || e.Level == "Error" ? "metric-critical" : e.Level == "Warning" ? "metric-warning" : "")}'>{e.Level}</td>
                <td>{e.Count}</td>
                <td>{(e.LastOccurrence.HasValue ? e.LastOccurrence.Value.ToString("yyyy-MM-dd HH:mm:ss") : "N/A")}</td>
            </tr>"))}
        </table>
        <p style='color: #666; font-size: 0.9em;'>Showing {Math.Min(20, snapshot.Events.Count)} of {snapshot.Events.Count} event types</p>" : "")}
        
        <h2>Recent Alerts</h2>
        <p><strong>{snapshot.Alerts?.Count ?? 0} alert(s)</strong> recorded</p>
        {(snapshot.Alerts != null && snapshot.Alerts.Any() ? $@"
        <table>
            <tr>
                <th>Timestamp (UTC)</th>
                <th>Severity</th>
                <th>Category</th>
                <th>Message</th>
                <th>Channel</th>
                <th>Destination</th>
                <th>Status</th>
            </tr>
            {string.Join("", snapshot.Alerts.OrderByDescending(a => a.Timestamp).SelectMany(alert =>
            {
                // If alert has distribution history, create one row per channel
                if (alert.DistributionHistory != null && alert.DistributionHistory.Any())
                {
                    return alert.DistributionHistory.Select(d => $@"
            <tr>
                <td>{alert.Timestamp:yyyy-MM-dd HH:mm:ss}</td>
                <td style='color: {(alert.Severity == AlertSeverity.Critical ? "red" : alert.Severity == AlertSeverity.Warning ? "orange" : "blue")};'><strong>{alert.Severity}</strong></td>
                <td>{alert.Category}</td>
                <td>{System.Net.WebUtility.HtmlEncode(alert.Message)}</td>
                <td><strong>{d.ChannelType}</strong></td>
                <td>{System.Net.WebUtility.HtmlEncode(d.Destination)}</td>
                <td><span style='color: {(d.Success ? "green" : "red")};'>{(d.Success ? "✅ Success" : "❌ Failed")}</span>{(d.ErrorMessage != null ? $"<br><small>{System.Net.WebUtility.HtmlEncode(d.ErrorMessage)}</small>" : "")}</td>
            </tr>");
                }
                else
                {
                    // No distribution recorded - create single row
                    return new[] { $@"
            <tr>
                <td>{alert.Timestamp:yyyy-MM-dd HH:mm:ss}</td>
                <td style='color: {(alert.Severity == AlertSeverity.Critical ? "red" : alert.Severity == AlertSeverity.Warning ? "orange" : "blue")};'><strong>{alert.Severity}</strong></td>
                <td>{alert.Category}</td>
                <td>{System.Net.WebUtility.HtmlEncode(alert.Message)}</td>
                <td colspan='3'><em>No distribution recorded</em></td>
            </tr>" };
                }
            }))}
        </table>" : "<p><em>No alerts recorded yet</em></p>")}
    </div>
</body>
</html>";
    }

    /// <summary>
    /// Public API to get current snapshot (reads cached states only)
    /// </summary>
    public SystemSnapshot GetCurrentSnapshot()
    {
        return CollectFullSnapshot();
    }
    
    /// <summary>
    /// Starts the self-monitoring timer to check process memory usage
    /// </summary>
    private void StartSelfMonitoringTimer()
    {
        var settings = _config.CurrentValue.SelfMonitoring;
        
        if (!settings.Enabled)
        {
            _logger.LogInformation("Self-monitoring is disabled");
            return;
        }
        
        // Self-monitoring is NOT subject to scaling - memory checks must always run at full frequency
        var intervalSeconds = settings.CheckIntervalSeconds;
        var thresholdMB = settings.MemoryThresholdMB;
        
        _selfMonitoringTimer = new Timer(
            _ => CheckProcessMemory(),
            null,
            TimeSpan.FromSeconds(intervalSeconds),
            TimeSpan.FromSeconds(intervalSeconds));
        
        _logger.LogInformation("Started self-monitoring timer (interval: {Interval}s, threshold: {Threshold} MB) - NOT subject to performance scaling",
            intervalSeconds, thresholdMB);
    }
    
    /// <summary>
    /// Checks process memory usage and triggers shutdown if threshold is exceeded
    /// </summary>
    private void CheckProcessMemory()
    {
        try
        {
            var settings = _config.CurrentValue.SelfMonitoring;
            if (!settings.Enabled) return;
            
            using var process = Process.GetCurrentProcess();
            var memoryMB = process.WorkingSet64 / (1024.0 * 1024.0);
            var thresholdMB = settings.MemoryThresholdMB;
            
            // Hard kill at 2x threshold (e.g. 6 GB) - no delay, no alert, just exit
            if (memoryMB > thresholdMB * 2)
            {
                _logger.LogCritical("🛑 HARD MEMORY LIMIT: {Memory:N0} MB exceeds 2x threshold ({HardLimit:N0} MB) - IMMEDIATE EXIT",
                    memoryMB, thresholdMB * 2);
                IsMemoryShutdown = true;
                // Delete persisted snapshot before hard exit so restart begins fresh
                _globalSnapshot.DeletePersistedSnapshot();
                Environment.Exit(99);
                return;
            }
            
            if (memoryMB > thresholdMB)
            {
                _logger.LogWarning("⚠️ MEMORY THRESHOLD EXCEEDED: {Memory:N0} MB > {Threshold:N0} MB - Attempting GC recovery first",
                    memoryMB, thresholdMB);
                
                // Attempt aggressive GC before deciding to shut down
                GC.Collect(2, GCCollectionMode.Aggressive, true, true);
                GC.WaitForPendingFinalizers();
                GC.Collect(2, GCCollectionMode.Aggressive, true, true);
                
                process.Refresh();
                var memoryAfterGcMB = process.WorkingSet64 / (1024.0 * 1024.0);
                _logger.LogWarning("⚠️ Memory after GC: {Memory:N0} MB (was {Before:N0} MB, freed {Freed:N0} MB)",
                    memoryAfterGcMB, memoryMB, memoryMB - memoryAfterGcMB);
                
                // If GC recovered enough, don't shut down
                if (memoryAfterGcMB <= thresholdMB * 0.8)
                {
                    _logger.LogInformation("✅ GC recovered below 80% of threshold ({Limit:N0} MB) - continuing normally",
                        thresholdMB * 0.8);
                    return;
                }
                
                var alert = new Alert
                {
                    Severity = Enum.Parse<AlertSeverity>(settings.MemoryAlertSeverity, true),
                    Category = "System/SelfMonitoring",
                    Message = $"ServerMonitor.exe memory usage exceeded threshold ({memoryAfterGcMB:N0} MB > {thresholdMB} MB after GC)",
                    Details = $"Memory before GC: {memoryMB:N1} MB | After GC: {memoryAfterGcMB:N1} MB | Threshold: {thresholdMB} MB | " +
                              $"Shutdown in {settings.ShutdownDelaySeconds} seconds | " +
                              "GC could not reclaim enough memory. Possible causes: unbounded diag entry storage, large RawBlock strings.",
                    Timestamp = DateTime.UtcNow,
                    Metadata = new Dictionary<string, object>
                    {
                        ["ProcessMemoryMB"] = memoryAfterGcMB,
                        ["MemoryBeforeGcMB"] = memoryMB,
                        ["ThresholdMB"] = thresholdMB,
                        ["ShutdownDelaySeconds"] = settings.ShutdownDelaySeconds,
                        ["MachineName"] = Environment.MachineName
                    }
                };
                
                try
                {
                    _alertManager.ProcessAlertsSync(new[] { alert });
                    _logger.LogInformation("Memory threshold alert sent successfully");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to send memory threshold alert");
                }
                
                _logger.LogWarning("⚠️ Scheduling graceful shutdown in {Seconds} seconds...", settings.ShutdownDelaySeconds);
                IsMemoryShutdown = true;
                
                Task.Run(async () =>
                {
                    await Task.Delay(TimeSpan.FromSeconds(settings.ShutdownDelaySeconds));
                    
                    _logger.LogWarning("⚠️ Initiating graceful shutdown now due to memory threshold");
                    
                    if (_shutdownCallback != null)
                    {
                        _shutdownCallback();
                    }
                    else
                    {
                        Environment.Exit(1);
                    }
                });
                
                _selfMonitoringTimer?.Dispose();
                _selfMonitoringTimer = null;
            }
            else
            {
                _logger.LogDebug("Self-monitoring: {Memory:N0} MB used (threshold: {Threshold} MB)",
                    memoryMB, thresholdMB);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in self-monitoring memory check");
        }
    }
}

