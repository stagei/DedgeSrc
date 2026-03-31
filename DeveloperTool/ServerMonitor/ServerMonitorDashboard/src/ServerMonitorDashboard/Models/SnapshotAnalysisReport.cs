namespace ServerMonitorDashboard.Models;

public class AnalysisJob
{
    public string JobId { get; set; } = "";
    public string Status { get; set; } = "Pending";
    public string ServerName { get; set; } = "";
    public DateTime FromUtc { get; set; }
    public DateTime ToUtc { get; set; }
    public int TotalFiles { get; set; }
    public int FilesProcessed { get; set; }
    public string? ErrorMessage { get; set; }
    public SnapshotAnalysisReport? Report { get; set; }
    public DateTime StartedAtUtc { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
}

public class SnapshotAnalysisReport
{
    public string ServerName { get; set; } = "";
    public DateTime FromUtc { get; set; }
    public DateTime ToUtc { get; set; }
    public int SnapshotCount { get; set; }
    public double DurationSeconds { get; set; }
    public List<TimeSeriesPoint> CpuHistory { get; set; } = new();
    public List<TimeSeriesPoint> MemoryHistory { get; set; } = new();
    public List<TimeSeriesPoint> VirtualMemoryHistory { get; set; } = new();
    public List<DiskTimeSeriesGroup> DiskHistory { get; set; } = new();
    public AggregateStats CpuStats { get; set; } = new();
    public AggregateStats MemoryStats { get; set; } = new();
    public List<DiskSpaceSummary> DiskSpaceSummary { get; set; } = new();
    public UptimeSummary Uptime { get; set; } = new();
    public List<AlertSummaryItem> AlertSummary { get; set; } = new();
    public int TotalAlerts { get; set; }

    /// <summary>
    /// Per-alert-type occurrence count over time (for timeline charts)
    /// </summary>
    public List<AlertTimeSeriesGroup> AlertTimeline { get; set; } = new();

    /// <summary>
    /// Every individual alert record across all snapshots in the period
    /// </summary>
    public List<AlertDetailItem> AlertDetails { get; set; } = new();
}

public class TimeSeriesPoint
{
    public DateTime Timestamp { get; set; }
    public double Value { get; set; }
}

public class AggregateStats
{
    public double Min { get; set; }
    public double Max { get; set; }
    public double Avg { get; set; }
    public double P95 { get; set; }
}

public class DiskTimeSeriesGroup
{
    public string Drive { get; set; } = "";
    public List<TimeSeriesPoint> UsedPercent { get; set; } = new();
}

public class DiskSpaceSummary
{
    public string Drive { get; set; } = "";
    public double TotalGB { get; set; }
    public double LatestAvailableGB { get; set; }
    public double LatestUsedPercent { get; set; }
}

public class UptimeSummary
{
    public DateTime? LastBootTime { get; set; }
    public double UptimeDays { get; set; }
    public bool HadUnexpectedReboot { get; set; }
}

public class AlertSummaryItem
{
    public string Message { get; set; } = "";
    public string Severity { get; set; } = "";
    public int Count { get; set; }
    public DateTime FirstSeen { get; set; }
    public DateTime LastSeen { get; set; }
}

public class AlertTimeSeriesGroup
{
    public string Label { get; set; } = "";
    public string Severity { get; set; } = "";
    public List<TimeSeriesPoint> Occurrences { get; set; } = new();
}

public class AlertDetailItem
{
    public DateTime Timestamp { get; set; }
    public string Severity { get; set; } = "";
    public string Category { get; set; } = "";
    public string Message { get; set; } = "";
    public string? Details { get; set; }
}

public class AnalysisServerInfo
{
    public string Name { get; set; } = "";
    public int FileCount { get; set; }
}

public class StartAnalysisRequest
{
    public string Server { get; set; } = "";
    public DateTime From { get; set; }
    public DateTime To { get; set; }
}
