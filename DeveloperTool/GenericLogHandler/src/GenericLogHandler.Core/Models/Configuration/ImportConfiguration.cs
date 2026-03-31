using Newtonsoft.Json;
using System.ComponentModel.DataAnnotations;

namespace GenericLogHandler.Core.Models.Configuration;

/// <summary>
/// Main configuration structure for the Generic Log Handler
/// </summary>
public class ImportConfiguration
{
    [Required]
    public string Version { get; set; } = "1.0";

    public ConfigurationMetadata Metadata { get; set; } = new();

    [Required]
    public GeneralSettings General { get; set; } = new();

    [Required]
    public DatabaseSettings Database { get; set; } = new();

    [Required]
    public RetentionSettings Retention { get; set; } = new();

    [Required]
    public List<ImportSource> ImportSources { get; set; } = new();

    public Dictionary<string, FieldMapping> FieldMappings { get; set; } = new();

    public TransformationRules TransformationRules { get; set; } = new();

    public ErrorHandlingSettings ErrorHandling { get; set; } = new();

    public MonitoringSettings Monitoring { get; set; } = new();

    public WebInterfaceSettings WebInterface { get; set; } = new();
}

/// <summary>
/// Configuration metadata
/// </summary>
public class ConfigurationMetadata
{
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public DateTime LastUpdated { get; set; } = DateTime.UtcNow;
    public string Author { get; set; } = string.Empty;
}

/// <summary>
/// General service settings
/// </summary>
public class GeneralSettings
{
    [Required]
    public string ServiceName { get; set; } = "GenericLogHandler";

    public string LogLevel { get; set; } = "INFO";
    public int MaxConcurrentImports { get; set; } = 4;
    public int BatchSize { get; set; } = 1000;
    public bool RunOnce { get; set; } = false;
    public int RetryAttempts { get; set; } = 3;
    public int RetryDelaySeconds { get; set; } = 5;
    public int HealthCheckInterval { get; set; } = 60;
    
    /// <summary>
    /// Advanced retry settings with exponential backoff
    /// </summary>
    public RetryPolicySettings RetryPolicy { get; set; } = new();
}

/// <summary>
/// Advanced retry policy settings with exponential backoff
/// </summary>
public class RetryPolicySettings
{
    /// <summary>
    /// Maximum number of retry attempts (0 = no retries)
    /// </summary>
    public int MaxRetries { get; set; } = 3;
    
    /// <summary>
    /// Initial delay in milliseconds before first retry
    /// </summary>
    public int InitialDelayMs { get; set; } = 1000;
    
    /// <summary>
    /// Maximum delay in milliseconds between retries (caps exponential growth)
    /// </summary>
    public int MaxDelayMs { get; set; } = 30000;
    
    /// <summary>
    /// Multiplier for exponential backoff (e.g., 2.0 doubles delay each retry)
    /// </summary>
    public double BackoffMultiplier { get; set; } = 2.0;
    
    /// <summary>
    /// Add random jitter to avoid thundering herd (0.0 to 1.0)
    /// </summary>
    public double JitterFactor { get; set; } = 0.1;
    
    /// <summary>
    /// Enable circuit breaker for sources with repeated failures
    /// </summary>
    public bool EnableCircuitBreaker { get; set; } = true;
    
    /// <summary>
    /// Number of consecutive failures before circuit opens
    /// </summary>
    public int CircuitBreakerThreshold { get; set; } = 5;
    
    /// <summary>
    /// Time in seconds to keep circuit open before retrying
    /// </summary>
    public int CircuitBreakerResetSeconds { get; set; } = 300;
}

/// <summary>
/// Database connection settings
/// </summary>
public class DatabaseSettings
{
    [Required]
    public string Type { get; set; } = "postgresql";

    [Required]
    public string ConnectionString { get; set; } = string.Empty;

    [Required]
    public string DatabaseName { get; set; } = "logs";

    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public int ConnectionTimeout { get; set; } = 30;
    public int CommandTimeout { get; set; } = 300;
    public int MaxConnections { get; set; } = 10;
    public int BatchInsertSize { get; set; } = 1000;
    public bool EnableCompression { get; set; } = true;
}

