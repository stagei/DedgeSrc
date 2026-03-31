using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;
using System.Runtime.Versioning;
using GenericLogHandler.ImportService.Importers;
using GenericLogHandler.ImportService.Services;
using GenericLogHandler.Data;
using System.Collections.Concurrent;
using System.Text.Json;

namespace GenericLogHandler.ImportService;

/// <summary>
/// Main import service that coordinates all import operations
/// </summary>
public class ImportService : BackgroundService
{
    private readonly ILogger<ImportService> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private readonly IServiceScopeFactory _scopeFactory;
    private ImportConfiguration _config;
    private readonly IConfiguration _appConfiguration;
    private readonly ConcurrentDictionary<string, ILogImporter> _importers = new();
    private readonly Timer _healthCheckTimer;
    private readonly Timer _cleanupTimer;
    private readonly Timer? _jobCorrelationTimer;
    private FileSystemWatcher? _configWatcher;
    private readonly SemaphoreSlim _reloadLock = new(1, 1);
    private readonly string? _configFilePath;
    private readonly RetryService _retryService;
    private readonly JobTrackingConfiguration _jobTrackingConfig;
    private DateTime _lastJobCorrelationRun = DateTime.UtcNow;
    private readonly WkmonitMetadataService _metadataService;

    public ImportService(
        ILogger<ImportService> logger,
        ILoggerFactory loggerFactory,
        IServiceScopeFactory scopeFactory,
        IOptions<ImportConfiguration> config,
        IConfiguration appConfiguration,
        IOptions<JobTrackingConfiguration> jobTrackingConfig)
    {
        _logger = logger;
        _loggerFactory = loggerFactory;
        _scopeFactory = scopeFactory;
        _config = config.Value;
        _appConfiguration = appConfiguration;
        _jobTrackingConfig = jobTrackingConfig.Value;
        _metadataService = new WkmonitMetadataService(_loggerFactory.CreateLogger<WkmonitMetadataService>());
        
        // Initialize retry service with configured policy
        _retryService = new RetryService(
            _loggerFactory.CreateLogger<RetryService>(),
            _config.General.RetryPolicy);

        // Determine config file path for hot-reload
        _configFilePath = FindConfigFilePath();

        // Setup health check timer
        var healthInterval = TimeSpan.FromSeconds(_config.General.HealthCheckInterval);
        _healthCheckTimer = new Timer(PerformHealthCheck, null, healthInterval, healthInterval);

        // Setup cleanup timer (daily at 2 AM by default)
        var cleanupInterval = TimeSpan.FromDays(1);
        _cleanupTimer = new Timer(PerformCleanup, null, GetTimeUntilNextCleanup(), cleanupInterval);

        // Setup job correlation timer (runs every CheckIntervalMinutes)
        if (_jobTrackingConfig.EnableJobCorrelation)
        {
            var correlationInterval = TimeSpan.FromMinutes(_jobTrackingConfig.CheckIntervalMinutes);
            _jobCorrelationTimer = new Timer(PerformJobCorrelation, null, correlationInterval, correlationInterval);
            _logger.LogInformation("Job correlation enabled, checking every {Minutes} minutes", _jobTrackingConfig.CheckIntervalMinutes);
        }

        // Setup config file watcher for hot-reload
        SetupConfigFileWatcher();

        _logger.LogInformation("ImportService initialized with {Sources} import sources", 
            _config.ImportSources.Count);
    }

