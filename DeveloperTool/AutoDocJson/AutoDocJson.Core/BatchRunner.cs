using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using Microsoft.Extensions.Configuration;

namespace AutoDocNew.Core;

/// <summary>
/// Batch Runner - main orchestration logic converted from AutoDocBatchRunner.ps1.
/// Covers the ENTIRE main script body (lines 2057-3203) and all handler functions.
/// Author: Geir Helge Starholm, www.dEdge.no
/// </summary>
public class BatchRunner
{
    private readonly CommandLineOptions _options;
    private readonly ISingleFileParser? _singleFileParser;
    private readonly ICSharpProjectRunner? _csharpRunner;
    private readonly IGsFileRunner? _gsRunner;

    private static readonly string[] ProtectedFiles = { "index.html", "web.config" };

    /// <summary>File type to output patterns (HTML, MMD, ERR) for Clean mode.</summary>
    private static readonly Dictionary<string, string[]> FileTypePatterns = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Cbl"] = new[] { "*.cbl.html" },
        ["Rex"] = new[] { "*.rex.html" },
        ["Bat"] = new[] { "*.bat.html" },
        ["Ps1"] = new[] { "*.ps1.html" },
        ["Sql"] = new[] { "*.sql.html" },
        ["CSharp"] = new[] { "*.csharp.html" },
        ["Gs"] = new[] { "*.screen.html", "*.gs.html" }
    };

    public BatchRunner(CommandLineOptions options,
        ISingleFileParser? singleFileParser = null,
        ICSharpProjectRunner? csharpRunner = null,
        IGsFileRunner? gsRunner = null)
    {
        _options = options;
        _singleFileParser = singleFileParser;
        _csharpRunner = csharpRunner;
        _gsRunner = gsRunner;
    }

    /// <summary>
    /// Run the batch processing.
    /// Flow: PID lock → Folder setup → Clean mode → Static assets → Unzip → Repo sync
    ///       → Write timestamp → Git change detection → Worklist creation → Cobdok export
    ///       → Process worklist → CSharp → GS → Smart SQL interactions → JSON indexes
    ///       → Zip → Error list → SMS → Remove PID lock
    /// </summary>
    public int Run()
    {
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        string autoDocDataFolder = Path.Combine(optPath, "data", "AutoDocJson");
        CreateFolderIfNeeded(autoDocDataFolder);

        // ── PID lock check ──────────────────────────────────────────────
        if (LastBatchRunState.IsAnotherInstanceRunning(autoDocDataFolder))
            return 2;

        try
        {
            return RunCore(optPath, autoDocDataFolder);
        }
        finally
        {
            LastBatchRunState.RemoveLockFile(autoDocDataFolder);
        }
    }

    private int RunCore(string optPath, string autoDocDataFolder)
    {
        try
        {
            var runStartTime = DateTime.UtcNow;

            // ── Folder setup ────────────────────────────────────────────
            string outputFolder = _options.OutputFolder;
            if (string.IsNullOrEmpty(outputFolder))
                outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");

            string workFolderRoot = autoDocDataFolder;
            string tmpFolder = Path.Combine(workFolderRoot, "tmp");
            string workFolder = Path.Combine(workFolderRoot, "tmp", "DedgeRepository");
            string cobdokFolder = Path.Combine(tmpFolder, "cobdok");
            string DedgeFolder = Path.Combine(workFolder, "Dedge");
            string DedgeGsFolder = Path.Combine(DedgeFolder, "gs");
            string DedgeImpFolder = Path.Combine(DedgeFolder, "imp");
            string serverMonitorFolder = Path.Combine(workFolder, "ServerMonitor");

            Logger.LogMessage($"Output folder: {outputFolder}", LogLevel.INFO);
            Logger.LogMessage($"Work folder:   {workFolder}", LogLevel.INFO);
            Logger.LogMessage($"Cobdok folder: {cobdokFolder}", LogLevel.INFO);

            // ── Regenerate-all trigger file check ───────────────────────
            string triggerFile = Path.Combine(autoDocDataFolder, "regenerate-all.trigger");
            if (File.Exists(triggerFile))
            {
                Logger.LogMessage("Regenerate-all trigger detected. Switching to All mode.", LogLevel.WARN);
                _options.Regenerate = RegenerateMode.All;
                try { File.Delete(triggerFile); } catch { }
                Logger.LogMessage("Regenerate-all trigger processed. Mode set to All.", LogLevel.INFO);
            }

            // ── Clean mode ──────────────────────────────────────────────
            if (_options.Regenerate == RegenerateMode.Clean)
                ExecuteCleanMode(outputFolder, autoDocDataFolder, workFolderRoot, workFolder, tmpFolder);

            if (_options.Regenerate == RegenerateMode.All)
                Logger.LogMessage("All mode: Will regenerate all files (overwrite existing, no deletions)", LogLevel.INFO);

            // Create essential folders
            CreateFolderIfNeeded(autoDocDataFolder);
            CreateFolderIfNeeded(tmpFolder);
            CreateFolderIfNeeded(cobdokFolder);
            CreateFolderIfNeeded(outputFolder);

            // ── Thread configuration ────────────────────────────────────
            int totalCores = Environment.ProcessorCount;
            int threadCount;
            if (_options.ThreadCountMax > 0)
                threadCount = Math.Max(2, Math.Min(_options.ThreadCountMax, totalCores));
            else
                threadCount = Math.Max(2, (int)Math.Floor(totalCores * (_options.ThreadPercentage / 100.0)));

            // ── Write PID lock file ─────────────────────────────────────
            LastBatchRunState.WriteLockFile(autoDocDataFolder, _options, threadCount);

            string machineName = Environment.MachineName.ToLower();
            Logger.LogMessage($"AutoDocBatchRunner started on: {machineName}. Parameter regenerate = {_options.Regenerate}", LogLevel.INFO);
            Logger.LogMessage($"Started AutoDocJson using .NET version: {Environment.Version}", LogLevel.INFO);
            Logger.LogMessage($"Thread configuration: {threadCount} threads (Cores: {totalCores})", LogLevel.INFO);

            // ── Copy static assets ──────────────────────────────────────
            CopyStaticAssetsToOutput(outputFolder);

            string jsonOutputFolder = Path.Combine(outputFolder, "_json");
            CreateFolderIfNeeded(jsonOutputFolder);

            // ── JsonOnly mode ───────────────────────────────────────────
            if (_options.Regenerate == RegenerateMode.JsonOnly)
            {
                Logger.LogMessage("JsonOnly mode: Regenerating JSON index files only.", LogLevel.INFO);
                JsonIndexService.UpdateAll(outputFolder, cobdokFolder, serverMonitorFolder);
                Logger.LogMessage("Batch processing completed (JsonOnly).", LogLevel.INFO);
                return 0;
            }

            // ── Unzip on test server ────────────────────────────────────
            ContentZipHelper.UnzipIfNeeded(outputFolder, tmpFolder);

            // ── Read previous batch run timestamp (BEFORE git sync) ─────
            DateTime previousStartedAt = LastBatchRunState.ReadPreviousStartedAt(autoDocDataFolder);

            // ── Repo sync ───────────────────────────────────────────────
            {
                bool workFolderHasRepos = Directory.Exists(workFolder)
                    && Directory.EnumerateDirectories(workFolder).Any(d =>
                        Directory.EnumerateFiles(d, "*", SearchOption.AllDirectories).Any());

                if (_options.SkipExisting && workFolderHasRepos)
                {
                    Logger.LogMessage("SkipExisting: Repos already present, skipping repo sync.", LogLevel.INFO);
                }
                else
                {
                    Logger.LogMessage("Discovering and updating source repositories from Azure DevOps...", LogLevel.INFO);
                    CreateFolderIfNeeded(workFolder);
                    var repoSync = new RepoSyncService();
                    var (synced, failed) = repoSync.Sync(workFolder);
                    Logger.LogMessage($"Source repositories updated: {synced} synced, {failed} failed.", LogLevel.INFO);
                }
            }

            // ── Write CURRENT batch run timestamp (AFTER git sync) ──────
            if (_options.Regenerate != RegenerateMode.Errors)
            {
                LastBatchRunState.WriteCurrentStartedAt(
                    autoDocDataFolder, runStartTime, _options.Regenerate.ToString());
            }

            // ── Cobdok export ───────────────────────────────────────────
            {
                string[] requiredCsvFiles = {
                    "call", "cobdok_meny", "copy", "copyset", "delsystem", "modul", "modkom", "sqlxtab", "tiltp_log",
                    "tables", "columns", "indexes", "indexcoluse", "tabconst", "keycoluse", "references", "checks",
                    "triggers", "packagedep", "routinedep"
                };
                bool allCsvsPresent = Directory.Exists(cobdokFolder)
                    && requiredCsvFiles.All(f => File.Exists(Path.Combine(cobdokFolder, f + ".csv")));

                if (_options.SkipExisting && allCsvsPresent)
                {
                    Logger.LogMessage("SkipExisting: All cobdok CSV files present, skipping db2 export.", LogLevel.INFO);
                }
                else
                {
                    CobdokExportService.Export(cobdokFolder);
                }
            }

            // ── Source file cache ───────────────────────────────────────
            {
                bool useCache = false;
                try
                {
                    var configBuilder = new ConfigurationBuilder();
                    string[] possiblePaths = new[]
                    {
                        Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "appsettings.json"),
                        Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json"),
                        Path.Combine(Path.GetDirectoryName(typeof(BatchRunner).Assembly.Location) ?? "", "appsettings.json")
                    };
                    string? foundPath = possiblePaths.FirstOrDefault(File.Exists);
                    if (foundPath != null)
                    {
                        var config = configBuilder.AddJsonFile(foundPath, optional: true).Build();
                        string? cacheValue = config["Performance:UseSourceFileCache"];
                        if (bool.TryParse(cacheValue, out bool parsed))
                            useCache = parsed;
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Failed to read Performance config: {ex.Message}", LogLevel.WARN);
                }

                if (useCache)
                {
                    Logger.LogMessage("SourceFileCache: Preloading source files into memory...", LogLevel.INFO);
                    var cacheSw = Stopwatch.StartNew();
                    SourceFileCache.PreloadAll(workFolder);
                    SourceFileCache.PreloadCobdok(cobdokFolder);
                    cacheSw.Stop();
                    Logger.LogMessage($"SourceFileCache: Ready. {SourceFileCache.CachedFileCount} files cached in {cacheSw.Elapsed.TotalSeconds:F1}s", LogLevel.INFO);
                }
                else
                {
                    Logger.LogMessage("SourceFileCache: Disabled (Performance:UseSourceFileCache = false)", LogLevel.INFO);
                }
            }

            // ── Single file mode ────────────────────────────────────────
            if (!string.IsNullOrWhiteSpace(_options.SingleFile))
            {
                if (_singleFileParser == null)
                {
                    Logger.LogMessage("Single file mode requires a parser implementation (ISingleFileParser).", LogLevel.ERROR);
                    return 1;
                }
                Logger.LogMessage($"Single file mode: Processing {_options.SingleFile}", LogLevel.INFO);
                int exitCode = _singleFileParser.Parse(
                    _options.SingleFile.Trim(), outputFolder, tmpFolder, workFolder,
                    _options.ClientSideRender, _options.SaveMmdFiles, _options.GenerateHtml);
                Logger.LogMessage($"Single file processing complete: {_options.SingleFile}", LogLevel.INFO);
                return exitCode;
            }

            // ── Build file type set ─────────────────────────────────────
            var fileTypes = (_options.FileTypes ?? Array.Empty<string>())
                .Where(t => !string.Equals(t, "All", StringComparison.OrdinalIgnoreCase))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (fileTypes.Count == 0)
                fileTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                    { "Cbl", "Rex", "Bat", "Ps1", "Sql", "CSharp", "Gs" };

            string regenerateStr = _options.Regenerate.ToString();
            int maxPerType = _options.MaxFilesPerType;
            if (maxPerType > 0)
                Logger.LogMessage($"Simulation mode: Processing max {maxPerType} files per type", LogLevel.INFO);

            string srcRootFolder = workFolder;

            if (_singleFileParser == null)
            {
                Logger.LogMessage("Batch mode requires a parser implementation (ISingleFileParser).", LogLevel.ERROR);
                return 1;
            }

            // ── Git change detection ────────────────────────────────────
            // For All/Clean: use 2010-01-01 as baseline (= all tracked files)
            // For Incremental: use previous batch run timestamp
            // For Errors: skip change detection (uses .err files)
            DateTime gitSince = _options.Regenerate switch
            {
                RegenerateMode.All or RegenerateMode.Clean => new DateTime(2010, 1, 1, 0, 0, 0, DateTimeKind.Utc),
                _ => previousStartedAt
            };

            List<ChangedFileInfo> changedFiles;
            if (_options.Regenerate == RegenerateMode.Errors)
            {
                Logger.LogMessage("Errors mode: Skipping git change detection, using .err files", LogLevel.INFO);
                changedFiles = new List<ChangedFileInfo>();
            }
            else
            {
                changedFiles = GitChangeDetector.DetectChanges(workFolder, gitSince, fileTypes, maxPerType);
            }

            // ── SQL change detection (from tables.csv ALTER_TIME) ───────
            var sqlWorklistItems = new List<SqlWorklistItem>();
            if (fileTypes.Contains("Sql") && _options.Regenerate != RegenerateMode.Errors)
            {
                string tablesCsv = Path.Combine(cobdokFolder, "tables.csv");
                if (File.Exists(tablesCsv))
                {
                    int sqlLimit = maxPerType > 0 ? maxPerType : int.MaxValue;
                    foreach (string line in File.ReadLines(tablesCsv))
                    {
                        if (sqlWorklistItems.Count >= sqlLimit) break;
                        string[] parts = line.Split(';');
                        if (parts.Length < 5) continue;
                        string schema = parts[0].Trim().Trim('"');
                        string table = parts[1].Trim().Trim('"');
                        string alterTime = (parts.Length > 4 ? parts[4].Trim() : "").Trim('"');
                        if (string.IsNullOrEmpty(schema) || string.IsNullOrEmpty(table)) continue;

                        if (RegenerationDecider.ShouldRegenerateSqlTable(
                            schema, table, alterTime, previousStartedAt, regenerateStr, outputFolder))
                        {
                            sqlWorklistItems.Add(new SqlWorklistItem
                            {
                                TableName = $"{schema}.{table}",
                                AlterTime = alterTime
                            });
                        }
                    }
                    Logger.LogMessage($"SQL tables to regenerate: {sqlWorklistItems.Count}", LogLevel.INFO);
                }
            }

            // ── Create worklist ─────────────────────────────────────────
            string worklistFolder = WorklistManager.CreateWorklist(
                autoDocDataFolder, changedFiles, sqlWorklistItems);

            // ── Claim worklist items and build work queue ───────────────
            var worklistItems = WorklistManager.ClaimWorklistItems(worklistFolder);

            // For Errors mode, use legacy queue builder with .err scanning
            List<WorkItem> workQueue;
            if (_options.Regenerate == RegenerateMode.Errors)
            {
                int legacyLastGen = int.Parse(previousStartedAt.ToString("yyyyMMdd"));
                workQueue = WorkQueueBuilder.Build(
                    workFolder, cobdokFolder, outputFolder,
                    fileTypes, regenerateStr, legacyLastGen, maxPerType);
            }
            else
            {
                workQueue = WorkQueueBuilder.BuildFromWorklist(worklistItems, maxPerType);
            }

            // ── Process work queue (parallel or sequential) ─────────────
            var regeneratedOutputFiles = new ConcurrentDictionary<string, byte>(StringComparer.OrdinalIgnoreCase);
            var counts = new ConcurrentDictionary<string, (int ok, int err)>(StringComparer.OrdinalIgnoreCase);
            foreach (string t in new[] { "CBL", "REX", "BAT", "PS1", "SQL", "GS" })
                counts[t] = (0, 0);
            int totalProcessed = 0;
            int totalErrors = 0;

            if (_options.Parallel && workQueue.Count > 1)
            {
                Logger.LogMessage($"Parallel processing ENABLED: {threadCount} threads on unified queue of {workQueue.Count} items", LogLevel.INFO);
                Logger.LogMessage($"  Queue order: {workQueue.Count(i => i.ParserType != "CBL")} non-CBL first, then {workQueue.Count(i => i.ParserType == "CBL")} CBL items", LogLevel.INFO);

                int processedAtomic = 0;
                int errorsAtomic = 0;

                Parallel.ForEach(workQueue,
                    new ParallelOptions { MaxDegreeOfParallelism = threadCount },
                    item =>
                    {
                        int idx = Interlocked.Increment(ref processedAtomic);
                        string displayName = item.FileName ?? item.TableName ?? "(unknown)";

                        // Pre-generation check: skip if already regenerated by another process
                        if (RegenerationDecider.IsOutputAlreadyFresh(outputFolder, displayName, runStartTime))
                        {
                            Logger.LogMessage($"[{idx}/{workQueue.Count}] {item.ParserType}: {displayName} - SKIP (already fresh)", LogLevel.INFO);
                            return;
                        }

                        Logger.LogMessage($"[{idx}/{workQueue.Count}] {item.ParserType}: {displayName}", LogLevel.INFO);
                        try
                        {
                            int exitCode = DispatchParse(item, outputFolder, tmpFolder, srcRootFolder);
                            if (exitCode == 0)
                            {
                                counts.AddOrUpdate(item.ParserType, (1, 0), (_, v) => (v.ok + 1, v.err));
                                string outputJsonName = (displayName) + ".json";
                                regeneratedOutputFiles.TryAdd(outputJsonName, 0);
                            }
                            else
                            {
                                counts.AddOrUpdate(item.ParserType, (0, 1), (_, v) => (v.ok, v.err + 1));
                                Interlocked.Increment(ref errorsAtomic);
                            }
                        }
                        catch (Exception ex)
                        {
                            Logger.LogMessage($"Error processing {displayName}: {ex.Message}", LogLevel.ERROR, ex);
                            counts.AddOrUpdate(item.ParserType, (0, 1), (_, v) => (v.ok, v.err + 1));
                            WriteErrorFile(item, outputFolder, ex.Message);
                            Interlocked.Increment(ref errorsAtomic);
                        }
                    });

                totalProcessed = processedAtomic - errorsAtomic;
                totalErrors = errorsAtomic;
                Logger.LogMessage("Parallel processing complete", LogLevel.INFO);
            }
            else
            {
                Logger.LogMessage($"Sequential processing mode ({workQueue.Count} items)", LogLevel.INFO);
                for (int i = 0; i < workQueue.Count; i++)
                {
                    var item = workQueue[i];
                    string displayName = item.FileName ?? item.TableName ?? "(unknown)";

                    if (RegenerationDecider.IsOutputAlreadyFresh(outputFolder, displayName, runStartTime))
                    {
                        Logger.LogMessage($"[{i + 1}/{workQueue.Count}] {item.ParserType}: {displayName} - SKIP (already fresh)", LogLevel.INFO);
                        continue;
                    }

                    Logger.LogMessage($"[{i + 1}/{workQueue.Count}] {item.ParserType}: {displayName}", LogLevel.INFO);
                    try
                    {
                        int exitCode = DispatchParse(item, outputFolder, tmpFolder, srcRootFolder);
                        if (exitCode == 0)
                        {
                            counts.AddOrUpdate(item.ParserType, (1, 0), (_, v) => (v.ok + 1, v.err));
                            totalProcessed++;
                            string outputJsonName = (displayName) + ".json";
                            regeneratedOutputFiles.TryAdd(outputJsonName, 0);
                        }
                        else
                        {
                            counts.AddOrUpdate(item.ParserType, (0, 1), (_, v) => (v.ok, v.err + 1));
                            totalErrors++;
                        }
                    }
                    catch (Exception ex)
                    {
                        Logger.LogMessage($"Error processing {displayName}: {ex.Message}", LogLevel.ERROR, ex);
                        counts.AddOrUpdate(item.ParserType, (0, 1), (_, v) => (v.ok, v.err + 1));
                        WriteErrorFile(item, outputFolder, ex.Message);
                        totalErrors++;
                    }
                }
            }

            // ── Handle C# projects ──────────────────────────────────────
            if (fileTypes.Contains("CSharp"))
            {
                if (_options.Regenerate is RegenerateMode.All or RegenerateMode.Clean)
                {
                    HandleCSharpProjects(workFolder, outputFolder, tmpFolder, srcRootFolder,
                        previousStartedAt, regenerateStr);
                }
                else
                {
                    var changedCSharpRepos = GitChangeDetector.DetectCSharpChangedRepos(workFolder, gitSince);
                    if (changedCSharpRepos.Count > 0)
                    {
                        Logger.LogMessage($"C# repos with changes: {string.Join(", ", changedCSharpRepos)}", LogLevel.INFO);
                        HandleCSharpProjects(workFolder, outputFolder, tmpFolder, srcRootFolder,
                            previousStartedAt, regenerateStr, changedCSharpRepos);
                    }
                    else
                    {
                        Logger.LogMessage("No C# repos with changes detected, skipping C# parsing", LogLevel.INFO);
                    }
                }
            }

            // ── Handle GS screensets ────────────────────────────────────
            if (fileTypes.Contains("Gs"))
            {
                bool skipGs = false;
                try
                {
                    string[] cfgPaths = {
                        Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "appsettings.json"),
                        Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json")
                    };
                    string? cfgPath = cfgPaths.FirstOrDefault(File.Exists);
                    if (cfgPath != null)
                    {
                        var cfg = new ConfigurationBuilder().AddJsonFile(cfgPath, optional: true).Build();
                        if (bool.TryParse(cfg["Performance:SkipGsParsing"], out bool parsed))
                            skipGs = parsed;
                    }
                }
                catch { }

                if (skipGs)
                {
                    Logger.LogMessage("GS parsing disabled (Performance:SkipGsParsing = true)", LogLevel.INFO);
                }
                else
                {
                    HandleGsFiles(DedgeGsFolder, DedgeImpFolder, outputFolder, tmpFolder,
                        previousStartedAt, regenerateStr, maxPerType);
                }
            }

            // ── Smart SQL interactions scan ─────────────────────────────
            if (fileTypes.Contains("Sql") && _options.Regenerate != RegenerateMode.Errors)
            {
                Logger.LogMessage("Scanning JSON files for SQL table interactions...", LogLevel.INFO);
                try
                {
                    var (interactions, alterTimes) = SqlInteractionsScanner.Scan(outputFolder, cobdokFolder);
                    if (interactions.Count > 0 && _singleFileParser != null)
                    {
                        var regenSet = new HashSet<string>(
                            regeneratedOutputFiles.Keys, StringComparer.OrdinalIgnoreCase);
                        var tablesToUpdate = SqlInteractionsScanner.FilterTablesWithChangedInteractions(
                            interactions, regenSet);

                        int skipped = 0;
                        Logger.LogMessage(
                            $"Updating SQL interaction diagrams for {tablesToUpdate.Count}/{interactions.Count} tables...",
                            LogLevel.INFO);

                        foreach (var tableRef in interactions.Keys)
                        {
                            if (!tablesToUpdate.Contains(tableRef))
                            {
                                skipped++;
                                continue;
                            }

                            try
                            {
                                _singleFileParser.Parse(tableRef, outputFolder, tmpFolder, workFolder,
                                    _options.ClientSideRender, _options.SaveMmdFiles, _options.GenerateHtml);
                            }
                            catch (Exception ex)
                            {
                                Logger.LogMessage($"Error updating SQL interactions for {tableRef}: {ex.Message}", LogLevel.WARN, ex);
                            }
                        }
                        if (skipped > 0)
                            Logger.LogMessage($"Skipped {skipped} SQL tables (no interacting files changed)", LogLevel.INFO);
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Error scanning for SQL interactions: {ex.Message}", LogLevel.WARN, ex);
                }
            }

            // ── JSON index generation ───────────────────────────────────
            Logger.LogMessage("Create json index files from output folder", LogLevel.INFO);
            JsonIndexService.UpdateAll(outputFolder, cobdokFolder, serverMonitorFolder);

            // ── Zip output & copy ───────────────────────────────────────
            ContentZipHelper.ZipAndCopyIfNeeded(outputFolder, tmpFolder);

            // ── Final statistics ────────────────────────────────────────
            var duration = DateTime.UtcNow - runStartTime;
            int cblDone = CountRecentFiles(outputFolder, "*.cbl.html", runStartTime);
            int rexDone = CountRecentFiles(outputFolder, "*.rex.html", runStartTime);
            int batDone = CountRecentFiles(outputFolder, "*.bat.html", runStartTime);
            int ps1Done = CountRecentFiles(outputFolder, "*.ps1.html", runStartTime);
            int sqlDone = CountRecentFiles(outputFolder, "*.sql.html", runStartTime);
            int csharpDone = CountRecentFiles(outputFolder, "*.csharp.html", runStartTime);
            int gsDone = CountRecentFiles(outputFolder, "*.screen.html", runStartTime);
            int errDone = CountRecentFiles(outputFolder, "*.err", runStartTime);
            int totalDone = cblDone + rexDone + batDone + ps1Done + sqlDone + csharpDone + gsDone;
            double rate = duration.TotalMinutes > 0 ? Math.Round(totalDone / duration.TotalMinutes, 1) : 0;

            Logger.LogMessage("=== FINAL STATISTICS ===", LogLevel.INFO);
            Logger.LogMessage($"Total generated: {totalDone} | Errors: {errDone}", LogLevel.INFO);
            Logger.LogMessage($"By type: CBL={cblDone} REX={rexDone} BAT={batDone} PS1={ps1Done} SQL={sqlDone} C#={csharpDone} GS={gsDone}", LogLevel.INFO);
            Logger.LogMessage($"Duration: {duration:hh\\:mm\\:ss} | Average rate: {rate} files/min", LogLevel.INFO);

            // ── Error file list ─────────────────────────────────────────
            if (Directory.Exists(outputFolder))
            {
                var errFiles = Directory.EnumerateFiles(outputFolder, "*.err").ToList();
                if (errFiles.Count > 0)
                {
                    Logger.LogMessage("List over all *.err files - start", LogLevel.WARN);
                    foreach (string ef in errFiles)
                        Logger.LogMessage($"Error file: {Path.GetFileName(ef)}", LogLevel.WARN);
                    Logger.LogMessage("List over all *.err files - end", LogLevel.WARN);
                }
            }

            Logger.LogMessage("AutoDocBatchRunner completed", LogLevel.INFO);

            // ── SMS notification ────────────────────────────────────────
            string smsMessage = BuildSmsMessage(
                totalDone, cblDone, rexDone, batDone, ps1Done,
                sqlDone, csharpDone, gsDone, errDone, duration);
            Logger.LogMessage($"SMS: {smsMessage}", LogLevel.INFO);
            try
            {
                string smsNumber = GetSmsNumber();
                SmsService.Send(smsNumber, smsMessage);
                Logger.LogMessage("SMS notification sent.", LogLevel.INFO);
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"SMS send failed: {ex.Message}", LogLevel.WARN, ex);
            }

            return totalErrors > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in BatchRunner: {ex.Message}", LogLevel.ERROR, ex);
            return 1;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Dispatch - routes a WorkItem to the correct parser via ISingleFileParser
    // ═══════════════════════════════════════════════════════════════════════
    private int DispatchParse(WorkItem item, string outputFolder, string tmpFolder, string srcRootFolder)
    {
        if (_singleFileParser == null) return 1;

        string arg = item.ParserType == "SQL"
            ? item.TableName ?? ""
            : item.FilePath ?? "";

        return _singleFileParser.Parse(arg, outputFolder, tmpFolder, srcRootFolder,
            _options.ClientSideRender, _options.SaveMmdFiles, _options.GenerateHtml);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HandleCSharpProjects - converted from PS lines 1713-1846
    // Scans all repos for .sln files, generates ecosystem + individual diagrams.
    // ═══════════════════════════════════════════════════════════════════════
    /// <param name="changedRepos">
    /// Optional: only process repos in this set. If null, process all repos.
    /// Used in Incremental mode to skip repos with no detected changes.
    /// </param>
    private void HandleCSharpProjects(string workFolder, string outputFolder, string tmpFolder,
        string srcRootFolder, DateTime previousStartedAt, string regenerate,
        HashSet<string>? changedRepos = null)
    {
        if (!Directory.Exists(workFolder))
        {
            Logger.LogMessage($"Work folder not found: {workFolder} - Skipping C# parsing", LogLevel.WARN);
            return;
        }

        Logger.LogMessage($"Starting C# project parsing for all repositories in {workFolder}...", LogLevel.INFO);

        var allSolutions = Directory.EnumerateFiles(workFolder, "*.sln", SearchOption.AllDirectories)
            .Where(f => !f.Contains("\\bin\\") && !f.Contains("\\obj\\") && !f.Contains("\\.vs\\") && !f.Contains("\\.git\\"))
            .Select(f => new FileInfo(f))
            .ToList();

        if (allSolutions.Count == 0)
        {
            Logger.LogMessage($"No .sln files found in {workFolder}", LogLevel.WARN);
            return;
        }

        Logger.LogMessage($"Found {allSolutions.Count} C# solution(s) across all repositories", LogLevel.INFO);

        int lastGenerationDate = int.Parse(previousStartedAt.ToString("yyyyMMdd"));

        // Step 1: Generate ecosystem diagrams per repository
        var repoNames = allSolutions
            .Select(s => s.Directory?.Parent?.Name ?? "")
            .Where(n => !string.IsNullOrEmpty(n))
            .Distinct()
            .OrderBy(n => n);

        foreach (string repoName in repoNames)
        {
            if (changedRepos != null && !changedRepos.Contains(repoName))
            {
                Logger.LogMessage($"Skipping {repoName} ecosystem - not in changed repos set", LogLevel.INFO);
                continue;
            }

            string repoFolder = Path.Combine(workFolder, repoName);
            if (!Directory.Exists(repoFolder)) continue;

            string ecosystemHtml = Path.Combine(outputFolder, $"{repoName}.ecosystem.csharp.html");
            bool shouldGenerate = true;

            if (regenerate is not ("All" or "Clean") && File.Exists(ecosystemHtml))
            {
                int ecosystemDate = int.Parse(File.GetLastWriteTime(ecosystemHtml).ToString("yyyyMMdd"));
                try
                {
                    var newestFile = Directory.EnumerateFiles(repoFolder, "*.cs", SearchOption.AllDirectories)
                        .Concat(Directory.EnumerateFiles(repoFolder, "*.csproj", SearchOption.AllDirectories))
                        .Where(f => !f.Contains("\\bin\\") && !f.Contains("\\obj\\"))
                        .Select(f => File.GetLastWriteTime(f))
                        .DefaultIfEmpty(DateTime.MinValue)
                        .Max();
                    if (int.Parse(newestFile.ToString("yyyyMMdd")) <= ecosystemDate)
                    {
                        shouldGenerate = false;
                        Logger.LogMessage($"Skipping {repoName} ecosystem - No changes since last generation", LogLevel.INFO);
                    }
                }
                catch { /* generate to be safe */ }
            }

            if (shouldGenerate && _csharpRunner != null)
            {
                try
                {
                    Logger.LogMessage($"Generating ecosystem diagram for {repoName}...", LogLevel.INFO);
                    _csharpRunner.ParseEcosystem(repoFolder, outputFolder, tmpFolder, repoName);
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Error generating ecosystem for {repoName}: {ex.Message}", LogLevel.ERROR, ex);
                }
            }
        }

        // Step 2: Generate individual solution diagrams
        Logger.LogMessage($"Processing {allSolutions.Count} C# solution(s) individually...", LogLevel.INFO);
        foreach (var solution in allSolutions)
        {
            string? parentRepo = solution.Directory?.Parent?.Name;
            if (changedRepos != null && parentRepo != null && !changedRepos.Contains(parentRepo))
            {
                Logger.LogMessage($"Skipping {solution.Name} - repo {parentRepo} not in changed repos set", LogLevel.INFO);
                continue;
            }

            try
            {
                string solutionName = Path.GetFileNameWithoutExtension(solution.Name);
                string htmlPath = Path.Combine(outputFolder, (solutionName + ".csharp.html").ToLower());
                bool shouldRegen = true;

                if (regenerate is not ("All" or "Clean") && File.Exists(htmlPath))
                {
                    int htmlDate = int.Parse(File.GetLastWriteTime(htmlPath).ToString("yyyyMMdd"));
                    int slnDate = int.Parse(solution.LastWriteTime.ToString("yyyyMMdd"));
                    if (slnDate <= htmlDate && slnDate <= lastGenerationDate)
                    {
                        string solDir = solution.DirectoryName ?? "";
                        try
                        {
                            var newestCs = Directory.EnumerateFiles(solDir, "*.cs", SearchOption.AllDirectories)
                                .Select(f => File.GetLastWriteTime(f))
                                .DefaultIfEmpty(DateTime.MinValue)
                                .Max();
                            if (int.Parse(newestCs.ToString("yyyyMMdd")) <= htmlDate)
                            {
                                shouldRegen = false;
                                Logger.LogMessage($"Skipping {solutionName} - No changes since last generation", LogLevel.INFO);
                            }
                        }
                        catch { /* generate */ }
                    }
                }

                if (shouldRegen && _csharpRunner != null)
                {
                    Logger.LogMessage($"Parsing C# solution: {solution.Name}", LogLevel.INFO);
                    _csharpRunner.ParseSolution(
                        solutionFolder: solution.DirectoryName ?? "",
                        solutionFile: solution.FullName,
                        outputFolder: outputFolder,
                        tmpRootFolder: tmpFolder,
                        srcRootFolder: srcRootFolder,
                        clientSideRender: true,
                        cleanUp: true);
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"Error parsing C# solution {solution.Name}: {ex.Message}", LogLevel.ERROR, ex);
            }
        }

        Logger.LogMessage("C# project parsing completed", LogLevel.INFO);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HandleGsFiles - converted from PS lines 1328-1481
    // Processes Dialog System .gs files through dswin.exe → .imp → HTML.
    // ═══════════════════════════════════════════════════════════════════════
    private void HandleGsFiles(string gsFolder, string impFolder, string outputFolder,
        string tmpFolder, DateTime previousStartedAt, string regenerate, int maxPerType)
    {
        if (!Directory.Exists(gsFolder))
        {
            Logger.LogMessage($"GS folder not found: {gsFolder} - skipping", LogLevel.WARN);
            return;
        }

        var gsFiles = new DirectoryInfo(gsFolder).GetFiles("*.gs")
            .Where(f => !f.Name.Contains("-") && !f.Name.Contains("_") && !f.Name.Contains(" "))
            .ToList();

        if (gsFiles.Count == 0)
        {
            Logger.LogMessage($"No GS files found in: {gsFolder}", LogLevel.WARN);
            return;
        }

        Logger.LogMessage($"All GS files: {gsFiles.Count}", LogLevel.INFO);

        int lastGenerationDate = int.Parse(previousStartedAt.ToString("yyyyMMdd"));
        int limit = maxPerType > 0 ? maxPerType : int.MaxValue;
        var toProcess = new List<FileInfo>();
        foreach (var gs in gsFiles)
        {
            if (toProcess.Count >= limit) break;
            string expectedHtml = Path.Combine(outputFolder, gs.Name.Replace(".gs", "").ToUpper() + ".screen.html");
            bool needsRegen = regenerate switch
            {
                "All" or "Clean" => true,
                "Incremental" => !File.Exists(expectedHtml) ||
                    int.Parse(gs.LastWriteTime.ToString("yyyyMMdd")) > lastGenerationDate,
                "Errors" => File.Exists(Path.Combine(outputFolder, gs.Name.Replace(".gs", "").ToUpper() + ".screen.err")),
                _ => false
            };
            if (needsRegen) toProcess.Add(gs);
        }

        Logger.LogMessage($"GS files to process: {toProcess.Count}", LogLevel.INFO);
        int exported = 0, failed = 0;

        if (_gsRunner == null)
        {
            Logger.LogMessage("GS file runner not configured - skipping", LogLevel.WARN);
            return;
        }

        foreach (var gs in toProcess)
        {
            string? result = _gsRunner.ParseGsFile(gs.FullName, impFolder, outputFolder);
            if (result != null) exported++; else failed++;
        }

        Logger.LogMessage($"GS processing complete: {exported} generated, {failed} failed", LogLevel.INFO);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Clean mode - converted from PS lines 2157-2323
    // ═══════════════════════════════════════════════════════════════════════
    private void ExecuteCleanMode(string outputFolder, string autoDocDataFolder,
        string workFolderRoot, string workFolder, string tmpFolder)
    {
        Logger.LogMessage("Clean mode: Resetting AutoDocJson data folders for fresh regeneration...", LogLevel.WARN);

        if (Directory.Exists(tmpFolder))
        {
            Logger.LogMessage($"Removing tmp folder: {tmpFolder}", LogLevel.INFO);
            ForceDeleteDirectory(tmpFolder);
        }

        string lastRunFile = Path.Combine(autoDocDataFolder, "LastBatchRunStart.json");
        if (File.Exists(lastRunFile))
        {
            Logger.LogMessage($"Removing last batch run state file: {lastRunFile}", LogLevel.INFO);
            try { File.Delete(lastRunFile); } catch { }
        }

        // Remove legacy .dat file if present
        string legacyDatFile = Path.Combine(autoDocDataFolder, "AutoDocBatchRunner.dat");
        if (File.Exists(legacyDatFile))
            try { File.Delete(legacyDatFile); } catch { }

        // Double-check: if workFolder still exists after tmpFolder deletion, force-remove it
        if (Directory.Exists(workFolder))
        {
            Logger.LogMessage($"Work folder still exists after tmp cleanup, force-removing: {workFolder}", LogLevel.WARN);
            ForceDeleteDirectory(workFolder);
        }

        var fileTypes = _options.FileTypes ?? Array.Empty<string>();
        bool cleanAllTypes = fileTypes.Length == 0 || fileTypes.Contains("All", StringComparer.OrdinalIgnoreCase);
        var patternsToClean = new List<string>();
        if (!cleanAllTypes)
        {
            foreach (string ft in fileTypes)
                if (FileTypePatterns.TryGetValue(ft, out string[]? patterns))
                    patternsToClean.AddRange(patterns);
        }
        else
        {
            patternsToClean.AddRange(FileTypePatterns.Values.SelectMany(x => x));
        }

        if (!Directory.Exists(outputFolder)) return;

        if (patternsToClean.Count > 0)
        {
            int htmlRemoved = 0, mmdRemoved = 0, errRemoved = 0;
            foreach (string pattern in patternsToClean.Distinct())
            {
                foreach (var f in Directory.EnumerateFiles(outputFolder, pattern)
                    .Where(p => !ProtectedFiles.Contains(Path.GetFileName(p))))
                {
                    try { File.Delete(f); htmlRemoved++; } catch { }
                }
                foreach (var f in Directory.EnumerateFiles(outputFolder, pattern.Replace(".html", ".mmd")))
                {
                    try { File.Delete(f); mmdRemoved++; } catch { }
                }
                foreach (var f in Directory.EnumerateFiles(outputFolder, pattern.Replace(".html", ".err")))
                {
                    try { File.Delete(f); errRemoved++; } catch { }
                }
            }
            if (htmlRemoved + mmdRemoved + errRemoved > 0)
                Logger.LogMessage($"Removed generated files: {htmlRemoved} HTML, {mmdRemoved} MMD, {errRemoved} ERR", LogLevel.INFO);
        }
        else
        {
            foreach (var f in Directory.EnumerateFiles(outputFolder, "*.html")
                .Where(p => !ProtectedFiles.Contains(Path.GetFileName(p))))
                try { File.Delete(f); } catch { }
            foreach (var f in Directory.EnumerateFiles(outputFolder, "*.mmd"))
                try { File.Delete(f); } catch { }
            foreach (var f in Directory.EnumerateFiles(outputFolder, "*.err"))
                try { File.Delete(f); } catch { }
        }

        string jsonFolder = Path.Combine(outputFolder, "_json");
        if (Directory.Exists(jsonFolder))
        {
            if (patternsToClean.Count > 0)
            {
                foreach (string ft in fileTypes.Where(x => !string.Equals(x, "All", StringComparison.OrdinalIgnoreCase)))
                    foreach (var f in Directory.EnumerateFiles(jsonFolder, $"*{ft}*.json"))
                        try { File.Delete(f); } catch { }
            }
            else
            {
                foreach (var f in Directory.EnumerateFiles(jsonFolder, "*.json"))
                    try { File.Delete(f); } catch { }
            }
            Logger.LogMessage("Cleared _json folder", LogLevel.INFO);
        }

        Logger.LogMessage("Clean mode: Data reset complete. Preserved: _images/, _js/, _css/ folders, index.html, web.config", LogLevel.INFO);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Copy static assets - converted from Copy-StaticAssetsToOutput (PS lines 2046-2113)
    // ═══════════════════════════════════════════════════════════════════════
    private static void CopyStaticAssetsToOutput(string outputRoot)
    {
        string sourceRoot = PathHelper.GetAutodocSharedFolder();
        if (string.IsNullOrEmpty(sourceRoot))
        {
            Logger.LogMessage("Shared AutoDoc folder not found; skipping static assets copy.", LogLevel.WARN);
            return;
        }

        Logger.LogMessage($"Copying static assets to output folder: {outputRoot}", LogLevel.INFO);
        string[] assetFolders = { "_js", "_css", "_images", "_templates" };

        foreach (string folder in assetFolders)
        {
            string sourceFolder = Path.Combine(sourceRoot, folder);
            string targetFolder = Path.Combine(outputRoot, folder);
            if (!Directory.Exists(sourceFolder))
            {
                Logger.LogMessage($"  Source folder not found: {sourceFolder}", LogLevel.WARN);
                continue;
            }
            if (!Directory.Exists(targetFolder))
                Directory.CreateDirectory(targetFolder);
            CopyDirectory(sourceFolder, targetFolder);
            int count = Directory.EnumerateFiles(sourceFolder, "*", SearchOption.AllDirectories).Count();
            Logger.LogMessage($"  Copied {folder}/ ({count} files)", LogLevel.INFO);
        }

        string templatesFolder = Path.Combine(sourceRoot, "_templates");
        string indexFile = Path.Combine(templatesFolder, "index.html");
        if (File.Exists(indexFile))
        {
            File.Copy(indexFile, Path.Combine(outputRoot, "index.html"), overwrite: true);
            Logger.LogMessage("  Copied index.html to output root", LogLevel.INFO);
        }

        string webConfigFile = Path.Combine(templatesFolder, "web.config");
        string destWebConfig = Path.Combine(outputRoot, "web.config");
        if (File.Exists(webConfigFile) && !File.Exists(destWebConfig))
        {
            File.Copy(webConfigFile, destWebConfig);
            Logger.LogMessage("  Copied web.config to output root", LogLevel.INFO);
        }

        Logger.LogMessage("Static assets copied successfully", LogLevel.INFO);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Utility methods
    // ═══════════════════════════════════════════════════════════════════════

    private static void CopyDirectory(string sourceDir, string targetDir)
    {
        foreach (string file in Directory.EnumerateFiles(sourceDir))
        {
            string dest = Path.Combine(targetDir, Path.GetFileName(file));
            File.Copy(file, dest, overwrite: true);
        }
        foreach (string subDir in Directory.EnumerateDirectories(sourceDir))
        {
            string destSub = Path.Combine(targetDir, Path.GetFileName(subDir));
            if (!Directory.Exists(destSub))
                Directory.CreateDirectory(destSub);
            CopyDirectory(subDir, destSub);
        }
    }

    private static void CreateFolderIfNeeded(string folderPath)
    {
        if (!Directory.Exists(folderPath))
            Directory.CreateDirectory(folderPath);
    }

    /// <summary>
    /// Force-delete a directory. Tries .NET first, then falls back to cmd /c rd /s /q
    /// which handles long paths and read-only git objects better on Windows.
    /// </summary>
    private static void ForceDeleteDirectory(string path)
    {
        if (!Directory.Exists(path)) return;

        // Attempt 1: .NET recursive delete
        try
        {
            Directory.Delete(path, recursive: true);
            if (!Directory.Exists(path))
            {
                Logger.LogMessage($"  Deleted: {path}", LogLevel.INFO);
                return;
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"  .NET delete failed for {path}: {ex.Message}", LogLevel.WARN);
        }

        // Attempt 2: cmd /c rd /s /q (handles read-only files, long paths)
        try
        {
            Logger.LogMessage($"  Falling back to cmd rd /s /q for: {path}", LogLevel.INFO);
            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/c rd /s /q \"{path}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            proc?.WaitForExit(120_000); // 2 minute timeout
            if (!Directory.Exists(path))
            {
                Logger.LogMessage($"  Deleted via rd /s /q: {path}", LogLevel.INFO);
                return;
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"  cmd rd failed: {ex.Message}", LogLevel.WARN);
        }

        // If still exists, log a clear warning
        if (Directory.Exists(path))
            Logger.LogMessage($"  WARNING: Could not fully delete {path}. Some files may be locked.", LogLevel.WARN);
    }

    private static void WriteErrorFile(WorkItem item, string outputFolder, string errorMessage)
    {
        string errName = item.ParserType == "SQL"
            ? (item.TableName ?? "unknown").Replace(".", "_") + ".sql.err"
            : (item.FileName ?? "unknown") + ".err";
        string errPath = Path.Combine(outputFolder, errName);
        try { File.WriteAllText(errPath, $"Error: {errorMessage}"); } catch { }
    }

    private static int CountRecentFiles(string folder, string pattern, DateTime sinceUtc)
    {
        if (!Directory.Exists(folder)) return 0;
        return Directory.EnumerateFiles(folder, pattern)
            .Count(f => File.GetLastWriteTimeUtc(f) >= sinceUtc);
    }

    /// <summary>
    /// Build SMS message with statistics (PS lines 3175-3194).
    /// Format: "AutoDocJson: N files (CBL:n REX:n ...) Err:n Time:hh:mm:ss"
    /// </summary>
    private static string BuildSmsMessage(int total, int cbl, int rex, int bat, int ps1,
        int sql, int csharp, int gs, int errors, TimeSpan duration)
    {
        return string.Join("\n", new[]
        {
            $"AutoDocJson: Total:{total}",
            $"CBL:{cbl} REX:{rex} BAT:{bat} PS1:{ps1} SQL:{sql} C#:{csharp} GS:{gs}",
            $"Err:{errors}",
            $"Time:{duration:hh\\:mm\\:ss}"
        });
    }

    /// <summary>Get SMS number for current user (team-and-sms rule).</summary>
    private static string GetSmsNumber()
    {
        string? user = Environment.UserName;
        return user switch
        {
            "FKGEISTA" => "+4797188358",
            "FKSVEERI" => "+4795762742",
            "FKMISTA" => "+4799348397",
            "FKCELERI" => "+4745269945",
            _ => "+4797188358"
        };
    }
}