/// <summary>
/// Data retention settings
/// </summary>
public class RetentionSettings
{
    public int DefaultDays { get; set; } = 90;
    public Dictionary<string, int> ByLevel { get; set; } = new();
    public string CleanupSchedule { get; set; } = "0 2 * * *";
    public int CleanupBatchSize { get; set; } = 10000;
    public bool ArchiveBeforeDelete { get; set; } = true;
    public string ArchiveLocation { get; set; } = string.Empty;
    public string ArchiveCompression { get; set; } = "gzip";
}

/// <summary>
/// Import source configuration
/// </summary>
public class ImportSource
{
    [Required]
    public string Name { get; set; } = string.Empty;

    [Required]
    public string Type { get; set; } = string.Empty;

    public bool Enabled { get; set; } = true;
    public int Priority { get; set; } = 1;

    [Required]
    public ImportSourceConfig Config { get; set; } = new();
}

/// <summary>
/// Import source specific configuration
/// </summary>
public class ImportSourceConfig
{
    // File-based imports
    public string Path { get; set; } = string.Empty;
    public string FilePattern { get; set; } = "*";
    public string Format { get; set; } = string.Empty;
    public bool WatchDirectory { get; set; } = false;
    public string Encoding { get; set; } = "utf-8";
    public int PollInterval { get; set; } = 30;
    public bool ProcessExistingFiles { get; set; } = false;
    public bool MoveProcessedFiles { get; set; } = false;
    public string ProcessedFilesLocation { get; set; } = string.Empty;
    public string ErrorFilesLocation { get; set; } = string.Empty;
    
    /// <summary>
    /// Path to quarantine folder for files with high error rates.
    /// If empty, uses a "Quarantine" subfolder in the source directory.
    /// </summary>
    public string QuarantinePath { get; set; } = string.Empty;
    
    /// <summary>
    /// Error rate threshold (0-100) above which files are quarantined.
    /// Default is 50% - files with more than 50% failed records are quarantined.
    /// </summary>
    public double QuarantineErrorRateThreshold { get; set; } = 50.0;
    
    /// <summary>
    /// If true, files are continuously appended to (like log files).
    /// The importer will track the file creation date and last processed line,
    /// resuming from where it left off on subsequent runs.
    /// When file creation date changes, it's treated as a new/rotated file and processing starts from line 0.
    /// </summary>
    public bool IsAppendOnly { get; set; } = false;
    
    /// <summary>
    /// Local directory to copy source files into before reading, for business-critical
    /// files on network shares. The importer copies the original file here, reads from
    /// the local copy, and tracks line position relative to the copy. The original file's
    /// creation date is still used for rotation detection.
    /// Leave empty to read directly from the source path.
    /// </summary>
    public string CopyToLocalPath { get; set; } = string.Empty;
    
    /// <summary>
    /// Maximum age in days for files to be processed.
    /// Files older than this will be skipped.
    /// Default is 30 days. Set to 0 or null to process all files regardless of age.
    /// </summary>
    public int? MaxFileAgeDays { get; set; } = 30;

    // Parser configuration for line-by-line parsing
    public ParserConfig? Parser { get; set; }

    // JSON specific
    public string JsonRootPath { get; set; } = "$";
    public bool FlattenNestedObjects { get; set; } = true;
    public int MaxDepth { get; set; } = 5;

    // XML specific
    public Dictionary<string, string> XmlNamespaces { get; set; } = new();
    public string RootElementXPath { get; set; } = string.Empty;

    // Log file specific
    public int SkipHeaderLines { get; set; } = 0;
    public int MaxFilesPerRun { get; set; } = 0;

    /// <summary>
    /// Maximum file size in MB for whole-file read of JSON/XML single-document files.
    /// Larger files are skipped to avoid OOM. Default is 100 when not set. Set to 0 for no limit (use with caution).
    /// </summary>
    public int? MaxFullReadMB { get; set; }

    // Database specific
    public string Provider { get; set; } = string.Empty;
    public string ConnectionString { get; set; } = string.Empty;
    public string Query { get; set; } = string.Empty;
    public string IncrementalColumn { get; set; } = string.Empty;
    public string IncrementalValueStore { get; set; } = string.Empty;
    public int Timeout { get; set; } = 120;

