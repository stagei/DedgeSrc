using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;
using System.Data;
using System.Data.Odbc;
using IBM.Data.DB2.Core;
using System.Diagnostics;
using Newtonsoft.Json;

namespace GenericLogHandler.ImportService.Importers;

/// <summary>
/// Imports log entries from database sources (DB2, SQL Server, etc.)
/// </summary>
public class DatabaseImporter : ILogImporter
{
    private readonly ILogger<DatabaseImporter> _logger;
    private ImportSource _source = null!;
    private ImportStatus _status = new();
    private Timer? _pollTimer;

    public string Name => "DatabaseImporter";
    public IEnumerable<string> SupportedSourceTypes => new[] { "database", "db2", "sqlserver", "odbc" };

    public DatabaseImporter(ILogger<DatabaseImporter> logger)
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

        // Setup polling timer if configured
        if (_source.Config.PollInterval > 0)
        {
            var interval = TimeSpan.FromSeconds(_source.Config.PollInterval);
            _pollTimer = new Timer(async _ => await PollDatabase(), null, interval, interval);
            _logger.LogInformation("Setup database polling for {SourceName} every {Interval} seconds", 
                source.Name, _source.Config.PollInterval);
        }

        _logger.LogInformation("Initialized DatabaseImporter for source: {SourceName}", source.Name);
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

            using var connection = CreateConnection();
            connection.Open();

            var query = BuildQuery();
            using var command = connection.CreateCommand();
            command.CommandText = query;
            command.CommandTimeout = _source.Config.Timeout;

            // Add incremental parameter if configured
            if (!string.IsNullOrEmpty(_source.Config.IncrementalColumn))
            {
                var lastValue = await GetLastIncrementalValue();
                if (lastValue != null)
                {
                    var parameter = command.CreateParameter();
                    parameter.ParameterName = "@LastValue";
                    parameter.Value = lastValue;
                    command.Parameters.Add(parameter);
                }
            }

            using var reader = command.ExecuteReader();
            var entries = new List<LogEntry>();

            while (reader.Read())
            {
                var entry = MapReaderToLogEntry(reader);
                if (entry != null)
                {
                    entries.Add(entry);
                    if (entries.Count >= 1000) // Use default batch size
                    {
                        result.ImportedEntries.AddRange(entries);
                        result.RecordsProcessed += entries.Count;
                        entries.Clear();
                    }
                }
            }

            // Add remaining entries
            if (entries.Count > 0)
            {
                result.ImportedEntries.AddRange(entries);
                result.RecordsProcessed += entries.Count;
            }

            // Update incremental value
            if (result.ImportedEntries.Count > 0 && !string.IsNullOrEmpty(_source.Config.IncrementalColumn))
            {
                var maxValue = GetMaxIncrementalValue(result.ImportedEntries);
                await SaveLastIncrementalValue(maxValue);
            }

            result.Success = true;
            _status.Status = ImportStatusType.Completed;
            _logger.LogInformation("Database import completed: {Records} records from {SourceName}", 
                result.RecordsProcessed, _source.Name);
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.ErrorMessage = ex.Message;
            _status.Status = ImportStatusType.Failed;
            _status.ErrorMessage = ex.Message;
            _logger.LogError(ex, "Error during database import for source: {SourceName}", _source.Name);
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
            using var connection = CreateConnection();
            connection.Open();
            
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT 1";
            command.CommandTimeout = 10;
            
            var result = command.ExecuteScalar();
            
