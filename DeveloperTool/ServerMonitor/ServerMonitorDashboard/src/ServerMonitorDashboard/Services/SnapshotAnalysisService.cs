using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

public class SnapshotAnalysisService : IDisposable
{
    private readonly IOptionsMonitor<DashboardConfig> _config;
    private readonly ILogger<SnapshotAnalysisService> _logger;
    private readonly ConcurrentDictionary<string, AnalysisJob> _jobs = new();
    private readonly Timer _cleanupTimer;

    // Regex: captures server name (everything before the date stamp)
    // Pattern: <ServerName>_<yyyyMMdd>_<HHmmssfff>.json
    //   ^           — start of string
    //   (.+?)       — group 1: server name (non-greedy, stops at first date match)
    //   _           — literal underscore separator
    //   (\d{8})     — group 2: date portion (yyyyMMdd, exactly 8 digits)
    //   _           — literal underscore separator
    //   (\d{9})     — group 3: time portion (HHmmssfff, exactly 9 digits)
    //   \.json$     — literal ".json" at end of string
    private static readonly Regex FileNamePattern = new(@"^(.+?)_(\d{8})_(\d{9})\.json$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public SnapshotAnalysisService(IOptionsMonitor<DashboardConfig> config, ILogger<SnapshotAnalysisService> logger)
    {
        _config = config;
        _logger = logger;
        _cleanupTimer = new Timer(CleanupOldJobs, null, TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(5));
    }

    public async Task<List<AnalysisServerInfo>> GetAvailableServersAsync()
    {
        var dir = _config.CurrentValue.SnapshotDirectory;
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
        {
            _logger.LogWarning("Snapshot directory does not exist or is not configured: {Dir}", dir);
            return new List<AnalysisServerInfo>();
        }

        return await Task.Run(() =>
        {
            var serverCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            foreach (var filePath in Directory.EnumerateFiles(dir, "*.json"))
            {
                var fileName = Path.GetFileName(filePath);
                var match = FileNamePattern.Match(fileName);
                if (!match.Success) continue;

                var serverName = match.Groups[1].Value;
                serverCounts.TryGetValue(serverName, out var count);
                serverCounts[serverName] = count + 1;
            }

            return serverCounts
                .OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase)
                .Select(kv => new AnalysisServerInfo { Name = kv.Key, FileCount = kv.Value })
                .ToList();
        });
    }

    public string StartJob(string server, DateTime from, DateTime to)
    {
        var job = new AnalysisJob
        {
            JobId = Guid.NewGuid().ToString("N"),
            ServerName = server,
            FromUtc = from,
            ToUtc = to,
            Status = "Running",
            StartedAtUtc = DateTime.UtcNow
        };

        _jobs[job.JobId] = job;

        _ = Task.Run(() => RunAnalysis(job));

        return job.JobId;
    }

    public AnalysisJob? GetJobStatus(string jobId)
    {
        _jobs.TryGetValue(jobId, out var job);
        return job;
    }

    private void RunAnalysis(AnalysisJob job)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            var dir = _config.CurrentValue.SnapshotDirectory;
            if (!Directory.Exists(dir))
            {
                job.Status = "Failed";
                job.ErrorMessage = $"Snapshot directory not found: {dir}";
                job.CompletedAtUtc = DateTime.UtcNow;
                return;
            }

            var matchingFiles = Directory.EnumerateFiles(dir, $"{job.ServerName}_*.json")
                .Select(f => (Path: f, FileName: Path.GetFileName(f)))
                .Select(f =>
                {
                    var m = FileNamePattern.Match(f.FileName);
                    if (!m.Success) return (f.Path, Timestamp: (DateTime?)null);
                    var dateStr = m.Groups[2].Value + m.Groups[3].Value;
                    if (DateTime.TryParseExact(dateStr, "yyyyMMddHHmmssfff",
                        System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.None, out var ts))
                    {
                        return (f.Path, Timestamp: (DateTime?)ts);
                    }
                    return (f.Path, Timestamp: (DateTime?)null);
                })
                .Where(f => f.Timestamp.HasValue && f.Timestamp.Value >= job.FromUtc && f.Timestamp.Value <= job.ToUtc)
                .OrderBy(f => f.Timestamp!.Value)
                .ToList();

            job.TotalFiles = matchingFiles.Count;

