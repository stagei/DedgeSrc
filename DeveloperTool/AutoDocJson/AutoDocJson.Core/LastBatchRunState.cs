using System;
using System.Diagnostics;
using System.IO;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AutoDocNew.Core;

/// <summary>
/// Manages LastBatchRunStart.json (persistent timestamp for change detection)
/// and BatchRunnerStarted.json (PID lock file to prevent concurrent runs).
/// Replaces the legacy LastExecutionStore / AutoDocBatchRunner.dat mechanism.
/// </summary>
public static class LastBatchRunState
{
    private const string LastRunFileName = "LastBatchRunStart.json";
    private const string LockFileName = "BatchRunnerStarted.json";

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    // ── LastBatchRunStart.json ────────────────────────────────────────────

    /// <summary>
    /// Read the previous batch run timestamp. Returns UTC DateTime.
    /// Falls back to 10 days ago if file is missing or invalid.
    /// </summary>
    public static DateTime ReadPreviousStartedAt(string autoDocDataFolder)
    {
        string path = Path.Combine(autoDocDataFolder, LastRunFileName);
        if (!File.Exists(path))
        {
            Logger.LogMessage($"{LastRunFileName} not found, falling back to 10 days ago", LogLevel.WARN);
            return DateTime.UtcNow.AddDays(-10);
        }

        try
        {
            string json = File.ReadAllText(path);
            var state = JsonSerializer.Deserialize<BatchRunStartInfo>(json, JsonOpts);
            if (state?.StartedAt != null && state.StartedAt.Value > DateTime.MinValue)
            {
                Logger.LogMessage($"Previous batch run: {state.StartedAt:O} (mode={state.Mode}, machine={state.MachineName})", LogLevel.INFO);
                return state.StartedAt.Value.ToUniversalTime();
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error reading {LastRunFileName}: {ex.Message}", LogLevel.WARN);
        }

        Logger.LogMessage($"{LastRunFileName} invalid, falling back to 10 days ago", LogLevel.WARN);
        return DateTime.UtcNow.AddDays(-10);
    }

    /// <summary>
    /// Write the current batch run timestamp. Called AFTER git pull/clone completes.
    /// </summary>
    public static void WriteCurrentStartedAt(string autoDocDataFolder, DateTime startedAtUtc, string mode)
    {
        string path = Path.Combine(autoDocDataFolder, LastRunFileName);
        var state = new BatchRunStartInfo
        {
            StartedAt = startedAtUtc,
            Mode = mode,
            MachineName = Environment.MachineName
        };

        try
        {
            string json = JsonSerializer.Serialize(state, JsonOpts);
            File.WriteAllText(path, json);
            Logger.LogMessage($"Written {LastRunFileName}: startedAt={startedAtUtc:O}, mode={mode}", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing {LastRunFileName}: {ex.Message}", LogLevel.WARN);
        }
    }

    // ── BatchRunnerStarted.json (PID lock) ───────────────────────────────

    /// <summary>
    /// Check if another batch runner instance is already running.
    /// Returns true if a valid lock is held (caller should exit).
    /// Cleans up stale locks automatically.
    /// </summary>
    public static bool IsAnotherInstanceRunning(string autoDocDataFolder)
    {
        string path = Path.Combine(autoDocDataFolder, LockFileName);
        if (!File.Exists(path))
            return false;

        try
        {
            string json = File.ReadAllText(path);
            var lockInfo = JsonSerializer.Deserialize<BatchRunnerLockInfo>(json, JsonOpts);
            if (lockInfo == null || lockInfo.Pid <= 0)
            {
                Logger.LogMessage($"Stale {LockFileName} (no PID), removing", LogLevel.WARN);
                TryDeleteFile(path);
                return false;
            }

            if (IsLockHeldByRunningProcess(lockInfo.Pid, lockInfo.ExeName ?? ""))
            {
                Logger.LogMessage(
                    $"Another BatchRunner is already running (PID={lockInfo.Pid}, exe={lockInfo.ExeName}, " +
                    $"started={lockInfo.StartedAt:O}). Exiting.", LogLevel.ERROR);
                return true;
            }

            Logger.LogMessage(
                $"Stale {LockFileName} found (PID={lockInfo.Pid} no longer running as {lockInfo.ExeName}), removing", LogLevel.WARN);
            TryDeleteFile(path);
            return false;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error reading {LockFileName}: {ex.Message}. Removing and continuing.", LogLevel.WARN);
            TryDeleteFile(path);
            return false;
        }
    }

    /// <summary>
    /// Write the PID lock file at job start.
    /// </summary>
    public static void WriteLockFile(string autoDocDataFolder, CommandLineOptions options, int threadCount)
    {
        string path = Path.Combine(autoDocDataFolder, LockFileName);
        var currentProcess = Process.GetCurrentProcess();

        var lockInfo = new BatchRunnerLockInfo
        {
            StartedAt = DateTime.UtcNow,
            MachineName = Environment.MachineName,
            Pid = Environment.ProcessId,
            ExeName = currentProcess.ProcessName,
            RegenerateMode = options.Regenerate.ToString(),
            FileTypes = options.FileTypes ?? Array.Empty<string>(),
            Parallel = options.Parallel,
            ThreadCount = threadCount,
            MaxFilesPerType = options.MaxFilesPerType,
            SkipExisting = options.SkipExisting,
            DotnetVersion = Environment.Version.ToString(),
            CommandLine = Environment.CommandLine
        };

        try
        {
            string json = JsonSerializer.Serialize(lockInfo, JsonOpts);
            File.WriteAllText(path, json);
            Logger.LogMessage($"Written {LockFileName}: PID={lockInfo.Pid}, mode={lockInfo.RegenerateMode}", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing {LockFileName}: {ex.Message}", LogLevel.WARN);
        }
    }

    /// <summary>
    /// Remove the PID lock file. Called in finally block when job finishes.
    /// </summary>
    public static void RemoveLockFile(string autoDocDataFolder)
    {
        string path = Path.Combine(autoDocDataFolder, LockFileName);
        TryDeleteFile(path);
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// <summary>
    /// Verify that a PID is running AND the process executable matches.
    /// Both must match because PIDs are recycled by the OS.
    /// </summary>
    private static bool IsLockHeldByRunningProcess(int pid, string expectedExeName)
    {
        try
        {
            var proc = Process.GetProcessById(pid);
            return string.Equals(
                Path.GetFileNameWithoutExtension(proc.ProcessName),
                Path.GetFileNameWithoutExtension(expectedExeName),
                StringComparison.OrdinalIgnoreCase);
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

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }
}

// ── JSON models ──────────────────────────────────────────────────────────

public class BatchRunStartInfo
{
    public DateTime? StartedAt { get; set; }
    public string? Mode { get; set; }
    public string? MachineName { get; set; }
}

public class BatchRunnerLockInfo
{
    public DateTime? StartedAt { get; set; }
    public string? MachineName { get; set; }
    public int Pid { get; set; }
    public string? ExeName { get; set; }
    public string? RegenerateMode { get; set; }
    public string[]? FileTypes { get; set; }
    public bool Parallel { get; set; }
    public int ThreadCount { get; set; }
    public int MaxFilesPerType { get; set; }
    public bool SkipExisting { get; set; }
    public string? DotnetVersion { get; set; }
    public string? CommandLine { get; set; }
}