            _logger.LogInformation("Database connection test successful for: {SourceName}", _source.Name);
            return Task.FromResult(true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Database connection test failed for: {SourceName}", _source.Name);
            return Task.FromResult(false);
        }
    }

    public ImportStatus GetStatus() => _status;

    public Task DisposeAsync()
    {
        _pollTimer?.Dispose();
        return Task.CompletedTask;
    }

    private async Task PollDatabase()
    {
        try
        {
            var result = await ImportAsync(CancellationToken.None);
            if (result.RecordsProcessed > 0)
            {
                _logger.LogInformation("Polling import completed: {Records} new records", result.RecordsProcessed);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during database polling for: {SourceName}", _source.Name);
        }
    }

    private IDbConnection CreateConnection()
    {
        return _source.Config.Provider?.ToLower() switch
        {
            "ibm.data.db2" or "db2" => new DB2Connection(_source.Config.ConnectionString),
            "system.data.odbc" or "odbc" => new OdbcConnection(_source.Config.ConnectionString),
            _ => new OdbcConnection(_source.Config.ConnectionString) // Default to ODBC
        };
    }

    private string BuildQuery()
    {
        var query = _source.Config.Query;
        
        if (!string.IsNullOrEmpty(_source.Config.IncrementalColumn))
        {
            // Replace placeholder with parameter
            query = query.Replace("?", "@LastValue");
        }

        return query;
    }

    private LogEntry? MapReaderToLogEntry(IDataReader reader)
    {
        try
        {
            var entry = new LogEntry
            {
                SourceFile = _source.Name,
                SourceType = "database",
                ImportTimestamp = DateTime.UtcNow
            };

            // Map database columns to LogEntry properties
            entry.Timestamp = GetReaderValue<DateTime?>(reader, "LOG_TIMESTAMP", "TIMESTAMP", "LOG_DATE") ?? DateTime.UtcNow;
            entry.Level = ParseLogLevel(GetReaderValue<string>(reader, "LOG_LEVEL", "LEVEL")) ?? Core.Models.LogLevel.INFO;
            entry.ComputerName = GetReaderValue<string>(reader, "COMPUTER_NAME", "HOST_NAME", "MACHINE_NAME") ?? Environment.MachineName;
            entry.UserName = GetReaderValue<string>(reader, "USER_NAME", "USERNAME", "USER_ID") ?? string.Empty;
            entry.Message = LogEntry.TrimMultiSpace(GetReaderValue<string>(reader, "LOG_MESSAGE", "MESSAGE", "DESCRIPTION") ?? string.Empty);
            entry.ProcessId = GetReaderValue<int?>(reader, "PROCESS_ID", "PID") ?? 0;
            entry.FunctionName = GetReaderValue<string>(reader, "FUNCTION_NAME", "PROCEDURE_NAME") ?? string.Empty;
            entry.Location = GetReaderValue<string>(reader, "LOCATION", "SOURCE_LOCATION") ?? string.Empty;
            entry.ErrorId = GetReaderValue<string>(reader, "ERROR_ID", "ERROR_CODE");
            entry.ExceptionType = GetReaderValue<string>(reader, "EXCEPTION_TYPE", "ERROR_TYPE");
            entry.StackTrace = GetReaderValue<string>(reader, "STACK_TRACE", "CALL_STACK");

            entry.GenerateConcatenatedSearchString();
            return entry;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error mapping database row to LogEntry");
            return null;
        }
    }

    private T? GetReaderValue<T>(IDataReader reader, params string[] columnNames)
    {
        foreach (var columnName in columnNames)
        {
            try
            {
                var ordinal = reader.GetOrdinal(columnName);
                if (!reader.IsDBNull(ordinal))
                {
                    var value = reader.GetValue(ordinal);
                    if (value is T typedValue)
                        return typedValue;
                    
                    // Try to convert
                    if (typeof(T) == typeof(string))
                        return (T)(object)value.ToString()!;
                    
                    return (T)Convert.ChangeType(value, typeof(T));
                }
            }
            catch (IndexOutOfRangeException)
            {
                // Column doesn't exist, try next one
                continue;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error getting value for column: {ColumnName}", columnName);
                continue;
            }
        }

        return default;
    }

    private static Core.Models.LogLevel? ParseLogLevel(string? levelString)
    {
        if (string.IsNullOrEmpty(levelString))
            return null;

        return levelString.ToUpper() switch
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

    private async Task<object?> GetLastIncrementalValue()
    {
        try
        {
            if (string.IsNullOrEmpty(_source.Config.IncrementalValueStore))
                return null;

            if (!File.Exists(_source.Config.IncrementalValueStore))
                return null;

            var json = await File.ReadAllTextAsync(_source.Config.IncrementalValueStore);
            var data = JsonConvert.DeserializeObject<Dictionary<string, object>>(json);
            
            if (data?.TryGetValue(_source.Name, out var value) == true)
                return value;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error reading incremental value for: {SourceName}", _source.Name);
        }

        return null;
    }

    private async Task SaveLastIncrementalValue(object value)
    {
        try
        {
            if (string.IsNullOrEmpty(_source.Config.IncrementalValueStore))
                return;

            var data = new Dictionary<string, object>();
            
            if (File.Exists(_source.Config.IncrementalValueStore))
            {
                var existingJson = await File.ReadAllTextAsync(_source.Config.IncrementalValueStore);
                data = JsonConvert.DeserializeObject<Dictionary<string, object>>(existingJson) ?? new();
            }

            data[_source.Name] = value;
            
            var directory = Path.GetDirectoryName(_source.Config.IncrementalValueStore);
            if (!string.IsNullOrEmpty(directory))
                Directory.CreateDirectory(directory);

            var json = JsonConvert.SerializeObject(data, Formatting.Indented);
            await File.WriteAllTextAsync(_source.Config.IncrementalValueStore, json);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving incremental value for: {SourceName}", _source.Name);
        }
    }

    private object GetMaxIncrementalValue(List<LogEntry> entries)
    {
        if (string.IsNullOrEmpty(_source.Config.IncrementalColumn))
            return DateTime.UtcNow;

        return _source.Config.IncrementalColumn.ToLower() switch
        {
            var col when col.Contains("timestamp") || col.Contains("date") || col.Contains("time") =>
                entries.Max(e => e.Timestamp),
            var col when col.Contains("id") =>
                entries.Max(e => e.ProcessId),
            _ => DateTime.UtcNow
        };
    }
}