    // Event log specific
    public List<string> LogNames { get; set; } = new();
    public List<string> EventLevels { get; set; } = new();
    public EventIdFilters EventIdFilters { get; set; } = new();
    public int MaxEventsPerPoll { get; set; } = 1000;
}

/// <summary>
/// Parser configuration for line-by-line log parsing
/// </summary>
public class ParserConfig
{
    /// <summary>
    /// Name of the parser configuration (e.g. "powershell_pipe")
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Delimiter for delimited formats (e.g. "|", ",", "\t")
    /// </summary>
    public string Delimiter { get; set; } = string.Empty;

    /// <summary>
    /// Regex pattern with named capture groups for complex log formats
    /// </summary>
    public string Pattern { get; set; } = string.Empty;

    /// <summary>
    /// Field mappings from column index or regex group to LogEntry property
    /// Key is column index (0-based) or regex group name
    /// </summary>
    public Dictionary<string, FieldExtractor> FieldMappings { get; set; } = new();

    /// <summary>
    /// Regex extractors to run on the Message field after parsing
    /// </summary>
    public List<MessageExtractor> MessageExtractors { get; set; } = new();
}

/// <summary>
/// Defines how to extract and transform a field from source data
/// </summary>
public class FieldExtractor
{
    /// <summary>
    /// Target property name on LogEntry (e.g. "Timestamp", "ComputerName", "Message")
    /// </summary>
    public string TargetColumn { get; set; } = string.Empty;

    /// <summary>
    /// Optional transformation to apply: "uppercase", "lowercase", "trim", "parseDate"
    /// </summary>
    public string Transform { get; set; } = string.Empty;

    /// <summary>
    /// Date format string for timestamp parsing (e.g. "yyyy-MM-dd HH:mm:ss")
    /// </summary>
    public string DateFormat { get; set; } = string.Empty;

    /// <summary>
    /// Default value if source field is empty or missing
    /// </summary>
    public string DefaultValue { get; set; } = string.Empty;
}

/// <summary>
/// Dynamic regex extractor to extract business identifiers from message content
/// </summary>
public class MessageExtractor
{
    /// <summary>
    /// Name of the extractor (e.g. "ordrenr_extractor")
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Regex pattern with named capture group (e.g. "(?:ordrenr|ordrenummer)[:\\s=]+(?<value>\\d+)")
    /// </summary>
    public string Pattern { get; set; } = string.Empty;

    /// <summary>
    /// Target property name on LogEntry (e.g. "Ordrenr", "Avdnr", "AlertId")
    /// </summary>
    public string TargetColumn { get; set; } = string.Empty;

    /// <summary>
    /// Name of the capture group to extract (default: "value")
    /// </summary>
    public string CaptureGroup { get; set; } = "value";

    /// <summary>
    /// If true, use case-insensitive matching
    /// </summary>
    public bool IgnoreCase { get; set; } = true;
}

/// <summary>
/// Event ID filtering configuration
/// </summary>
public class EventIdFilters
{
    public List<int> Include { get; set; } = new();
    public List<int> Exclude { get; set; } = new();
}

/// <summary>
/// Field mapping configuration for a parser
/// </summary>
public class FieldMapping
{
    public Dictionary<string, FieldMappingRule> Fields { get; set; } = new();
}

/// <summary>
/// Individual field mapping rule
/// </summary>
public class FieldMappingRule
{
    public string SourceField { get; set; } = string.Empty;
    public string SourceExpression { get; set; } = string.Empty;
    public string SourceXPath { get; set; } = string.Empty;
    public string DataType { get; set; } = "string";
    public string Format { get; set; } = string.Empty;
    public bool Required { get; set; } = false;
    public object? DefaultValue { get; set; }
    public Dictionary<string, string> ValueMapping { get; set; } = new();
    public int MaxLength { get; set; } = 0;
    public string Transform { get; set; } = string.Empty;
    public bool Trim { get; set; } = false;
    public bool Index { get; set; } = false;
}

/// <summary>
/// Data transformation rules
/// </summary>
public class TransformationRules
{
    public GlobalTransformations Global { get; set; } = new();
    public Dictionary<string, FieldTransformation> Fields { get; set; } = new();
}

