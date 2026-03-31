using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;
using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Runtime.Versioning;

namespace GenericLogHandler.ImportService.Importers;

/// <summary>
/// Imports log entries from Windows Event Logs
/// </summary>
[SupportedOSPlatform("windows")]
public class EventLogImporter : ILogImporter
{
    private readonly ILogger<EventLogImporter> _logger;
    private ImportSource _source = null!;
    private ImportStatus _status = new();
    private Timer? _pollTimer;
    private DateTime _lastProcessedTime = DateTime.MinValue;

    public string Name => "EventLogImporter";
    public IEnumerable<string> SupportedSourceTypes => new[] { "eventlog", "windows_eventlog" };

    public EventLogImporter(ILogger<EventLogImporter> logger)
    {
        _logger = logger;
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

        _lastProcessedTime = DateTime.UtcNow.AddHours(-1); // Start from 1 hour ago

        // Setup polling timer
        if (_source.Config.PollInterval > 0)
        {
            var interval = TimeSpan.FromSeconds(_source.Config.PollInterval);
            _pollTimer = new Timer(async _ => await PollEventLogs(), null, interval, interval);
            _logger.LogInformation("Setup event log polling for {SourceName} every {Interval} seconds", 
                source.Name, _source.Config.PollInterval);
        }

        _logger.LogInformation("Initialized EventLogImporter for source: {SourceName}", source.Name);
        return Task.CompletedTask;
    }

    public async Task<ImportResult> ImportAsync(CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var result = new ImportResult();

        try
        {
            _status.Status = ImportStatusType.Processing;
            _status.LastImportTimestamp = DateTime.UtcNow;

            var entries = new List<LogEntry>();

            foreach (var logName in _source.Config.LogNames)
            {
                var logEntries = await ReadEventLog(logName, cancellationToken);
                entries.AddRange(logEntries);
            }

            result.ImportedEntries.AddRange(entries);
            result.RecordsProcessed = entries.Count;
            result.Success = true;
            _status.Status = ImportStatusType.Completed;

            // Update last processed time
            if (entries.Count > 0)
            {
                _lastProcessedTime = entries.Max(e => e.Timestamp);
            }

            _logger.LogInformation("Event log import completed: {Records} records from {SourceName}", 
                result.RecordsProcessed, _source.Name);
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.ErrorMessage = ex.Message;
            _status.Status = ImportStatusType.Failed;
            _status.ErrorMessage = ex.Message;
            _logger.LogError(ex, "Error during event log import for source: {SourceName}", _source.Name);
        }
        finally
        {
            stopwatch.Stop();
            result.Duration = stopwatch.Elapsed;
            _status.ProcessingDurationMs = stopwatch.ElapsedMilliseconds;
            _status.RecordsProcessed = result.RecordsProcessed;
            _status.RecordsFailed = result.RecordsFailed;
        }

        return result;
    }

    public Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            foreach (var logName in _source.Config.LogNames)
            {
                if (!EventLog.Exists(logName))
                {
                    _logger.LogWarning("Event log does not exist: {LogName}", logName);
                    return Task.FromResult(false);
                }
            }

