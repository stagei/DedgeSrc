using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;
using GenericLogHandler.ImportService.Services;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Xml;
using System.Text.RegularExpressions;
using System.Diagnostics;

namespace GenericLogHandler.ImportService.Importers;

/// <summary>
/// Imports log entries from various file formats (JSON, XML, log files)
/// Supports incremental processing for append-only files by tracking file creation date and last processed line.
/// When ILogRepository and batch size are provided, streams files line-by-line and saves in batches to avoid loading multi-GB files into memory.
/// </summary>
public class FileImporter : ILogImporter
{
    private readonly ILogger<FileImporter> _logger;
    private readonly ILogRepository? _repository;
    private readonly int _batchSize;
    private ImportSource _source = null!;
    private FileSystemWatcher? _watcher;
    private readonly List<string> _processedFiles = new();
    private ImportStatus _status = new();
    
    // Debouncing for file events - prevents multiple rapid events for the same file
    private readonly Dictionary<string, DateTime> _pendingFileEvents = new();
    private readonly object _debouncelock = new();
    private Timer? _debounceTimer;
    private const int DebounceDelayMs = 500;
    
    // File tracking state for append-only files (keyed by file path)
    private readonly Dictionary<string, FileTrackingInfo> _fileTracking = new();
    
    // Cache of active level filters for this import session
    private List<ImportLevelFilter>? _levelFilters;
    
    // Stats for filtered entries
    private int _entriesFilteredByLevel;
    
    // WKMONIT metadata enrichment service (optional, injected from ImportService)
    private readonly WkmonitMetadataService? _metadataService;
    
    // Per-source poll tracking for append-only files
    private DateTime _lastImportTime = DateTime.MinValue;

    public string Name => "FileImporter";
    public IEnumerable<string> SupportedSourceTypes => new[] { "file", "json", "xml", "log" };

    /// <summary>
    /// Default maximum file size (bytes) for whole-file read of JSON/XML when not configured per source.
    /// </summary>
    private const long DefaultMaxFullReadBytes = 100 * 1024 * 1024; // 100 MB

    private long GetMaxFullReadBytes()
    {
        if (_source.Config.MaxFullReadMB.HasValue)
        {
            if (_source.Config.MaxFullReadMB.Value <= 0)
                return long.MaxValue; // no limit
            return (long)_source.Config.MaxFullReadMB.Value * 1024 * 1024;
        }
        return DefaultMaxFullReadBytes;
    }
    
    /// <summary>
    /// Tracking info for append-only files
    /// </summary>
    private class FileTrackingInfo
    {
        public DateTime CreationDate { get; set; }
        public long LastProcessedLine { get; set; }
        public long LastFileSize { get; set; }
    }

    public FileImporter(ILogger<FileImporter> logger, ILogRepository? repository = null, int batchSize = 1000, WkmonitMetadataService? metadataService = null)
    {
        _logger = logger;
        _repository = repository;
        _batchSize = batchSize > 0 ? batchSize : 1000;
        _metadataService = metadataService;
    }

    public Task InitializeAsync(ImportSource source, CancellationToken cancellationToken = default)
    {
        _source = source;
        _status = new ImportStatus
        {
            SourceName = source.Name,
            SourceType = source.Type,
            Status = ImportStatusType.Pending
        };

        if (_source.Config.WatchDirectory)
        {
            SetupFileWatcher();
        }

        _logger.LogInformation("Initialized FileImporter for source: {SourceName}", source.Name);
        return Task.CompletedTask;
    }

    public async Task<ImportResult> ImportAsync(CancellationToken cancellationToken = default)
    {
        // Honor per-source PollInterval for append-only files
        if (_source.Config.IsAppendOnly && _source.Config.PollInterval > 0)
        {
            var elapsed = (DateTime.UtcNow - _lastImportTime).TotalSeconds;
            if (elapsed < _source.Config.PollInterval)
            {
                return new ImportResult { Success = true };
            }
        }
        _lastImportTime = DateTime.UtcNow;

        var stopwatch = Stopwatch.StartNew();
        var result = new ImportResult();
        _entriesFilteredByLevel = 0;
        
        try
        {
            _status.Status = ImportStatusType.Processing;
            _status.LastImportTimestamp = DateTime.UtcNow;

            // Load level filters once per import session
            if (_repository != null)
            {
                _levelFilters = await _repository.GetActiveImportLevelFiltersAsync(cancellationToken);
                if (_levelFilters.Count > 0)
                {
                    _logger.LogInformation("Loaded {Count} active import level filters", _levelFilters.Count);
                }
            }

            var files = GetFilesToProcess();
            
            foreach (var file in files)
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                var fileResult = await ProcessFile(file, cancellationToken);
                result.RecordsProcessed += fileResult.RecordsProcessed;
                result.RecordsFailed += fileResult.RecordsFailed;
                result.ImportedEntries.AddRange(fileResult.ImportedEntries);
                
                // Save import status for this file to the database
                await SaveImportStatusForFileAsync(file, fileResult, cancellationToken);
                
                if (fileResult.Success && _source.Config.MoveProcessedFiles)
                {
                    MoveProcessedFile(file);
                }
                
                // Check for quarantine - if error rate exceeds threshold
                if (ShouldQuarantineFile(fileResult))
                {
                    QuarantineFile(file, fileResult);
                }
            }

            result.Success = true;
            _status.Status = ImportStatusType.Completed;
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.ErrorMessage = ex.Message;
            _status.Status = ImportStatusType.Failed;
            _status.ErrorMessage = ex.Message;
            _logger.LogError(ex, "Error during file import for source: {SourceName}", _source.Name);
        }
        finally
        {
            stopwatch.Stop();
            result.Duration = stopwatch.Elapsed;
            _status.ProcessingDurationMs = stopwatch.ElapsedMilliseconds;
            _status.RecordsProcessed = result.RecordsProcessed;
            _status.RecordsFailed = result.RecordsFailed;
            
            if (_entriesFilteredByLevel > 0)
            {
                _logger.LogInformation("Level filtering: {Filtered} entries skipped due to level filters", _entriesFilteredByLevel);
            }
        }