/// <summary>
/// Global transformation settings
/// </summary>
public class GlobalTransformations
{
    public bool NormalizeWhitespace { get; set; } = true;
    public bool TrimStrings { get; set; } = true;
    public bool ConvertEmptyToNull { get; set; } = true;
    public bool ValidateTimestamps { get; set; } = true;
    public string DefaultTimezone { get; set; } = "UTC";
}

/// <summary>
/// Field-specific transformation settings
/// </summary>
public class FieldTransformation
{
    public bool Uppercase { get; set; } = false;
    public bool RemoveDomainSuffix { get; set; } = false;
    public int MaxLength { get; set; } = 0;
    public bool EscapeSpecialChars { get; set; } = false;
    public bool NormalizeLineEndings { get; set; } = false;
    public List<string> ValidValues { get; set; } = new();
}

/// <summary>
/// Error handling configuration
/// </summary>
public class ErrorHandlingSettings
{
    public string OnParseError { get; set; } = "skip_and_log";
    public string OnValidationError { get; set; } = "skip_and_log";
    public string OnDatabaseError { get; set; } = "retry_and_log";
    public string ErrorLogPath { get; set; } = string.Empty;
    public int MaxErrorsPerSource { get; set; } = 100;
    public double MaxErrorRatePercent { get; set; } = 5.0;
    public bool QuarantineBadFiles { get; set; } = true;
    public string QuarantinePath { get; set; } = string.Empty;
}

/// <summary>
/// Monitoring and alerting configuration
/// </summary>
public class MonitoringSettings
{
    public bool EnablePerformanceCounters { get; set; } = true;
    public int MetricsCollectionInterval { get; set; } = 60;
    public int MetricsRetentionDays { get; set; } = 30;
    public AlertThresholds AlertThresholds { get; set; } = new();
    public NotificationSettings Notifications { get; set; } = new();
}

/// <summary>
/// Alert threshold configuration
/// </summary>
public class AlertThresholds
{
    public int ImportRateMinimum { get; set; } = 100;
    public double ErrorRateMaximum { get; set; } = 5.0;
    public int QueueSizeMaximum { get; set; } = 10000;
    public double MemoryUsageMaximum { get; set; } = 80.0;
    public double DiskSpaceMinimum { get; set; } = 10.0;
}

/// <summary>
/// Notification settings
/// </summary>
public class NotificationSettings
{
    public EmailNotificationSettings Email { get; set; } = new();
    public WindowsEventSettings WindowsEvents { get; set; } = new();
}

/// <summary>
/// Email notification settings
/// </summary>
public class EmailNotificationSettings
{
    public bool Enabled { get; set; } = false;
    public string SmtpServer { get; set; } = string.Empty;
    public List<string> Recipients { get; set; } = new();
}

/// <summary>
/// Windows event log settings
/// </summary>
public class WindowsEventSettings
{
    public bool Enabled { get; set; } = true;
    public string SourceName { get; set; } = "GenericLogHandler";
}

/// <summary>
/// Web interface configuration
/// </summary>
public class WebInterfaceSettings
{
    public bool Enabled { get; set; } = true;
    public int Port { get; set; } = 8080;
    public bool SslEnabled { get; set; } = true;
    public string SslCertificatePath { get; set; } = string.Empty;
    public AuthenticationSettings Authentication { get; set; } = new();
    public SessionSettings Session { get; set; } = new();
    public CorsSettings Cors { get; set; } = new();
}

/// <summary>
/// Authentication configuration
/// </summary>
public class AuthenticationSettings
{
    public string Type { get; set; } = "windows";
    public bool RequireAuthentication { get; set; } = true;
    public List<string> AdminGroups { get; set; } = new();
    public List<string> UserGroups { get; set; } = new();
}

/// <summary>
/// Session configuration
/// </summary>
public class SessionSettings
{
    public int TimeoutMinutes { get; set; } = 30;
    public bool SlidingExpiration { get; set; } = true;
}

/// <summary>
/// CORS configuration
/// </summary>
public class CorsSettings
{
    public bool Enabled { get; set; } = false;
    public List<string> AllowedOrigins { get; set; } = new();
}
