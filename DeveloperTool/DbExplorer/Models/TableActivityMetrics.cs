using System;

namespace DbExplorer.Models;

/// <summary>
/// Represents database activity metrics for a table.
/// Uses database-agnostic property names for multi-provider support.
/// </summary>
public class TableActivityMetrics
{
    public string SchemaName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string TablespaceName { get; set; } = string.Empty;
    public long TotalRowsRead { get; set; }
    public long TotalRowsInserted { get; set; }
    public long TotalRowsUpdated { get; set; }
    public long TotalRowsDeleted { get; set; }
    
    /// <summary>
    /// Total activity score (sum of all operations)
    /// </summary>
    public long TotalActivity => TotalRowsRead + TotalRowsInserted + TotalRowsUpdated + TotalRowsDeleted;
    
    /// <summary>
    /// Percentage of read operations
    /// </summary>
    public double ReadPercentage => TotalActivity > 0 ? (TotalRowsRead * 100.0 / TotalActivity) : 0;
    
    /// <summary>
    /// Percentage of write operations (INSERT + UPDATE + DELETE)
    /// </summary>
    public double WritePercentage => TotalActivity > 0 ? ((TotalRowsInserted + TotalRowsUpdated + TotalRowsDeleted) * 100.0 / TotalActivity) : 0;
    
    /// <summary>
    /// Activity level indicator (High, Medium, Low)
    /// </summary>
    public string ActivityLevel
    {
        get
        {
            if (TotalActivity >= 1_000_000) return "High";
            if (TotalActivity >= 10_000) return "Medium";
            if (TotalActivity > 0) return "Low";
            return "Idle";
        }
    }
}

/// <summary>
/// Filter criteria for database load monitoring
/// </summary>
public class LoadMonitorFilter
{
    public string? SelectedSchema { get; set; } = "*"; // Default: All schemas
    public string? SelectedTable { get; set; } = "*";  // Default: All tables
    public bool ExcludeSystemSchemas { get; set; } = true; // Default: Exclude system schemas
    
    /// <summary>
    /// List of system schemas to exclude
    /// </summary>
    public static readonly string[] SystemSchemas = new[]
    {
        "SYSIBM", "SYSIBMADM", "SYSIBMINTERNAL", "SYSIBMTS",
        "SYSPROC", "SYSPUBLIC", "SYSSTAT", "SYSTOOLS",
        "SYSCAT", "SYSFUN", "SYSINSTALLOBJECTS"
    };
}

/// <summary>
/// Represents a snapshot of table activity at a specific point in time
/// </summary>
public class ActivitySnapshot
{
    public DateTime SnapshotTime { get; set; }
    public List<TableActivityMetrics> Metrics { get; set; } = new();
}

/// <summary>
/// Represents delta between two snapshots.
/// Uses database-agnostic property names for multi-provider support.
/// </summary>
public class TableActivityDelta
{
    public string SchemaName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    
    // Current snapshot values
    public long CurrentRowsRead { get; set; }
    public long CurrentRowsInserted { get; set; }
    public long CurrentRowsUpdated { get; set; }
    public long CurrentRowsDeleted { get; set; }
    
    // Previous snapshot values
    public long PreviousRowsRead { get; set; }
    public long PreviousRowsInserted { get; set; }
    public long PreviousRowsUpdated { get; set; }
    public long PreviousRowsDeleted { get; set; }
    
    // Delta (difference) values
    public long DeltaRowsRead => CurrentRowsRead - PreviousRowsRead;
    public long DeltaRowsInserted => CurrentRowsInserted - PreviousRowsInserted;
    public long DeltaRowsUpdated => CurrentRowsUpdated - PreviousRowsUpdated;
    public long DeltaRowsDeleted => CurrentRowsDeleted - PreviousRowsDeleted;
    
    // Total delta activity
    public long TotalDeltaActivity => DeltaRowsRead + DeltaRowsInserted + DeltaRowsUpdated + DeltaRowsDeleted;
    
    // Delta activity rate (operations per second)
    public double DeltaActivityRate { get; set; }
    
    /// <summary>
    /// Delta activity level indicator (High, Medium, Low)
    /// </summary>
    public string DeltaActivityLevel
    {
        get
        {
            if (TotalDeltaActivity >= 100_000) return "High";
            if (TotalDeltaActivity >= 1_000) return "Medium";
            if (TotalDeltaActivity > 0) return "Low";
            return "Idle";
        }
    }
}