            if (matchingFiles.Count == 0)
            {
                job.Status = "Completed";
                job.CompletedAtUtc = DateTime.UtcNow;
                sw.Stop();
                job.Report = new SnapshotAnalysisReport
                {
                    ServerName = job.ServerName,
                    FromUtc = job.FromUtc,
                    ToUtc = job.ToUtc,
                    SnapshotCount = 0,
                    DurationSeconds = sw.Elapsed.TotalSeconds
                };
                return;
            }

            var cpuPoints = new List<TimeSeriesPoint>();
            var memPoints = new List<TimeSeriesPoint>();
            var vmemPoints = new List<TimeSeriesPoint>();
            var diskPointsMap = new Dictionary<string, List<TimeSeriesPoint>>(StringComparer.OrdinalIgnoreCase);
            var lastDiskSpace = new Dictionary<string, DiskSnapshotEntry>(StringComparer.OrdinalIgnoreCase);
            UptimeSnapshotEntry? lastUptime = null;
            var alertGroups = new Dictionary<string, (string Severity, int Count, DateTime First, DateTime Last)>();
            var allAlertDetails = new List<AlertDetailItem>();
            var alertTimelineMap = new Dictionary<string, (string Severity, Dictionary<DateTime, int> BucketCounts)>(StringComparer.OrdinalIgnoreCase);
            int totalAlerts = 0;

