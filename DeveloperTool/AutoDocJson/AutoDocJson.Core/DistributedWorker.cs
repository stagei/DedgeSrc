using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using Microsoft.Extensions.Configuration;

namespace AutoDocNew.Core;

/// <summary>
/// Distributed worker that watches for the server's BatchRunnerStarted.json trigger,
/// then consumes worklist items randomly from the shared _regenerate_worklist folder.
/// Must NOT run on the same machine as the primary batch runner server.
/// </summary>
public class DistributedWorker
{
    private readonly CommandLineOptions _options;
    private readonly ISingleFileParser _parser;
    private readonly string _serverName;
    private readonly string _serverDataPath;
    private readonly string _serverOutputPath;
    private readonly string _worklistPath;
    private readonly string _triggerFilePath;

    private static readonly Random Rng = new();

    public DistributedWorker(CommandLineOptions options, ISingleFileParser parser, string serverName)
    {
        _options = options;
        _parser = parser;
        _serverName = serverName;
        _serverDataPath = $"\\\\{serverName}\\opt\\data\\AutoDocJson";
        _serverOutputPath = $"\\\\{serverName}\\opt\\Webs\\AutoDocJson";
        _worklistPath = Path.Combine(_serverDataPath, WorklistManager.WorklistFolderName);
        _triggerFilePath = Path.Combine(_serverDataPath, "BatchRunnerStarted.json");
    }

    /// <summary>
    /// Validate configuration and start the watch loop.
    /// Returns exit code (0 = clean shutdown, 1 = error).
    /// </summary>
    public int Run()
    {
        if (string.Equals(Environment.MachineName, _serverName, StringComparison.OrdinalIgnoreCase))
        {
            Logger.LogMessage(
                $"Distributed worker cannot run on the primary server ({_serverName}). " +
                "Use the normal batch runner instead.", LogLevel.ERROR);
            return 1;
        }

        Logger.LogMessage($"Distributed Worker starting on {Environment.MachineName}", LogLevel.INFO);
        Logger.LogMessage($"  Server: {_serverName}", LogLevel.INFO);
        Logger.LogMessage($"  Worklist: {_worklistPath}", LogLevel.INFO);
        Logger.LogMessage($"  Output: {_serverOutputPath}", LogLevel.INFO);
        Logger.LogMessage($"  Trigger: {_triggerFilePath}", LogLevel.INFO);

        if (!Directory.Exists(_serverDataPath))
        {
            Logger.LogMessage($"Server data path not accessible: {_serverDataPath}", LogLevel.ERROR);
            return 1;
        }

        // If the trigger file already exists, process immediately
        if (File.Exists(_triggerFilePath))
        {
            Logger.LogMessage("BatchRunnerStarted.json already present, starting worklist processing", LogLevel.INFO);
            ProcessWorklist();
        }

        Logger.LogMessage("Watching for BatchRunnerStarted.json...", LogLevel.INFO);
        Logger.LogMessage("Press Ctrl+C to stop.", LogLevel.INFO);

        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            cts.Cancel();
            Logger.LogMessage("Shutdown requested, finishing current item...", LogLevel.INFO);
        };

        WatchLoop(cts.Token);