    private string? FindConfigFilePath()
    {
        // Look for import-config.json or appsettings.json in common locations
        var searchPaths = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "import-config.json"),
            Path.Combine(Directory.GetCurrentDirectory(), "import-config.json"),
            GetRepositoryRoot("import-config.json"),
            Path.Combine(AppContext.BaseDirectory, "appsettings.json"),
            Path.Combine(Directory.GetCurrentDirectory(), "appsettings.json"),
            GetRepositoryRoot("appsettings.json")
        };

        foreach (var path in searchPaths.Where(p => !string.IsNullOrEmpty(p)))
        {
            if (File.Exists(path))
            {
                _logger.LogInformation("Found config file for hot-reload: {Path}", path);
                return path;
            }
        }

        _logger.LogWarning("No config file found for hot-reload monitoring");
        return null;
    }

    private static string GetRepositoryRoot(string fileName)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            var configPath = Path.Combine(dir.FullName, fileName);
            if (File.Exists(configPath))
                return configPath;

            if (File.Exists(Path.Combine(dir.FullName, "GenericLogHandler.sln")))
                return Path.Combine(dir.FullName, fileName);

            dir = dir.Parent;
        }
        return string.Empty;
    }

    private void SetupConfigFileWatcher()
    {
        if (string.IsNullOrEmpty(_configFilePath) || !File.Exists(_configFilePath))
        {
            _logger.LogWarning("Config file watcher not setup: no valid config file path");
            return;
        }

        try
        {
            var directory = Path.GetDirectoryName(_configFilePath);
            var fileName = Path.GetFileName(_configFilePath);

            if (string.IsNullOrEmpty(directory))
                return;

            _configWatcher = new FileSystemWatcher(directory, fileName)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size
            };

            _configWatcher.Changed += OnConfigFileChanged;
            _configWatcher.EnableRaisingEvents = true;

            _logger.LogInformation("Config file watcher enabled for: {FilePath}", _configFilePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to setup config file watcher for: {FilePath}", _configFilePath);
        }
    }

    private async void OnConfigFileChanged(object sender, FileSystemEventArgs e)
    {
        // Debounce: wait a bit to ensure file is fully written
        await Task.Delay(500);

        if (!await _reloadLock.WaitAsync(0))
        {
            _logger.LogDebug("Config reload already in progress, skipping");
            return;
        }

        try
        {
            _logger.LogInformation("Config file changed, reloading configuration...");
            await ReloadConfiguration();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reloading configuration from: {FilePath}", _configFilePath);
        }
        finally
        {
            _reloadLock.Release();
        }
    }

    private async Task ReloadConfiguration()
    {
        if (string.IsNullOrEmpty(_configFilePath) || !File.Exists(_configFilePath))
            return;

        try
        {
            var jsonContent = await File.ReadAllTextAsync(_configFilePath);
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            
            ImportConfiguration? newConfig = null;
            
            if (_configFilePath.EndsWith("import-config.json", StringComparison.OrdinalIgnoreCase))
            {
                // import-config.json has config at root level
                newConfig = JsonSerializer.Deserialize<ImportConfiguration>(jsonContent, options);
            }
            else
            {
                // appsettings.json has config under "ImportConfiguration" section
                using var doc = JsonDocument.Parse(jsonContent);
                if (doc.RootElement.TryGetProperty("ImportConfiguration", out var configSection))
                {
                    newConfig = JsonSerializer.Deserialize<ImportConfiguration>(configSection.GetRawText(), options);
                }
            }

            if (newConfig != null && newConfig.ImportSources.Count > 0)
            {
                _config = newConfig;
                _logger.LogInformation("Configuration reloaded: {Sources} import sources", _config.ImportSources.Count);
                
                // Reinitialize importers with new config
                await ReinitializeImporters(CancellationToken.None);
            }
            else
            {
                _logger.LogWarning("Reloaded config is empty or invalid, keeping existing configuration");
            }
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Invalid JSON in config file: {FilePath}", _configFilePath);
        }
    }

    private async Task ReinitializeImporters(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Reinitializing importers with updated configuration...");
        
        // Cleanup existing importers
        await CleanupImporters();
        
        // Initialize new importers
        await InitializeImporters(cancellationToken);
        
        _logger.LogInformation("Importers reinitialized: {Count} active importers", _importers.Count);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("ImportService starting...");

        try
        {
            // Migrate JSON config sources to database on first run
            await MigrateJsonSourcesToDatabaseAsync(stoppingToken);
            
            await InitializeImporters(stoppingToken);

            if (_config.General.RunOnce)
            {
                await RunImportCycle(stoppingToken);
                return;
            }

            while (!stoppingToken.IsCancellationRequested)
            {
                await RunImportCycle(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken); // Wait between cycles
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("ImportService stopping due to cancellation request");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ImportService encountered an error");
            throw;
        }
        finally
        {
            await CleanupImporters();
            _healthCheckTimer?.Dispose();
            _cleanupTimer?.Dispose();
            _jobCorrelationTimer?.Dispose();
            _configWatcher?.Dispose();
            _reloadLock?.Dispose();
        }
    }

    private async Task InitializeImporters(CancellationToken cancellationToken)
    {
        // Load import sources from database first, then fall back to JSON config
        var enabledSources = await GetImportSourcesAsync(cancellationToken);
        
        _logger.LogInformation("Initializing {Count} enabled import sources", enabledSources.Count);

        foreach (var source in enabledSources)
        {
            try
            {
                var importer = CreateImporter(source);
                await importer.InitializeAsync(source, cancellationToken);
                
                // Test connection
                var connectionTest = await importer.TestConnectionAsync(cancellationToken);
                if (!connectionTest)
                {
                    _logger.LogWarning("Connection test failed for source: {SourceName}", source.Name);
                    continue;
                }

                _importers[source.Name] = importer;
                _logger.LogInformation("Successfully initialized importer for: {SourceName}", source.Name);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to initialize importer for source: {SourceName}", source.Name);
            }
        }

        _logger.LogInformation("Initialized {Count} importers successfully", _importers.Count);
    }
    
    /// <summary>
    /// Load import sources from database, falling back to JSON config if database is empty
    /// </summary>
    private async Task<List<ImportSource>> GetImportSourcesAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
            
            var dbSources = await context.ImportSources
                .Where(s => s.Enabled)
                .OrderBy(s => s.Priority)
                .ToListAsync(cancellationToken);
            
            if (dbSources.Count > 0)
            {
                _logger.LogInformation("Loaded {Count} import sources from database", dbSources.Count);
                return dbSources.Select(ConvertToImportSource).ToList();
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not load import sources from database, using JSON config");
        }
        
        // Fallback to JSON config
        _logger.LogInformation("Using JSON config for import sources ({Count} sources)", _config.ImportSources.Count);
        return _config.ImportSources.Where(s => s.Enabled).ToList();
    }
    
    /// <summary>
    /// Convert database entity to ImportSource model
    /// </summary>
    private ImportSource ConvertToImportSource(ImportSourceEntity entity)
    {
        var source = new ImportSource
        {
            Name = entity.Name,
            Type = entity.Type,
            Enabled = entity.Enabled,
            Priority = entity.Priority,
            Config = new ImportSourceConfig
            {
                Path = entity.Path,
                Format = entity.Format,
                WatchDirectory = entity.WatchDirectory,
                Encoding = entity.Encoding,
                PollInterval = entity.PollInterval,
                ProcessExistingFiles = entity.ProcessExistingFiles,
                IsAppendOnly = entity.IsAppendOnly,
                MaxFileAgeDays = entity.MaxFileAgeDays
            }
        };
        
        // Parse advanced config from JSON if present
        if (!string.IsNullOrEmpty(entity.ConfigJson))
        {
            try
            {
                var advancedConfig = JsonSerializer.Deserialize<ImportSourceConfig>(entity.ConfigJson);
                if (advancedConfig != null)
                {
                    // Merge advanced settings
                    source.Config.Parser = advancedConfig.Parser;
                    source.Config.JsonRootPath = advancedConfig.JsonRootPath;
                    source.Config.FlattenNestedObjects = advancedConfig.FlattenNestedObjects;
                    source.Config.MaxDepth = advancedConfig.MaxDepth;
                    source.Config.XmlNamespaces = advancedConfig.XmlNamespaces;
                    source.Config.RootElementXPath = advancedConfig.RootElementXPath;
                    source.Config.SkipHeaderLines = advancedConfig.SkipHeaderLines;
                    source.Config.MaxFilesPerRun = advancedConfig.MaxFilesPerRun;
                    source.Config.MaxFullReadMB = advancedConfig.MaxFullReadMB;
                    source.Config.MoveProcessedFiles = advancedConfig.MoveProcessedFiles;
                    source.Config.ProcessedFilesLocation = advancedConfig.ProcessedFilesLocation;
                    source.Config.ErrorFilesLocation = advancedConfig.ErrorFilesLocation;
                    source.Config.QuarantinePath = advancedConfig.QuarantinePath;
                    source.Config.QuarantineErrorRateThreshold = advancedConfig.QuarantineErrorRateThreshold;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse advanced config JSON for source: {Name}", entity.Name);
            }
        }
        
        return source;
    }
    
    /// <summary>
    /// Migrate JSON config sources to database on first run (if database is empty)
    /// </summary>
    private async Task MigrateJsonSourcesToDatabaseAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
            
            var hasDbSources = await context.ImportSources.AnyAsync(cancellationToken);
            if (hasDbSources)
            {
                _logger.LogDebug("Database already has import sources, skipping migration");
                return;
            }
            
            if (_config.ImportSources == null || _config.ImportSources.Count == 0)
            {
                _logger.LogDebug("No JSON import sources to migrate");
                return;
            }
            
            _logger.LogInformation("Migrating {Count} import sources from JSON config to database...", 
                _config.ImportSources.Count);
            
            foreach (var source in _config.ImportSources)
            {
                var entity = new ImportSourceEntity
                {
                    Id = Guid.NewGuid(),
                    Name = source.Name,
                    Type = source.Type,
                    Enabled = source.Enabled,
                    Priority = source.Priority,
                    Path = source.Config.Path,
                    Format = source.Config.Format,
                    WatchDirectory = source.Config.WatchDirectory,
                    Encoding = source.Config.Encoding,
                    PollInterval = source.Config.PollInterval,
                    ProcessExistingFiles = source.Config.ProcessExistingFiles,
                    IsAppendOnly = source.Config.IsAppendOnly,
                    MaxFileAgeDays = source.Config.MaxFileAgeDays ?? 30,
                    Description = $"Migrated from JSON config",
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    CreatedBy = "System (Migration)"
                };
                
                if (source.Config.Parser != null || 
                    source.Config.MaxFullReadMB.HasValue ||
                    !string.IsNullOrEmpty(source.Config.RootElementXPath))
                {
                    entity.ConfigJson = JsonSerializer.Serialize(source.Config);
                }
                
                context.ImportSources.Add(entity);
            }
            
            await context.SaveChangesAsync(cancellationToken);
            _logger.LogInformation("Successfully migrated {Count} import sources to database", 
                _config.ImportSources.Count);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to migrate JSON sources to database - will use JSON config");
        }
    }

    private async Task RunImportCycle(CancellationToken cancellationToken)
    {
        await DrainIngestQueueAsync(cancellationToken);

        var importTasks = new List<Task>();
        var semaphore = new SemaphoreSlim(_config.General.MaxConcurrentImports);

        foreach (var (sourceName, importer) in _importers)
        {
            var task = RunImporterWithSemaphore(sourceName, importer, semaphore, cancellationToken);
            importTasks.Add(task);
        }

        await Task.WhenAll(importTasks);
    }

    /// <summary>
    /// Drains the ingest_queue table FIFO: deserialises each payload into a LogEntry,
    /// saves via the repository, then deletes the queue row.
    /// </summary>
    private async Task DrainIngestQueueAsync(CancellationToken cancellationToken)
    {
        const int batchSize = 200;
        var jsonOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
            var repository = scope.ServiceProvider.GetRequiredService<ILogRepository>();

            while (!cancellationToken.IsCancellationRequested)
            {
                var batch = await context.IngestQueue
                    .OrderBy(q => q.Id)
                    .Take(batchSize)
                    .ToListAsync(cancellationToken);

                if (batch.Count == 0)
                    break;

                var logEntries = new List<LogEntry>(batch.Count);
                var processedIds = new List<long>(batch.Count);

                foreach (var queueEntry in batch)
                {
                    try
                    {
                        var req = JsonSerializer.Deserialize<IngestLogRequest>(queueEntry.Payload, jsonOpts);
                        if (req == null)
                        {
                            _logger.LogWarning("Skipping ingest queue entry {Id} — null payload", queueEntry.Id);
                            processedIds.Add(queueEntry.Id);
                            continue;
                        }

                        var entry = MapIngestRequestToLogEntry(req, queueEntry.CreatedAt);
                        logEntries.Add(entry);
                        processedIds.Add(queueEntry.Id);
                    }
                    catch (JsonException ex)
                    {
                        _logger.LogWarning(ex, "Skipping ingest queue entry {Id} — invalid JSON", queueEntry.Id);
                        processedIds.Add(queueEntry.Id);
                    }
                }

                if (logEntries.Count > 0)
                {
                    await repository.AddBatchAsync(logEntries, cancellationToken);
                    _logger.LogInformation("Ingest queue: saved {Count} log entries", logEntries.Count);
                }

                context.IngestQueue.RemoveRange(
                    batch.Where(b => processedIds.Contains(b.Id)));
                await context.SaveChangesAsync(cancellationToken);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "Error draining ingest queue");
        }
    }

    private static LogEntry MapIngestRequestToLogEntry(IngestLogRequest req, DateTime queuedAt)
    {
        var level = Core.Models.LogLevel.INFO;
        if (!string.IsNullOrWhiteSpace(req.Level) &&
            Enum.TryParse<Core.Models.LogLevel>(req.Level, true, out var parsed))
        {
            level = parsed;
        }

        return new LogEntry
        {
            Id = Guid.NewGuid(),
            Timestamp = req.Timestamp?.ToUniversalTime() ?? queuedAt,
            Level = level,
            Message = req.Message,
            ComputerName = req.ComputerName ?? Environment.MachineName,
            UserName = req.UserName ?? string.Empty,
            JobName = req.JobName,
            JobStatus = req.JobStatus,
            ErrorId = req.ErrorId,
            ExceptionType = req.ExceptionType,
            StackTrace = req.StackTrace,
            FunctionName = req.FunctionName ?? string.Empty,
            Location = req.Location ?? string.Empty,
            SourceType = "api-ingest",
            SourceFile = req.Source ?? "ingest-api",
            ImportTimestamp = DateTime.UtcNow,
            ImportBatchId = $"ingest-{DateTime.UtcNow:yyyyMMddHHmmss}"
        };
    }

    private async Task RunImporterWithSemaphore(string sourceName, ILogImporter importer, 
        SemaphoreSlim semaphore, CancellationToken cancellationToken)
    {
        await semaphore.WaitAsync(cancellationToken);
        
        try
        {
            // Use retry service with exponential backoff for import operations
            await _retryService.ExecuteAsync(
                "ImportAsync",
                sourceName,
                async () =>
                {
                    var result = await importer.ImportAsync(cancellationToken);
                    
                    if (result.Success && result.ImportedEntries.Count > 0)
                    {
                        // Save to repository with retry
                        await SaveLogEntriesWithRetry(result.ImportedEntries, sourceName, cancellationToken);
                        
                        _logger.LogInformation("Import completed for {SourceName}: {Records} records in {Duration}ms", 
                            sourceName, result.RecordsProcessed, result.Duration.TotalMilliseconds);
                    }
                    else if (!result.Success)
                    {
                        _logger.LogWarning("Import failed for {SourceName}: {Error}", sourceName, result.ErrorMessage);
                        // Don't throw here - just log the warning for non-critical failures
                    }
                },
                cancellationToken);
        }
        catch (CircuitBreakerOpenException ex)
        {
            _logger.LogWarning("Skipping import for {SourceName}: {Message}", sourceName, ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running importer for source: {SourceName}", sourceName);
        }
        finally
        {
            semaphore.Release();
        }
    }
    
    private async Task SaveLogEntriesWithRetry(List<Core.Models.LogEntry> entries, string sourceName, CancellationToken cancellationToken)
    {
        await _retryService.ExecuteAsync(
            "SaveLogEntries",
            $"{sourceName}_db",
            async () => await SaveLogEntries(entries, cancellationToken),
            cancellationToken);
    }

    private async Task SaveLogEntries(List<Core.Models.LogEntry> entries, CancellationToken cancellationToken)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var repository = scope.ServiceProvider.GetRequiredService<ILogRepository>();
            var batchSize = _config.General.BatchSize;
            
            for (int i = 0; i < entries.Count; i += batchSize)
            {
                var batch = entries.Skip(i).Take(batchSize);
                await repository.AddBatchAsync(batch, cancellationToken);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving log entries to repository");
            throw;
        }
    }

    private readonly ConcurrentBag<IServiceScope> _importerScopes = new();

    private ILogImporter CreateImporter(Core.Models.Configuration.ImportSource source)
    {
        var scope = _scopeFactory.CreateScope();
        _importerScopes.Add(scope);
        var repository = scope.ServiceProvider.GetRequiredService<ILogRepository>();
        return source.Type.ToLower() switch
        {
            "file" or "json" or "xml" or "log" => new FileImporter(
                _loggerFactory.CreateLogger<FileImporter>(),
                repository,
                _config.General.BatchSize,
                _metadataService),
            "database" or "db2" or "sqlserver" or "odbc" => new DatabaseImporter(_loggerFactory.CreateLogger<DatabaseImporter>()),
            "eventlog" => CreateEventLogImporterIfSupported(),
            _ => throw new NotSupportedException($"Import source type '{source.Type}' is not supported")
        };
    }

    private ILogImporter CreateEventLogImporterIfSupported()
    {
        if (OperatingSystem.IsWindows())
        {
            return CreateEventLogImporter();
        }
        else
        {
            throw new NotSupportedException("EventLog importer is only supported on Windows");
        }
    }

    [SupportedOSPlatform("windows")]
    private EventLogImporter CreateEventLogImporter()
    {
        return new EventLogImporter(_loggerFactory.CreateLogger<EventLogImporter>());
    }

    private void PerformHealthCheck(object? state)
    {
        try
        {
            _logger.LogDebug("Performing health check...");
            
            var healthyImporters = 0;
            var failedImporters = 0;

            foreach (var (sourceName, importer) in _importers)
            {
                try
                {
                    var status = importer.GetStatus();
                    if (status.Status == Core.Models.ImportStatusType.Failed)
                    {
                        failedImporters++;
                        _logger.LogWarning("Importer {SourceName} is in failed state: {Error}", 
                            sourceName, status.ErrorMessage);
                    }
                    else
                    {
                        healthyImporters++;
                    }
                }
                catch (Exception ex)
                {
                    failedImporters++;
                    _logger.LogError(ex, "Error checking health for importer: {SourceName}", sourceName);
                }
            }

            _logger.LogDebug("Health check completed: {Healthy} healthy, {Failed} failed importers", 
                healthyImporters, failedImporters);

            // Check alert thresholds
            if (_config.Monitoring.AlertThresholds.ErrorRateMaximum > 0)
            {
                var errorRate = failedImporters / (double)_importers.Count * 100;
                if (errorRate > _config.Monitoring.AlertThresholds.ErrorRateMaximum)
                {
                    _logger.LogWarning("High error rate detected: {ErrorRate}% of importers are failing", errorRate);
                    // TODO: Send alerts
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during health check");
        }
    }

    private async void PerformCleanup(object? state)
    {
        try
        {
            _logger.LogInformation("Starting data cleanup process with level-specific retention...");
            
            using var scope = _scopeFactory.CreateScope();
            var repository = scope.ServiceProvider.GetRequiredService<ILogRepository>();
            var totalDeleted = 0;
            
            if (_config.Retention.ByLevel != null && _config.Retention.ByLevel.Count > 0)
            {
                foreach (var (levelName, retentionDays) in _config.Retention.ByLevel)
                {
                    if (Enum.TryParse<Core.Models.LogLevel>(levelName, true, out var level))
                    {
                        var cutoffDate = DateTime.UtcNow.AddDays(-retentionDays);
                        var deleted = await repository.DeleteOlderThanByLevelAsync(cutoffDate, level);
                        totalDeleted += deleted;
                        
                        if (deleted > 0)
                        {
                            _logger.LogInformation("Deleted {Count} {Level} entries older than {Days} days", 
                                deleted, level, retentionDays);
                        }
                    }
                    else
                    {
                        _logger.LogWarning("Invalid log level in retention config: {LevelName}", levelName);
                    }
                }
                
                var configuredLevels = _config.Retention.ByLevel.Keys
                    .Select(k => Enum.TryParse<Core.Models.LogLevel>(k, true, out var l) ? l : (Core.Models.LogLevel?)null)
                    .Where(l => l.HasValue)
                    .Select(l => l!.Value)
                    .ToHashSet();
                
                var defaultCutoff = DateTime.UtcNow.AddDays(-_config.Retention.DefaultDays);
                foreach (var level in Enum.GetValues<Core.Models.LogLevel>())
                {
                    if (!configuredLevels.Contains(level))
                    {
                        var deleted = await repository.DeleteOlderThanByLevelAsync(defaultCutoff, level);
                        totalDeleted += deleted;
                    }
                }
            }
            else
            {
                var cutoffDate = DateTime.UtcNow.AddDays(-_config.Retention.DefaultDays);
                totalDeleted = await repository.DeleteOlderThanAsync(cutoffDate);
            }
            
            _logger.LogInformation("Cleanup completed: deleted {Count} total log entries", totalDeleted);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during cleanup process");
        }
    }

    private async void PerformJobCorrelation(object? state)
    {
        try
        {
            _logger.LogDebug("Running job correlation cycle...");
            
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
            
            var sinceTime = _lastJobCorrelationRun.AddMinutes(-5);
            _lastJobCorrelationRun = DateTime.UtcNow;
            
            var jobEntries = await context.LogEntries
                .Where(e => e.Timestamp >= sinceTime 
                    && e.JobStatus != null 
                    && e.JobName != null)
                .OrderBy(e => e.Timestamp)
                .ToListAsync();
            
            if (jobEntries.Count > 0)
            {
                var correlationService = new JobCorrelationService(
                    context, 
                    _loggerFactory.CreateLogger<JobCorrelationService>(),
                    Options.Create(_jobTrackingConfig));
                
                await correlationService.CorrelateJobsAsync(jobEntries);
            }
            
            if (_jobTrackingConfig.AutoMarkOrphanedJobs)
            {
                var orphanedService = new JobCorrelationService(
                    context, 
                    _loggerFactory.CreateLogger<JobCorrelationService>(),
                    Options.Create(_jobTrackingConfig));
                
                await orphanedService.MarkOrphanedJobsAsync();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during job correlation process");
        }
    }

    private TimeSpan GetTimeUntilNextCleanup()
    {
        // Parse cleanup schedule (cron format: "0 2 * * *" = 2 AM daily)
        var now = DateTime.Now;
        var nextCleanup = new DateTime(now.Year, now.Month, now.Day, 2, 0, 0);
        
        if (nextCleanup <= now)
            nextCleanup = nextCleanup.AddDays(1);
            
        return nextCleanup - now;
    }

    private async Task CleanupImporters()
    {
        foreach (var (sourceName, importer) in _importers)
        {
            try
            {
                await importer.DisposeAsync();
                _logger.LogDebug("Disposed importer for: {SourceName}", sourceName);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error disposing importer for: {SourceName}", sourceName);
            }
        }
        
        _importers.Clear();
        
        while (_importerScopes.TryTake(out var scope))
        {
            scope.Dispose();
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("ImportService is stopping...");
        await base.StopAsync(cancellationToken);
        _logger.LogInformation("ImportService stopped");
    }
}
