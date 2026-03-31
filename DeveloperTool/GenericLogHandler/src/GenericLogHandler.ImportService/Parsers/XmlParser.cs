using System.Xml;
using System.Xml.XPath;
using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Configuration;

namespace GenericLogHandler.ImportService.Parsers;

/// <summary>
/// XML parser with XPath support for extracting log entries from XML files.
/// Supports streaming for large files using XmlReader.
/// </summary>
public class XmlParser
{
    private readonly ILogger _logger;
    private readonly XmlParserConfig _config;

    public XmlParser(ILogger logger, XmlParserConfig config)
    {
        _logger = logger;
        _config = config ?? throw new ArgumentNullException(nameof(config));
    }

    /// <summary>
    /// Parse XML file and extract log entries using streaming
    /// </summary>
    public async IAsyncEnumerable<LogEntry> ParseFileAsync(string filePath, string sourceName, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        if (!File.Exists(filePath))
        {
            _logger.LogWarning("XML file not found: {FilePath}", filePath);
            yield break;
        }

        var settings = new XmlReaderSettings
        {
            Async = true,
            IgnoreWhitespace = true,
            IgnoreComments = true
        };

        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 65536, true);
        using var reader = XmlReader.Create(stream, settings);

        var entryElementName = GetElementNameFromXPath(_config.RootElementXPath);
        var entryCount = 0;

        while (await reader.ReadAsync())
        {
            if (cancellationToken.IsCancellationRequested)
                yield break;

            if (reader.NodeType == XmlNodeType.Element && reader.LocalName == entryElementName)
            {
                LogEntry? entry = null;
                try
                {
                    var entryXml = await reader.ReadOuterXmlAsync();
                    entry = ParseEntryFromXml(entryXml, sourceName, filePath);
                    entryCount++;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to parse XML entry at position {Position}", entryCount);
                }

                if (entry != null)
                {
                    yield return entry;
                }
            }
        }

