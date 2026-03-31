using System;

namespace DbExplorer.Models;

/// <summary>
/// Represents table statistics information.
/// Uses database-agnostic property names for multi-provider support.
/// </summary>
public class TableStatistics
{
    public string SchemaName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public DateTime? StatsTime { get; set; }
    public string TablespaceName { get; set; } = string.Empty;
    public long? CardinalityEstimate { get; set; }
    
    /// <summary>
    /// Days since last statistics update
    /// </summary>
    public int? DaysSinceUpdate
    {
        get
        {
            if (!StatsTime.HasValue)
                return null;
            
            return (int)(DateTime.Now - StatsTime.Value).TotalDays;
        }
    }
    
    /// <summary>
    /// Status level for statistics freshness
    /// </summary>
    public string StatsStatus
    {
        get
        {
            if (!StatsTime.HasValue)
                return "Never Analyzed";
            
            var days = DaysSinceUpdate ?? 0;
            
            if (days > 90) return "Critical";
            if (days > 30) return "Warning";
            if (days > 7) return "Caution";
            return "Good";
        }
    }
    
    /// <summary>
    /// Icon for status
    /// </summary>
    public string StatsIcon
    {
        get
        {
            return StatsStatus switch
            {
                "Critical" => "🔴",
                "Warning" => "⚠️",
                "Caution" => "⚡",
                "Good" => "✅",
                _ => "❓"
            };
        }
    }
}

/// <summary>
/// Filter for statistics monitoring
/// </summary>
public class StatisticsFilter
{
    public string? SchemaFilter { get; set; } = "*";
    public bool ShowOnlyOutdated { get; set; } = false;
    public int OutdatedThresholdDays { get; set; } = 30;
}

