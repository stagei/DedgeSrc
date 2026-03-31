namespace ServerMonitor.Core.Models;

/// <summary>
/// Scheduled task monitoring data with metadata
/// </summary>
public class ScheduledTaskData
{
    public string TaskPath { get; init; } = string.Empty;
    public string TaskName { get; init; } = string.Empty;
    public string State { get; init; } = string.Empty;
    public DateTime? LastRunTime { get; init; }
    public int? LastRunResult { get; init; }
    public DateTime? NextRunTime { get; init; }
    public int MissedRuns { get; init; }
    public bool IsEnabled { get; init; }
    
    /// <summary>
    /// Task description from task definition
    /// </summary>
    public string? Description { get; init; }
    
    /// <summary>
    /// User account that runs the task
    /// </summary>
    public string? RunAsUser { get; init; }
    
    /// <summary>
    /// Whether the task runs only when the user is logged on.
    /// True = Run only when user is logged on (interactive)
    /// False = Run whether user is logged on or not (background)
    /// </summary>
    public bool RunOnlyIfLoggedOn { get; init; }
    
    /// <summary>
    /// Author of the task (from registration info)
    /// </summary>
    public string? Author { get; init; }
    
    /// <summary>
    /// Date when the task was created/registered
    /// </summary>
    public DateTime? RegistrationDate { get; init; }
    
    /// <summary>
    /// Command/executable to run (from first Exec action)
    /// </summary>
    public string? Command { get; init; }
    
    /// <summary>
    /// Command arguments (from first Exec action)
    /// </summary>
    public string? Arguments { get; init; }
    
    /// <summary>
    /// Working directory for the task (from first Exec action)
    /// </summary>
    public string? WorkingDirectory { get; init; }
}

