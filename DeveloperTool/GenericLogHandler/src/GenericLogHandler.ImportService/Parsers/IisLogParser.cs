using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Models;

namespace GenericLogHandler.ImportService.Parsers;

/// <summary>
/// Parser for IIS W3C Extended Log Format files.
/// Handles both standard IIS logs and custom field configurations.
/// </summary>
public class IisLogParser
{
    private readonly ILogger _logger;
    private readonly IisLogParserConfig _config;
    private string[]? _fieldNames;
    private readonly Dictionary<string, int> _fieldIndexMap = new();

    public IisLogParser(ILogger logger, IisLogParserConfig? config = null)
    {
        _logger = logger;
        _config = config ?? new IisLogParserConfig();
    }

    /// <summary>
    /// Parse IIS log file line by line
    /// </summary>
    public async IAsyncEnumerable<LogEntry> ParseFileAsync(string filePath, string sourceName, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        if (!File.Exists(filePath))
        {
            _logger.LogWarning("IIS log file not found: {FilePath}", filePath);
            yield break;
        }

        var entryCount = 0;
        var errorCount = 0;

        using var reader = new StreamReader(filePath, System.Text.Encoding.UTF8, detectEncodingFromByteOrderMarks: true, bufferSize: 65536);
        string? line;
        var lineNumber = 0;

        while ((line = await reader.ReadLineAsync(cancellationToken)) != null)
        {
            lineNumber++;
            if (cancellationToken.IsCancellationRequested) yield break;

            // Skip empty lines
            if (string.IsNullOrWhiteSpace(line)) continue;

            // Handle directives
            if (line.StartsWith('#'))
            {
                ProcessDirective(line);
                continue;
            }

            // Parse data line
            LogEntry? entry = null;
            try
            {
                entry = ParseLine(line, sourceName, filePath, lineNumber);
                if (entry != null) entryCount++;
            }
            catch (Exception ex)
            {
                errorCount++;
                if (errorCount <= 10)
                {
                    _logger.LogWarning(ex, "Failed to parse IIS log line {LineNumber} in {FilePath}", lineNumber, filePath);
                }
            }

            if (entry != null)
            {
                yield return entry;
            }
        }

        _logger.LogInformation("Parsed {Count} entries ({Errors} errors) from IIS log: {FilePath}", entryCount, errorCount, filePath);
    }

    /// <summary>
    /// Process W3C directive lines (#Fields:, #Date:, etc.)
    /// </summary>
    private void ProcessDirective(string line)
    {
        if (line.StartsWith("#Fields:", StringComparison.OrdinalIgnoreCase))
        {
            // Parse field names from #Fields: directive
            var fieldsPart = line.Substring("#Fields:".Length).Trim();
            _fieldNames = fieldsPart.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            
            _fieldIndexMap.Clear();
            for (int i = 0; i < _fieldNames.Length; i++)
            {
                _fieldIndexMap[_fieldNames[i].ToLowerInvariant()] = i;
            }
            
            _logger.LogDebug("IIS log fields: {Fields}", string.Join(", ", _fieldNames));
        }
    }

    /// <summary>
    /// Parse a single data line
    /// </summary>
    private LogEntry? ParseLine(string line, string sourceName, string filePath, int lineNumber)
    {
        // Use default fields if no #Fields directive was found
        _fieldNames ??= IisLogParserConfig.DefaultFields;
        
        var values = line.Split(' ');
        if (values.Length < 2) return null;

        var entry = new LogEntry
        {
            SourceType = "iis",
            SourceFile = filePath,
            LineNumber = lineNumber,
            ImportTimestamp = DateTime.UtcNow,
            ImportBatchId = Guid.NewGuid().ToString("N")[..8]
        };

        // Parse timestamp
        entry.Timestamp = ParseTimestamp(values);

        // Map IIS fields to LogEntry properties
        entry.ComputerName = GetFieldValue(values, "s-computername") ?? GetFieldValue(values, "s-sitename") ?? Environment.MachineName;
        entry.UserName = GetFieldValue(values, "cs-username") ?? "-";
        
        // Build message from URI and query
        var uriStem = GetFieldValue(values, "cs-uri-stem") ?? "-";
        var uriQuery = GetFieldValue(values, "cs-uri-query") ?? "";
        var method = GetFieldValue(values, "cs-method") ?? "GET";
        
        entry.Message = BuildMessage(method, uriStem, uriQuery, values);
        
        // Determine log level from status code
        entry.Level = DetermineLogLevel(values);
        
        // Additional fields
        var clientIp = GetFieldValue(values, "c-ip");
        if (!string.IsNullOrEmpty(clientIp) && clientIp != "-")
        {
            entry.Location = $"Client: {clientIp}";
        }

        // Extract process ID if available
        var processId = GetFieldValue(values, "s-process-id");
        if (int.TryParse(processId, out var pid))
        {
            entry.ProcessId = pid;
        }

        // Set function name to the HTTP method
        entry.FunctionName = method;

        entry.GenerateConcatenatedSearchString();
        return entry;
    }

