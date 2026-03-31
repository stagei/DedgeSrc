using System;

namespace DbExplorer.Models;

/// <summary>
/// Represents data capture (CDC) information for a table.
/// Uses database-agnostic property names for multi-provider support.
/// </summary>
public class DataCaptureInfo
{
    public string SchemaName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string DataCapture { get; set; } = string.Empty;
    public string TablespaceName { get; set; } = string.Empty;
    public string TableType { get; set; } = string.Empty;
    
    /// <summary>
    /// Is data capture enabled?
    /// </summary>
    public bool IsCdcEnabled => DataCapture == "Y" || DataCapture == "L";
    
    /// <summary>
    /// CDC status description
    /// </summary>
    public string CdcStatus
    {
        get
        {
            return DataCapture switch
            {
                "Y" => "Changes Captured",
                "L" => "Changes + Logging",
                "N" => "Not Enabled",
                _ => "Unknown"
            };
        }
    }
    
    /// <summary>
    /// Icon for CDC status
    /// </summary>
    public string CdcIcon
    {
        get
        {
            return IsCdcEnabled ? "✅" : "❌";
        }
    }
}

/// <summary>
/// Filter for CDC monitoring
/// </summary>
public class CdcMonitorFilter
{
    public string? SchemaFilter { get; set; } = "*";
    public bool ShowOnlyDisabled { get; set; } = false;
}

