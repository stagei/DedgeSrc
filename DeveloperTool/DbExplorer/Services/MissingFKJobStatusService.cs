using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing Missing FK Discovery batch job status using PID-based tracking.
/// 
/// Simple approach:
/// - Client saves a single file with PID + process executable path when starting job
/// - On check: verify PID exists AND that the process is running the batch job exe (PIDs are reused)
/// - Listen for process exit to re-enable start button
/// - Clean up stale files automatically
/// 
/// File: MissingFK/running_job.json (contains PID + job info + optional ProcessPath)
/// </summary>
public class MissingFKJobStatusService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Gets the base folder for status files.
    /// </summary>
    private static string GetStatusBaseFolder()
    {
        return UserDataFolderHelper.GetMissingFKBaseFolder();
    }

    /// <summary>
    /// Get the path to the running job file.
    /// </summary>
    public static string GetRunningJobFilePath()
    {
        return Path.Combine(GetStatusBaseFolder(), "running_job.json");
    }

    /// <summary>
    /// Get log file path for a job (in project folder). Static filename per folder.
    /// </summary>
    public static string GetLogFilePath(string outputFolder)
    {
        return Path.Combine(outputFolder, "missing_fk_job.log");
    }

    /// <summary>
    /// Save running job info with PID and process executable path. Called by CLIENT when starting a job.
    /// ProcessPath is used to verify the PID is still the batch job (PIDs are reused by the OS).
    /// </summary>
    public void SaveRunningJob(int processId, string jobId, string projectFolder, string? processPath = null)
    {
        Logger.Debug("Saving running job info - PID: {Pid}, JobId: {JobId}, ProcessPath: {Path}", processId, jobId, processPath ?? "(none)");

        try
        {
            // Ensure directory exists
            var baseFolder = GetStatusBaseFolder();
            if (!Directory.Exists(baseFolder))
            {
                Directory.CreateDirectory(baseFolder);
            }

            var jobInfo = new RunningJobInfo
            {
                ProcessId = processId,
                JobId = jobId,
                ProjectFolder = projectFolder,
                StartedAtUtc = DateTime.UtcNow,
                ProcessPath = !string.IsNullOrWhiteSpace(processPath) ? processPath.Trim() : null
            };

            var filePath = GetRunningJobFilePath();
            var json = JsonSerializer.Serialize(jobInfo, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(filePath, json);
            
            Logger.Info("Saved running job file: {Path} (PID: {Pid})", filePath, processId);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save running job info");
            throw;
        }
    }

    /// <summary>
    /// Read running job info from file.
    /// </summary>
    public RunningJobInfo? ReadRunningJob()
    {
        try
        {
            var filePath = GetRunningJobFilePath();
            if (!File.Exists(filePath))
            {
                return null;
            }

            var json = File.ReadAllText(filePath);
            return JsonSerializer.Deserialize<RunningJobInfo>(json);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to read running job file");
            return null;
        }
    }

    /// <summary>
    /// Clear running job file (job completed or no longer running).
    /// </summary>
    public void ClearRunningJob()
    {
        try
        {
            var filePath = GetRunningJobFilePath();
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                Logger.Info("Cleared running job file: {Path}", filePath);
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to clear running job file");
        }
    }

    /// <summary>
    /// Check if a job is currently running: PID exists AND process is running the batch job exe (PID reuse safe).
    /// Returns the running job info if running, null otherwise.
    /// Automatically clears stale files if process doesn't exist or PID was reused by another exe.
    /// </summary>
    public RunningJobInfo? GetRunningJobIfActive()
    {
        var jobInfo = ReadRunningJob();
        if (jobInfo == null)
        {
            return null;
        }

        // Check if the process still exists and is actually the batch job exe (PIDs are reused)
        if (IsProcessRunningBatchJob(jobInfo.ProcessId, jobInfo.ProcessPath))
        {
            Logger.Debug("Job process still running - PID: {Pid}", jobInfo.ProcessId);
            return jobInfo;
        }

        // Process doesn't exist or PID was reused by another executable - clear stale file
        Logger.Info("Job process no longer running or PID reused (PID: {Pid}), clearing stale file", jobInfo.ProcessId);
        ClearRunningJob();
        return null;
    }

    /// <summary>
    /// Check if job is locked (legacy compatibility - uses new PID check).
    /// </summary>
    public bool IsJobLocked(string outputFolder)
    {
        return GetRunningJobIfActive() != null;
    }

    /// <summary>
    /// Check if job is locked (no output folder needed).
    /// </summary>
    public bool IsJobLocked()
    {
        return GetRunningJobIfActive() != null;
    }

    /// <summary>
    /// Acquire job lock (legacy compatibility - just checks if job running).
    /// </summary>
    public bool AcquireJobLock(string outputFolder, string jobId)
    {
        // Check if another job is running
        if (GetRunningJobIfActive() != null)
        {
            return false;
        }
        return true;
    }

    /// <summary>
    /// Release job lock (legacy compatibility - clears running job).
    /// </summary>
    public void ReleaseJobLock(string outputFolder)
    {
        ClearRunningJob();
    }

    /// <summary>
    /// Get lock info (legacy compatibility).
    /// </summary>
    public MissingFKJobLock? GetLockInfo(string outputFolder)
    {
        var jobInfo = GetRunningJobIfActive();
        if (jobInfo == null) return null;

        return new MissingFKJobLock
        {
            JobId = jobInfo.JobId,
            StartedAtUtc = jobInfo.StartedAtUtc
        };
    }

    /// <summary>
    /// Get a Process object for the running job. Can be used to wait for exit.
    /// Returns null if no job running, process not found, or PID was reused by another exe.
    /// </summary>
    public Process? GetRunningJobProcess()
    {
        var jobInfo = ReadRunningJob();
        if (jobInfo == null)
        {
            return null;
        }

        try
        {
            var process = Process.GetProcessById(jobInfo.ProcessId);
            if (process.HasExited)
            {
                ClearRunningJob();
                return null;
            }
            if (!IsProcessRunningBatchJob(jobInfo.ProcessId, jobInfo.ProcessPath))
            {
                return null;
            }
            return process;
        }
        catch (ArgumentException)
        {
            // Process doesn't exist
            ClearRunningJob();
            return null;
        }
    }

    /// <summary>
    /// Check if a process with the given PID is running (existence only).
    /// </summary>
    public static bool IsProcessRunning(int processId)
    {
        try
        {
            var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            // Process doesn't exist
            return false;
        }
        catch (InvalidOperationException)
        {
            // Process has exited
            return false;
        }
    }

    /// <summary>
    /// Check if the given PID is running and is the batch job executable (PID reuse safe).
    /// If expectedProcessPath is null/empty, only existence is checked (legacy JSON without ProcessPath).
    /// </summary>
    public static bool IsProcessRunningBatchJob(int processId, string? expectedProcessPath)
    {
        try
        {
            var process = Process.GetProcessById(processId);
            if (process.HasExited)
            {
                return false;
            }
            if (string.IsNullOrWhiteSpace(expectedProcessPath))
            {
                return true; // Legacy: no path stored, trust PID only
            }
            var actualPath = GetProcessExecutablePath(processId);
            if (string.IsNullOrEmpty(actualPath))
            {
                Logger.Debug("Could not get executable path for PID {Pid}, treating as not our job", processId);
                return false;
            }
            var match = Path.GetFullPath(actualPath).Equals(Path.GetFullPath(expectedProcessPath.Trim()), StringComparison.OrdinalIgnoreCase);
            if (!match)
            {
                Logger.Debug("PID {Pid} is running {Actual}, not batch job {Expected}", processId, actualPath, expectedProcessPath);
            }
            return match;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    /// <summary>
    /// Get the main module executable path for a process. Returns null if inaccessible (e.g. permissions).
    /// </summary>
    private static string? GetProcessExecutablePath(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return process.MainModule?.FileName;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    /// <summary>
    /// Clean up all old status files (job_status_*, job_error_*, .job_lock, etc.)
    /// </summary>
    public void CleanupOldStatusFiles()
    {
        Logger.Debug("Cleaning up old status files");
        
        try
        {
            var baseFolder = GetStatusBaseFolder();
            if (!Directory.Exists(baseFolder))
            {
                return;
            }

            // Patterns to clean up
            var patterns = new[] 
            { 
                "job_status_*.json",
                "job_error_*.json", 
                ".job_lock",
                "missing_fk_status_*.json",
                "missing_fk_error_*.json"
            };

            int deletedCount = 0;
            foreach (var pattern in patterns)
            {
                var files = Directory.GetFiles(baseFolder, pattern);
                foreach (var file in files)
                {
                    try
                    {
                        File.Delete(file);
                        deletedCount++;
                        Logger.Debug("Deleted old status file: {File}", file);
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, "Failed to delete old status file: {File}", file);
                    }
                }
            }

            // Also clean up project folders
            var projectsFolder = Path.Combine(baseFolder, "Projects");
            if (Directory.Exists(projectsFolder))
            {
                foreach (var projectDir in Directory.GetDirectories(projectsFolder))
                {
                    foreach (var pattern in patterns)
                    {
                        var files = Directory.GetFiles(projectDir, pattern);
                        foreach (var file in files)
                        {
                            try
                            {
                                File.Delete(file);
                                deletedCount++;
                                Logger.Debug("Deleted old status file from project: {File}", file);
                            }
                            catch (Exception ex)
                            {
                                Logger.Warn(ex, "Failed to delete old status file: {File}", file);
                            }
                        }
                    }
                }
            }

            if (deletedCount > 0)
            {
                Logger.Info("Cleaned up {Count} old status files", deletedCount);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during status file cleanup");
        }
    }
}

/// <summary>
/// Running job info - stored by CLIENT when starting a batch job.
/// ProcessPath is used to verify the PID is still our batch job (PIDs are reused).
/// </summary>
public class RunningJobInfo
{
    public int ProcessId { get; set; }
    public string JobId { get; set; } = string.Empty;
    public string ProjectFolder { get; set; } = string.Empty;
    public DateTime StartedAtUtc { get; set; }
    /// <summary>Full path to the batch job executable; used to verify PID was not reused by another process.</summary>
    public string? ProcessPath { get; set; }
}

/// <summary>
/// Job lock model (legacy compatibility).
/// </summary>
public class MissingFKJobLock
{
    public string JobId { get; set; } = string.Empty;
    public DateTime StartedAtUtc { get; set; }
}