        return result;
    }

    public Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var directory = Path.GetDirectoryName(_source.Config.Path);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
            {
                _logger.LogWarning("Directory does not exist: {Directory}", directory);
                return Task.FromResult(false);
            }

            var files = Directory.GetFiles(directory, Path.GetFileName(_source.Config.Path));
            _logger.LogInformation("Found {Count} files matching pattern: {Pattern}", files.Length, _source.Config.Path);
            return Task.FromResult(true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error testing file connection for: {Path}", _source.Config.Path);
            return Task.FromResult(false);
        }
    }

    public ImportStatus GetStatus() => _status;

    /// <summary>
    /// Saves import status for a specific file to the database
    /// </summary>
    private async Task SaveImportStatusForFileAsync(string filePath, ImportResult fileResult, CancellationToken cancellationToken)
    {
        if (_repository == null)
        {
            _logger.LogDebug("No repository available for saving import status");
            return;
        }

        try
        {
            // Get tracking info for this file
            _fileTracking.TryGetValue(filePath, out var tracking);
            
            var fileInfo = new FileInfo(filePath);
            var status = new ImportStatus
            {
                SourceName = _source.Name,
                SourceType = _source.Type,
                FilePath = filePath,
                LastProcessedTimestamp = DateTime.UtcNow,
                LastImportTimestamp = DateTime.UtcNow,
                RecordsProcessed = fileResult.RecordsProcessed,
                RecordsFailed = fileResult.RecordsFailed,
                Status = fileResult.Success ? ImportStatusType.Completed : ImportStatusType.Failed,
                ErrorMessage = fileResult.ErrorMessage ?? string.Empty,
                ProcessingDurationMs = (long)fileResult.Duration.TotalMilliseconds,
                Metadata = string.Empty,
                LastFileSize = fileInfo.Exists ? fileInfo.Length : 0,
                FileCreationDate = fileInfo.Exists ? fileInfo.CreationTimeUtc : null,
                LastProcessedLine = tracking?.LastProcessedLine ?? 0,
                LastProcessedByteOffset = 0
            };

            await _repository.UpdateImportStatusAsync(status, cancellationToken);
            _logger.LogDebug("Saved import status for {SourceName}/{FilePath}: {Records} records", 
                _source.Name, filePath, fileResult.RecordsProcessed);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to save import status for {FilePath}", filePath);
            // Don't throw - this shouldn't stop the import process
        }
    }

    public Task DisposeAsync()
    {
        _watcher?.Dispose();
        return Task.CompletedTask;
    }

    private void SetupFileWatcher()
    {
        try
        {
            var directory = Path.GetDirectoryName(_source.Config.Path);
            var filePattern = Path.GetFileName(_source.Config.Path);

            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
            {
                _logger.LogWarning("Cannot setup file watcher: directory does not exist: {Directory}", directory);
                return;
            }

            _watcher = new FileSystemWatcher(directory, filePattern)
            {
                NotifyFilter = NotifyFilters.CreationTime | NotifyFilters.LastWrite | NotifyFilters.Size,
                InternalBufferSize = 64 * 1024 // 64KB buffer to handle burst of events
            };

            _watcher.Created += OnFileCreated;
            _watcher.Changed += OnFileChanged;
            _watcher.Error += OnWatcherError;
            _watcher.EnableRaisingEvents = true;

            // Setup debounce timer
            _debounceTimer = new Timer(ProcessPendingFileEvents, null, Timeout.Infinite, Timeout.Infinite);

            _logger.LogInformation("File watcher setup for: {Directory}/{Pattern}", directory, filePattern);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error setting up file watcher for: {Path}", _source.Config.Path);
        }
    }

    private void OnWatcherError(object sender, ErrorEventArgs e)
    {
        var ex = e.GetException();
        _logger.LogWarning(ex, "File watcher error - will attempt to restart. Source: {SourceName}", _source.Name);
        
        // Attempt to restart the watcher
        try
        {
            _watcher?.Dispose();
            _watcher = null;
            Task.Delay(5000).ContinueWith(_ => SetupFileWatcher());
        }
        catch (Exception restartEx)
        {
            _logger.LogError(restartEx, "Failed to restart file watcher for: {SourceName}", _source.Name);
        }
    }

    private void OnFileCreated(object sender, FileSystemEventArgs e)
    {
        QueueFileEvent(e.FullPath);
    }

    private void OnFileChanged(object sender, FileSystemEventArgs e)
    {
        QueueFileEvent(e.FullPath);
    }

    private void QueueFileEvent(string filePath)
    {
        lock (_debouncelock)
        {
            _pendingFileEvents[filePath] = DateTime.UtcNow;
            // Reset debounce timer
            _debounceTimer?.Change(DebounceDelayMs, Timeout.Infinite);
        }
    }

    private async void ProcessPendingFileEvents(object? state)
    {
        List<string> filesToProcess;
        
        lock (_debouncelock)
        {
            filesToProcess = _pendingFileEvents.Keys.ToList();
            _pendingFileEvents.Clear();
        }

        foreach (var filePath in filesToProcess)
        {
            await ProcessFileEvent(filePath);
        }
    }

    private async Task ProcessFileEvent(string filePath)
    {
        try
        {
            // Wait a bit to ensure file is fully written
            await Task.Delay(500);
            
            // Check if file is still being written (size changing)
            var initialSize = new FileInfo(filePath).Length;
            await Task.Delay(200);
            var currentSize = new FileInfo(filePath).Length;
            
            if (currentSize != initialSize)
            {
                // File still being written, requeue
                _logger.LogDebug("File still being written, requeueing: {FilePath}", filePath);
                QueueFileEvent(filePath);
                return;
            }
            
            _logger.LogInformation("Processing file event: {FilePath}", filePath);
            var result = await ProcessFile(filePath, CancellationToken.None);
            _logger.LogInformation("Processed file {FilePath}: {Processed} records, {Failed} failures", 
                filePath, result.RecordsProcessed, result.RecordsFailed);
        }
        catch (IOException ex) when (ex.Message.Contains("being used by another process"))
        {
            // File locked, try again later
            _logger.LogDebug("File locked, will retry: {FilePath}", filePath);
            await Task.Delay(1000);
            QueueFileEvent(filePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing file event for: {FilePath}", filePath);
        }
    }

    private string[] GetFilesToProcess()
    {
        try
        {
            var directory = Path.GetDirectoryName(_source.Config.Path);
            var filePattern = Path.GetFileName(_source.Config.Path);

            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
                return Array.Empty<string>();

            var allFiles = Directory.GetFiles(directory, filePattern)
                .OrderBy(f => File.GetCreationTime(f))
                .ToArray();

            // Apply max file age filter (default 30 days, 0 or null = no filter)
            var maxAgeDays = _source.Config.MaxFileAgeDays;
            if (maxAgeDays.HasValue && maxAgeDays.Value > 0)
            {
                var cutoffDate = DateTime.Now.AddDays(-maxAgeDays.Value);
                var beforeCount = allFiles.Length;
                allFiles = allFiles.Where(f => File.GetLastWriteTime(f) >= cutoffDate).ToArray();
                
                if (beforeCount != allFiles.Length)
                {
                    _logger.LogDebug("Filtered {Skipped} files older than {Days} days (cutoff: {Cutoff})",
                        beforeCount - allFiles.Length, maxAgeDays.Value, cutoffDate);
                }
            }

            string[] files;
            
            // For append-only files, always include them (they handle their own incremental tracking)
            if (_source.Config.IsAppendOnly)
            {
                files = allFiles;
            }
            else
            {
                // For non-append files, skip already processed ones
                files = allFiles.Where(f => !_processedFiles.Contains(f)).ToArray();
            }

            if (_source.Config.MaxFilesPerRun > 0)
            {
                files = files.Take(_source.Config.MaxFilesPerRun).ToArray();
            }

            return files;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting files to process for: {Path}", _source.Config.Path);
            return Array.Empty<string>();
        }
    }

    private async Task<ImportResult> ProcessFile(string filePath, CancellationToken cancellationToken)
    {
        var result = new ImportResult();
        
        try
        {
            _logger.LogDebug("Processing file: {FilePath}", filePath);
            
            // For append-only files, use incremental processing
            if (_source.Config.IsAppendOnly)
            {
                return await ProcessAppendOnlyFile(filePath, cancellationToken);
            }
            
            // When repository is set, stream line-by-line and batch-save to avoid loading multi-GB files into memory
            if (_repository != null)
            {
                return await ProcessFileStreaming(filePath, result, cancellationToken);
            }
            
            // Legacy path: load full file (avoid for very large files)
            var content = await File.ReadAllTextAsync(filePath, cancellationToken);
            if (string.IsNullOrWhiteSpace(content))
            {
                _logger.LogWarning("File is empty: {FilePath}", filePath);
                return result;
            }

            // Get file fallback time for entries without timestamps
            var fileInfo = new FileInfo(filePath);
            var fileFallbackTime = fileInfo.Exists ? GetFileFallbackTime(fileInfo) : DateTime.UtcNow;

            var entries = _source.Config.Format?.ToLower() switch
            {
                "json" => ParseJsonFile(content, filePath, fileFallbackTime),
                "xml" => ParseXmlFile(content, filePath, fileFallbackTime),
                "delimited" or "pipe" or "csv" => ParseDelimitedFile(content, filePath, fileFallbackTime),
                "powershell" or "log" => ParseLogFile(content, filePath, fileFallbackTime),
                "raw" or "text" or "plain" => ParseRawFile(content, filePath, fileFallbackTime),
                _ => ParseLogFile(content, filePath, fileFallbackTime) // Default to log file parsing
            };

            // Apply message extractors to all entries if configured
            if (_source.Config.Parser?.MessageExtractors?.Count > 0)
            {
                foreach (var entry in entries)
                {
                    ApplyMessageExtractors(entry);
                }
            }

            result.ImportedEntries.AddRange(entries);
            result.RecordsProcessed = entries.Count;
            result.Success = true;

            _processedFiles.Add(filePath);
            _logger.LogInformation("Successfully processed file {FilePath}: {Count} entries", filePath, entries.Count);
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.ErrorMessage = ex.Message;
            result.RecordsFailed = 1;
            _logger.LogError(ex, "Error processing file: {FilePath}", filePath);
        }

        return result;
    }

    /// <summary>
    /// Process a file by streaming line-by-line and saving in batches. Used when ILogRepository is set to avoid OOM on large files.
    /// </summary>
    private async Task<ImportResult> ProcessFileStreaming(string filePath, ImportResult result, CancellationToken cancellationToken)
    {
        var format = _source.Config.Format?.ToLower() ?? "log";
        var fileInfo = new FileInfo(filePath);
        if (!fileInfo.Exists)
        {
            _logger.LogWarning("File does not exist: {FilePath}", filePath);
            return result;
        }
        
        // Get file fallback time for entries without timestamps (use file creation/modification time)
        var fileFallbackTime = GetFileFallbackTime(fileInfo);

        // Whole-file JSON/XML: size guard to avoid OOM
        if (format == "xml" || format == "json")
        {
            var maxBytes = GetMaxFullReadBytes();
            if (maxBytes < long.MaxValue && fileInfo.Length > maxBytes)
            {
                _logger.LogWarning("Skipping large {Format} file (size {Size} MB > limit {Limit} MB): {FilePath}",
                    format, fileInfo.Length / (1024 * 1024), maxBytes / (1024 * 1024), filePath);
                result.Success = true;
                return result;
            }
            
            if (format == "xml")
            {
                // XML: single document, must read fully (size already checked above)
                var content = await File.ReadAllTextAsync(filePath, cancellationToken);
                var entries = ParseXmlFile(content, filePath, fileFallbackTime);
                if (_source.Config.Parser?.MessageExtractors?.Count > 0)
                {
                    foreach (var entry in entries)
                        ApplyMessageExtractors(entry);
                }
                await FlushBatch(entries, result, cancellationToken);
                result.Success = true;
                result.RecordsProcessed += entries.Count;
                _processedFiles.Add(filePath);
                _logger.LogInformation("Processed XML file {FilePath}: {Count} entries", filePath, entries.Count);
                return result;
            }
            // JSON: Try to parse as full JSON document (array or object) first
            
            if (fileInfo.Length <= maxBytes)
            {
                var content = await File.ReadAllTextAsync(filePath, cancellationToken);
                var firstTrim = content.TrimStart();
                
                // Try parsing as full JSON document if it starts with [ or {
                // This handles both JSON arrays and single/multi-line JSON objects
                if (firstTrim.StartsWith("[") || firstTrim.StartsWith("{"))
                {
                    try
                    {
                        var entries = ParseJsonFile(content, filePath, fileFallbackTime);
                        if (entries.Count > 0)
                        {
                            if (_source.Config.Parser?.MessageExtractors?.Count > 0)
                            {
                                foreach (var entry in entries)
                                    ApplyMessageExtractors(entry);
                            }
                            await FlushBatch(entries, result, cancellationToken);
                            result.Success = true;
                            result.RecordsProcessed += entries.Count;
                            _processedFiles.Add(filePath);
                            _logger.LogInformation("Processed JSON file {FilePath}: {Count} entries", filePath, entries.Count);
                            return result;
                        }
                    }
                    catch (Exception ex)
                    {
                        // If full JSON parsing fails, try JSON Lines as fallback
                        _logger.LogDebug(ex, "Full JSON parse failed for {FilePath}, trying JSON Lines format", filePath);
                    }
                }
            }
            // JSON Lines fallback: stream line-by-line (each line is a separate JSON object)
            await ProcessFileStreamingJsonLines(filePath, result, cancellationToken);
            result.Success = true;
            _processedFiles.Add(filePath);
            return result;
        }

        // Line-based formats: stream with StreamReader
        var skipHeaderLines = _source.Config.SkipHeaderLines;
        var parser = _source.Config.Parser;
        var delimiter = parser?.Delimiter == "\\t" ? "\t" : parser?.Delimiter ?? "";
        var batch = new List<LogEntry>();
        var encoding = System.Text.Encoding.UTF8;
        if (!string.IsNullOrEmpty(_source.Config.Encoding))
        {
            try
            {
                encoding = System.Text.Encoding.GetEncoding(_source.Config.Encoding);
            }
            catch
            {
                // use UTF-8
            }
        }

        await using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, bufferSize: 65536, useAsync: true))
        using (var reader = new StreamReader(stream, encoding, detectEncodingFromByteOrderMarks: false))
        {
            string? line;
            int lineNumber = 0;
            while ((line = await reader.ReadLineAsync(cancellationToken)) != null)
            {
                lineNumber++;
                if (lineNumber <= skipHeaderLines) continue;
                var trimmed = line.TrimEnd('\r');
                if (string.IsNullOrWhiteSpace(trimmed)) continue;

                try
                {
                    LogEntry? entry = format switch
                    {
                        "delimited" or "pipe" or "csv" when parser != null => ParseDelimitedLine(trimmed, delimiter, filePath, lineNumber, parser, fileFallbackTime),
                        "powershell" or "log" => ParseLogLine(trimmed, filePath, lineNumber, fileFallbackTime),
                        "raw" or "text" or "plain" => CreateRawLineEntry(trimmed, filePath, lineNumber, fileFallbackTime),
                        _ => ParseLogLine(trimmed, filePath, lineNumber, fileFallbackTime)
                    };
                    if (entry != null)
                    {
                        if (_source.Config.Parser?.MessageExtractors?.Count > 0)
                            ApplyMessageExtractors(entry);
                        batch.Add(entry);
                        if (batch.Count >= _batchSize)
                        {
                            await FlushBatch(batch, result, cancellationToken);
                            batch.Clear();
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Error parsing line {LineNumber} in {FilePath}", lineNumber, filePath);
                    result.RecordsFailed++;
                }
            }

            if (batch.Count > 0)
                await FlushBatch(batch, result, cancellationToken);
        }

        result.Success = true;
        _processedFiles.Add(filePath);
        _logger.LogInformation("Processed file {FilePath}: {Count} entries (streaming)", filePath, result.RecordsProcessed);
        return result;
    }

    private async Task ProcessFileStreamingJsonLines(string filePath, ImportResult result, CancellationToken cancellationToken)
    {
        var batch = new List<LogEntry>();
        var encoding = System.Text.Encoding.UTF8;
        if (!string.IsNullOrEmpty(_source.Config.Encoding))
        {
            try { encoding = System.Text.Encoding.GetEncoding(_source.Config.Encoding); }
            catch { }
        }
        
        // Get file fallback time for entries without timestamps
        var fileInfo = new FileInfo(filePath);
        var fileFallbackTime = fileInfo.Exists ? GetFileFallbackTime(fileInfo) : DateTime.UtcNow;
        
        await using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, bufferSize: 65536, useAsync: true))
        using (var reader = new StreamReader(stream, encoding, detectEncodingFromByteOrderMarks: false))
        {
            string? line;
            int lineNumber = 0;
            while ((line = await reader.ReadLineAsync(cancellationToken)) != null)
            {
                lineNumber++;
                if (string.IsNullOrWhiteSpace(line.Trim())) continue;
                try
                {
                    var token = JToken.Parse(line);
                    var entry = ParseJsonLogEntry(token, filePath, fileFallbackTime);
                    if (entry != null)
                    {
                        if (_source.Config.Parser?.MessageExtractors?.Count > 0)
                            ApplyMessageExtractors(entry);
                        batch.Add(entry);
                        if (batch.Count >= _batchSize)
                        {
                            await FlushBatch(batch, result, cancellationToken);
                            batch.Clear();
                        }
                    }
                }
                catch
                {
                    result.RecordsFailed++;
                }
            }
            if (batch.Count > 0)
                await FlushBatch(batch, result, cancellationToken);
        }
        _logger.LogInformation("Processed JSON Lines file {FilePath}: {Count} entries", filePath, result.RecordsProcessed);
    }

    private async Task FlushBatch(List<LogEntry> batch, ImportResult result, CancellationToken cancellationToken)
    {
        if (batch.Count == 0 || _repository == null) return;
        
        // Apply level filters
        var filteredBatch = ApplyLevelFilters(batch);
        
        if (filteredBatch.Count > 0)
        {
            await _repository.AddBatchAsync(filteredBatch, cancellationToken);
            result.RecordsProcessed += filteredBatch.Count;
        }
    }
    
    /// <summary>
    /// Applies import level filters to a batch of entries
    /// </summary>
    private List<LogEntry> ApplyLevelFilters(List<LogEntry> batch)
    {
        if (_levelFilters == null || _levelFilters.Count == 0)
            return batch;
            
        var result = new List<LogEntry>(batch.Count);
        foreach (var entry in batch)
        {
            if (ShouldImportEntry(entry))
            {
                result.Add(entry);
            }
            else
            {
                _entriesFilteredByLevel++;
            }
        }
        return result;
    }
    
    /// <summary>
    /// Checks if an entry should be imported based on level filters.
    /// JOB_* entries (JOB_STARTED, JOB_COMPLETED, JOB_FAILED) always bypass level filters.
    /// </summary>
    private bool ShouldImportEntry(LogEntry entry)
    {
        // ALWAYS import JOB_* entries regardless of level filters
        // These are critical for job tracking and should never be filtered out
        if (!string.IsNullOrEmpty(entry.JobStatus))
        {
            return true; // Job status entries always imported
        }
        
        if (_levelFilters == null || _levelFilters.Count == 0)
            return true;
            
        var filePath = entry.SourceFile ?? string.Empty;
        
        foreach (var filter in _levelFilters)
        {
            try
            {
                if (Regex.IsMatch(filePath, filter.FilePattern, RegexOptions.IgnoreCase))
                {
                    // Found a matching filter - check if entry level meets the minimum
                    var entryLevel = (int)entry.Level - 1; // LogLevel enum is 1-6, filter uses 0-5
                    return entryLevel >= filter.MinLevel;
                }
            }
            catch (RegexMatchTimeoutException)
            {
                // Skip invalid regex patterns
            }
        }
        
        return true; // No matching filter = import all
    }
    
    /// <summary>
    /// Normalizes job status values to consistent names
    /// JOB_STARTED, STARTED, START, RUNNING -> Started
    /// JOB_COMPLETED, COMPLETED, COMPLETE, SUCCESS, SUCCEEDED -> Completed
    /// JOB_FAILED, FAILED, FAIL, ERROR -> Failed
    /// </summary>
    private static string? NormalizeJobStatus(string? rawStatus)
    {
        if (string.IsNullOrEmpty(rawStatus)) 
            return null;
            
        var upper = rawStatus.ToUpperInvariant().Trim();
        
        return upper switch
        {
            "JOB_STARTED" or "STARTED" or "START" or "RUNNING" or "IN_PROGRESS" or "INPROGRESS" => "Started",
            "JOB_COMPLETED" or "COMPLETED" or "COMPLETE" or "SUCCESS" or "SUCCEEDED" or "DONE" or "FINISHED" => "Completed",
            "JOB_FAILED" or "FAILED" or "FAIL" or "ERROR" or "FAULTED" or "ABORTED" or "CANCELLED" or "CANCELED" => "Failed",
            _ => rawStatus // Keep original value for unknown statuses
        };
    }

    private static LogEntry CreateRawLineEntry(string line, string filePath, int lineNumber, DateTime? fileFallbackTime = null)
    {
        var entry = new LogEntry
        {
            Timestamp = fileFallbackTime ?? DateTime.UtcNow,
            Level = Core.Models.LogLevel.INFO,
            ComputerName = Environment.MachineName,
            Message = LogEntry.TrimMultiSpace(line),
            SourceFile = filePath,
            SourceType = "raw",
            ImportTimestamp = DateTime.UtcNow,
            LineNumber = lineNumber
        };
        entry.GenerateConcatenatedSearchString();
        return entry;
    }

    /// <summary>
    /// Process an append-only file incrementally, resuming from the last processed line.
    /// Detects file rotation by comparing creation dates of the ORIGINAL source file.
    /// When CopyToLocalPath is set, copies the source file locally before reading to
    /// avoid holding network file locks on business-critical files.
    /// </summary>
    private async Task<ImportResult> ProcessAppendOnlyFile(string filePath, CancellationToken cancellationToken)
    {
        var result = new ImportResult();
        
        try
        {
            var fileInfo = new FileInfo(filePath);
            if (!fileInfo.Exists)
            {
                _logger.LogWarning("Append-only file does not exist: {FilePath}", filePath);
                return result;
            }

            var currentCreationDate = fileInfo.CreationTimeUtc;
            var currentFileSize = fileInfo.Length;
            
            // Get or create tracking info for this file
            if (!_fileTracking.TryGetValue(filePath, out var tracking))
            {
                tracking = new FileTrackingInfo
                {
                    CreationDate = currentCreationDate,
                    LastProcessedLine = 0,
                    LastFileSize = 0
                };
                _fileTracking[filePath] = tracking;
                
                // Try to restore from database if available
                if (_repository != null)
                {
                    try
                    {
                        var dbStatus = await _repository.GetImportStatusAsync(_source.Name, filePath, cancellationToken);
                        if (dbStatus != null && dbStatus.FileCreationDate.HasValue)
                        {
                            tracking.CreationDate = dbStatus.FileCreationDate.Value;
                            tracking.LastProcessedLine = dbStatus.LastProcessedLine;
                            tracking.LastFileSize = dbStatus.LastFileSize;
                            _logger.LogDebug("Restored tracking from database for {FilePath}: line {Line}, size {Size}",
                                filePath, tracking.LastProcessedLine, tracking.LastFileSize);
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Failed to load import status from database for {FilePath}", filePath);
                    }
                }
                else if (_status.FilePath == filePath && _status.FileCreationDate.HasValue)
                {
                    tracking.CreationDate = _status.FileCreationDate.Value;
                    tracking.LastProcessedLine = _status.LastProcessedLine;
                    tracking.LastFileSize = _status.LastFileSize;
                }
            }
            
            // Detect file rotation using the ORIGINAL source file's creation date
            bool rotated = false;
            if (tracking.CreationDate != currentCreationDate)
            {
                _logger.LogInformation("File rotation detected for {FilePath}: creation date changed from {OldDate} to {NewDate}. Resetting to line 0.",
                    filePath, tracking.CreationDate, currentCreationDate);
                rotated = true;
            }
            else if (currentFileSize < tracking.LastFileSize)
            {
                _logger.LogInformation("File rotation detected for {FilePath}: file size decreased from {OldSize} to {NewSize}. Resetting to line 0.",
                    filePath, tracking.LastFileSize, currentFileSize);
                rotated = true;
            }

            if (rotated)
            {
                tracking.CreationDate = currentCreationDate;
                tracking.LastProcessedLine = 0;
                tracking.LastFileSize = 0;
            }
            
            // If file size hasn't grown, nothing new to process
            if (currentFileSize <= tracking.LastFileSize)
            {
                _logger.LogDebug("No new content in append-only file {FilePath} (size: {Size})", filePath, currentFileSize);
                result.Success = true;
                return result;
            }

            // Determine the actual file to read from: local copy or original
            var readPath = filePath;
            if (!string.IsNullOrEmpty(_source.Config.CopyToLocalPath))
            {
                readPath = await CopyToLocalAsync(filePath, _source.Config.CopyToLocalPath, cancellationToken);
                _logger.LogDebug("Reading from local copy: {LocalPath} (source: {SourcePath})", readPath, filePath);
            }
            
            var startLine = (int)tracking.LastProcessedLine;
            var skipHeaderLines = _source.Config.SkipHeaderLines;
            if (startLine < skipHeaderLines)
                startLine = skipHeaderLines;
            
            var parser = _source.Config.Parser;
            var delimiter = parser?.Delimiter == "\\t" ? "\t" : parser?.Delimiter ?? "";
            var format = _source.Config.Format?.ToLower() ?? "";
            var batch = new List<LogEntry>();
            var encoding = System.Text.Encoding.UTF8;
            if (!string.IsNullOrEmpty(_source.Config.Encoding))
            {
                try { encoding = System.Text.Encoding.GetEncoding(_source.Config.Encoding); }
                catch { }
            }
            
            int lineNumber = 0;
            long totalLinesRead = 0;
            await using (var stream = new FileStream(readPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, bufferSize: 65536, useAsync: true))
            using (var reader = new StreamReader(stream, encoding, detectEncodingFromByteOrderMarks: false))
            {
                string? line;
                while ((line = await reader.ReadLineAsync(cancellationToken)) != null)
                {
                    lineNumber++;
                    totalLinesRead++;
                    if (lineNumber <= startLine) continue;
                    var trimmed = line.TrimEnd('\r');
                    if (string.IsNullOrWhiteSpace(trimmed)) continue;

                    try
                    {
                        LogEntry? entry = format switch
                        {
                            "delimited" or "pipe" or "csv" when parser != null =>
                                ParseDelimitedLine(trimmed, delimiter, filePath, lineNumber, parser),
                            "powershell" or "log" => ParseLogLine(trimmed, filePath, lineNumber),
                            _ => ParseLogLine(trimmed, filePath, lineNumber)
                        };
                        if (entry != null)
                        {
                            if (_source.Config.Parser?.MessageExtractors?.Count > 0)
                                ApplyMessageExtractors(entry);
                            batch.Add(entry);
                            if (_repository != null && batch.Count >= _batchSize)
                            {
                                await FlushBatch(batch, result, cancellationToken);
                                batch.Clear();
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogDebug(ex, "Error parsing line {LineNumber} in append-only file: {FilePath}", lineNumber, filePath);
                        result.RecordsFailed++;
                    }
                }

                if (batch.Count > 0)
                {
                    if (_repository != null)
                        await FlushBatch(batch, result, cancellationToken);
                    else
                    {
                        result.ImportedEntries.AddRange(batch);
                        result.RecordsProcessed += batch.Count;
                    }
                }
            }
            
            result.Success = true;
            
            // Track line position relative to the file we actually read (local copy)
            tracking.LastProcessedLine = totalLinesRead;
            // Track file size of the ORIGINAL source (for growth/rotation detection)
            tracking.LastFileSize = currentFileSize;
            
            // Persist original source file's creation date for rotation detection
            _status.FilePath = filePath;
            _status.FileCreationDate = tracking.CreationDate;
            _status.LastProcessedLine = tracking.LastProcessedLine;
            _status.LastFileSize = tracking.LastFileSize;
            
            _logger.LogInformation("Successfully processed append-only file {FilePath}: {Count} new entries (now at line {Line})",
                filePath, result.RecordsProcessed, tracking.LastProcessedLine);
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.ErrorMessage = ex.Message;
            result.RecordsFailed++;
            _logger.LogError(ex, "Error processing append-only file: {FilePath}", filePath);
        }

        return result;
    }

    /// <summary>
    /// Copies a source file to a local directory for safe reading.
    /// Uses the original filename in the local directory. Creates the directory if needed.
    /// </summary>
    private async Task<string> CopyToLocalAsync(string sourcePath, string localDir, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(localDir);
        var fileName = Path.GetFileName(sourcePath);
        var localPath = Path.Combine(localDir, fileName);

        await using var sourceStream = new FileStream(sourcePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, bufferSize: 65536, useAsync: true);
        await using var destStream = new FileStream(localPath, FileMode.Create, FileAccess.Write, FileShare.None, bufferSize: 65536, useAsync: true);
        await sourceStream.CopyToAsync(destStream, cancellationToken);

        _logger.LogDebug("Copied {Source} to {Local} ({Bytes} bytes)", sourcePath, localPath, new FileInfo(localPath).Length);
        return localPath;
    }

    private List<LogEntry> ParseJsonFile(string content, string filePath, DateTime? fileFallbackTime = null)
    {
        var entries = new List<LogEntry>();
        
        try
        {
            var json = JToken.Parse(content);
            
            if (json is JArray array)
            {
                foreach (var item in array)
                {
                    var entry = ParseJsonLogEntry(item, filePath, fileFallbackTime);
                    if (entry != null)
                        entries.Add(entry);
                }
            }
            else if (json is JObject obj)
            {
                var entry = ParseJsonLogEntry(obj, filePath, fileFallbackTime);
                if (entry != null)
                    entries.Add(entry);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error parsing JSON file: {FilePath}", filePath);
            throw;
        }

        return entries;
    }

    /// <summary>
    /// Parse a single JSON log entry. Uses fileFallbackTime (file creation/modification time) 
    /// if no timestamp is found in the entry. If fileFallbackTime is null, uses current UTC time.
    /// </summary>
    private LogEntry? ParseJsonLogEntry(JToken token, string filePath, DateTime? fileFallbackTime = null)
    {
        try
        {
            var entry = new LogEntry
            {
                SourceFile = filePath,
                SourceType = "json",
                ImportTimestamp = DateTime.UtcNow
            };

            // Try multiple common field name variations (case-insensitive)
            var obj = token as JObject;
            
            // Timestamp field variations - use file time as fallback, then current time
            entry.Timestamp = ParseDateTime(
                GetJsonValue(obj, "timestamp", "time", "date", "datetime", "createdAt", "created_at", "eventTime")) 
                ?? fileFallbackTime ?? DateTime.UtcNow;
            
            // Level/Severity field variations
            var levelStr = GetJsonValue(obj, "level", "severity", "logLevel", "log_level", "type");
            entry.Level = ParseLogLevel(levelStr) ?? Core.Models.LogLevel.INFO;
            
            // Extract Location early so we can use it for JOB_* job name extraction
            var location = GetJsonValue(obj, "location", "source", "category") ?? string.Empty;
            entry.Location = location;
            
            // If Level is a JOB_* status, also set JobStatus for job tracking
            if (IsJobLevel(levelStr))
            {
                entry.JobStatus = NormalizeJobStatus(levelStr);
                // Extract JobName from Location (script name) if available, otherwise from filename
                // Location example: Db2-AutoCatalog.ps1
                if (string.IsNullOrEmpty(entry.JobName))
                {
                    if (!string.IsNullOrEmpty(location))
                    {
                        // Use script name as job name
                        entry.JobName = System.IO.Path.GetFileNameWithoutExtension(location);
                    }
                    else if (!string.IsNullOrEmpty(filePath))
                    {
                        var fileName = System.IO.Path.GetFileNameWithoutExtension(filePath);
                        entry.JobName = ExtractJobNameFromContext(fileName, null);
                    }
                }
            }
            
            // Computer/Server name variations
            entry.ComputerName = GetJsonValue(obj, "computerName", "computer_name", "computer", "hostname", 
                "host", "server", "serverName", "server_name", "machine") ?? Environment.MachineName;
            
            // User name variations
            entry.UserName = GetJsonValue(obj, "user", "userName", "user_name", "username", "userId", "user_id") ?? string.Empty;
            
            // Message field variations - if no dedicated message field, serialize the whole object
            var message = GetJsonValue(obj, "message", "msg", "text", "description", "content", "details");
            if (string.IsNullOrEmpty(message))
            {
                // Serialize the entire JSON object as the message for full-text search
                message = token.ToString(Newtonsoft.Json.Formatting.None);
            }
            entry.Message = LogEntry.TrimMultiSpace(message);
            
            // Other optional fields
            entry.ProcessId = GetJsonValueInt(obj, "processId", "process_id", "pid") ?? 0;
            // Note: Location is already set above before JOB_* handling
            entry.FunctionName = GetJsonValue(obj, "functionName", "function_name", "function", "method") ?? string.Empty;
            entry.LineNumber = GetJsonValueInt(obj, "lineNumber", "line_number", "line") ?? 0;
            entry.ErrorId = GetJsonValue(obj, "errorId", "error_id", "errorCode", "error_code");
            entry.AlertId = GetJsonValue(obj, "alertId", "alert_id", "id");
            entry.ExceptionType = GetJsonValue(obj, "exceptionType", "exception_type", "exception");
            entry.StackTrace = GetJsonValue(obj, "stackTrace", "stack_trace", "stack");
            entry.InnerException = GetJsonValue(obj, "innerException", "inner_exception");
            entry.CommandInvocation = GetJsonValue(obj, "commandInvocation", "command_invocation", "command");
            entry.ScriptLineNumber = GetJsonValueInt(obj, "scriptLineNumber", "script_line_number");
            entry.ScriptName = GetJsonValue(obj, "scriptName", "script_name", "script");
            entry.Position = GetJsonValueInt(obj, "position");
            entry.JobName = GetJsonValue(obj, "jobName", "job_name", "job", "task");
            
            // Only set JobStatus from status/result field if it wasn't already set from Level (JOB_*)
            // This prevents overwriting proper job statuses like "Started" with boolean values like "True"
            if (string.IsNullOrEmpty(entry.JobStatus))
            {
                var statusValue = GetJsonValue(obj, "jobStatus", "job_status");
                // Only use status/state/result if they're actual job status strings, not boolean values
                if (string.IsNullOrEmpty(statusValue))
                {
                    var genericStatus = GetJsonValue(obj, "status", "state", "result");
                    // Filter out boolean-like values that aren't job statuses
                    if (!string.IsNullOrEmpty(genericStatus) && 
                        !genericStatus.Equals("true", StringComparison.OrdinalIgnoreCase) &&
                        !genericStatus.Equals("false", StringComparison.OrdinalIgnoreCase) &&
                        !genericStatus.Equals("1", StringComparison.Ordinal) &&
                        !genericStatus.Equals("0", StringComparison.Ordinal))
                    {
                        statusValue = genericStatus;
                    }
                }
                entry.JobStatus = NormalizeJobStatus(statusValue);
            }

            entry.GenerateConcatenatedSearchString();
            return entry;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error parsing JSON log entry from: {FilePath}", filePath);
            return null;
        }
    }

    /// <summary>
    /// Gets a string value from a JObject using multiple possible field names (case-insensitive)
    /// </summary>
    private static string? GetJsonValue(JObject? obj, params string[] fieldNames)
    {
        if (obj == null) return null;
        foreach (var name in fieldNames)
        {
            // Try exact match first
            if (obj.TryGetValue(name, StringComparison.OrdinalIgnoreCase, out var token))
            {
                return token?.ToString();
            }
        }
        return null;
    }

    /// <summary>
    /// Gets an integer value from a JObject using multiple possible field names (case-insensitive)
    /// </summary>
    private static int? GetJsonValueInt(JObject? obj, params string[] fieldNames)
    {
        var strValue = GetJsonValue(obj, fieldNames);
        if (int.TryParse(strValue, out var intValue))
            return intValue;
        return null;
    }

    private List<LogEntry> ParseXmlFile(string content, string filePath, DateTime? fileFallbackTime = null)
    {
        var entries = new List<LogEntry>();
        
        try
        {
            var doc = new XmlDocument();
            doc.LoadXml(content);

            var logNodes = doc.SelectNodes("//LogEntry") ?? doc.SelectNodes("//*[local-name()='LogEntry']");
            
            if (logNodes != null)
            {
                foreach (XmlNode node in logNodes)
                {
                    var entry = ParseXmlLogEntry(node, filePath, fileFallbackTime);
                    if (entry != null)
                        entries.Add(entry);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error parsing XML file: {FilePath}", filePath);
            throw;
        }

        return entries;
    }

    /// <summary>
    /// Parse a single XML log entry. Uses fileFallbackTime if no timestamp in entry.
    /// </summary>
    private LogEntry? ParseXmlLogEntry(XmlNode node, string filePath, DateTime? fileFallbackTime = null)
    {
        try
        {
            var entry = new LogEntry
            {
                SourceFile = filePath,
                SourceType = "xml",
                ImportTimestamp = DateTime.UtcNow
            };

            entry.Timestamp = ParseDateTime(GetXmlValue(node, "Timestamp") ?? GetXmlValue(node, "@timestamp")) ?? fileFallbackTime ?? DateTime.UtcNow;
            entry.Level = ParseLogLevel(GetXmlValue(node, "Level") ?? GetXmlValue(node, "@level")) ?? Core.Models.LogLevel.INFO;
            entry.ComputerName = GetXmlValue(node, "ComputerName") ?? GetXmlValue(node, "@computerName") ?? Environment.MachineName;
            entry.UserName = GetXmlValue(node, "UserName") ?? GetXmlValue(node, "@userName") ?? string.Empty;
            entry.Message = LogEntry.TrimMultiSpace(GetXmlValue(node, "Message") ?? node.InnerText ?? string.Empty);
            entry.FunctionName = GetXmlValue(node, "FunctionName") ?? string.Empty;
            entry.Location = GetXmlValue(node, "Location") ?? string.Empty;

            if (int.TryParse(GetXmlValue(node, "ProcessId"), out var processId))
                entry.ProcessId = processId;

            if (int.TryParse(GetXmlValue(node, "LineNumber"), out var lineNumber))
                entry.LineNumber = lineNumber;

            entry.ErrorId = GetXmlValue(node, "ErrorId");
            entry.ExceptionType = GetXmlValue(node, "ExceptionType");
            entry.StackTrace = GetXmlValue(node, "StackTrace");

            entry.GenerateConcatenatedSearchString();
            return entry;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error parsing XML log entry from: {FilePath}", filePath);
            return null;
        }
    }

    private List<LogEntry> ParseLogFile(string content, string filePath, DateTime? fileFallbackTime = null)
    {
        var entries = new List<LogEntry>();
        var lines = content.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        
        // Skip header lines if configured
        var startLine = _source.Config.SkipHeaderLines;
        
        for (int i = startLine; i < lines.Length; i++)
        {
            var line = lines[i].Trim();
            if (string.IsNullOrEmpty(line)) continue;

            var entry = ParseLogLine(line, filePath, i + 1, fileFallbackTime);
            if (entry != null)
                entries.Add(entry);
        }

        return entries;
    }

    /// <summary>
    /// Parse a single log line. Uses fileFallbackTime if no timestamp in entry.
    /// Tries WKMONIT/COBNT format first (HH:MM JOBNAME CODE message) so job start/stop lines get JobName and JobStatus into the job log.
    /// </summary>
    private LogEntry? ParseLogLine(string line, string filePath, int lineNumber, DateTime? fileFallbackTime = null)
    {
        try
        {
            // WKMONIT/COBNT format: HH:MM JOBNAME CODE [optional id/timestamp] MESSAGE (e.g. 00:01 WKSTYR 0000 WKSTYR INN I NYTT DØGN ...)
            var wkmMatch = Regex.Match(line, @"^(\d{2}:\d{2})\s+(\S+)\s+(\d{4})\s+(.*)$");
            if (wkmMatch.Success)
            {
                var entry = ParseWkmontLine(wkmMatch, filePath, lineNumber, fileFallbackTime);
                if (entry != null)
                    return entry;
            }

            // PowerShell log format: [timestamp] [level] [computer] [user] [function] message
            var match = Regex.Match(line, @"^\[([^\]]+)\]\s*\[([^\]]+)\]\s*\[([^\]]*)\]\s*\[([^\]]*)\]\s*\[([^\]]*)\]\s*(.*)$");
            
            if (match.Success)
            {
                var entry = new LogEntry
                {
                    SourceFile = filePath,
                    SourceType = "log",
                    ImportTimestamp = DateTime.UtcNow,
                    LineNumber = lineNumber
                };

                entry.Timestamp = ParseDateTime(match.Groups[1].Value) ?? fileFallbackTime ?? DateTime.UtcNow;
                entry.Level = ParseLogLevel(match.Groups[2].Value) ?? Core.Models.LogLevel.INFO;
                entry.ComputerName = match.Groups[3].Value.Trim();
                entry.UserName = match.Groups[4].Value.Trim();
                entry.FunctionName = match.Groups[5].Value.Trim();
                entry.Message = LogEntry.TrimMultiSpace(match.Groups[6].Value.Trim());

                if (string.IsNullOrEmpty(entry.ComputerName))
                    entry.ComputerName = Environment.MachineName;

                entry.GenerateConcatenatedSearchString();
                return entry;
            }
            else
            {
                // Fallback: treat entire line as message, use file time if no timestamp
                return new LogEntry
                {
                    Timestamp = fileFallbackTime ?? DateTime.UtcNow,
                    Level = Core.Models.LogLevel.INFO,
                    ComputerName = Environment.MachineName,
                    Message = LogEntry.TrimMultiSpace(line),
                    SourceFile = filePath,
                    SourceType = "log",
                    ImportTimestamp = DateTime.UtcNow,
                    LineNumber = lineNumber
                };
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error parsing log line {LineNumber} from: {FilePath}", lineNumber, filePath);
            return null;
        }
    }

    /// <summary>
    /// Parse a WKMONIT/COBNT line with tiered log levels, enhanced job detection,
    /// embedded server name extraction, and AutoDocJson metadata enrichment.
    /// Format: HH:MM JOBNAME CODE MESSAGE
    /// </summary>
    private LogEntry? ParseWkmontLine(Match wkmMatch, string filePath, int lineNumber, DateTime? fileFallbackTime)
    {
        var timePart = wkmMatch.Groups[1].Value;
        var jobName = wkmMatch.Groups[2].Value.Trim();
        var codeStr = wkmMatch.Groups[3].Value;
        var rest = wkmMatch.Groups[4].Value;

        if (!int.TryParse(codeStr, out var code))
            return null;

        var baseDate = DateTime.SpecifyKind((fileFallbackTime ?? DateTime.UtcNow).Date, DateTimeKind.Utc);
        if (TimeSpan.TryParse(timePart, out var timeOfDay))
            baseDate = baseDate.Add(timeOfDay);
        else
            baseDate = fileFallbackTime ?? DateTime.UtcNow;

        var level = ClassifyWkmonitLevel(code);

        var message = LogEntry.TrimMultiSpace(rest);
        var upperMsg = message.ToUpperInvariant();

        // Extract embedded server name: "P-NO1FKMPRD-APP: ..." or "P-NO1INLPRD-DB: ..."
        // Regex: sequence of uppercase/digit/hyphens followed by a colon at the start of the message
        string? computerName = null;
        var serverMatch = Regex.Match(message, @"^(P-\S+?):\s");
        if (serverMatch.Success)
            computerName = serverMatch.Groups[1].Value;

        string? jobStatus = null;
        string? functionName = null;

        // STEP tracking: "STEP: 130 PROGRAM: SFBDKON AVSLUTTER OK"
        // Regex: STEP: <number> PROGRAM: <name> <rest>
        var stepMatch = Regex.Match(upperMsg, @"STEP:\s*(\d+)\s+PROGRAM:\s*(\S+)");
        if (stepMatch.Success)
        {
            functionName = $"Step {stepMatch.Groups[1].Value} / {stepMatch.Groups[2].Value}";
            if (upperMsg.Contains("AVSLUTTER OK") || upperMsg.Contains("AVSLUTTET OK"))
                jobStatus = "Completed";
            else if (upperMsg.Contains("FEIL") || upperMsg.Contains("ABEND"))
                jobStatus = "Failed";
        }

        if (jobStatus == null)
        {
            if (upperMsg.Contains("ER STARTET OK"))
                jobStatus = "Completed";
            else if (upperMsg.Contains("SUCCESS"))
                jobStatus = "Completed";
            else if (upperMsg.Contains("GIKK FEIL"))
                jobStatus = "Failed";
            else if (upperMsg.Contains("AVSLUTTET FEIL"))
                jobStatus = "Failed";
            else if (upperMsg.Contains("FEIL VED") || upperMsg.Contains("FEIL I ") || upperMsg.Contains("SQL-FEIL"))
                jobStatus = "Failed";
            else if (upperMsg.Contains("STARTER") || upperMsg.Contains("INN I NYTT"))
                jobStatus = "Started";
            else if (upperMsg.Contains("STARTET") && !upperMsg.Contains("ER STARTET OK"))
                jobStatus = "Started";
            else if (upperMsg.Contains("#TIDSPUNKT#"))
                jobStatus = "TimePoint";
            else if (upperMsg.Contains("AVSLUTTET OK") || upperMsg.Contains("AVSLUTTET NORMALT") || upperMsg.Contains("ALT SÅ UT"))
                jobStatus = "Completed";
        }

        // SQLKODE non-zero check: "SQLKODE:nnn" where nnn != 0 → Failed
        var sqlCodeMatch = Regex.Match(upperMsg, @"SQLKODE:\s*(-?\d+)");
        if (sqlCodeMatch.Success && int.TryParse(sqlCodeMatch.Groups[1].Value, out var sqlCode) && sqlCode != 0)
        {
            jobStatus = "Failed";
            if (level < Core.Models.LogLevel.ERROR)
                level = Core.Models.LogLevel.ERROR;
        }

        // Metadata enrichment from AutoDocJson
        string? location = null;
        if (_metadataService != null && _metadataService.TryGetProgramInfo(jobName, out var progInfo) && progInfo != null)
        {
            location = progInfo.TypeLabel;
            if (functionName == null && !string.IsNullOrEmpty(progInfo.System))
                functionName = progInfo.System;
        }

        var entry = new LogEntry
        {
            Timestamp = baseDate,
            Level = level,
            ComputerName = computerName ?? Environment.MachineName,
            Message = message,
            JobName = jobName,
            JobStatus = jobStatus,
            FunctionName = functionName ?? string.Empty,
            Location = location ?? string.Empty,
            SourceFile = filePath,
            SourceType = "log",
            ImportTimestamp = DateTime.UtcNow,
            LineNumber = lineNumber
        };
        entry.GenerateConcatenatedSearchString();
        return entry;
    }

    /// <summary>
    /// Tiered log level classification for WKMONIT 4-digit codes.
    /// 0000 = INFO, 0001-0009 = INFO (routine), 0010-0016 = WARN (mild),
    /// 0017-0099 = WARN (moderate), 0100-0899 = ERROR, 0900-0998 = ERROR (severe),
    /// 0999 = FATAL (critical import failures), 9999 = DEBUG (SQL startup diagnostics).
    /// </summary>
    private static Core.Models.LogLevel ClassifyWkmonitLevel(int code) => code switch
    {
        0 => Core.Models.LogLevel.INFO,
        >= 1 and <= 9 => Core.Models.LogLevel.INFO,
        >= 10 and <= 16 => Core.Models.LogLevel.WARN,
        >= 17 and <= 99 => Core.Models.LogLevel.WARN,
        >= 100 and <= 899 => Core.Models.LogLevel.ERROR,
        >= 900 and <= 998 => Core.Models.LogLevel.ERROR,
        999 => Core.Models.LogLevel.FATAL,
        9999 => Core.Models.LogLevel.DEBUG,
        _ => Core.Models.LogLevel.WARN
    };

    private void MoveProcessedFile(string filePath)
    {
        try
        {
            if (string.IsNullOrEmpty(_source.Config.ProcessedFilesLocation))
                return;

            var fileName = Path.GetFileName(filePath);
            var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var newFileName = $"{timestamp}_{fileName}";
            var destinationPath = Path.Combine(_source.Config.ProcessedFilesLocation, newFileName);

            Directory.CreateDirectory(_source.Config.ProcessedFilesLocation);
            File.Move(filePath, destinationPath);

            _logger.LogDebug("Moved processed file from {Source} to {Destination}", filePath, destinationPath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error moving processed file: {FilePath}", filePath);
        }
    }

    /// <summary>
    /// Check if file should be quarantined based on error rate
    /// </summary>
    private bool ShouldQuarantineFile(ImportResult result)
    {
        // Must have processed at least some records to calculate error rate
        var totalRecords = result.RecordsProcessed + result.RecordsFailed;
        if (totalRecords < 10) return false; // Don't quarantine small files
        
        // Calculate error rate
        var errorRate = (double)result.RecordsFailed / totalRecords * 100;
        
        // Get threshold from config or use default (50%)
        var threshold = _source.Config.QuarantineErrorRateThreshold > 0 
            ? _source.Config.QuarantineErrorRateThreshold 
            : 50.0;
        
        return errorRate >= threshold;
    }

    /// <summary>
    /// Move file to quarantine folder
    /// </summary>
    private void QuarantineFile(string filePath, ImportResult result)
    {
        try
        {
            // Get quarantine path - use config or default to "Quarantine" subfolder
            var quarantinePath = !string.IsNullOrEmpty(_source.Config.QuarantinePath) 
                ? _source.Config.QuarantinePath 
                : Path.Combine(Path.GetDirectoryName(_source.Config.Path) ?? ".", "Quarantine");

            // Create folder structure: {QuarantinePath}/{SourceName}/{Date}/
            var dateFolder = DateTime.Now.ToString("yyyy-MM-dd");
            var sourceName = _source.Name.Replace(" ", "_").Replace("/", "_").Replace("\\", "_");
            var destinationFolder = Path.Combine(quarantinePath, sourceName, dateFolder);
            
            Directory.CreateDirectory(destinationFolder);

            // Move file
            var fileName = Path.GetFileName(filePath);
            var destinationPath = Path.Combine(destinationFolder, fileName);
            
            // If file already exists, add timestamp
            if (File.Exists(destinationPath))
            {
                var timestamp = DateTime.Now.ToString("HHmmss");
                var ext = Path.GetExtension(fileName);
                var nameWithoutExt = Path.GetFileNameWithoutExtension(fileName);
                destinationPath = Path.Combine(destinationFolder, $"{nameWithoutExt}_{timestamp}{ext}");
            }

            File.Move(filePath, destinationPath);

            // Calculate error rate for logging
            var totalRecords = result.RecordsProcessed + result.RecordsFailed;
            var errorRate = totalRecords > 0 ? (double)result.RecordsFailed / totalRecords * 100 : 0;

            // Write quarantine reason to a companion .reason file
            var reasonFilePath = destinationPath + ".quarantine-reason.txt";
            var reason = $"Quarantined: {DateTime.UtcNow:O}\n" +
                        $"Source: {_source.Name}\n" +
                        $"Original Path: {filePath}\n" +
                        $"Records Processed: {result.RecordsProcessed}\n" +
                        $"Records Failed: {result.RecordsFailed}\n" +
                        $"Error Rate: {errorRate:F2}%\n" +
                        $"Error Message: {result.ErrorMessage ?? "Multiple parse errors"}";
            File.WriteAllText(reasonFilePath, reason);

            _logger.LogWarning("Quarantined file with {ErrorRate:F1}% error rate: {SourcePath} -> {DestPath}", 
                errorRate, filePath, destinationPath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error quarantining file: {FilePath}", filePath);
        }
    }

    /// <summary>
    /// Gets the fallback timestamp from a file - uses the earlier of creation time or modified time.
    /// This is used when a log entry doesn't have its own timestamp.
    /// </summary>
    private static DateTime GetFileFallbackTime(FileInfo fileInfo)
    {
        var creationTime = fileInfo.CreationTimeUtc;
        var modifiedTime = fileInfo.LastWriteTimeUtc;
        // Use the earlier time as it's more likely to be when the log was actually created
        return creationTime < modifiedTime ? creationTime : modifiedTime;
    }

    private static DateTime? ParseDateTime(string? dateTimeString)
    {
        if (string.IsNullOrEmpty(dateTimeString))
            return null;

        var formats = new[]
        {
            "yyyy-MM-dd HH:mm:ss.fff",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-ddTHH:mm:ss.fffZ",
            "yyyy-MM-ddTHH:mm:ssZ",
            "MM/dd/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm:ss"
        };

        foreach (var format in formats)
        {
            if (DateTime.TryParseExact(dateTimeString, format, null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out var result))
                return result;
        }

        if (DateTime.TryParse(dateTimeString, null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out var parsed))
            return parsed;

        return null;
    }

    private static Core.Models.LogLevel? ParseLogLevel(string? levelString)
    {
        if (string.IsNullOrEmpty(levelString))
            return null;

        var upper = levelString.ToUpperInvariant();
        
        // Map JOB_* levels to appropriate severity while preserving job tracking
        // JOB_STARTED and JOB_COMPLETED are informational
        // JOB_FAILED is an error condition
        if (upper.StartsWith("JOB_"))
        {
            return upper switch
            {
                "JOB_STARTED" => Core.Models.LogLevel.INFO,
                "JOB_COMPLETED" => Core.Models.LogLevel.INFO,
                "JOB_FAILED" => Core.Models.LogLevel.ERROR,
                _ => Core.Models.LogLevel.INFO
            };
        }

        return upper switch
        {
            "TRACE" or "0" => Core.Models.LogLevel.TRACE,
            "DEBUG" or "1" => Core.Models.LogLevel.DEBUG,
            "INFO" or "INFORMATION" or "2" => Core.Models.LogLevel.INFO,
            "WARN" or "WARNING" or "3" => Core.Models.LogLevel.WARN,
            "ERROR" or "4" => Core.Models.LogLevel.ERROR,
            "FATAL" or "CRITICAL" or "5" => Core.Models.LogLevel.FATAL,
            _ => null
        };
    }
    
    /// <summary>
    /// Checks if a level string represents a job status (JOB_STARTED, JOB_COMPLETED, JOB_FAILED)
    /// </summary>
    private static bool IsJobLevel(string? levelString)
    {
        if (string.IsNullOrEmpty(levelString))
            return false;
        return levelString.StartsWith("JOB_", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Extracts a job name from filename or location context.
    /// Filename format example: 20250826-195307-519_JOB_STARTED_30237-FK_38160.json
    /// Location example: Db2-AutoCatalog.ps1
    /// </summary>
    private static string ExtractJobNameFromContext(string? fileName, string? location)
    {
        // Prefer location (script name) as job name if available
        if (!string.IsNullOrEmpty(location))
        {
            // Remove extension if present
            var name = System.IO.Path.GetFileNameWithoutExtension(location);
            if (!string.IsNullOrEmpty(name))
                return name;
        }

        // Try to extract from filename pattern: TIMESTAMP_STATUS_COMPUTER_PID
        // We want to return the script that generated this job
        if (!string.IsNullOrEmpty(fileName))
        {
            // Look for patterns like Db2-AutoCatalog in the context
            // For now, just use the computer name from the filename
            var parts = fileName.Split('_');
            if (parts.Length >= 4)
            {
                // parts[0] = timestamp, parts[1] = status, parts[2] = computer, parts[3] = pid
                return $"Job_{parts[2]}"; // Use computer as fallback identifier
            }
        }

        return "Unknown Job";
    }

    private static string? GetXmlValue(XmlNode node, string xpath)
    {
        var selectedNode = node.SelectSingleNode(xpath);
        return selectedNode?.InnerText ?? selectedNode?.Value;
    }

    private List<LogEntry> ParseRawFile(string content, string filePath, DateTime? fileFallbackTime = null)
    {
        var entries = new List<LogEntry>();

        var entry = new LogEntry
        {
            SourceFile = filePath,
            SourceType = "raw",
            ImportTimestamp = DateTime.UtcNow,
            Timestamp = fileFallbackTime ?? File.GetLastWriteTimeUtc(filePath),
            Level = Core.Models.LogLevel.INFO,
            ComputerName = Environment.MachineName,
            Message = LogEntry.TrimMultiSpace(content)
        };

        entry.GenerateConcatenatedSearchString();
        entries.Add(entry);

        return entries;
    }

    /// <summary>
    /// Parse delimited file (pipe, comma, tab separated) using ParserConfig
    /// </summary>
    private List<LogEntry> ParseDelimitedFile(string content, string filePath, DateTime? fileFallbackTime = null)
    {
        var entries = new List<LogEntry>();
        var parser = _source.Config.Parser;
        
        if (parser == null || string.IsNullOrEmpty(parser.Delimiter))
        {
            _logger.LogWarning("No parser configuration or delimiter specified for delimited file: {FilePath}", filePath);
            return ParseLogFile(content, filePath, fileFallbackTime); // Fallback
        }

        var lines = content.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        var startLine = _source.Config.SkipHeaderLines;
        var delimiter = parser.Delimiter == "\\t" ? "\t" : parser.Delimiter;

        for (int i = startLine; i < lines.Length; i++)
        {
            var line = lines[i].TrimEnd('\r');
            if (string.IsNullOrWhiteSpace(line)) continue;

            try
            {
                var entry = ParseDelimitedLine(line, delimiter, filePath, i + 1, parser, fileFallbackTime);
                if (entry != null)
                    entries.Add(entry);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error parsing line {LineNumber} in file: {FilePath}", i + 1, filePath);
            }
        }

        return entries;
    }

    /// <summary>
    /// Parse a single delimited line using field mappings from ParserConfig.
    /// Uses fileFallbackTime if no timestamp is parsed from the line.
    /// </summary>
    private LogEntry? ParseDelimitedLine(string line, string delimiter, string filePath, int lineNumber, ParserConfig parser, DateTime? fileFallbackTime = null)
    {
        var parts = line.Split(delimiter);
        
        var entry = new LogEntry
        {
            SourceFile = filePath,
            SourceType = "delimited",
            ImportTimestamp = DateTime.UtcNow,
            LineNumber = lineNumber,
            ComputerName = Environment.MachineName,
            Level = Core.Models.LogLevel.INFO,
            Timestamp = fileFallbackTime ?? DateTime.UtcNow  // Default to file time, override if parsed
        };

        // Apply field mappings
        foreach (var mapping in parser.FieldMappings)
        {
            if (!int.TryParse(mapping.Key, out var index) || index < 0 || index >= parts.Length)
                continue;

            var value = parts[index].Trim();
            var extractor = mapping.Value;
            
            // Apply transform if specified
            value = ApplyTransform(value, extractor.Transform);
            
            // Use default value if empty
            if (string.IsNullOrEmpty(value) && !string.IsNullOrEmpty(extractor.DefaultValue))
                value = extractor.DefaultValue;

            // Set the property on LogEntry, passing file fallback time for timestamp parsing
            SetLogEntryProperty(entry, extractor.TargetColumn, value, extractor.DateFormat, fileFallbackTime);
        }

        // Fallback: if no mappings or Message is empty, use entire line
        if (string.IsNullOrEmpty(entry.Message))
        {
            entry.Message = LogEntry.TrimMultiSpace(line);
        }

        entry.GenerateConcatenatedSearchString();
        return entry;
    }

    /// <summary>
    /// Apply transformation to a value
    /// </summary>
    private static string ApplyTransform(string value, string? transform)
    {
        if (string.IsNullOrEmpty(transform) || string.IsNullOrEmpty(value))
            return value;

        return transform.ToLower() switch
        {
            "uppercase" or "upper" => value.ToUpperInvariant(),
            "lowercase" or "lower" => value.ToLowerInvariant(),
            "trim" => value.Trim(),
            _ => value
        };
    }

    /// <summary>
    /// Set a property on LogEntry by name. Uses fileFallbackTime for timestamp if parsing fails.
    /// </summary>
    private void SetLogEntryProperty(LogEntry entry, string propertyName, string value, string? dateFormat, DateTime? fileFallbackTime = null)
    {
        if (string.IsNullOrEmpty(propertyName) || string.IsNullOrEmpty(value))
            return;

        try
        {
            switch (propertyName.ToLower())
            {
                case "timestamp":
                    entry.Timestamp = ParseDateTimeWithFormat(value, dateFormat) ?? fileFallbackTime ?? DateTime.UtcNow;
                    break;
                case "level":
                    if (IsJobLevel(value))
                    {
                        entry.JobStatus = NormalizeJobStatus(value);
                    }
                    entry.Level = ParseLogLevel(value) ?? Core.Models.LogLevel.INFO;
                    break;
                case "processid":
                    if (int.TryParse(value, out var pid))
                        entry.ProcessId = pid;
                    break;
                case "location":
                    entry.Location = value;
                    break;
                case "functionname":
                    entry.FunctionName = value;
                    break;
                case "linenumber":
                    if (int.TryParse(value, out var ln))
                        entry.LineNumber = ln;
                    break;
                case "computername":
                    entry.ComputerName = value;
                    break;
                case "username":
                    entry.UserName = value;
                    break;
                case "message":
                    entry.Message = LogEntry.TrimMultiSpace(value);
                    break;
                case "errorid":
                    entry.ErrorId = value;
                    break;
                case "alertid":
                    entry.AlertId = value;
                    break;
                case "ordrenr":
                    entry.Ordrenr = value;
                    break;
                case "avdnr":
                    entry.Avdnr = value;
                    break;
                case "jobname":
                    entry.JobName = value;
                    break;
                case "jobstatus":
                    entry.JobStatus = NormalizeJobStatus(value);
                    break;
                case "exceptiontype":
                    entry.ExceptionType = value;
                    break;
                case "stacktrace":
                    entry.StackTrace = value;
                    break;
                case "innerexception":
                    entry.InnerException = value;
                    break;
                case "commandinvocation":
                    entry.CommandInvocation = value;
                    break;
                case "scriptlinenumber":
                    if (int.TryParse(value, out var sln))
                        entry.ScriptLineNumber = sln;
                    break;
                case "scriptname":
                    entry.ScriptName = value;
                    break;
                case "position":
                    if (int.TryParse(value, out var pos))
                        entry.Position = pos;
                    break;
                default:
                    _logger.LogDebug("Unknown property mapping: {PropertyName}", propertyName);
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error setting property {PropertyName} to value {Value}", propertyName, value);
        }
    }

    /// <summary>
    /// Parse datetime with optional custom format
    /// </summary>
    private static DateTime? ParseDateTimeWithFormat(string? dateTimeString, string? format)
    {
        if (string.IsNullOrEmpty(dateTimeString))
            return null;

        // Try custom format first
        if (!string.IsNullOrEmpty(format))
        {
            if (DateTime.TryParseExact(dateTimeString, format, null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out var customResult))
                return customResult;
        }

        // Fall back to standard parsing
        return ParseDateTime(dateTimeString);
    }

    /// <summary>
    /// Apply MessageExtractors to extract business identifiers from message content
    /// </summary>
    private void ApplyMessageExtractors(LogEntry entry)
    {
        if (_source.Config.Parser?.MessageExtractors == null || string.IsNullOrEmpty(entry.Message))
            return;

        foreach (var extractor in _source.Config.Parser.MessageExtractors)
        {
            if (string.IsNullOrEmpty(extractor.Pattern) || string.IsNullOrEmpty(extractor.TargetColumn))
                continue;

            try
            {
                var options = extractor.IgnoreCase ? RegexOptions.IgnoreCase : RegexOptions.None;
                var match = Regex.Match(entry.Message, extractor.Pattern, options);
                
                if (match.Success)
                {
                    var captureGroup = string.IsNullOrEmpty(extractor.CaptureGroup) ? "value" : extractor.CaptureGroup;
                    var group = match.Groups[captureGroup];
                    
                    if (group.Success)
                    {
                        SetLogEntryProperty(entry, extractor.TargetColumn, group.Value, null);
                        _logger.LogDebug("Extracted {Property}={Value} from message using extractor {Name}",
                            extractor.TargetColumn, group.Value, extractor.Name);
                    }
                }
            }
            catch (RegexMatchTimeoutException)
            {
                _logger.LogWarning("Regex timeout for extractor {Name} with pattern {Pattern}", 
                    extractor.Name, extractor.Pattern);
            }
            catch (ArgumentException ex)
            {
                _logger.LogWarning(ex, "Invalid regex pattern for extractor {Name}: {Pattern}", 
                    extractor.Name, extractor.Pattern);
            }
        }

        // Regenerate search string after extracting fields
        entry.GenerateConcatenatedSearchString();
    }
}
