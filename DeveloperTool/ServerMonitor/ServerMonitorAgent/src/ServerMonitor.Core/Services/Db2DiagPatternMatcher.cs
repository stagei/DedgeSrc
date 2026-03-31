using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Result of pattern matching against a DB2 diagnostic entry.
/// </summary>
public class Db2PatternMatchResult
{
    /// <summary>Whether any pattern matched.</summary>
    public bool Matched { get; init; }
    
    /// <summary>The matched pattern (null if no match).</summary>
    public Db2DiagPattern? Pattern { get; init; }
    
    /// <summary>Action to take.</summary>
    public Db2PatternAction Action { get; init; } = Db2PatternAction.Keep;
    
    /// <summary>Final severity level after remapping.</summary>
    public string FinalSeverity { get; init; } = "Error";
    
    /// <summary>Formatted message (using template if available).</summary>
    public string FormattedMessage { get; init; } = string.Empty;
    
    /// <summary>Extracted SQL code if present (e.g., SQL0530N).</summary>
    public string? SqlCode { get; init; }
    
    /// <summary>Channels to suppress for this entry.</summary>
    public List<string> SuppressedChannels { get; init; } = new();
}

/// <summary>
/// Matches DB2 diagnostic entries against configured patterns.
/// </summary>
public class Db2DiagPatternMatcher
{
    private readonly ILogger<Db2DiagPatternMatcher> _logger;
    private List<Db2DiagPattern> _patterns = new();
    private bool _initialized;
    
    // Regex to extract SQL error codes like SQL0530N, SQL0911N
    private static readonly Regex SqlCodePattern = new(
        @"SQL(\d{4,5})([A-Z]?)",
        RegexOptions.Compiled);

    public Db2DiagPatternMatcher(ILogger<Db2DiagPatternMatcher> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Initialize patterns from configuration.
    /// </summary>
    public void Initialize(List<Db2DiagPattern> patterns)
    {
        _patterns = patterns
            .Where(p => p.Enabled)
            .OrderBy(p => p.Priority)
            .ToList();
        
        // Compile all regex patterns
        foreach (var pattern in _patterns)
        {
            try
            {
                pattern.CompiledRegex = new Regex(
                    pattern.Regex,
                    RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.Singleline,
                    TimeSpan.FromMilliseconds(100)); // Timeout to prevent ReDoS
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Invalid regex in pattern {PatternId}: {Regex}", 
                    pattern.PatternId, pattern.Regex);
            }
        }
        
        _initialized = true;
        _logger.LogInformation("Db2DiagPatternMatcher initialized with {Count} patterns", _patterns.Count);
    }

    /// <summary>
    /// Match an entry against all configured patterns.
    /// Returns the first matching pattern result.
    /// </summary>
    public Db2PatternMatchResult Match(Db2DiagEntry entry)
    {
        if (!_initialized || _patterns.Count == 0)
        {
            // No patterns configured - keep original behavior
            return new Db2PatternMatchResult
            {
                Matched = false,
                Action = Db2PatternAction.Keep,
                FinalSeverity = MapDb2LevelToSeverity(entry.Level),
                FormattedMessage = GetDefaultMessage(entry),
                SqlCode = ExtractSqlCode(entry)
            };
        }

        var rawBlock = entry.RawBlock ?? string.Empty;
        var sqlCode = ExtractSqlCode(entry);
        
        foreach (var pattern in _patterns)
        {
            if (pattern.CompiledRegex == null) continue;
            
            try
            {
                if (pattern.CompiledRegex.IsMatch(rawBlock))
                {
                    var finalSeverity = pattern.Action switch
                    {
                        Db2PatternAction.Remap => pattern.Level,
                        Db2PatternAction.Escalate => pattern.Level,
                        _ => MapDb2LevelToSeverity(entry.Level)
                    };
                    
                    return new Db2PatternMatchResult
                    {
                        Matched = true,
                        Pattern = pattern,
                        Action = pattern.Action,
                        FinalSeverity = finalSeverity,
                        FormattedMessage = FormatMessage(pattern.MessageTemplate, entry, sqlCode),
                        SqlCode = sqlCode,
                        SuppressedChannels = pattern.SuppressedChannels
                    };
                }
            }
            catch (RegexMatchTimeoutException)
            {
                _logger.LogWarning("Regex timeout for pattern {PatternId}", pattern.PatternId);
            }
        }
        
        // No pattern matched - keep as-is
        return new Db2PatternMatchResult
        {
            Matched = false,
            Action = Db2PatternAction.Keep,
            FinalSeverity = MapDb2LevelToSeverity(entry.Level),
            FormattedMessage = GetDefaultMessage(entry),
            SqlCode = sqlCode
        };
    }

    /// <summary>
    /// Map DB2 severity level to standard severity string.
    /// </summary>
    private static string MapDb2LevelToSeverity(string db2Level)
    {
        return db2Level.ToUpperInvariant() switch
        {
            "CRITICAL" => "Critical",
            "SEVERE" => "Critical",
            "ERROR" => "Critical",
            "WARNING" => "Warning",
            "INFO" => "Informational",
            "EVENT" => "Informational",
            _ => "Warning"
        };
    }

    /// <summary>
    /// Format message using template with placeholders.
    /// </summary>
    private string FormatMessage(string? template, Db2DiagEntry entry, string? sqlCode)
    {
        if (string.IsNullOrEmpty(template))
            return GetDefaultMessage(entry);
        
        return template
            .Replace("{Database}", entry.DatabaseName ?? "N/A")
            .Replace("{Instance}", entry.InstanceName ?? "N/A")
            .Replace("{Function}", entry.Function ?? "N/A")
            .Replace("{AuthId}", entry.AuthorizationId ?? "N/A")
            .Replace("{Hostname}", entry.HostName ?? "N/A")
            .Replace("{AppId}", entry.ApplicationId ?? "N/A")
            .Replace("{SqlCode}", sqlCode ?? "N/A")
            .Replace("{RetCode}", entry.ReturnCode ?? "N/A")
            .Replace("{Message}", entry.Message ?? "N/A");
    }

    /// <summary>
    /// Get default message for entries without custom template.
    /// </summary>
    private static string GetDefaultMessage(Db2DiagEntry entry)
    {
        var parts = new List<string>();
        
        if (!string.IsNullOrWhiteSpace(entry.InstanceName))
            parts.Add($"[{entry.InstanceName}]");
        
        if (!string.IsNullOrWhiteSpace(entry.DatabaseName))
            parts.Add($"[{entry.DatabaseName}]");
        
        parts.Add(entry.Message ?? $"DB2 {entry.Level} detected");
        
        return string.Join(" ", parts);
    }

    /// <summary>
    /// Extract SQL error code from entry (e.g., SQL0530N).
    /// </summary>
    private static string? ExtractSqlCode(Db2DiagEntry entry)
    {
        // Check raw block for SQL code
        var rawBlock = entry.RawBlock ?? string.Empty;
        var match = SqlCodePattern.Match(rawBlock);
        
        if (match.Success)
        {
            return $"SQL{match.Groups[1].Value}{match.Groups[2].Value}";
        }
        
        // Check data sections
        if (entry.DataSections != null)
        {
            foreach (var section in entry.DataSections)
            {
                if (!string.IsNullOrEmpty(section.Value))
                {
                    var dataMatch = SqlCodePattern.Match(section.Value);
                    if (dataMatch.Success)
                    {
                        return $"SQL{dataMatch.Groups[1].Value}{dataMatch.Groups[2].Value}";
                    }
                }
            }
        }
        
        return null;
    }
}
