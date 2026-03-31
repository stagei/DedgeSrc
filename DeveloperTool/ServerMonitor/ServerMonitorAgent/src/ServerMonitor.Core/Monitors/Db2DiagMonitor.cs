using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

// Static initializer to register code page encoding provider (needed for Windows-1252 in .NET Core+)
file static class Db2DiagEncodingInitializer
{
    static Db2DiagEncodingInitializer()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }
    
    public static void EnsureInitialized() { }
}

/// <summary>
/// Monitors IBM DB2 diagnostic log files for errors and warnings.
/// Only active on servers matching the ServerNamePattern regex (default: "-db$" for servers ending in "-db").
/// Supports pattern-based filtering, severity remapping, and SQL error logging.
/// </summary>
public partial class Db2DiagMonitor : IMonitor
{
    private readonly ILogger<Db2DiagMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly Db2DiagPatternMatcher _patternMatcher;
    private readonly Db2SqlErrorLogger _sqlErrorLogger;
    private MonitorResult? _currentState;
    private Db2DiagMessageMap? _messageMap;
    private bool _messageMapLoaded;
    private bool _patternMatcherInitialized;
    
    // In-memory storage for all entries (when KeepAllEntriesInMemory is enabled)
    private readonly List<Db2DiagEntry> _allEntries = new();
    private readonly object _entriesLock = new();
    
    // Per-instance db2diag.log file sizes (populated each collection cycle)
    private readonly Dictionary<string, long> _diagLogFileSizes = new(StringComparer.OrdinalIgnoreCase);
    
    // Statistics for pattern matching
    private int _entriesSkipped;
    private int _entriesLoggedOnly;
    private int _entriesRemapped;
    
    // Compiled regex patterns for performance
    private static readonly Regex HeaderPattern = new(
        @"^(\d{4}-\d{2}-\d{2}-\d{2}\.\d{2}\.\d{2}\.\d{6}[+-]\d{3})\s+(\S+)\s+LEVEL:\s*(\w+)",
        RegexOptions.Compiled);
    
    private static readonly Regex KeyValuePattern = new(
        @"(\w+)\s*:\s*([^\s].*?)(?=\s{2,}\w+\s*:|$)",
        RegexOptions.Compiled);
    
    private static readonly Regex Db2TimestampPattern = new(
        @"^(\d{4})-(\d{2})-(\d{2})-(\d{2})\.(\d{2})\.(\d{2})\.(\d{6})([+-])(\d{3})$",
        RegexOptions.Compiled);
    
    private static readonly Regex ZrcCodePattern = new(
        @"ZRC=(0x[0-9A-Fa-f]+)",
        RegexOptions.Compiled);
    
    private static readonly Regex ProbePattern = new(
        @"(\w+(?:::\w+)?),\s*probe:(\d+)",
        RegexOptions.Compiled);

    public string Category => "Db2Diag";
    
    public bool IsEnabled
    {
        get
        {
            var settings = _config.CurrentValue.Db2DiagMonitoring;
            if (!settings.Enabled) return false;
            
            // Only run on servers matching the configured pattern (default: ends with "-db")
            var computerName = Environment.MachineName;
            return settings.IsServerNameMatch(computerName);
        }
    }
    
    public MonitorResult? CurrentState => _currentState;

    public Db2DiagMonitor(
        ILogger<Db2DiagMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        Db2DiagPatternMatcher patternMatcher,
        Db2SqlErrorLogger sqlErrorLogger)
    {
        _logger = logger;
        _config = config;
        _patternMatcher = patternMatcher;
        _sqlErrorLogger = sqlErrorLogger;
    }