        Logger.LogMessage("Distributed Worker stopped.", LogLevel.INFO);
        return 0;
    }

    private void WatchLoop(CancellationToken ct)
    {
        try
        {
            using var watcher = new FileSystemWatcher(_serverDataPath)
            {
                Filter = "BatchRunnerStarted.json",
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.CreationTime | NotifyFilters.LastWrite,
                EnableRaisingEvents = true
            };

            while (!ct.IsCancellationRequested)
            {
                var result = watcher.WaitForChanged(WatcherChangeTypes.Created | WatcherChangeTypes.Changed, 5000);
                if (result.TimedOut)
                    continue;

                Logger.LogMessage("BatchRunnerStarted.json detected! Waiting 10s for worklist population...", LogLevel.INFO);
                if (ct.WaitHandle.WaitOne(10_000))
                    break;

                ProcessWorklist();
                Logger.LogMessage("Worklist exhausted. Resuming watch...", LogLevel.INFO);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"FileSystemWatcher error: {ex.Message}. Falling back to polling.", LogLevel.WARN);
            PollLoop(ct);
        }
    }

    /// <summary>Fallback when FileSystemWatcher fails on UNC paths.</summary>
    private void PollLoop(CancellationToken ct)
    {
        bool lastSeen = File.Exists(_triggerFilePath);

        while (!ct.IsCancellationRequested)
        {
            if (ct.WaitHandle.WaitOne(15_000))
                break;

            bool exists = File.Exists(_triggerFilePath);
            if (exists && !lastSeen)
            {
                Logger.LogMessage("BatchRunnerStarted.json detected (poll). Waiting 10s for worklist population...", LogLevel.INFO);
                if (ct.WaitHandle.WaitOne(10_000))
                    break;

                ProcessWorklist();
                Logger.LogMessage("Worklist exhausted. Resuming poll...", LogLevel.INFO);
            }
            lastSeen = exists;
        }
    }

    /// <summary>
    /// Consume worklist items randomly until none remain.
    /// Each iteration: list .work files, pick one at random, lock-read-delete, parse.
    /// </summary>
    private void ProcessWorklist()
    {
        DateTime batchStartedAt = ReadBatchStartedAt();
        int processed = 0, errors = 0, skipped = 0;
        var sw = Stopwatch.StartNew();
        int emptyRounds = 0;

        Logger.LogMessage("Processing worklist items...", LogLevel.INFO);

        while (true)
        {
            var item = ClaimRandomItem();
            if (item == null)
            {
                emptyRounds++;
                if (emptyRounds >= 3)
                    break;
                Thread.Sleep(2000);
                continue;
            }
            emptyRounds = 0;

            string displayName = item.FileName ?? item.TableName ?? "(unknown)";

            // Pre-generation check
            if (RegenerationDecider.IsOutputAlreadyFresh(_serverOutputPath, displayName, batchStartedAt))
            {
                Logger.LogMessage($"  SKIP (already fresh): {displayName}", LogLevel.INFO);
                skipped++;
                continue;
            }

            Logger.LogMessage($"  Processing: {item.ParserType} {displayName}", LogLevel.INFO);

            try
            {
                string arg = string.Equals(item.ParserType, "SQL", StringComparison.OrdinalIgnoreCase)
                    ? item.TableName ?? ""
                    : item.UncPath ?? item.LocalPath ?? "";

                string srcRootFolder = Path.Combine(_serverDataPath, "tmp", "DedgeRepository");
                string tmpFolder = Path.Combine(_serverDataPath, "tmp");

                int exitCode = _parser.Parse(
                    arg, _serverOutputPath, tmpFolder, srcRootFolder,
                    _options.ClientSideRender, _options.SaveMmdFiles, _options.GenerateHtml);

                if (exitCode == 0)
                    processed++;
                else
                    errors++;
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"  Error: {displayName}: {ex.Message}", LogLevel.ERROR, ex);
                errors++;
            }
        }

        sw.Stop();
        Logger.LogMessage(
            $"Worklist processing complete: {processed} OK, {errors} errors, {skipped} skipped " +
            $"in {sw.Elapsed:hh\\:mm\\:ss}", LogLevel.INFO);
    }

    /// <summary>
    /// List all .work files, pick one at random, lock-read-delete it.
    /// Returns null if no files available.
    /// </summary>
    private WorklistItem? ClaimRandomItem()
    {
        if (!Directory.Exists(_worklistPath))
            return null;

        string[] workFiles;
        try
        {
            workFiles = Directory.GetFiles(_worklistPath, "*.work");
        }
        catch
        {
            return null;
        }

        if (workFiles.Length == 0)
            return null;

        // Shuffle and try each until one succeeds (others may be locked)
        var shuffled = workFiles.OrderBy(_ => Rng.Next()).ToArray();

        foreach (string workFile in shuffled)
        {
            try
            {
                string json;
                using (var fs = new FileStream(workFile, FileMode.Open, FileAccess.Read, FileShare.None))
                using (var reader = new StreamReader(fs))
                {
                    json = reader.ReadToEnd();
                }
                File.Delete(workFile);

                var item = JsonSerializer.Deserialize<WorklistItem>(json, new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });
                return item;
            }
            catch (IOException)
            {
                // Locked by another worker, try next
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"Error claiming {Path.GetFileName(workFile)}: {ex.Message}", LogLevel.WARN);
            }
        }

        return null;
    }

    private DateTime ReadBatchStartedAt()
    {
        try
        {
            if (File.Exists(_triggerFilePath))
            {
                string json = File.ReadAllText(_triggerFilePath);
                var info = JsonSerializer.Deserialize<BatchRunnerLockInfo>(json, new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });
                if (info?.StartedAt != null)
                    return info.StartedAt.Value.ToUniversalTime();
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Could not read batch start time: {ex.Message}", LogLevel.WARN);
        }

        return DateTime.UtcNow.AddMinutes(-5);
    }

    /// <summary>
    /// Read the server name from appsettings.json. Returns null if not configured.
    /// </summary>
    public static string? ReadServerName()
    {
        string[] possiblePaths =
        {
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "appsettings.json"),
            Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json"),
            Path.Combine(Path.GetDirectoryName(typeof(DistributedWorker).Assembly.Location) ?? "", "appsettings.json")
        };

        string? foundPath = possiblePaths.FirstOrDefault(File.Exists);
        if (foundPath == null)
        {
            Logger.LogMessage("appsettings.json not found for worker config", LogLevel.ERROR);
            return null;
        }

        try
        {
            var config = new ConfigurationBuilder()
                .AddJsonFile(foundPath, optional: false)
                .Build();
            return config["AutoDocJson:ServerName"];
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error reading AutoDocJson:ServerName: {ex.Message}", LogLevel.ERROR);
            return null;
        }
    }
}
