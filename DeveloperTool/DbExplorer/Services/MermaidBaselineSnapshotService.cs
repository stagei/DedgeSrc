using System;
using System.Collections.Generic;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Manages baseline snapshots of Mermaid diagrams for comparison.
/// Maintains a snapshot of the current database state (Mermaid ERD) that represents the "truth" for comparison.
/// </summary>
public class MermaidBaselineSnapshotService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private string? _currentBaselineMermaid;
    private DateTime? _baselineTimestamp;
    private string? _baselineConnectionProfile;
    private List<string> _baselineTableList = new();
    
    /// <summary>
    /// Capture current database state as baseline snapshot.
    /// Called automatically when user loads tables from DB.
    /// </summary>
    public async Task CaptureBaselineAsync(
        IConnectionManager connectionManager,
        List<string> selectedTables,
        string mermaidDiagram)
    {
        Logger.Info("Capturing baseline snapshot for {Count} tables", selectedTables.Count);
        Logger.Debug("Selected tables: {Tables}", string.Join(", ", selectedTables));
        
        _currentBaselineMermaid = mermaidDiagram;
        _baselineTimestamp = DateTime.Now;
        _baselineConnectionProfile = connectionManager.ConnectionInfo.Name;
        _baselineTableList = new List<string>(selectedTables);
        
        Logger.Info("Baseline captured at {Timestamp} for profile {Profile}", 
            _baselineTimestamp, _baselineConnectionProfile);
        Logger.Debug("Baseline Mermaid length: {Length} characters", mermaidDiagram.Length);
        Logger.Debug("Baseline contains {Count} tables: {Tables}", 
            _baselineTableList.Count, string.Join(", ", _baselineTableList));
    }
    
    /// <summary>
    /// Get current baseline snapshot.
    /// </summary>
    public string? GetBaseline()
    {
        return _currentBaselineMermaid;
    }
    
    /// <summary>
    /// Check if baseline exists.
    /// </summary>
    public bool HasBaseline()
    {
        return !string.IsNullOrEmpty(_currentBaselineMermaid);
    }
    
    /// <summary>
    /// Get baseline metadata.
    /// </summary>
    public BaselineMetadata GetBaselineMetadata()
    {
        return new BaselineMetadata
        {
            Timestamp = _baselineTimestamp,
            ConnectionProfile = _baselineConnectionProfile,
            TableCount = _baselineTableList.Count,
            Tables = new List<string>(_baselineTableList)
        };
    }
    
    /// <summary>
    /// Clear baseline (when user starts fresh).
    /// </summary>
    public void ClearBaseline()
    {
        Logger.Info("Clearing baseline snapshot");
        _currentBaselineMermaid = null;
        _baselineTimestamp = null;
        _baselineConnectionProfile = null;
        _baselineTableList.Clear();
    }
}

/// <summary>
/// Metadata about the baseline snapshot.
/// </summary>
public class BaselineMetadata
{
    public DateTime? Timestamp { get; set; }
    public string? ConnectionProfile { get; set; }
    public int TableCount { get; set; }
    public List<string> Tables { get; set; } = new();
}