            var jsonOptions = new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip };

            foreach (var (filePath, fileTimestamp) in matchingFiles)
            {
                try
                {
                    var ts = fileTimestamp!.Value;
                    using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
                    using var doc = JsonDocument.Parse(stream, jsonOptions);
                    var root = doc.RootElement;

                    ExtractCpu(root, ts, cpuPoints);
                    ExtractMemory(root, ts, memPoints);
                    ExtractVirtualMemory(root, ts, vmemPoints);
                    ExtractDisks(root, ts, diskPointsMap, lastDiskSpace);
                    ExtractUptime(root, ref lastUptime);
                    ExtractAlerts(root, ts, alertGroups, allAlertDetails, alertTimelineMap, ref totalAlerts);
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Error parsing snapshot file {File}", filePath);
                }

                job.FilesProcessed++;
            }

            sw.Stop();

            var actualFrom = matchingFiles.First().Timestamp!.Value;
            var actualTo = matchingFiles.Last().Timestamp!.Value;

            var report = new SnapshotAnalysisReport
            {
                ServerName = job.ServerName,
                FromUtc = actualFrom,
                ToUtc = actualTo,
                SnapshotCount = matchingFiles.Count,
                DurationSeconds = Math.Round(sw.Elapsed.TotalSeconds, 2),
                CpuHistory = cpuPoints,
                MemoryHistory = memPoints,
                VirtualMemoryHistory = vmemPoints,
                DiskHistory = diskPointsMap
                    .Select(kv => new DiskTimeSeriesGroup { Drive = kv.Key, UsedPercent = kv.Value })
                    .OrderBy(d => d.Drive)
                    .ToList(),
                CpuStats = ComputeStats(cpuPoints),
                MemoryStats = ComputeStats(memPoints),
                DiskSpaceSummary = lastDiskSpace.Values
                    .Select(d => new Models.DiskSpaceSummary
                    {
                        Drive = d.Drive,
                        TotalGB = Math.Round(d.TotalGB, 2),
                        LatestAvailableGB = Math.Round(d.AvailableGB, 2),
                        LatestUsedPercent = Math.Round(d.UsedPercent, 1)
                    })
                    .OrderBy(d => d.Drive)
                    .ToList(),
                Uptime = new UptimeSummary
                {
                    LastBootTime = lastUptime?.LastBootTime,
                    UptimeDays = Math.Round(lastUptime?.CurrentUptimeDays ?? 0, 2),
                    HadUnexpectedReboot = lastUptime?.UnexpectedReboot ?? false
                },
                AlertSummary = alertGroups
                    .Select(kv => new AlertSummaryItem
                    {
                        Message = kv.Key,
                        Severity = kv.Value.Severity,
                        Count = kv.Value.Count,
                        FirstSeen = kv.Value.First,
                        LastSeen = kv.Value.Last
                    })
                    .OrderByDescending(a => a.Count)
                    .ToList(),
                TotalAlerts = totalAlerts,
                AlertTimeline = alertTimelineMap
                    .Select(kv => new AlertTimeSeriesGroup
                    {
                        Label = kv.Key,
                        Severity = kv.Value.Severity,
                        Occurrences = kv.Value.BucketCounts
                            .OrderBy(b => b.Key)
                            .Select(b => new TimeSeriesPoint { Timestamp = b.Key, Value = b.Value })
                            .ToList()
                    })
                    .OrderByDescending(g => g.Occurrences.Sum(o => o.Value))
                    .ToList(),
                AlertDetails = allAlertDetails
                    .OrderBy(a => a.Timestamp)
                    .ToList()
            };

            job.Report = report;
            job.Status = "Completed";
            job.CompletedAtUtc = DateTime.UtcNow;

            _logger.LogInformation("Analysis job {JobId} completed: {Count} snapshots, {Duration:F1}s",
                job.JobId, matchingFiles.Count, sw.Elapsed.TotalSeconds);
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex, "Analysis job {JobId} failed", job.JobId);
            job.Status = "Failed";
            job.ErrorMessage = ex.Message;
            job.CompletedAtUtc = DateTime.UtcNow;
        }
    }

    private static void ExtractCpu(JsonElement root, DateTime ts, List<TimeSeriesPoint> points)
    {
        if (root.TryGetProperty("processor", out var proc) ||
            root.TryGetProperty("Processor", out proc))
        {
            if (proc.TryGetProperty("overallUsagePercent", out var val) ||
                proc.TryGetProperty("OverallUsagePercent", out val))
            {
                points.Add(new TimeSeriesPoint { Timestamp = ts, Value = Math.Round(val.GetDouble(), 1) });
            }
        }
    }

    private static void ExtractMemory(JsonElement root, DateTime ts, List<TimeSeriesPoint> points)
    {
        if (root.TryGetProperty("memory", out var mem) ||
            root.TryGetProperty("Memory", out mem))
        {
            if (mem.TryGetProperty("usedPercent", out var val) ||
                mem.TryGetProperty("UsedPercent", out val))
            {
                points.Add(new TimeSeriesPoint { Timestamp = ts, Value = Math.Round(val.GetDouble(), 1) });
            }
        }
    }

    private static void ExtractVirtualMemory(JsonElement root, DateTime ts, List<TimeSeriesPoint> points)
    {
        if (root.TryGetProperty("virtualMemory", out var vmem) ||
            root.TryGetProperty("VirtualMemory", out vmem))
        {
            if (vmem.TryGetProperty("usedPercent", out var val) ||
                vmem.TryGetProperty("UsedPercent", out val))
            {
                points.Add(new TimeSeriesPoint { Timestamp = ts, Value = Math.Round(val.GetDouble(), 1) });
            }
        }
    }

    private static void ExtractDisks(JsonElement root, DateTime ts,
        Dictionary<string, List<TimeSeriesPoint>> diskPointsMap,
        Dictionary<string, DiskSnapshotEntry> lastDiskSpace)
    {
        if (!root.TryGetProperty("disks", out var disks) &&
            !root.TryGetProperty("Disks", out disks))
            return;

        if (disks.TryGetProperty("space", out var space) ||
            disks.TryGetProperty("Space", out space))
        {
            foreach (var disk in space.EnumerateArray())
            {
                var drive = "";
                if (disk.TryGetProperty("drive", out var drv) || disk.TryGetProperty("Drive", out drv))
                    drive = drv.GetString() ?? "";

                double usedPct = 0, totalGB = 0, availGB = 0;
                if (disk.TryGetProperty("usedPercent", out var u) || disk.TryGetProperty("UsedPercent", out u))
                    usedPct = u.GetDouble();
                if (disk.TryGetProperty("totalGB", out var t) || disk.TryGetProperty("TotalGB", out t))
                    totalGB = t.GetDouble();
                if (disk.TryGetProperty("availableGB", out var a) || disk.TryGetProperty("AvailableGB", out a))
                    availGB = a.GetDouble();

                if (string.IsNullOrEmpty(drive)) continue;

                if (!diskPointsMap.TryGetValue(drive, out var list))
                {
                    list = new List<TimeSeriesPoint>();
                    diskPointsMap[drive] = list;
                }
                list.Add(new TimeSeriesPoint { Timestamp = ts, Value = Math.Round(usedPct, 1) });

                lastDiskSpace[drive] = new DiskSnapshotEntry(drive, totalGB, availGB, usedPct);
            }
        }
    }

    private static void ExtractUptime(JsonElement root, ref UptimeSnapshotEntry? lastUptime)
    {
        if (root.TryGetProperty("uptime", out var up) ||
            root.TryGetProperty("Uptime", out up))
        {
            DateTime lastBoot = default;
            double uptimeDays = 0;
            bool unexpectedReboot = false;

            if (up.TryGetProperty("lastBootTime", out var lb) || up.TryGetProperty("LastBootTime", out lb))
                DateTime.TryParse(lb.GetString(), out lastBoot);
            if (up.TryGetProperty("currentUptimeDays", out var ud) || up.TryGetProperty("CurrentUptimeDays", out ud))
                uptimeDays = ud.GetDouble();
            if (up.TryGetProperty("unexpectedReboot", out var ur) || up.TryGetProperty("UnexpectedReboot", out ur))
                unexpectedReboot = ur.GetBoolean();

            lastUptime = new UptimeSnapshotEntry(
                lastBoot == default ? DateTime.MinValue : lastBoot,
                uptimeDays,
                unexpectedReboot);
        }
    }

    private record DiskSnapshotEntry(string Drive, double TotalGB, double AvailableGB, double UsedPercent);
    private record UptimeSnapshotEntry(DateTime LastBootTime, double CurrentUptimeDays, bool UnexpectedReboot);

    private static void ExtractAlerts(JsonElement root, DateTime snapshotTimestamp,
        Dictionary<string, (string Severity, int Count, DateTime First, DateTime Last)> alertGroups,
        List<AlertDetailItem> allDetails,
        Dictionary<string, (string Severity, Dictionary<DateTime, int> BucketCounts)> timelineMap,
        ref int totalAlerts)
    {
        if (!root.TryGetProperty("alerts", out var alerts) &&
            !root.TryGetProperty("Alerts", out alerts))
            return;

        foreach (var alert in alerts.EnumerateArray())
        {
            totalAlerts++;

            var message = "";
            var severity = "Warning";
            var category = "";
            var details = (string?)null;
            DateTime ts = snapshotTimestamp;

            if (alert.TryGetProperty("message", out var m) || alert.TryGetProperty("Message", out m))
                message = m.GetString() ?? "";
            if (alert.TryGetProperty("severity", out var s) || alert.TryGetProperty("Severity", out s))
                severity = s.GetString() ?? s.ToString();
            if (alert.TryGetProperty("timestamp", out var t) || alert.TryGetProperty("Timestamp", out t))
                if (DateTime.TryParse(t.GetString(), out var parsed)) ts = parsed;
            if (alert.TryGetProperty("category", out var c) || alert.TryGetProperty("Category", out c))
                category = c.GetString() ?? "";
            if (alert.TryGetProperty("details", out var d) || alert.TryGetProperty("Details", out d))
                details = d.GetString();

            if (string.IsNullOrEmpty(message)) continue;

            allDetails.Add(new AlertDetailItem
            {
                Timestamp = ts,
                Severity = severity,
                Category = category,
                Message = message,
                Details = details
            });

            if (alertGroups.TryGetValue(message, out var existing))
            {
                alertGroups[message] = (severity, existing.Count + 1,
                    ts < existing.First ? ts : existing.First,
                    ts > existing.Last ? ts : existing.Last);
            }
            else
            {
                alertGroups[message] = (severity, 1, ts, ts);
            }

            var bucket = new DateTime(ts.Year, ts.Month, ts.Day, ts.Hour, 0, 0, ts.Kind);
            if (!timelineMap.TryGetValue(message, out var entry))
            {
                entry = (severity, new Dictionary<DateTime, int>());
                timelineMap[message] = entry;
            }
            entry.BucketCounts.TryGetValue(bucket, out var cnt);
            entry.BucketCounts[bucket] = cnt + 1;
        }
    }

    private static AggregateStats ComputeStats(List<TimeSeriesPoint> points)
    {
        if (points.Count == 0)
            return new AggregateStats();

        var values = points.Select(p => p.Value).OrderBy(v => v).ToList();
        var p95Index = (int)Math.Ceiling(values.Count * 0.95) - 1;
        if (p95Index < 0) p95Index = 0;
        if (p95Index >= values.Count) p95Index = values.Count - 1;

        return new AggregateStats
        {
            Min = Math.Round(values[0], 1),
            Max = Math.Round(values[^1], 1),
            Avg = Math.Round(values.Average(), 1),
            P95 = Math.Round(values[p95Index], 1)
        };
    }

    private void CleanupOldJobs(object? state)
    {
        var cutoff = DateTime.UtcNow.AddMinutes(-30);
        foreach (var (key, job) in _jobs)
        {
            if (job.CompletedAtUtc.HasValue && job.CompletedAtUtc.Value < cutoff)
            {
                _jobs.TryRemove(key, out _);
            }
        }
    }

    public void Dispose()
    {
        _cleanupTimer.Dispose();
    }
}