    /// <summary>
    /// Parse timestamp from date and time fields
    /// </summary>
    private DateTime ParseTimestamp(string[] values)
    {
        var dateStr = GetFieldValue(values, "date");
        var timeStr = GetFieldValue(values, "time");

        if (!string.IsNullOrEmpty(dateStr) && !string.IsNullOrEmpty(timeStr))
        {
            if (DateTime.TryParse($"{dateStr} {timeStr}", out var dt))
            {
                return DateTime.SpecifyKind(dt, DateTimeKind.Utc);
            }
        }

        return DateTime.UtcNow;
    }

    /// <summary>
    /// Build message from IIS fields
    /// </summary>
    private string BuildMessage(string method, string uriStem, string uriQuery, string[] values)
    {
        var status = GetFieldValue(values, "sc-status") ?? "0";
        var subStatus = GetFieldValue(values, "sc-substatus") ?? "0";
        var win32Status = GetFieldValue(values, "sc-win32-status") ?? "0";
        var timeTaken = GetFieldValue(values, "time-taken") ?? "0";
        var bytesReceived = GetFieldValue(values, "cs-bytes") ?? "0";
        var bytesSent = GetFieldValue(values, "sc-bytes") ?? "0";

        var query = !string.IsNullOrEmpty(uriQuery) && uriQuery != "-" ? $"?{uriQuery}" : "";
        
        return $"{method} {uriStem}{query} - Status: {status}.{subStatus} (Win32: {win32Status}) - {timeTaken}ms - Recv: {bytesReceived}B Sent: {bytesSent}B";
    }

    /// <summary>
    /// Determine log level from HTTP status codes
    /// </summary>
    private Core.Models.LogLevel DetermineLogLevel(string[] values)
    {
        var statusStr = GetFieldValue(values, "sc-status");
        if (!int.TryParse(statusStr, out var status))
        {
            return Core.Models.LogLevel.INFO;
        }

        return status switch
        {
            >= 500 => Core.Models.LogLevel.ERROR,  // 5xx = Server error
            >= 400 => Core.Models.LogLevel.WARN,   // 4xx = Client error
            >= 300 => Core.Models.LogLevel.INFO,   // 3xx = Redirect
            >= 200 => Core.Models.LogLevel.INFO,   // 2xx = Success
            _ => Core.Models.LogLevel.DEBUG
        };
    }

    /// <summary>
    /// Get field value by field name
    /// </summary>
    private string? GetFieldValue(string[] values, string fieldName)
    {
        if (_fieldIndexMap.TryGetValue(fieldName.ToLowerInvariant(), out var index))
        {
            if (index < values.Length)
            {
                var value = values[index];
                return value == "-" ? null : value;
            }
        }
        return null;
    }
}

/// <summary>
/// Configuration for IIS log parser
/// </summary>
public class IisLogParserConfig
{
    /// <summary>
    /// Default W3C extended log format fields
    /// </summary>
    public static readonly string[] DefaultFields = new[]
    {
        "date", "time", "s-ip", "cs-method", "cs-uri-stem", "cs-uri-query",
        "s-port", "cs-username", "c-ip", "cs(User-Agent)", "cs(Referer)",
        "sc-status", "sc-substatus", "sc-win32-status", "time-taken"
    };

    /// <summary>
    /// Minimum HTTP status code to import (0 = all)
    /// </summary>
    public int MinStatusCode { get; set; } = 0;

    /// <summary>
    /// Only import entries with these status codes (empty = all)
    /// </summary>
    public List<int>? FilterStatusCodes { get; set; }

    /// <summary>
    /// Exclude paths matching these patterns
    /// </summary>
    public List<string>? ExcludePathPatterns { get; set; }
}