        _logger.LogInformation("Parsed {Count} entries from XML file: {FilePath}", entryCount, filePath);
    }

    /// <summary>
    /// Parse a single entry from XML string using XPath field mappings
    /// </summary>
    private LogEntry? ParseEntryFromXml(string xml, string sourceName, string filePath)
    {
        try
        {
            var doc = new XmlDocument();
            doc.LoadXml(xml);

            var nav = doc.CreateNavigator();
            if (nav == null) return null;

            // Create namespace manager if namespaces are defined
            var nsManager = CreateNamespaceManager(nav);

            var entry = new LogEntry
            {
                SourceType = "xml",
                SourceFile = filePath,
                ImportTimestamp = DateTime.UtcNow,
                ImportBatchId = Guid.NewGuid().ToString("N")[..8]
            };

            // Extract fields using XPath mappings
            foreach (var mapping in _config.FieldMappings)
            {
                var value = GetXPathValue(nav, mapping.Value, nsManager);
                if (string.IsNullOrEmpty(value)) continue;

                SetEntryField(entry, mapping.Key, value);
            }

            // Ensure required fields have defaults
            if (entry.Timestamp == default)
            {
                entry.Timestamp = DateTime.UtcNow;
            }

            if (string.IsNullOrEmpty(entry.ComputerName))
            {
                entry.ComputerName = Environment.MachineName;
            }

            if (string.IsNullOrEmpty(entry.Message))
            {
                entry.Message = "(no message)";
            }

            entry.GenerateConcatenatedSearchString();
            return entry;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse XML entry");
            return null;
        }
    }

    /// <summary>
    /// Get element name from XPath (last segment)
    /// </summary>
    private static string GetElementNameFromXPath(string xpath)
    {
        if (string.IsNullOrEmpty(xpath)) return "entry";
        
        var parts = xpath.Split('/');
        var lastPart = parts.LastOrDefault(p => !string.IsNullOrEmpty(p)) ?? "entry";
        
        // Remove namespace prefix if present
        if (lastPart.Contains(':'))
        {
            lastPart = lastPart.Split(':').Last();
        }
        
        // Remove predicates like [1]
        if (lastPart.Contains('['))
        {
            lastPart = lastPart.Substring(0, lastPart.IndexOf('['));
        }
        
        return lastPart;
    }

    /// <summary>
    /// Create XPath namespace manager from config
    /// </summary>
    private XmlNamespaceManager? CreateNamespaceManager(XPathNavigator nav)
    {
        if (_config.Namespaces == null || _config.Namespaces.Count == 0)
            return null;

        var nsManager = new XmlNamespaceManager(nav.NameTable);
        foreach (var ns in _config.Namespaces)
        {
            nsManager.AddNamespace(ns.Key, ns.Value);
        }
        return nsManager;
    }

    /// <summary>
    /// Get value from XPath expression
    /// </summary>
    private static string? GetXPathValue(XPathNavigator nav, string xpath, XmlNamespaceManager? nsManager)
    {
        try
        {
            var node = nsManager != null 
                ? nav.SelectSingleNode(xpath, nsManager) 
                : nav.SelectSingleNode(xpath);
            return node?.Value?.Trim();
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Set LogEntry field from field name and value
    /// </summary>
    private void SetEntryField(LogEntry entry, string fieldName, string value)
    {
        switch (fieldName.ToLowerInvariant())
        {
            case "timestamp":
            case "time":
            case "datetime":
            case "date":
                if (DateTime.TryParse(value, out var dt))
                {
                    entry.Timestamp = dt.Kind == DateTimeKind.Unspecified 
                        ? DateTime.SpecifyKind(dt, DateTimeKind.Local).ToUniversalTime()
                        : dt.ToUniversalTime();
                }
                break;
            case "level":
            case "severity":
            case "loglevel":
                entry.Level = ParseLogLevel(value);
                break;
            case "message":
            case "msg":
            case "text":
            case "description":
                entry.Message = value;
                break;
            case "computer":
            case "computername":
            case "host":
            case "hostname":
            case "machine":
                entry.ComputerName = value;
                break;
            case "user":
            case "username":
            case "userid":
                entry.UserName = value;
                break;
            case "function":
            case "functionname":
            case "method":
            case "methodname":
                entry.FunctionName = value;
                break;
            case "location":
            case "source":
            case "logger":
            case "class":
                entry.Location = value;
                break;
            case "exception":
            case "exceptiontype":
            case "error":
                entry.ExceptionType = value;
                break;
            case "stacktrace":
            case "stack":
                entry.StackTrace = value;
                break;
            case "processid":
            case "pid":
                if (int.TryParse(value, out var pid))
                    entry.ProcessId = pid;
                break;
            case "linenumber":
            case "line":
                if (int.TryParse(value, out var line))
                    entry.LineNumber = line;
                break;
            case "jobname":
            case "job":
                entry.JobName = value;
                break;
            case "jobstatus":
            case "status":
                entry.JobStatus = NormalizeJobStatus(value);
                break;
            case "alertid":
            case "alert":
                entry.AlertId = value;
                break;
            case "errorid":
                entry.ErrorId = value;
                break;
            default:
                // Add to message if unknown field
                if (!string.IsNullOrEmpty(value))
                {
                    entry.Message = string.IsNullOrEmpty(entry.Message) 
                        ? $"{fieldName}: {value}"
                        : $"{entry.Message} | {fieldName}: {value}";
                }
                break;
        }
    }

    /// <summary>
    /// Parse log level from string
    /// </summary>
    private static Core.Models.LogLevel ParseLogLevel(string value)
    {
        return value.ToUpperInvariant() switch
        {
            "TRACE" or "TRC" or "VERBOSE" => Core.Models.LogLevel.TRACE,
            "DEBUG" or "DBG" => Core.Models.LogLevel.DEBUG,
            "INFO" or "INF" or "INFORMATION" => Core.Models.LogLevel.INFO,
            "WARN" or "WRN" or "WARNING" => Core.Models.LogLevel.WARN,
            "ERROR" or "ERR" or "SEVERE" => Core.Models.LogLevel.ERROR,
            "FATAL" or "FTL" or "CRITICAL" or "CRIT" => Core.Models.LogLevel.FATAL,
            _ => Core.Models.LogLevel.INFO
        };
    }
    
    /// <summary>
    /// Normalizes job status values to consistent names
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
            _ => rawStatus
        };
    }
}

/// <summary>
/// Configuration for XML parser
/// </summary>
public class XmlParserConfig
{
    /// <summary>
    /// XPath to the root element containing log entries
    /// </summary>
    public string RootElementXPath { get; set; } = "//LogEntry";

    /// <summary>
    /// Field mappings: LogEntry field name -> XPath expression
    /// </summary>
    public Dictionary<string, string> FieldMappings { get; set; } = new()
    {
        { "Timestamp", "@time" },
        { "Level", "@level" },
        { "Message", "text()" },
        { "ComputerName", "@host" },
        { "UserName", "@user" }
    };

    /// <summary>
    /// XML namespace definitions: prefix -> URI
    /// </summary>
    public Dictionary<string, string>? Namespaces { get; set; }

    /// <summary>
    /// Maximum file size for full load (bytes). Larger files use streaming.
    /// </summary>
    public long StreamingThreshold { get; set; } = 10 * 1024 * 1024; // 10 MB
}
