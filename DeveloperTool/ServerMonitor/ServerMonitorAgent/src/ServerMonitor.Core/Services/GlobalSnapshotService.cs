using ServerMonitor.Core.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Utilities;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Maintains a global, always-available system snapshot that's initialized at startup
/// and continuously updated by monitors
/// </summary>
public class GlobalSnapshotService
{
    private readonly ILogger<GlobalSnapshotService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly object _lock = new();
    private SystemSnapshot _currentSnapshot;

    public GlobalSnapshotService(
        ILogger<GlobalSnapshotService> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;
        
        // Initialize with default data immediately
        _currentSnapshot = CreateInitialSnapshot();
        
        // Subscribe to configuration changes to update context
        _config.OnChange(newConfig =>
        {
            UpdateConfigurationContext();
        });
        
        _logger.LogInformation("Global snapshot initialized: ServerName={ServerName}, BootTime={BootTime}",
            _currentSnapshot.Metadata.ServerName,
            _currentSnapshot.Uptime?.LastBootTime);
    }

    /// <summary>
    /// Creates initial snapshot with default system data (uptime, servername, etc.)
    /// </summary>
    private SystemSnapshot CreateInitialSnapshot()
    {
        var snapshot = new SystemSnapshot
        {
            Metadata = new SnapshotMetadata
            {
                ServerName = Environment.MachineName,
                Timestamp = DateTime.UtcNow,
                ToolVersion = GetAssemblyVersion()
            }
        };

        // Initialize with basic uptime data (always available)
        try
        {
            var uptimeMs = Environment.TickCount64;
            var bootTime = DateTime.UtcNow.AddMilliseconds(-uptimeMs);
            
            snapshot.Uptime = new UptimeData
            {
                LastBootTime = bootTime,
                CurrentUptimeDays = uptimeMs / (1000.0 * 60 * 60 * 24),
                UnexpectedReboot = false
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to initialize uptime data");
        }

        // Populate configuration context
        snapshot.Metadata.Configuration = CreateConfigurationContext();
        
        _logger.LogInformation("Created initial snapshot with default data");
        return snapshot;
    }

    private static string ConvertToUncPath(string localPath)
        => PathHelper.ToUncPath(localPath);

    /// <summary>
    /// Creates configuration context from current configuration
    /// </summary>
    private ConfigurationContext CreateConfigurationContext()
    {
        var config = _config.CurrentValue;
        var exportSettings = config.ExportSettings;
        
        // Get output directories
        var outputDirs = new List<string>();
        if (!string.IsNullOrEmpty(exportSettings.OutputDirectory))
        {
            outputDirs.Add(exportSettings.OutputDirectory);
        }
        if (exportSettings.OutputDirectories != null)
        {
            outputDirs.AddRange(exportSettings.OutputDirectories);
        }
        
        // Get alert log path (from FileAlertChannel)
        var alertLogPath = Path.Combine(
            config.Logging.LogDirectory,
            $"{config.Logging.AppName}_Alerts_{{date}}.log".Replace("{date}", DateTime.Now.ToString("yyyyMMdd")));
        
        // Safely get current snapshot disk data (may be null during initialization)
        List<DiskSpaceData>? currentSpaceData = null;
        List<DiskUsageData>? currentUsageData = null;
        lock (_lock)
        {
            if (_currentSnapshot != null)
            {
                currentSpaceData = _currentSnapshot.Disks?.Space;
                currentUsageData = _currentSnapshot.Disks?.Usage;
            }
        }
        
        // Convert paths to UNC versions
        var logDirectoryUnc = ConvertToUncPath(config.Logging.LogDirectory);
        var alertLogPathUnc = ConvertToUncPath(alertLogPath);
        var outputDirsUnc = outputDirs.Select(ConvertToUncPath).Distinct().ToList();
        
        return new ConfigurationContext
        {
            LogDirectory = config.Logging.LogDirectory,
            LogDirectoryUnc = logDirectoryUnc,
            AppName = config.Logging.AppName,
            SnapshotOutputDirectories = outputDirs.Distinct().ToList(),
            SnapshotOutputDirectoriesUnc = outputDirsUnc,
            SnapshotFileNamePattern = exportSettings.FileNamePattern,
            AlertLogPath = alertLogPath,
            AlertLogPathUnc = alertLogPathUnc,
            ProcessorMonitoring = new MonitorConfigContext
            {
                Enabled = config.ProcessorMonitoring.Enabled,
                PollingIntervalSeconds = config.ProcessorMonitoring.PollingIntervalSeconds,
                WarningPercent = config.ProcessorMonitoring.Thresholds.WarningPercent,
                CriticalPercent = config.ProcessorMonitoring.Thresholds.CriticalPercent,
                SustainedDurationSeconds = config.ProcessorMonitoring.Thresholds.SustainedDurationSeconds,
                TrackTopProcesses = config.ProcessorMonitoring.TrackTopProcesses,
                ProcessCacheRefreshSeconds = config.ProcessorMonitoring.ProcessCacheRefreshSeconds,
                ServiceMapRefreshMinutes = config.ProcessorMonitoring.ServiceMapRefreshMinutes,
                EnhancedProcessMetadata = config.ProcessorMonitoring.EnhancedProcessMetadata
            },
            MemoryMonitoring = new MonitorConfigContext
            {
                Enabled = config.MemoryMonitoring.Enabled,
                PollingIntervalSeconds = config.MemoryMonitoring.PollingIntervalSeconds,
                WarningPercent = config.MemoryMonitoring.Thresholds.WarningPercent,
                CriticalPercent = config.MemoryMonitoring.Thresholds.CriticalPercent,
                SustainedDurationSeconds = config.MemoryMonitoring.Thresholds.SustainedDurationSeconds,
                TrackTopProcesses = config.MemoryMonitoring.TrackTopProcesses,
                ProcessCacheRefreshSeconds = config.MemoryMonitoring.ProcessCacheRefreshSeconds,
                ServiceMapRefreshMinutes = config.MemoryMonitoring.ServiceMapRefreshMinutes,
                EnhancedProcessMetadata = config.MemoryMonitoring.EnhancedProcessMetadata
            },
            VirtualMemoryMonitoring = new VirtualMemoryConfigContext
            {
                Enabled = config.VirtualMemoryMonitoring.Enabled,
                PollingIntervalSeconds = config.VirtualMemoryMonitoring.PollingIntervalSeconds,
                WarningPercent = config.VirtualMemoryMonitoring.Thresholds.WarningPercent,
                CriticalPercent = config.VirtualMemoryMonitoring.Thresholds.CriticalPercent,
                SustainedDurationSeconds = config.VirtualMemoryMonitoring.Thresholds.SustainedDurationSeconds,
                ExcessivePagingRate = config.VirtualMemoryMonitoring.Thresholds.ExcessivePagingRate
            },
            DiskSpaceMonitoring = new DiskSpaceConfigContext
            {
                Enabled = config.DiskSpaceMonitoring.Enabled,
                PollingIntervalSeconds = config.DiskSpaceMonitoring.PollingIntervalSeconds,
                // Show actual detected drives if "*" was used, otherwise show config value
                DisksToMonitor = GetActualDetectedDrives(config.DiskSpaceMonitoring.DisksToMonitor, currentSpaceData),
                WarningPercent = config.DiskSpaceMonitoring.Thresholds.WarningPercent,
                CriticalPercent = config.DiskSpaceMonitoring.Thresholds.CriticalPercent,
                MinimumFreeSpaceGB = config.DiskSpaceMonitoring.Thresholds.MinimumFreeSpaceGB
            },
            DiskUsageMonitoring = new DiskUsageConfigContext
            {
                Enabled = config.DiskUsageMonitoring.Enabled,
                PollingIntervalSeconds = config.DiskUsageMonitoring.PollingIntervalSeconds,
                // Show actual detected drives if "*" was used, otherwise show config value
                DisksToMonitor = GetActualDetectedDrives(config.DiskUsageMonitoring.DisksToMonitor, currentUsageData),
                MaxQueueLength = config.DiskUsageMonitoring.Thresholds.MaxQueueLength,
                MaxResponseTimeMs = config.DiskUsageMonitoring.Thresholds.MaxResponseTimeMs,
                SustainedDurationSeconds = config.DiskUsageMonitoring.Thresholds.SustainedDurationSeconds
            },
            WindowsUpdateMonitoring = new WindowsUpdateConfigContext
            {
                Enabled = config.WindowsUpdateMonitoring.Enabled,
                PollingIntervalSeconds = config.WindowsUpdateMonitoring.PollingIntervalSeconds,
                MaxPendingSecurityUpdates = config.WindowsUpdateMonitoring.Thresholds.MaxPendingSecurityUpdates,
                MaxPendingCriticalUpdates = config.WindowsUpdateMonitoring.Thresholds.MaxPendingCriticalUpdates,
                MaxDaysSinceLastUpdate = config.WindowsUpdateMonitoring.Thresholds.MaxDaysSinceLastUpdate,
                AlertOnPendingSecurityUpdates = config.WindowsUpdateMonitoring.Alerts.AlertOnPendingSecurityUpdates
            },
            ExportSettings = new ExportConfigContext
            {
                Enabled = exportSettings.Enabled,
                IntervalMinutes = exportSettings.ExportIntervals.IntervalMinutes,
                OnAlertTrigger = exportSettings.ExportIntervals.OnAlertTrigger,
                OnDemand = exportSettings.ExportIntervals.OnDemand,
                MaxAgeHours = exportSettings.Retention.MaxAgeHours,
                MaxFileCount = exportSettings.Retention.MaxFileCount,
                CompressionEnabled = exportSettings.Retention.CompressionEnabled
            },
            Alerting = new AlertingConfigContext
            {
                Enabled = config.Alerting.Enabled,
                MaxAlertsPerHour = config.Alerting.Throttling.MaxAlertsPerHour,
                WarningSuppressionMinutes = config.Alerting.Throttling.WarningSuppressionMinutes,
                ErrorSuppressionMinutes = config.Alerting.Throttling.ErrorSuppressionMinutes,
                InformationalSuppressionMinutes = config.Alerting.Throttling.InformationalSuppressionMinutes,
                EnabledChannels = config.Alerting.Channels
                    .Where(c => c.Enabled)
                    .Select(c => c.Type)
                    .ToList()
            },
            RestApi = config.RestApi != null ? new RestApiConfigContext
            {
                Enabled = config.RestApi.Enabled,
                Port = config.RestApi.Port,
                EnableSwagger = config.RestApi.EnableSwagger
            } : null
        };
    }

    /// <summary>
    /// Gets actual detected drives from snapshot data, or returns config value if not auto-detected
    /// </summary>
    private List<string> GetActualDetectedDrives(List<string> configDisksToMonitor, List<DiskSpaceData>? snapshotSpaceData)
    {
        // If config uses "*" or is empty, get actual detected drives from snapshot
        bool isAutoDetect = configDisksToMonitor == null || 
                           configDisksToMonitor.Count == 0 || 
                           (configDisksToMonitor.Count == 1 && configDisksToMonitor[0] == "*");
        
        if (isAutoDetect && snapshotSpaceData != null && snapshotSpaceData.Count > 0)
        {
            // Return actual detected drives from snapshot
            return snapshotSpaceData.Select(d => d.Drive).Distinct().ToList();
        }
        
        // Return config value (may be specific drives or ["*"])
        // If auto-detect but no data yet, return ["*"] to indicate auto-detect mode
        return configDisksToMonitor ?? new List<string>();
    }

    /// <summary>
    /// Gets actual detected drives from snapshot usage data, or returns config value if not auto-detected
    /// </summary>
    private List<string> GetActualDetectedDrives(List<string> configDisksToMonitor, List<DiskUsageData>? snapshotUsageData)
    {
        // If config uses "*" or is empty, get actual detected drives from snapshot
        bool isAutoDetect = configDisksToMonitor == null || 
                           configDisksToMonitor.Count == 0 || 
                           (configDisksToMonitor.Count == 1 && configDisksToMonitor[0] == "*");
        
        if (isAutoDetect && snapshotUsageData != null && snapshotUsageData.Count > 0)
        {
            // Return actual detected drives from snapshot
            return snapshotUsageData.Select(d => d.Drive).Distinct().ToList();
        }
        
        // Return config value (may be specific drives or ["*"])
        // If auto-detect but no data yet, return ["*"] to indicate auto-detect mode
        return configDisksToMonitor ?? new List<string>();
    }

    /// <summary>
    /// Updates configuration context when config changes
    /// </summary>
    private void UpdateConfigurationContext()
    {
        lock (_lock)
        {
            _currentSnapshot.Metadata.Configuration = CreateConfigurationContext();
            TouchTimestamp();
            _logger.LogDebug("Updated configuration context in snapshot");
        }
    }

    /// <summary>
    /// Gets current snapshot (thread-safe, never null)
    /// Returns a fresh copy with current timestamp
    /// </summary>
    public SystemSnapshot GetCurrentSnapshot()
    {
        lock (_lock)
        {
            // Always return current timestamp - snapshot is "now"
            _currentSnapshot.Metadata.Timestamp = DateTime.UtcNow;
            
            // Update self-monitoring info
            UpdateSelfMonitoringInfo();
            
            return _currentSnapshot;
        }
    }
    
    /// <summary>
    /// Updates self-monitoring information (process memory usage)
    /// </summary>
    private void UpdateSelfMonitoringInfo()
    {
        try
        {
            using var process = System.Diagnostics.Process.GetCurrentProcess();
            _currentSnapshot.Metadata.ProcessMemoryMB = process.WorkingSet64 / (1024.0 * 1024.0);
            _currentSnapshot.Metadata.SnapshotSizeMB = EstimateSnapshotSizeMB();
            _currentSnapshot.Metadata.LogFileUncPath = GetLogFileUncPath();
        }
        catch
        {
            // Ignore errors in self-monitoring
        }
    }
    
    /// <summary>
    /// Gets the current log file path as UNC path
    /// </summary>
    private string GetLogFileUncPath()
    {
        try
        {
            var logging = _config.CurrentValue.Logging;
            var machineNameLower = Environment.MachineName.ToLowerInvariant();
            var logFileName = $"{logging.AppName}_{machineNameLower}_{DateTime.Now:yyyy-MM-dd}.log";
            var localPath = Path.Combine(logging.LogDirectory, logFileName);

            return PathHelper.ToUncPath(localPath);
        }
        catch
        {
            return "";
        }
    }
    
    /// <summary>
    /// Estimates the size of the in-memory snapshot in MB
    /// </summary>
    private double EstimateSnapshotSizeMB()
    {
        // Rough estimation based on object counts and typical sizes
        var alertSize = (_currentSnapshot.Alerts?.Count ?? 0) * 2.0; // ~2KB per alert
        var eventSize = (_currentSnapshot.ExternalEvents?.Count ?? 0) * 0.5; // ~0.5KB per event
        var db2Size = (_currentSnapshot.Db2Diagnostics?.AllEntries?.Count ?? 0) * 5.0; // ~5KB per DB2 entry
        
        return (alertSize + eventSize + db2Size) / 1024.0; // Convert KB to MB
    }
    
    /// <summary>
    /// Returns snapshot size information for API
    /// </summary>
    public SnapshotSizeInfo GetSnapshotSizeInfo()
    {
        lock (_lock)
        {
            return new SnapshotSizeInfo
            {
                EstimatedSizeMB = EstimateSnapshotSizeMB(),
                AlertCount = _currentSnapshot.Alerts?.Count ?? 0,
                EventCount = _currentSnapshot.ExternalEvents?.Count ?? 0,
                Db2DiagEntryCount = _currentSnapshot.Db2Diagnostics?.AllEntries?.Count ?? 0
            };
        }
    }

    /// <summary>
    /// Updates metadata timestamp (called on every data change)
    /// </summary>
    private void TouchTimestamp()
    {
        _currentSnapshot.Metadata.Timestamp = DateTime.UtcNow;
    }

    /// <summary>
    /// Updates processor data
    /// </summary>
    public void UpdateProcessor(ProcessorData data)
    {
        lock (_lock)
        {
            _currentSnapshot.Processor = data;
            TouchTimestamp();
            _logger.LogDebug("Updated processor data: {CPU}%", data.OverallUsagePercent);
        }
    }

    /// <summary>
    /// Updates memory data
    /// </summary>
    public void UpdateMemory(MemoryData data)
    {
        lock (_lock)
        {
            _currentSnapshot.Memory = data;
            TouchTimestamp();
            _logger.LogDebug("Updated memory data: {Usage}%", data.UsedPercent);
        }
    }

    /// <summary>
    /// Updates virtual memory data
    /// </summary>
    public void UpdateVirtualMemory(VirtualMemoryData data)
    {
        lock (_lock)
        {
            _currentSnapshot.VirtualMemory = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Updates disk data
    /// </summary>
    public void UpdateDisk(DiskData data)
    {
        lock (_lock)
        {
            _currentSnapshot.Disks = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Updates network data
    /// </summary>
    public void UpdateNetwork(List<NetworkHostData> data)
    {
        lock (_lock)
        {
            _currentSnapshot.Network = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Updates uptime data
    /// </summary>
    public void UpdateUptime(UptimeData data)
    {
        lock (_lock)
        {
            _currentSnapshot.Uptime = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Updates Windows Update data
    /// </summary>
    public void UpdateWindowsUpdates(WindowsUpdateData data)
    {
        lock (_lock)
        {
            _currentSnapshot.WindowsUpdates = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Updates event log data (full list replacement - used by polling)
    /// </summary>
    public void UpdateEvents(List<EventData> data)
    {
        lock (_lock)
        {
            _currentSnapshot.Events = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Updates a single event's data (used by real-time EventLogWatcher)
    /// </summary>
    public void UpdateEventData(int eventId, EventData data)
    {
        lock (_lock)
        {
            _currentSnapshot.Events ??= new List<EventData>();
            
            // Find existing entry for this event ID
            var existingIndex = _currentSnapshot.Events.FindIndex(e => e.EventId == eventId);
            
            if (existingIndex >= 0)
            {
                // Update existing entry
                _currentSnapshot.Events[existingIndex] = data;
            }
            else
            {
                // Add new entry
                _currentSnapshot.Events.Add(data);
            }
            
            TouchTimestamp();
            _logger.LogDebug("Updated event data for EventID {EventId}: Count={Count}", eventId, data.Count);
        }
    }

    /// <summary>
    /// Updates scheduled task data
    /// </summary>
    public void UpdateScheduledTasks(List<ScheduledTaskData> data)
    {
        lock (_lock)
        {
            _currentSnapshot.ScheduledTasks = data;
            TouchTimestamp();
        }
    }

    public void UpdateDb2Diagnostics(Db2DiagData data)
    {
        lock (_lock)
        {
            _currentSnapshot.Db2Diagnostics = data;
            TouchTimestamp();
        }
    }
    
    public void UpdateDb2Instance(Db2InstanceSnapshot data)
    {
        lock (_lock)
        {
            _currentSnapshot.Db2Instance = data;
            TouchTimestamp();
        }
    }

    public void UpdateIis(IisSnapshot data)
    {
        lock (_lock)
        {
            _currentSnapshot.Iis = data;
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Adds an alert to the global history (distribution handled separately by caller)
    /// </summary>
    /// <summary>
    /// Adds an external event to the snapshot and cleans up old events to prevent memory leaks
    /// </summary>
    public void AddExternalEvent(ExternalEvent externalEvent)
    {
        lock (_lock)
        {
            // Add the new event first
            _currentSnapshot.ExternalEvents.Add(externalEvent);
            
            // Clean up old events AFTER adding to prevent memory leak
            // Strategy: Use RegisteredTimestamp (when event was added) for cleanup, not Timestamp (when event occurred)
            // This ensures historical events from log files are preserved when first added,
            // but cleaned up after 24 hours based on when they were registered
            var maxRetentionWindow = TimeSpan.FromHours(24);
            var registeredCutoff = DateTime.UtcNow - maxRetentionWindow;
            
            // Clean up events that were registered more than 24 hours ago
            // This uses RegisteredTimestamp (when added) not Timestamp (when occurred)
            var removedCount = _currentSnapshot.ExternalEvents.RemoveAll(e => e.RegisteredTimestamp < registeredCutoff);
            
            if (removedCount > 0)
            {
                _logger.LogDebug("Cleaned up {Count} old external events (registered more than {Hours} hours ago)", 
                    removedCount, maxRetentionWindow.TotalHours);
            }
            _logger.LogDebug("External event added: {EventCode} - {Message} | Alert Time: {AlertTime:yyyy-MM-dd HH:mm:ss} UTC | Registered: {RegisteredTime:yyyy-MM-dd HH:mm:ss} UTC (Total: {Count})", 
                externalEvent.ExternalEventCode, externalEvent.Message, externalEvent.AlertTimestamp, externalEvent.RegisteredTimestamp, _currentSnapshot.ExternalEvents.Count);
        }
    }

    public void AddAlert(Alert alert)
    {
        lock (_lock)
        {
            _currentSnapshot.Alerts.Add(alert);
            
            // Clean up old alerts to prevent memory leak
            CleanupOldAlerts();
            
            TouchTimestamp();
            _logger.LogInformation("Alert added to global snapshot: [{Severity}] {Category}: {Message} (ID: {Id}, Total: {Count})", 
                alert.Severity, alert.Category, alert.Message, alert.Id, _currentSnapshot.Alerts.Count);
        }
    }
    
    /// <summary>
    /// Cleans up old alerts based on configured retention settings.
    /// Removes alerts older than CleanupAgeHours and trims to MaxAlertsInMemory.
    /// </summary>
    private void CleanupOldAlerts()
    {
        var memSettings = _config.CurrentValue.General.MemoryManagement;
        var cleanupAgeHours = memSettings.CleanupAgeHours;
        var maxAlerts = memSettings.MaxAlertsInMemory;
        
        // Remove alerts older than cleanup age
        var cutoffTime = DateTime.UtcNow.AddHours(-cleanupAgeHours);
        var removedByAge = _currentSnapshot.Alerts.RemoveAll(a => a.Timestamp < cutoffTime);
        
        if (removedByAge > 0)
        {
            _logger.LogDebug("Cleaned up {Count} old alerts (older than {Hours} hours)", 
                removedByAge, cleanupAgeHours);
        }
        
        // Also enforce max count (remove oldest first)
        if (maxAlerts > 0 && _currentSnapshot.Alerts.Count > maxAlerts)
        {
            // Sort by timestamp ascending (oldest first) and remove excess
            var sorted = _currentSnapshot.Alerts.OrderBy(a => a.Timestamp).ToList();
            var excess = sorted.Count - maxAlerts;
            var toRemove = sorted.Take(excess).Select(a => a.Id).ToHashSet();
            
            var removedByCount = _currentSnapshot.Alerts.RemoveAll(a => toRemove.Contains(a.Id));
            
            _logger.LogDebug("Trimmed {Count} alerts to stay within MaxAlertsInMemory ({Max})", 
                removedByCount, maxAlerts);
        }
    }
    
    /// <summary>
    /// Runs periodic cleanup of all in-memory collections.
    /// Should be called on a timer (e.g., every hour).
    /// </summary>
    public void RunPeriodicCleanup()
    {
        lock (_lock)
        {
            var memSettings = _config.CurrentValue.General.MemoryManagement;
            var cleanupAgeHours = memSettings.CleanupAgeHours;
            var cutoffTime = DateTime.UtcNow.AddHours(-cleanupAgeHours);
            
            // Cleanup alerts
            var alertsRemoved = _currentSnapshot.Alerts.RemoveAll(a => a.Timestamp < cutoffTime);
            
            // Cleanup external events (already has its own cleanup, but enforce consistency)
            var eventsRemoved = _currentSnapshot.ExternalEvents.RemoveAll(e => e.RegisteredTimestamp < cutoffTime);
            
            if (alertsRemoved > 0 || eventsRemoved > 0)
            {
                _logger.LogInformation("Periodic memory cleanup: removed {Alerts} alerts, {Events} external events (older than {Hours}h)",
                    alertsRemoved, eventsRemoved, cleanupAgeHours);
            }
            
            // Memory tracking - log current collection sizes and memory usage
            var gcMemory = GC.GetTotalMemory(false);
            var db2EntriesCount = _currentSnapshot.Db2Diagnostics?.AllEntries?.Count ?? 0;
            _logger.LogDebug("GlobalSnapshot memory state: Alerts={Alerts}, ExternalEvents={Events}, Db2Entries={Db2}, GC Memory={MemMB:N1} MB",
                _currentSnapshot.Alerts.Count, _currentSnapshot.ExternalEvents.Count, db2EntriesCount, gcMemory / (1024.0 * 1024.0));
            
            TouchTimestamp();
        }
    }

    /// <summary>
    /// Records that an alert was distributed to a channel
    /// </summary>
    public void RecordAlertDistribution(Guid alertId, string channelType, string destination, bool success, string? errorMessage = null)
    {
        lock (_lock)
        {
            var alert = _currentSnapshot.Alerts.FirstOrDefault(a => a.Id == alertId);
            if (alert != null)
            {
                alert.DistributionHistory.Add(new AlertDistribution
                {
                    ChannelType = channelType,
                    Timestamp = DateTime.UtcNow,  // Absolute timestamp - not duration
                    Destination = destination,
                    Success = success,
                    ErrorMessage = errorMessage
                });

                TouchTimestamp();  // Update global snapshot timestamp
                
                _logger.LogDebug("Recorded distribution: Alert={AlertId}, Channel={Channel}, Destination={Dest}, Success={Success}",
                    alertId, channelType, destination, success);
            }
            else
            {
                _logger.LogWarning("Cannot record distribution: Alert {AlertId} not found in global history", alertId);
            }
        }
    }

    /// <summary>
    /// Clears all alerts from the current snapshot.
    /// Used during scheduled data flush operations.
    /// </summary>
    /// <returns>Number of alerts that were cleared</returns>
    public int ClearAlerts()
    {
        lock (_lock)
        {
            var count = _currentSnapshot.Alerts.Count;
            _currentSnapshot.Alerts.Clear();
            TouchTimestamp();
            return count;
        }
    }
    
    /// <summary>
    /// Gets the actual assembly version from the entry assembly
    /// </summary>
    private static string GetAssemblyVersion()
    {
        try
        {
            var assembly = System.Reflection.Assembly.GetEntryAssembly() 
                        ?? System.Reflection.Assembly.GetExecutingAssembly();
            
            // Try to get InformationalVersion first (most accurate)
            var infoVersionAttr = System.Reflection.CustomAttributeExtensions
                .GetCustomAttribute<System.Reflection.AssemblyInformationalVersionAttribute>(assembly);
            
            if (infoVersionAttr != null && !string.IsNullOrEmpty(infoVersionAttr.InformationalVersion))
            {
                var infoVersion = infoVersionAttr.InformationalVersion;
                // Remove any +metadata suffix (e.g., "1.0.42+abc123" -> "1.0.42")
                var plusIndex = infoVersion.IndexOf('+');
                return plusIndex > 0 ? infoVersion[..plusIndex] : infoVersion;
            }
            
            // Fall back to file version or assembly version
            var version = assembly.GetName().Version;
            return version?.ToString() ?? "1.0.0";
        }
        catch
        {
            return "1.0.0";
        }
    }

    /// <summary>
    /// Clears the in-memory snapshot (resets to initial state) and deletes any persisted snapshot file.
    /// Used by admins via the dashboard when the agent's memory is out of control.
    /// </summary>
    public void ClearSnapshot()
    {
        lock (_lock)
        {
            var serverName = _currentSnapshot.Metadata.ServerName;
            _currentSnapshot = CreateInitialSnapshot();
            _logger.LogWarning("🗑️ Snapshot cleared by admin request. Server: {Server}. All accumulated data has been reset.", serverName);
        }
        
        DeletePersistedSnapshot();
        
        // Force GC to reclaim memory from the old snapshot
        GC.Collect(2, GCCollectionMode.Aggressive, true, true);
        GC.WaitForPendingFinalizers();
        GC.Collect(2, GCCollectionMode.Aggressive, true, true);
        
        var memAfterMb = System.Diagnostics.Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
        _logger.LogInformation("🗑️ Post-clear memory: {MemMB:N0} MB", memAfterMb);
    }

    #region Snapshot Persistence
    
    private const string PersistedSnapshotFileName = "persisted_snapshot.json";
    
    /// <summary>
    /// Gets the path to the persisted snapshot file (same folder as exe)
    /// </summary>
    private static string GetPersistedSnapshotPath()
    {
        var basePath = AppContext.BaseDirectory;
        return Path.Combine(basePath, PersistedSnapshotFileName);
    }
    
    /// <summary>
    /// Saves the current snapshot to disk. Called when the agent is stopping.
    /// </summary>
    public void SaveSnapshotToDisk()
    {
        try
        {
            var path = GetPersistedSnapshotPath();
            
            lock (_lock)
            {
                // Update timestamp before saving
                _currentSnapshot.Metadata.Timestamp = DateTime.UtcNow;
                _currentSnapshot.Metadata.PersistedAt = DateTime.UtcNow;
                
                var options = new System.Text.Json.JsonSerializerOptions
                {
                    WriteIndented = true,
                    PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
                };
                options.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
                
                var json = System.Text.Json.JsonSerializer.Serialize(_currentSnapshot, options);
                File.WriteAllText(path, json);
            }
            
            _logger.LogInformation("💾 Snapshot persisted to disk: {Path}", path);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to persist snapshot to disk");
        }
    }
    
    /// <summary>
    /// Tries to load a persisted snapshot from disk. Called at startup.
    /// Returns true if snapshot was loaded, false otherwise.
    /// Handles version changes gracefully by mapping what can be mapped from old snapshots.
    /// </summary>
    public bool TryLoadSnapshotFromDisk()
    {
        var path = GetPersistedSnapshotPath();
        
        try
        {
            if (!File.Exists(path))
            {
                _logger.LogDebug("No persisted snapshot found at {Path} (normal after reinstall)", path);
                return false;
            }
            
            var json = File.ReadAllText(path);
            
            var options = new System.Text.Json.JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                // Handle unknown properties gracefully (new version might have removed fields)
                // This is the default behavior, but being explicit
            };
            options.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
            
            SystemSnapshot? loadedSnapshot = null;
            
            try
            {
                loadedSnapshot = System.Text.Json.JsonSerializer.Deserialize<SystemSnapshot>(json, options);
            }
            catch (System.Text.Json.JsonException jsonEx)
            {
                // Deserialization failed - likely due to schema changes between versions
                _logger.LogWarning("Persisted snapshot has incompatible schema (version change). Deleting and starting fresh. Error: {Error}", 
                    jsonEx.Message);
                DeletePersistedSnapshot();
                return false;
            }
            
            if (loadedSnapshot == null)
            {
                _logger.LogWarning("Failed to deserialize persisted snapshot (null result). Deleting and starting fresh.");
                DeletePersistedSnapshot();
                return false;
            }
            
            lock (_lock)
            {
                // Preserve metadata from current snapshot (version, servername)
                var currentMetadata = _currentSnapshot.Metadata;
                
                // Restore the loaded snapshot data - use null-coalescing to handle missing properties
                // This allows loading snapshots from older versions that might not have all fields
                _currentSnapshot.Alerts = loadedSnapshot.Alerts ?? new List<Alert>();
                _currentSnapshot.ExternalEvents = loadedSnapshot.ExternalEvents ?? new List<ExternalEvent>();
                _currentSnapshot.Events = loadedSnapshot.Events ?? new List<EventData>();
                _currentSnapshot.ScheduledTasks = loadedSnapshot.ScheduledTasks ?? new List<ScheduledTaskData>();
                
                // Restore monitoring data (may be stale but better than nothing)
                // Each can be null if the old snapshot didn't have it
                _currentSnapshot.Processor = loadedSnapshot.Processor;
                _currentSnapshot.Memory = loadedSnapshot.Memory;
                _currentSnapshot.VirtualMemory = loadedSnapshot.VirtualMemory;
                _currentSnapshot.Disks = loadedSnapshot.Disks;
                _currentSnapshot.Network = loadedSnapshot.Network;
                _currentSnapshot.Uptime = loadedSnapshot.Uptime;
                _currentSnapshot.WindowsUpdates = loadedSnapshot.WindowsUpdates;
                _currentSnapshot.Db2Diagnostics = loadedSnapshot.Db2Diagnostics;
                
                // Keep current metadata but note it was restored
                _currentSnapshot.Metadata = currentMetadata;
                _currentSnapshot.Metadata.RestoredFromPersistence = true;
                _currentSnapshot.Metadata.PersistedAt = loadedSnapshot.Metadata?.PersistedAt;
            }
            
            var age = DateTime.UtcNow - (loadedSnapshot.Metadata?.PersistedAt ?? DateTime.UtcNow);
            _logger.LogInformation("📂 Snapshot restored from disk (age: {Age:F1} minutes)", age.TotalMinutes);
            
            // Delete the file after successful load to avoid loading stale data next time
            // (new snapshot will be saved on next shutdown)
            DeletePersistedSnapshot();
            
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load persisted snapshot from disk (will start fresh)");
            // Try to delete the corrupt file
            DeletePersistedSnapshot();
            return false;
        }
    }
    
    /// <summary>
    /// Deletes the persisted snapshot file if it exists.
    /// Called during data flush operations and after loading.
    /// </summary>
    public void DeletePersistedSnapshot()
    {
        try
        {
            var path = GetPersistedSnapshotPath();
            if (File.Exists(path))
            {
                File.Delete(path);
                _logger.LogDebug("Deleted persisted snapshot file: {Path}", path);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete persisted snapshot file");
        }
    }
    
    #endregion
}