    public async Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default)
    {
        var totalStopwatch = Stopwatch.StartNew();
        var phaseStopwatch = new Stopwatch();
        var alerts = new List<Alert>();
        var db2Data = new Db2DiagData { LastCheck = DateTime.UtcNow };

        try
        {
            var computerName = Environment.MachineName;
            _logger.LogDebug("📊 DB2 Diag Monitor starting collection cycle on {Computer}", computerName);
            
            var settings = _config.CurrentValue.Db2DiagMonitoring;
            
            if (!settings.Enabled)
            {
                db2Data.IsActive = false;
                db2Data.InactiveReason = "Monitor is disabled";
                return CreateResult(db2Data, alerts, totalStopwatch);
            }
            
            if (!settings.IsServerNameMatch(computerName))
            {
                db2Data.IsActive = false;
                db2Data.InactiveReason = $"Server '{computerName}' does not match pattern '{settings.ServerNamePattern}'";
                _logger.LogDebug("DB2 Diag Monitor skipped: {Reason}", db2Data.InactiveReason);
                return CreateResult(db2Data, alerts, totalStopwatch);
            }

            db2Data.IsActive = true;
            
            // Phase 1: Load message map and initialize pattern matcher if not loaded
            phaseStopwatch.Restart();
            if (!_messageMapLoaded)
            {
                await LoadMessageMapAsync(cancellationToken).ConfigureAwait(false);
                _logger.LogDebug("📊 Phase 1a - Message Map Load: {Ms}ms", phaseStopwatch.ElapsedMilliseconds);
            }
            
            if (!_patternMatcherInitialized)
            {
                _patternMatcher.Initialize(settings.PatternsToMonitor);
                _patternMatcherInitialized = true;
                _logger.LogDebug("📊 Phase 1b - Pattern Matcher Init: {Count} patterns", settings.PatternsToMonitor.Count);
            }
            
            // Reset per-cycle statistics
            _entriesSkipped = 0;
            _entriesLoggedOnly = 0;
            _entriesRemapped = 0;
            
            // Phase 2: Find search directory
            phaseStopwatch.Restart();
            var searchDirectory = await GetSearchDirectoryAsync(settings, cancellationToken).ConfigureAwait(false);
            _logger.LogDebug("📊 Phase 2 - Find Search Directory: {Ms}ms | Path: {Path}", 
                phaseStopwatch.ElapsedMilliseconds, searchDirectory ?? "NOT FOUND");
            
            if (string.IsNullOrEmpty(searchDirectory))
            {
                db2Data.InactiveReason = "Could not find DB2 installation path";
                _logger.LogWarning("DB2 Diag Monitor: {Reason}", db2Data.InactiveReason);
                return CreateResult(db2Data, alerts, totalStopwatch);
            }
            
            // Phase 3: Find db2diag.log files
            phaseStopwatch.Restart();
            var diagFiles = FindDiagLogFiles(searchDirectory);
            _logger.LogDebug("📊 Phase 3 - Find Log Files: {Ms}ms | Found: {Count} file(s)", 
                phaseStopwatch.ElapsedMilliseconds, diagFiles.Count);
            
            if (diagFiles.Count == 0)
            {
                db2Data.InactiveReason = $"No db2diag.log files found in {searchDirectory}";
                _logger.LogDebug("DB2 Diag Monitor: {Reason}", db2Data.InactiveReason);
                return CreateResult(db2Data, alerts, totalStopwatch);
            }
            
            // Store per-instance file sizes for dashboard display
            _diagLogFileSizes.Clear();
            foreach (var df in diagFiles)
            {
                _logger.LogDebug("📊   - {Path} ({Size:N0} bytes)", df.FullName, df.Length);
                var inst = GetInstanceFromPath(df.DirectoryName ?? "");
                _diagLogFileSizes[inst] = df.Length;
            }
            
            // Phase 4: Process each log file
            var allEntries = new List<Db2DiagEntry>();
            var totalLinesProcessed = 0;
            var totalBlocksProcessed = 0;
            
            foreach (var diagFile in diagFiles)
            {
                if (cancellationToken.IsCancellationRequested) break;
                
                phaseStopwatch.Restart();
                var instanceName = GetInstanceFromPath(diagFile.DirectoryName ?? "");
                db2Data.Instances.Add(instanceName);
                
                // Inline memory safety check before processing each file
                var currentMemMb = Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
                if (currentMemMb > 2048)
                {
                    _logger.LogWarning("📊 MEMORY GUARD: Working set is {MemMB:N0} MB before processing {File} - forcing GC",
                        currentMemMb, diagFile.Name);
                    GC.Collect(2, GCCollectionMode.Aggressive, true, true);
                    GC.WaitForPendingFinalizers();
                    currentMemMb = Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
                    _logger.LogInformation("📊 MEMORY GUARD: After GC: {MemMB:N0} MB", currentMemMb);
                    
                    if (currentMemMb > 3072)
                    {
                        _logger.LogError("📊 MEMORY GUARD: Aborting file processing - working set {MemMB:N0} MB exceeds 3 GB safety limit", currentMemMb);
                        break;
                    }
                }
                
                // Check file size limit to prevent out-of-memory issues
                if (settings.MaxLogFileSizeBytes > 0 && diagFile.Length > settings.MaxLogFileSizeBytes)
                {
                    var fileSizeMB = diagFile.Length / (1024.0 * 1024.0);
                    var limitMB = settings.MaxLogFileSizeBytes / (1024.0 * 1024.0);
                    
                    _logger.LogWarning("📊 SKIPPING large db2diag.log file: {Path} ({Size:N1} MB exceeds limit of {Limit:N0} MB)",
                        diagFile.FullName, fileSizeMB, limitMB);
                    
                    // Generate a warning alert for the skipped file
                    var skipAlert = new Alert
                    {
                        Severity = AlertSeverity.Warning,
                        Category = $"Database/{instanceName}",
                        Message = $"[{instanceName}] DB2 diag log file skipped - too large ({fileSizeMB:N1} MB)",
                        Details = $"File: {diagFile.FullName} | Size: {fileSizeMB:N1} MB | Limit: {limitMB:N0} MB | " +
                                  "Large log files are skipped to prevent out-of-memory issues. Consider archiving or rotating the log.",
                        Timestamp = DateTime.UtcNow,
                        SuppressedChannels = settings.SuppressedChannels ?? new List<string>(),
                        Metadata = new Dictionary<string, object>
                        {
                            ["FilePath"] = diagFile.FullName,
                            ["FileSizeMB"] = fileSizeMB,
                            ["LimitMB"] = limitMB,
                            ["Instance"] = instanceName
                        }
                    };
                    alerts.Add(skipAlert);
                    
                    continue; // Skip this file
                }
                
                var (entries, stats) = await ProcessLogFileWithStatsAsync(diagFile, instanceName, settings, cancellationToken)
                    .ConfigureAwait(false);
                
                allEntries.AddRange(entries);
                totalLinesProcessed += stats.LinesScanned;
                totalBlocksProcessed += stats.BlocksFound;
                
                _logger.LogDebug("📊 Phase 4 - Process [{Instance}]: {Ms}ms | Lines: {Lines:N0} | Blocks: {Blocks} | Entries: {Entries} | Skipped: {Skipped}",
                    instanceName, phaseStopwatch.ElapsedMilliseconds, 
                    stats.LinesScanned, stats.BlocksFound, entries.Count, stats.EntriesSkipped);
                
                // Phase 5: Apply pattern matching and generate alerts
                phaseStopwatch.Restart();
                var fileAlerts = 0;
                var fileSkipped = 0;
                var fileLoggedOnly = 0;
                
                // Log SuppressedChannels configuration once per cycle
                if (entries.Count > 0 && settings.SuppressedChannels?.Count > 0)
                {
                    _logger.LogDebug("📊 Db2DiagMonitor SuppressedChannels configured: [{Channels}]", 
                        string.Join(", ", settings.SuppressedChannels));
                }
                
                foreach (var entry in entries)
                {
                    // Apply pattern matching
                    var matchResult = _patternMatcher.Match(entry);
                    
                    switch (matchResult.Action)
                    {
                        case Db2PatternAction.Skip:
                            // Completely skip - no alert, no logging
                            fileSkipped++;
                            _entriesSkipped++;
                            _logger.LogDebug("📊   Skipped entry: {PatternId} | {Level}", 
                                matchResult.Pattern?.PatternId, entry.Level);
                            continue;
                            
                        case Db2PatternAction.LogOnly:
                            // Log to SQL error file, but don't create alert
                            _sqlErrorLogger.LogSqlError(entry, matchResult.SqlCode, settings.SqlErrorLogPath);
                            fileLoggedOnly++;
                            _entriesLoggedOnly++;
                            _logger.LogDebug("📊   LogOnly entry: {PatternId} | {SqlCode}", 
                                matchResult.Pattern?.PatternId, matchResult.SqlCode);
                            continue;
                            
                        case Db2PatternAction.Remap:
                        case Db2PatternAction.Escalate:
                            _entriesRemapped++;
                            // If AlsoLogToFile is enabled, log ALL occurrences to SQL error file
                            if (matchResult.Pattern?.AlsoLogToFile == true && !string.IsNullOrEmpty(settings.SqlErrorLogPath))
                            {
                                _sqlErrorLogger.LogSqlError(entry, matchResult.SqlCode, settings.SqlErrorLogPath);
                                _logger.LogDebug("📊   AlsoLogToFile: {PatternId} logged to SQL error file", 
                                    matchResult.Pattern?.PatternId);
                            }
                            break;
                            
                        case Db2PatternAction.Keep:
                        default:
                            // Use original behavior
                            break;
                    }
                    
                    // Create alert with (possibly remapped) severity
                    var alert = CreateAlertFromEntry(entry, instanceName, settings, matchResult);
                    if (alert != null)
                    {
                        alerts.Add(alert);
                        fileAlerts++;
                    }
                }
                _logger.LogDebug("📊 Phase 5 - Pattern Match [{Instance}]: {Ms}ms | Alerts: {Count} | Skipped: {Skip} | LogOnly: {Log}",
                    instanceName, phaseStopwatch.ElapsedMilliseconds, fileAlerts, fileSkipped, fileLoggedOnly);
            }
            
            db2Data.InstanceCount = db2Data.Instances.Distinct().Count();
            db2Data.EntriesProcessedLastCycle = allEntries.Count;
            db2Data.AlertsGeneratedLastCycle = alerts.Count;
            
            // Phase 6: Store entries in memory if enabled
            phaseStopwatch.Restart();
            if (settings.KeepAllEntriesInMemory && allEntries.Count > 0)
            {
                lock (_entriesLock)
                {
                    _allEntries.AddRange(allEntries);
                    
                    // Trim if exceeds max (treat 0 as 5000 to prevent unbounded growth)
                    var effectiveMax = settings.MaxEntriesInMemory > 0 ? settings.MaxEntriesInMemory : 5000;
                    if (_allEntries.Count > effectiveMax)
                    {
                        var excess = _allEntries.Count - effectiveMax;
                        _allEntries.RemoveRange(0, excess);
                        _logger.LogDebug("📊   Trimmed {Count} old entries from memory (max: {Max})", excess, effectiveMax);
                    }
                    
                    db2Data.TotalEntriesInMemory = _allEntries.Count;
                    // Share the reference instead of duplicating the entire list.
                    // The old `.ToList()` copy doubled memory usage for all diag entries.
                    db2Data.AllEntries = _allEntries;
                }
                _logger.LogDebug("📊 Phase 6 - Memory Storage: {Ms}ms | Total in memory: {Count:N0}",
                    phaseStopwatch.ElapsedMilliseconds, db2Data.TotalEntriesInMemory);
            }
            
            // Populate RecentEntries from persistent memory store if enabled, otherwise from current cycle
            if (settings.KeepAllEntriesInMemory && _allEntries.Count > 0)
            {
                lock (_entriesLock)
                {
                    db2Data.RecentEntries = _allEntries
                        .OrderByDescending(e => e.TimestampParsed)
                        .Take(10)
                        .ToList();
                }
            }
            else
            {
                db2Data.RecentEntries = allEntries
                    .OrderByDescending(e => e.TimestampParsed)
                    .Take(10)
                    .ToList();
            }
            
            // Final summary
            totalStopwatch.Stop();
            
            // Memory tracking at end of collection cycle
            var memAtEnd = GC.GetTotalMemory(false);
            _logger.LogInformation(
                "📊 DB2 Diag Monitor COMPLETE: {TotalMs}ms | Files: {Files} | Instances: {Instances} | Lines: {Lines:N0} | Blocks: {Blocks} | Entries: {Entries} | Alerts: {Alerts} | Skipped: {Skip} | LogOnly: {Log} | Remapped: {Remap} | Memory: {MemMB:N1} MB",
                totalStopwatch.ElapsedMilliseconds, diagFiles.Count, db2Data.InstanceCount, 
                totalLinesProcessed, totalBlocksProcessed, allEntries.Count, alerts.Count,
                _entriesSkipped, _entriesLoggedOnly, _entriesRemapped, memAtEnd / (1024.0 * 1024.0));
            
            return CreateResult(db2Data, alerts, totalStopwatch);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in DB2 Diag Monitor after {Ms}ms", totalStopwatch.ElapsedMilliseconds);
            db2Data.InactiveReason = ex.Message;
            
            return new MonitorResult
            {
                Category = Category,
                Success = false,
                ErrorMessage = ex.Message,
                Data = db2Data,
                Alerts = alerts,
                CollectionDurationMs = totalStopwatch.ElapsedMilliseconds
            };
        }
    }
    
    /// <summary>
    /// Statistics from processing a log file
    /// </summary>
    private record LogProcessingStats(int LinesScanned, int BlocksFound, int EntriesSkipped);
    
    private MonitorResult CreateResult(Db2DiagData data, List<Alert> alerts, Stopwatch stopwatch)
    {
        stopwatch.Stop();
        var result = new MonitorResult
        {
            Category = Category,
            Success = true,
            Data = data,
            Alerts = alerts,
            CollectionDurationMs = stopwatch.ElapsedMilliseconds
        };
        _currentState = result;
        return result;
    }
    
    /// <summary>
    /// Gets today's diagnostic log summary (entry counts by severity).
    /// Used by Db2InstanceMonitor for dashboard display.
    /// </summary>
    public Db2DiagSummary GetTodaysDiagSummary()
    {
        return GetTodaysDiagSummary(null);
    }
    
    /// <summary>
    /// Gets today's diagnostic summary filtered by database name.
    /// </summary>
    /// <param name="databaseName">Database name to filter by, or null for all databases.</param>
    public Db2DiagSummary GetTodaysDiagSummary(string? databaseName)
    {
        var today = DateTime.Today;
        
        lock (_entriesLock)
        {
            var todayEntries = _allEntries
                .Where(e => e.TimestampParsed?.Date == today);
            
            // Filter by database name if specified
            if (!string.IsNullOrEmpty(databaseName))
            {
                todayEntries = todayEntries.Where(e => 
                    !string.IsNullOrEmpty(e.DatabaseName) && 
                    e.DatabaseName.Equals(databaseName, StringComparison.OrdinalIgnoreCase));
            }
            
            var entries = todayEntries.ToList();
            
            return new Db2DiagSummary
            {
                Date = today,
                TotalEvents = entries.Count,
                CriticalCount = entries.Count(e => 
                    e.Level?.Equals("Critical", StringComparison.OrdinalIgnoreCase) == true),
                SevereCount = entries.Count(e => 
                    e.Level?.Equals("Severe", StringComparison.OrdinalIgnoreCase) == true),
                ErrorCount = entries.Count(e => 
                    e.Level?.Equals("Error", StringComparison.OrdinalIgnoreCase) == true),
                WarningCount = entries.Count(e => 
                    e.Level?.Equals("Warning", StringComparison.OrdinalIgnoreCase) == true),
                EventCount = entries.Count(e => 
                    e.Level?.Equals("Event", StringComparison.OrdinalIgnoreCase) == true),
                InfoCount = entries.Count(e => 
                    e.Level?.Equals("Info", StringComparison.OrdinalIgnoreCase) == true)
            };
        }
    }
    
    /// <summary>
    /// Gets the db2diag.log file size in bytes for the given instance.
    /// Returns null if no file was found for that instance.
    /// </summary>
    public long? GetDiagLogFileSizeBytes(string instanceName)
    {
        return _diagLogFileSizes.TryGetValue(instanceName, out var size) ? size : null;
    }
    
    /// <summary>
    /// Gets all unique instance/database combinations from the in-memory entries.
    /// Used by Db2InstanceMonitor as fallback when db2 commands don't return databases.
    /// </summary>
    public IEnumerable<(string Instance, string Database)> GetKnownDatabases()
    {
        lock (_entriesLock)
        {
            return _allEntries
                .Where(e => !string.IsNullOrEmpty(e.InstanceName) && !string.IsNullOrEmpty(e.DatabaseName))
                .Select(e => (e.InstanceName!, e.DatabaseName!))
                .Distinct()
                .ToList();
        }
    }
    
    /// <summary>
    /// Gets today's diagnostic entries, optionally filtered by database name.
    /// </summary>
    public List<Db2DiagEntry> GetTodaysEntries(string? databaseName = null)
    {
        var today = DateTime.Today;
        
        lock (_entriesLock)
        {
            var todayEntries = _allEntries
                .Where(e => e.TimestampParsed?.Date == today);
            
            // Filter by database name if specified
            if (!string.IsNullOrEmpty(databaseName))
            {
                todayEntries = todayEntries.Where(e => 
                    !string.IsNullOrEmpty(e.DatabaseName) && 
                    e.DatabaseName.Equals(databaseName, StringComparison.OrdinalIgnoreCase));
            }
            
            return todayEntries
                .OrderByDescending(e => e.TimestampParsed)
                .ToList();
        }
    }

    private async Task LoadMessageMapAsync(CancellationToken cancellationToken)
    {
        try
        {
            var paths = new[]
            {
                Path.Combine(AppContext.BaseDirectory, "Db2DiagMessageMap.json"),
                Path.Combine(Directory.GetCurrentDirectory(), "Db2DiagMessageMap.json")
            };
            
            foreach (var path in paths)
            {
                if (File.Exists(path))
                {
                    var json = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
                    _messageMap = JsonSerializer.Deserialize<Db2DiagMessageMap>(json);
                    _messageMapLoaded = true;
                    _logger.LogInformation("Loaded DB2 message map from {Path}", path);
                    return;
                }
            }
            
            _logger.LogWarning("DB2 message map file not found");
            _messageMapLoaded = true; // Don't retry
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load DB2 message map");
            _messageMapLoaded = true; // Don't retry
        }
    }

    private async Task<string?> GetSearchDirectoryAsync(Db2DiagMonitoringSettings settings, CancellationToken cancellationToken)
    {
        // Use configured directory if specified
        if (!string.IsNullOrWhiteSpace(settings.SearchDirectory))
        {
            if (Directory.Exists(settings.SearchDirectory))
            {
                return settings.SearchDirectory;
            }
            _logger.LogWarning("Configured DB2 search directory not found: {Path}", settings.SearchDirectory);
        }
        
        // Try to detect via db2set command
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "db2set",
                Arguments = "DB2INSTPROF",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            
            using var process = Process.Start(psi);
            if (process == null) return null;
            
            var output = await process.StandardOutput.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            
            if (string.IsNullOrWhiteSpace(output)) return null;
            
            // Extract path up to and including first DB2 folder
            // Pattern: ^(.+?\\DB2)(?:\\|$)
            var match = Regex.Match(output.Trim(), @"^(.+?\\DB2)(?:\\|$)", RegexOptions.IgnoreCase);
            if (match.Success)
            {
                var path = match.Groups[1].Value;
                if (Directory.Exists(path))
                {
                    _logger.LogInformation("Detected DB2 path: {Path}", path);
                    return path;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to detect DB2 path via db2set");
        }
        
        // Try common paths
        var commonPaths = new[]
        {
            @"C:\ProgramData\IBM\DB2",
            @"D:\ProgramData\IBM\DB2",
            @"C:\DB2"
        };
        
        foreach (var path in commonPaths)
        {
            if (Directory.Exists(path))
            {
                _logger.LogInformation("Using common DB2 path: {Path}", path);
                return path;
            }
        }
        
        return null;
    }

    private List<FileInfo> FindDiagLogFiles(string searchDirectory)
    {
        try
        {
            return Directory.GetFiles(searchDirectory, "db2diag.log", SearchOption.AllDirectories)
                .Select(f => new FileInfo(f))
                .ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error searching for db2diag.log files in {Path}", searchDirectory);
            return new List<FileInfo>();
        }
    }

    private static string TruncateRawBlock(List<string> blockLines, int maxChars)
    {
        var sb = new System.Text.StringBuilder(Math.Min(maxChars + 50, blockLines.Count * 80));
        foreach (var bline in blockLines)
        {
            if (sb.Length + bline.Length + 2 > maxChars)
            {
                sb.Append("... [truncated]");
                break;
            }
            if (sb.Length > 0) sb.Append(Environment.NewLine);
            sb.Append(bline);
        }
        return sb.ToString();
    }

    private static string GetInstanceFromPath(string path)
    {
        // DB2 diagnostic log paths follow this structure:
        //   C:\ProgramData\IBM\DB2\<DB2COPY>\<INSTANCE>\DIAG0000\db2diag.log
        //
        // Examples:
        //   C:\ProgramData\IBM\DB2\DB2COPY1\DB2\DIAG0000\db2diag.log         → instance "DB2"
        //   C:\ProgramData\IBM\DB2\DB2COPY1\DB2FED\DIAG0000\db2diag.log      → instance "DB2FED"
        //   C:\ProgramData\IBM\DB2\DB2COPY1\DB2HFED\DIAG0000\db2diag.log     → instance "DB2HFED"
        //
        // The DIAG0000 folder is the key landmark — the folder directly above it is the instance name.
        // DB2COPY1 is the software copy folder (NOT the instance name).
        var parts = (path ?? "").Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

        for (var i = 0; i < parts.Length; i++)
        {
            if (parts[i].StartsWith("DIAG", StringComparison.OrdinalIgnoreCase) && i > 0)
                return parts[i - 1].ToUpperInvariant();
        }

        // Fallback: look for the last DB2* folder that isn't DB2COPY*
        for (var i = parts.Length - 1; i >= 0; i--)
        {
            var p = parts[i];
            if (p.StartsWith("DB2", StringComparison.OrdinalIgnoreCase) &&
                !p.StartsWith("DB2COPY", StringComparison.OrdinalIgnoreCase) &&
                !p.Contains('.'))
            {
                return p.ToUpperInvariant();
            }
        }

        return "DB2";
    }

    private async Task<(List<Db2DiagEntry> entries, LogProcessingStats stats)> ProcessLogFileWithStatsAsync(
        FileInfo diagFile,
        string instanceName,
        Db2DiagMonitoringSettings settings,
        CancellationToken cancellationToken)
    {
        var entries = new List<Db2DiagEntry>();
        var linesScanned = 0;
        var blocksFound = 0;
        var entriesSkipped = 0;
        var phaseTimer = new Stopwatch();
        
        try
        {
            phaseTimer.Restart();
            var stateVarName = $"{settings.StateVariablePrefix}{instanceName}";
            var state = LoadState(stateVarName, diagFile);
            _logger.LogDebug("📊   [{Instance}] State load: {Ms}ms | Resume from line: {Line}",
                instanceName, phaseTimer.ElapsedMilliseconds, state.LastProcessedLine);
            
            var encoding = GetEncoding(settings.FileEncoding);
            
            var memBeforeRead = GC.GetTotalMemory(false);
            _logger.LogDebug("📊   [{Instance}] Memory before processing: {MemMB:N1} MB | File size: {SizeMB:N1} MB",
                instanceName, memBeforeRead / (1024.0 * 1024.0), diagFile.Length / (1024.0 * 1024.0));
            
            var startLine = state.LastProcessedLine;
            var targetLevels = GetTargetLevels(settings.Db2MinimumLogLevel);
            _logger.LogDebug("📊   [{Instance}] Target severity levels: {Levels}",
                instanceName, string.Join(", ", targetLevels));
            
            var processedCount = 0;
            var lastEndLine = startLine;
            var headersFound = 0;
            var headersMatched = 0;
            var totalLineCount = 0;
            
            // Stream the file line-by-line instead of loading the entire file into memory.
            // A 500 MB file via ReadAllLinesAsync would allocate ~1.5 GB (UTF-16); streaming uses < 1 MB.
            phaseTimer.Restart();
            using var stream = new FileStream(diagFile.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 
                bufferSize: 65536);
            using var reader = new StreamReader(stream, encoding);
            
            var currentLineNumber = 0;
            string? line;
            
            while ((line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false)) != null)
            {
                currentLineNumber++;
                
                // Skip lines we already processed
                if (currentLineNumber < startLine) continue;
                
                if (cancellationToken.IsCancellationRequested) break;
                if (processedCount >= settings.MaxEntriesPerCycle) break;
                
                linesScanned++;
                
                // Fast pre-filter
                if (!line.Contains("LEVEL:")) continue;
                
                headersFound++;
                var headerMatch = HeaderPattern.Match(line);
                if (!headerMatch.Success) continue;
                
                var level = headerMatch.Groups[3].Value;
                if (!targetLevels.Contains(level, StringComparer.OrdinalIgnoreCase))
                {
                    entriesSkipped++;
                    continue;
                }
                
                headersMatched++;
                blocksFound++;
                
                var headerLine = currentLineNumber;
                var blockLines = new List<string> { line };
                
                // Read block lines until blank line or EOF
                while ((line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false)) != null)
                {
                    currentLineNumber++;
                    linesScanned++;
                    if (string.IsNullOrWhiteSpace(line)) break;
                    blockLines.Add(line);
                }
                
                var endLine = currentLineNumber;
                lastEndLine = endLine;
                
                var entry = ParseLogBlock(
                    headerMatch.Groups[1].Value,
                    headerMatch.Groups[2].Value,
                    level,
                    headerLine,
                    endLine,
                    blockLines,
                    instanceName);
                
                entries.Add(entry);
                processedCount++;
                
                if (processedCount % 100 == 0)
                {
                    _logger.LogDebug("📊   [{Instance}] Progress: {Count} entries processed, {Lines:N0} lines scanned",
                        instanceName, processedCount, linesScanned);
                }
            }
            
            totalLineCount = currentLineNumber;
            
            var scanMs = phaseTimer.ElapsedMilliseconds;
            _logger.LogDebug("📊   [{Instance}] Line scanning: {Ms}ms | Total lines: {Total:N0} | Headers found: {Headers} | Matched: {Matched} | Skipped (wrong level): {Skipped}",
                instanceName, scanMs, totalLineCount, headersFound, headersMatched, entriesSkipped);
            
            phaseTimer.Restart();
            var nextLine = Math.Max(lastEndLine + 1, totalLineCount);
            SaveState(stateVarName, diagFile, nextLine);
            _logger.LogDebug("📊   [{Instance}] State save: {Ms}ms | Next line: {Next}",
                instanceName, phaseTimer.ElapsedMilliseconds, nextLine);
            
            var memAfterProcess = GC.GetTotalMemory(false);
            _logger.LogDebug("📊   [{Instance}] Memory after processing: {MemMB:N1} MB | Entries created: {Count}",
                instanceName, memAfterProcess / (1024.0 * 1024.0), entries.Count);
            
            if (scanMs > 0)
            {
                var linesPerSecond = (linesScanned * 1000.0) / scanMs;
                _logger.LogDebug("📊   [{Instance}] Throughput: {LPS:N0} lines/sec",
                    instanceName, linesPerSecond);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "📊   [{Instance}] Error processing log file", instanceName);
        }
        
        return (entries, new LogProcessingStats(linesScanned, blocksFound, entriesSkipped));
    }
    
    // Keep old method for backward compatibility (unused but kept to avoid breaking changes)
    private async Task<List<Db2DiagEntry>> ProcessLogFileAsync(
        FileInfo diagFile,
        string instanceName,
        Db2DiagMonitoringSettings settings,
        CancellationToken cancellationToken)
    {
        var (entries, _) = await ProcessLogFileWithStatsAsync(diagFile, instanceName, settings, cancellationToken);
        return entries;
    }

    private Db2DiagInstanceState LoadState(string varName, FileInfo diagFile)
    {
        var state = new Db2DiagInstanceState
        {
            FileCreationTime = diagFile.CreationTime.ToString("yyyy-MM-dd HH:mm:ss"),
            LastProcessedLine = 1
        };
        
        try
        {
            var savedValue = Environment.GetEnvironmentVariable(varName, EnvironmentVariableTarget.User);
            if (string.IsNullOrWhiteSpace(savedValue)) return state;
            
            var parts = savedValue.Split(';');
            if (parts.Length != 2) return state;
            
            var savedCreationTime = parts[0];
            if (!int.TryParse(parts[1], out var savedLine) || savedLine <= 0) return state;
            
            // Check if file was rotated
            if (savedCreationTime != state.FileCreationTime)
            {
                _logger.LogInformation("DB2 log file rotated, resetting state");
                return state;
            }
            
            state.LastProcessedLine = savedLine;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error loading DB2 state from {Var}", varName);
        }
        
        return state;
    }

    private void SaveState(string varName, FileInfo diagFile, int nextLine)
    {
        try
        {
            var creationTime = diagFile.CreationTime.ToString("yyyy-MM-dd HH:mm:ss");
            var value = $"{creationTime};{nextLine}";
            Environment.SetEnvironmentVariable(varName, value, EnvironmentVariableTarget.User);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to save DB2 state to {Var}", varName);
        }
    }

    private HashSet<string> GetTargetLevels(string minimumLevel)
    {
        var levels = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        
        // Priority map for DB2 log levels (lower = more severe)
        var priorityMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["Critical"] = 0,
            ["Severe"] = 1,
            ["Error"] = 2,
            ["Warning"] = 3,
            ["Info"] = 4,
            ["Event"] = 5  // Event is lowest priority
        };
        
        if (!priorityMap.TryGetValue(minimumLevel, out var minPriority))
        {
            minPriority = 2; // Default to Error
        }
        
        foreach (var (level, priority) in priorityMap)
        {
            if (priority <= minPriority)
            {
                levels.Add(level);
            }
        }
        
        return levels;
    }

    private static bool MeetsMinimumAlertSeverity(AlertSeverity severity, string minimumAlertSeverity)
    {
        // Priority: Critical (0) > Warning (1) > Informational (2)
        var priorityMap = new Dictionary<AlertSeverity, int>
        {
            [AlertSeverity.Critical] = 0,
            [AlertSeverity.Warning] = 1,
            [AlertSeverity.Informational] = 2
        };

        var minLevelMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            ["Critical"] = 0,
            ["Warning"] = 1,
            ["Informational"] = 2,
            ["Info"] = 2
        };

        if (!priorityMap.TryGetValue(severity, out var severityPriority))
        {
            severityPriority = 2; // Default to Informational
        }

        if (!minLevelMap.TryGetValue(minimumAlertSeverity, out var minPriority))
        {
            minPriority = 1; // Default to Warning
        }

        // Severity must have priority <= minPriority to be included
        return severityPriority <= minPriority;
    }

    private static Encoding GetEncoding(string encodingName)
    {
        // Ensure code page provider is registered (needed for Windows-1252 in .NET Core+)
        Db2DiagEncodingInitializer.EnsureInitialized();
        
        return encodingName.ToUpperInvariant() switch
        {
            "UTF8" => Encoding.UTF8,
            "UTF7" => Encoding.UTF8, // UTF7 is obsolete, fallback to UTF8
            "UTF32" => Encoding.UTF32,
            "UNICODE" => Encoding.Unicode,
            "ASCII" => Encoding.ASCII,
            _ => Encoding.GetEncoding(1252) // Windows-1252
        };
    }

    // Pattern for DATA section headers like "DATA #1 : String, 8 bytes"
    private static readonly Regex DataSectionPattern = new(
        @"^DATA\s+#(\d+)\s*:\s*(.+)$",
        RegexOptions.Compiled);
    
    // Pattern for CALLSTACK section
    private static readonly Regex CallStackPattern = new(
        @"^CALLSTCK\s*:",
        RegexOptions.Compiled);
    
    // Pattern for callstack frame line like "[0] 0x..."
    private static readonly Regex CallStackFramePattern = new(
        @"^\s*\[\d+\]",
        RegexOptions.Compiled);
    
    // Pattern to match standard DB2 property line (properties like PID, TID, PROC, INSTANCE, NODE, DB, APPHDL, etc.)
    // These start at the beginning of the line with a known property name followed by spaces and colon
    private static readonly Regex StandardPropertyLinePattern = new(
        @"^(PID|TID|PROC|INSTANCE|NODE|DB|APPHDL|APPID|UOWID|ACTID|AUTHID|HOSTNAME|EDUID|EDUNAME|FUNCTION|MESSAGE|RETCODE|CALLED|START|STOP|IMPACT|ARG)\s*:",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private Db2DiagEntry ParseLogBlock(
        string timestamp,
        string recordId,
        string level,
        int startLine,
        int endLine,
        List<string> blockLines,
        string instanceName)
    {
        var entry = new Db2DiagEntry
        {
            Timestamp = timestamp,
            RecordId = recordId,
            Level = level,
            SourceLineNumber = startLine,
            EndLineNumber = endLine,
            InstanceName = instanceName,
            TimestampParsed = ParseDb2Timestamp(timestamp),
            RawBlock = TruncateRawBlock(blockLines, 4000)
        };
        
        // Parse properties from block with support for multi-line values, DATA sections, and CALLSTACK
        var properties = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var dataSections = new List<Db2DataSection>();
        var callStack = new List<string>();
        
        // Track the last property key for potential multi-line continuation
        string? lastPropertyKey = null;
        Db2DataSection? currentDataSection = null;
        var currentDataValue = new StringBuilder();
        var inCallStack = false;
        
        // For Event level entries, DATA sections should capture ALL content until next DATA or end
        var isEventLevel = level.Equals("Event", StringComparison.OrdinalIgnoreCase);
        
        foreach (var line in blockLines.Skip(1)) // Skip header
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            
            // Check for CALLSTACK section
            if (CallStackPattern.IsMatch(line))
            {
                // Save any pending data section
                SaveCurrentDataSection(dataSections, ref currentDataSection, currentDataValue);
                lastPropertyKey = null;
                inCallStack = true;
                continue;
            }
            
            // If in callstack, collect frames
            if (inCallStack)
            {
                if (CallStackFramePattern.IsMatch(line))
                {
                    callStack.Add(line.Trim());
                    continue;
                }
                else
                {
                    // End of callstack section
                    inCallStack = false;
                }
            }
            
            // Check for DATA section header
            var dataMatch = DataSectionPattern.Match(line);
            if (dataMatch.Success)
            {
                // Save any pending data section
                SaveCurrentDataSection(dataSections, ref currentDataSection, currentDataValue);
                lastPropertyKey = null;
                
                currentDataSection = new Db2DataSection
                {
                    Number = int.Parse(dataMatch.Groups[1].Value),
                    Type = dataMatch.Groups[2].Value.Trim()
                };
                currentDataValue.Clear();
                continue;
            }
            
            // If we're in a data section, capture content
            if (currentDataSection != null)
            {
                // For Event level entries, capture ALL lines as data content
                // Don't try to parse them as properties - lines like "CPU binding:" are data, not properties
                if (isEventLevel)
                {
                    // Only exit data section for another DATA header (handled above) or CALLSTCK
                    if (currentDataValue.Length > 0) currentDataValue.AppendLine();
                    currentDataValue.Append(line);
                    continue;
                }
                
                // For non-Event levels, check if this line looks like a standard DB2 property line
                // (like PID:, TID:, FUNCTION:, etc.) - only then exit the data section
                if (StandardPropertyLinePattern.IsMatch(line))
                {
                    // This is a standard property line - end the data section and process as property
                    SaveCurrentDataSection(dataSections, ref currentDataSection, currentDataValue);
                }
                else
                {
                    // This is data content (may contain colons like "CPU binding: not in use")
                    if (currentDataValue.Length > 0) currentDataValue.AppendLine();
                    currentDataValue.Append(line);
                    continue;
                }
            }
            
            // Check if this is a continuation line (starts with significant whitespace)
            // Continuation lines typically start with 10+ spaces and don't have a property pattern at the start
            if (line.Length > 0 && char.IsWhiteSpace(line[0]) && lastPropertyKey != null)
            {
                // Check if the line matches key:value pattern - if so, it's NOT a continuation
                var potentialKvMatches = KeyValuePattern.Matches(line);
                if (potentialKvMatches.Count == 0 || line.TrimStart().Length == line.Trim().Length)
                {
                    // This is a continuation line - append to the last property
                    if (properties.TryGetValue(lastPropertyKey, out var existingValue))
                    {
                        properties[lastPropertyKey] = existingValue + " " + line.Trim();
                    }
                    continue;
                }
            }
            
            // Parse key-value pairs from the line
            var matches = KeyValuePattern.Matches(line);
            if (matches.Count > 0)
            {
                string? lastKeyOnThisLine = null;
                
                foreach (Match match in matches)
                {
                    var key = match.Groups[1].Value.Trim();
                    var value = match.Groups[2].Value.Trim();
                    
                    if (!properties.ContainsKey(key))
                    {
                        properties[key] = value;
                        lastKeyOnThisLine = key;
                    }
                }
                
                // Track the last property on this line for potential continuation
                if (lastKeyOnThisLine != null)
                {
                    lastPropertyKey = lastKeyOnThisLine;
                }
            }
        }
        
        // Save any remaining data section
        SaveCurrentDataSection(dataSections, ref currentDataSection, currentDataValue);
        
        // Map properties to entry
        entry.DatabaseName = properties.GetValueOrDefault("DB");
        entry.ProcessId = properties.GetValueOrDefault("PID");
        entry.ThreadId = properties.GetValueOrDefault("TID");
        entry.ProcessName = properties.GetValueOrDefault("PROC");
        entry.ApplicationHandle = properties.GetValueOrDefault("APPHDL");
        entry.ApplicationId = properties.GetValueOrDefault("APPID");
        entry.AuthorizationId = properties.GetValueOrDefault("AUTHID");
        entry.HostName = properties.GetValueOrDefault("HOSTNAME");
        entry.UnitOfWorkId = properties.GetValueOrDefault("UOWID");
        entry.ActivityId = properties.GetValueOrDefault("ACTID");
        entry.PartitionNumber = properties.GetValueOrDefault("NODE");
        entry.EduId = properties.GetValueOrDefault("EDUID");
        entry.EduName = properties.GetValueOrDefault("EDUNAME");
        entry.Function = properties.GetValueOrDefault("FUNCTION");
        entry.Message = properties.GetValueOrDefault("MESSAGE");
        entry.ReturnCode = properties.GetValueOrDefault("RETCODE");
        entry.CalledFunction = properties.GetValueOrDefault("CALLED");
        
        // Assign data sections and callstack if any
        if (dataSections.Count > 0) entry.DataSections = dataSections;
        if (callStack.Count > 0) entry.CallStack = callStack;
        
        // Look up descriptions from message map
        if (_messageMap != null)
        {
            entry.Description = new Db2DiagDescription
            {
                ZrcCode = GetZrcDescription(entry.ReturnCode),
                ProbeCode = GetProbeDescription(entry.Function),
                MessageInfo = GetMessageDescription(entry.Message),
                LevelInfo = GetLevelDescription(level)
            };
            
            entry.LevelPriority = entry.Description.LevelInfo?.Priority;
        }
        
        return entry;
    }
    
    
    private static void SaveCurrentDataSection(
        List<Db2DataSection> dataSections,
        ref Db2DataSection? currentSection,
        StringBuilder currentValue)
    {
        if (currentSection != null)
        {
            currentSection.Value = currentValue.ToString().Trim();
            dataSections.Add(currentSection);
        }
        currentSection = null;
        currentValue.Clear();
    }

    private DateTime? ParseDb2Timestamp(string timestamp)
    {
        try
        {
            var match = Db2TimestampPattern.Match(timestamp);
            if (!match.Success) return null;
            
            var year = int.Parse(match.Groups[1].Value);
            var month = int.Parse(match.Groups[2].Value);
            var day = int.Parse(match.Groups[3].Value);
            var hour = int.Parse(match.Groups[4].Value);
            var minute = int.Parse(match.Groups[5].Value);
            var second = int.Parse(match.Groups[6].Value);
            var microseconds = int.Parse(match.Groups[7].Value);
            var tzSign = match.Groups[8].Value;
            var tzOffsetMinutes = int.Parse(match.Groups[9].Value);
            
            var milliseconds = microseconds / 1000;
            var localTime = new DateTime(year, month, day, hour, minute, second, milliseconds);
            
            // Convert to UTC then to local
            var offsetMinutes = tzSign == "+" ? -tzOffsetMinutes : tzOffsetMinutes;
            var utcTime = localTime.AddMinutes(offsetMinutes);
            
            return TimeZoneInfo.ConvertTimeFromUtc(utcTime, TimeZoneInfo.Local);
        }
        catch
        {
            return null;
        }
    }

    private Db2ZrcInfo? GetZrcDescription(string? retCode)
    {
        if (string.IsNullOrWhiteSpace(retCode) || _messageMap?.ZrcCodes == null) return null;
        
        var match = ZrcCodePattern.Match(retCode);
        if (!match.Success) return null;
        
        var zrcHex = match.Groups[1].Value.ToUpperInvariant();
        
        // Try exact match
        if (_messageMap.ZrcCodes.TryGetValue(zrcHex, out var info)) return info;
        
        // Try with 0x prefix normalized
        var normalized = "0x" + zrcHex.Substring(2).ToUpperInvariant();
        if (_messageMap.ZrcCodes.TryGetValue(normalized, out info)) return info;
        
        // Try short form (last 4 hex digits)
        if (zrcHex.Length >= 6)
        {
            var shortCode = "0x" + zrcHex.Substring(zrcHex.Length - 4).ToUpperInvariant();
            if (_messageMap.ZrcCodes.TryGetValue(shortCode, out info)) return info;
        }
        
        return null;
    }

    private Db2ProbeInfo? GetProbeDescription(string? function)
    {
        if (string.IsNullOrWhiteSpace(function) || _messageMap?.ProbeCodes == null) return null;
        
        var match = ProbePattern.Match(function);
        if (!match.Success) return null;
        
        var funcName = match.Groups[1].Value;
        var probeNum = match.Groups[2].Value;
        var probeKey = $"{funcName}:{probeNum}";
        
        return _messageMap.ProbeCodes.GetValueOrDefault(probeKey);
    }

    private Db2MessageInfo? GetMessageDescription(string? message)
    {
        if (string.IsNullOrWhiteSpace(message) || _messageMap?.MessagePatterns == null) return null;
        
        foreach (var (pattern, info) in _messageMap.MessagePatterns)
        {
            if (message.Contains(pattern, StringComparison.OrdinalIgnoreCase))
            {
                return info;
            }
        }
        
        return null;
    }

    private Db2LevelInfo? GetLevelDescription(string level)
    {
        if (_messageMap?.LevelDescriptions == null) return null;
        return _messageMap.LevelDescriptions.GetValueOrDefault(level);
    }

    private Alert? CreateAlertFromEntry(Db2DiagEntry entry, string instanceName, Db2DiagMonitoringSettings settings, Db2PatternMatchResult? matchResult = null)
    {
        // Map DB2 level to alert severity, using pattern result if available
        AlertSeverity severity;
        string message;
        List<string> suppressedChannels;
        
        if (matchResult != null && matchResult.Matched)
        {
            // Use remapped severity from pattern
            severity = matchResult.FinalSeverity.ToUpperInvariant() switch
            {
                "CRITICAL" => AlertSeverity.Critical,
                "WARNING" => AlertSeverity.Warning,
                "INFORMATIONAL" => AlertSeverity.Informational,
                "INFO" => AlertSeverity.Informational,
                _ => AlertSeverity.Warning
            };
            
            // Use formatted message from pattern
            message = matchResult.FormattedMessage;
            
            // Merge suppressed channels from pattern and global settings
            suppressedChannels = (settings.SuppressedChannels ?? new List<string>())
                .Concat(matchResult.SuppressedChannels ?? new List<string>())
                .Distinct()
                .ToList();
        }
        else
        {
            // Original behavior - map DB2 level directly
            severity = entry.Level.ToUpperInvariant() switch
        {
            "CRITICAL" => AlertSeverity.Critical,
            "SEVERE" => AlertSeverity.Critical,
            "ERROR" => AlertSeverity.Critical,
            "WARNING" => AlertSeverity.Warning,
            _ => AlertSeverity.Informational
        };

        // Build message
        var messageParts = new List<string> { $"[{instanceName}]" };
        if (!string.IsNullOrWhiteSpace(entry.DatabaseName))
        {
            messageParts.Add($"[{entry.DatabaseName}]");
        }
        messageParts.Add(entry.Message ?? $"DB2 {entry.Level} detected");
            message = string.Join(" ", messageParts);

            suppressedChannels = settings.SuppressedChannels ?? new List<string>();
        }

        // Build category
        var category = string.IsNullOrWhiteSpace(entry.DatabaseName)
            ? "Database"
            : $"Database/{entry.DatabaseName}";

        // Build metadata with all properties (following PowerShell naming convention)
        var metadata = new Dictionary<string, object>
        {
            // Core identifiers
            ["Db2Timestamp"] = entry.Timestamp,
            ["RecordId"] = entry.RecordId,
            ["Level"] = entry.Level,
            ["SourceLineNumber"] = entry.SourceLineNumber,
            
            // Process information
            ["ProcessId_PID"] = entry.ProcessId ?? "",
            ["ThreadId_TID"] = entry.ThreadId ?? "",
            ["ProcessName_PROC"] = entry.ProcessName ?? "",
            
            // Instance and database
            ["Instance"] = instanceName,
            ["PartitionNumber_NODE"] = entry.PartitionNumber ?? "",
            ["DatabaseName_DB"] = entry.DatabaseName ?? "",
            
            // Application information
            ["ApplicationHandle_APPHDL"] = entry.ApplicationHandle ?? "",
            ["ApplicationId_APPID"] = entry.ApplicationId ?? "",
            ["UnitOfWorkId_UOWID"] = entry.UnitOfWorkId ?? "",
            ["ActivityId_ACTID"] = entry.ActivityId ?? "",
            ["AuthorizationId_AUTHID"] = entry.AuthorizationId ?? "",
            ["HostName_HOSTNAME"] = entry.HostName ?? "",
            
            // EDU information
            ["EngineDispatchableUnitId_EDUID"] = entry.EduId ?? "",
            ["EngineDispatchableUnitName_EDUNAME"] = entry.EduName ?? "",
            
            // Function and error details
            ["FunctionAndProbe_FUNCTION"] = entry.Function ?? "",
            ["MessageText_MESSAGE"] = entry.Message ?? "",
            ["CalledFunction_CALLED"] = entry.CalledFunction ?? "",
            ["ReturnCode_RETCODE"] = entry.ReturnCode ?? "",
            
            // Raw block for display (truncated to prevent large alert metadata)
            ["Db2RawBlock"] = entry.RawBlock != null && entry.RawBlock.Length > 2000 
                ? entry.RawBlock[..2000] + "... [truncated]" 
                : entry.RawBlock ?? ""
        };
        
        // Add Description info if available
        if (entry.Description != null)
        {
            if (entry.Description.ZrcCode != null)
            {
                metadata["ZrcDescription"] = entry.Description.ZrcCode.Description ?? "";
                metadata["ZrcCategory"] = entry.Description.ZrcCode.Category ?? "";
            }
            if (entry.Description.ProbeCode != null)
            {
                metadata["ProbeDescription"] = entry.Description.ProbeCode.Description ?? "";
                metadata["ProbeCategory"] = entry.Description.ProbeCode.Category ?? "";
            }
            if (entry.Description.MessageInfo != null)
            {
                metadata["MessageDescription"] = entry.Description.MessageInfo.Description ?? "";
                metadata["MessageRecommendation"] = entry.Description.MessageInfo.Recommendation ?? "";
            }
            if (entry.Description.LevelInfo != null)
            {
                metadata["LevelDescription"] = entry.Description.LevelInfo.Description ?? "";
                metadata["LevelAction"] = entry.Description.LevelInfo.Action ?? "";
                metadata["LevelPriority"] = entry.Description.LevelInfo.Priority.ToString();
            }
        }
        
        // Add CallStack if present
        if (entry.CallStack != null && entry.CallStack.Count > 0)
        {
            metadata["CallStack"] = string.Join("\n", entry.CallStack);
        }
        
        // Add DataSections if present
        if (entry.DataSections != null && entry.DataSections.Count > 0)
        {
            metadata["DataSectionsCount"] = entry.DataSections.Count.ToString();
            foreach (var dataSection in entry.DataSections)
            {
                metadata[$"Data#{dataSection.Number}"] = dataSection.Value;
            }
        }
        
        // Add pattern matching info if remapped
        if (matchResult != null && matchResult.Matched)
        {
            metadata["PatternId"] = matchResult.Pattern?.PatternId ?? "";
            metadata["PatternAction"] = matchResult.Action.ToString();
            metadata["OriginalLevel"] = entry.Level;
            metadata["RemappedSeverity"] = matchResult.FinalSeverity;
            if (matchResult.SqlCode != null)
            {
                metadata["SqlCode"] = matchResult.SqlCode;
            }
        }

        // Filter based on MinimumAlertSeverity (applied AFTER remapping - default: Warning)
        if (!MeetsMinimumAlertSeverity(severity, settings.MinimumAlertSeverity))
        {
            return null;
        }

        // Create alert
        return new Alert
        {
            Severity = severity,
            Category = category,
            Message = message,
            Details = $"Source: Db2DiagMonitor | Instance: {instanceName} | Level: {entry.Level}" + 
                      (matchResult?.Matched == true ? $" | Pattern: {matchResult.Pattern?.PatternId}" : ""),
            Timestamp = entry.TimestampParsed ?? DateTime.UtcNow,
            SuppressedChannels = suppressedChannels,
            Metadata = metadata
        };
    }
}