            _logger.LogInformation("Event log connection test successful for: {SourceName}", _source.Name);
            return Task.FromResult(true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Event log connection test failed for: {SourceName}", _source.Name);
            return Task.FromResult(false);
        }
    }

    public ImportStatus GetStatus() => _status;

    public Task DisposeAsync()
    {
        _pollTimer?.Dispose();
        return Task.CompletedTask;
    }

    private async Task PollEventLogs()
    {
        try
        {
            var result = await ImportAsync(CancellationToken.None);
            if (result.RecordsProcessed > 0)
            {
                _logger.LogInformation("Event log polling completed: {Records} new records", result.RecordsProcessed);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during event log polling for: {SourceName}", _source.Name);
        }
    }

    private Task<List<LogEntry>> ReadEventLog(string logName, CancellationToken cancellationToken)
    {
        var entries = new List<LogEntry>();

        try
        {
            var query = BuildEventLogQuery(logName);
            using var reader = new EventLogReader(new EventLogQuery(logName, PathType.LogName, query));

            var count = 0;
            EventRecord? eventRecord;

            while ((eventRecord = reader.ReadEvent()) != null && count < _source.Config.MaxEventsPerPoll)
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                var entry = ConvertEventRecordToLogEntry(eventRecord, logName);
                if (entry != null)
                {
                    entries.Add(entry);
                    count++;
                }

                eventRecord.Dispose();
            }

            _logger.LogDebug("Read {Count} events from {LogName}", entries.Count, logName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reading from event log: {LogName}", logName);
        }

        return Task.FromResult(entries);
    }

    private string BuildEventLogQuery(string logName)
    {
        var conditions = new List<string>();

        // Time filter
        if (_lastProcessedTime > DateTime.MinValue)
        {
            var timeFilter = _lastProcessedTime.ToUniversalTime().ToString("o");
            conditions.Add($"TimeCreated[@SystemTime >= '{timeFilter}']");
        }

        // Level filter
        if (_source.Config.EventLevels.Count > 0)
        {
            var levelConditions = _source.Config.EventLevels
                .Select(level => GetEventLevelValue(level))
                .Where(value => value.HasValue)
                .Select(value => $"Level={value}")
                .ToList();

            if (levelConditions.Count > 0)
            {
                conditions.Add($"({string.Join(" or ", levelConditions)})");
            }
        }

        // Event ID filters
        if (_source.Config.EventIdFilters.Include.Count > 0)
        {
            var includeConditions = _source.Config.EventIdFilters.Include
                .Select(id => $"EventID={id}");
            conditions.Add($"({string.Join(" or ", includeConditions)})");
        }

        if (_source.Config.EventIdFilters.Exclude.Count > 0)
        {
            var excludeConditions = _source.Config.EventIdFilters.Exclude
                .Select(id => $"EventID!={id}");
            conditions.AddRange(excludeConditions);
        }

        var query = conditions.Count > 0 ? $"*[System[{string.Join(" and ", conditions)}]]" : "*";
        
        _logger.LogDebug("Event log query for {LogName}: {Query}", logName, query);
        return query;
    }

    private LogEntry? ConvertEventRecordToLogEntry(EventRecord eventRecord, string logName)
    {
        try
        {
            var message = eventRecord.FormatDescription() ?? $"Event ID: {eventRecord.Id}";
            if (eventRecord.Properties?.Count > 0)
            {
                var additionalData = string.Join("; ", 
                    eventRecord.Properties.Select((p, i) => $"Data[{i}]: {p.Value}"));
                message += $" | Additional Data: {additionalData}";
            }

            var entry = new LogEntry
            {
                Timestamp = eventRecord.TimeCreated?.ToUniversalTime() ?? DateTime.UtcNow,
                Level = MapEventLevelToLogLevel(eventRecord.Level),
                ComputerName = eventRecord.MachineName ?? Environment.MachineName,
                UserName = eventRecord.UserId?.Value ?? string.Empty,
                Message = LogEntry.TrimMultiSpace(message),
                SourceFile = logName,
                SourceType = "eventlog",
                ImportTimestamp = DateTime.UtcNow,
                ProcessId = eventRecord.ProcessId ?? 0
            };

            // Add event-specific information
            entry.ErrorId = eventRecord.Id.ToString();
            entry.Location = $"{logName}\\{eventRecord.ProviderName}";
            entry.FunctionName = eventRecord.ProviderName ?? string.Empty;

            entry.GenerateConcatenatedSearchString();
            return entry;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error converting event record to log entry. Event ID: {EventId}", 
                eventRecord.Id);
            return null;
        }
    }

    private static Core.Models.LogLevel MapEventLevelToLogLevel(byte? eventLevel)
    {
        return eventLevel switch
        {
            1 => Core.Models.LogLevel.FATAL,    // Critical
            2 => Core.Models.LogLevel.ERROR,    // Error
            3 => Core.Models.LogLevel.WARN,     // Warning
            4 => Core.Models.LogLevel.INFO,     // Information
            5 => Core.Models.LogLevel.DEBUG,    // Verbose
            _ => Core.Models.LogLevel.INFO
        };
    }

    private static int? GetEventLevelValue(string levelName)
    {
        return levelName.ToLower() switch
        {
            "critical" => 1,
            "error" => 2,
            "warning" => 3,
            "information" => 4,
            "verbose" => 5,
            _ => null
        };
    }
}
