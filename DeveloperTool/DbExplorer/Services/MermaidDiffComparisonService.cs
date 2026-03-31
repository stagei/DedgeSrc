using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NLog;
using SqlMermaidErdTools.Models;

namespace DbExplorer.Services;

/// <summary>
/// Automatically detects changes when user modifies Mermaid script.
/// Uses SqlMermaidErdTools for accurate comparison.
/// </summary>
public class MermaidDiffComparisonService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly SqlMermaidIntegrationService _sqlMermaidService;
    private readonly MermaidBaselineSnapshotService _baselineService;
    private Timer? _diffCheckTimer;
    private string? _lastCheckedMermaid;
    
    public event EventHandler<DiffDetectedEventArgs>? DiffDetected;
    
    public MermaidDiffComparisonService(
        SqlMermaidIntegrationService sqlMermaidService,
        MermaidBaselineSnapshotService baselineService)
    {
        _sqlMermaidService = sqlMermaidService;
        _baselineService = baselineService;
    }
    
    /// <summary>
    /// Check for differences between baseline and current Mermaid.
    /// Called automatically when user edits Mermaid script.
    /// </summary>
    public void CheckForDifferences(string currentMermaid)
    {
        // Debounce: Wait 1 second after user stops typing
        _diffCheckTimer?.Dispose();
        _diffCheckTimer = new Timer(async _ => await PerformDiffCheckAsync(currentMermaid), 
            null, 1000, Timeout.Infinite);
    }
    
    private async Task PerformDiffCheckAsync(string currentMermaid)
    {
        if (string.IsNullOrEmpty(currentMermaid) || currentMermaid == _lastCheckedMermaid)
        {
            Logger.Debug("Skipping diff check - no changes or already checked");
            return;
        }
        
        _lastCheckedMermaid = currentMermaid;
        
        var baseline = _baselineService.GetBaseline();
        if (string.IsNullOrEmpty(baseline))
        {
            Logger.Debug("No baseline available for diff comparison");
            DiffDetected?.Invoke(this, new DiffDetectedEventArgs
            {
                HasChanges = false,
                Message = "No baseline - Load from DB first"
            });
            return;
        }
        
        // Normalize both strings for comparison (trim, normalize whitespace)
        var normalizedBaseline = NormalizeMermaidString(baseline);
        var normalizedCurrent = NormalizeMermaidString(currentMermaid);
        
        if (normalizedBaseline == normalizedCurrent)
        {
            Logger.Debug("No changes detected - Mermaid matches baseline (after normalization)");
            DiffDetected?.Invoke(this, new DiffDetectedEventArgs
            {
                HasChanges = false,
                Message = "No changes detected"
            });
            return;
        }
        
        try
        {
            Logger.Info("Detecting differences between baseline and current Mermaid");
            Logger.Debug("Baseline length: {BaselineLength}, Current length: {CurrentLength}", 
                baseline.Length, currentMermaid.Length);
            Logger.Debug("Normalized baseline length: {BaselineLength}, Normalized current length: {CurrentLength}", 
                normalizedBaseline.Length, normalizedCurrent.Length);
            
            // Use SqlMermaidErdTools to generate diff ALTER statements
            // Use normalized versions for comparison to avoid false positives from whitespace
            var diffDdl = await _sqlMermaidService.GenerateMigrationFromMermaidDiffAsync(
                normalizedBaseline,
                normalizedCurrent,
                SqlDialect.AnsiSql);
            
            var hasChanges = !string.IsNullOrWhiteSpace(diffDdl) && 
                            !diffDdl.Contains("-- No changes detected", StringComparison.OrdinalIgnoreCase);
            
            if (hasChanges)
            {
                Logger.Info("Changes detected - Generated {Length} characters of ALTER statements", diffDdl.Length);
                Logger.Debug("Diff DDL preview (first 500 chars): {Preview}", 
                    diffDdl.Substring(0, Math.Min(500, diffDdl.Length)));
                
                // Parse diff DDL to count changes
                var changeCount = CountChangesInDdl(diffDdl);
                
                DiffDetected?.Invoke(this, new DiffDetectedEventArgs
                {
                    HasChanges = true,
                    DiffDdl = diffDdl,
                    ChangeCount = changeCount,
                    Message = $"Detected {changeCount} change(s) - Click 'Show Diff' to view"
                });
            }
            else
            {
                Logger.Debug("No changes detected by SqlMermaidErdTools");
                DiffDetected?.Invoke(this, new DiffDetectedEventArgs
                {
                    HasChanges = false,
                    Message = "No changes detected"
                });
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during diff comparison");
            DiffDetected?.Invoke(this, new DiffDetectedEventArgs
            {
                HasChanges = false,
                Message = $"Error: {ex.Message}",
                Error = ex
            });
        }
    }
    
    private int CountChangesInDdl(string ddl)
    {
        // Count ALTER TABLE statements
        var alterMatches = System.Text.RegularExpressions.Regex.Matches(
            ddl, 
            @"ALTER\s+TABLE", 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        return alterMatches.Count;
    }
    
    /// <summary>
    /// Normalizes Mermaid string for comparison by removing extra whitespace and normalizing line endings.
    /// </summary>
    private string NormalizeMermaidString(string mermaid)
    {
        if (string.IsNullOrEmpty(mermaid))
            return string.Empty;
        
        // Normalize line endings to \n
        var normalized = mermaid.Replace("\r\n", "\n").Replace("\r", "\n");
        
        // Remove trailing whitespace from each line
        var lines = normalized.Split('\n');
        var trimmedLines = lines.Select(line => line.TrimEnd()).ToList();
        
        // Remove empty lines at the end
        while (trimmedLines.Count > 0 && string.IsNullOrWhiteSpace(trimmedLines[trimmedLines.Count - 1]))
        {
            trimmedLines.RemoveAt(trimmedLines.Count - 1);
        }
        
        return string.Join("\n", trimmedLines);
    }
    
    public void Dispose()
    {
        _diffCheckTimer?.Dispose();
    }
}

/// <summary>
/// Event arguments for diff detection.
/// </summary>
public class DiffDetectedEventArgs : EventArgs
{
    public bool HasChanges { get; set; }
    public string? DiffDdl { get; set; }
    public int ChangeCount { get; set; }
    public string Message { get; set; } = string.Empty;
    public Exception? Error { get; set; }
}
