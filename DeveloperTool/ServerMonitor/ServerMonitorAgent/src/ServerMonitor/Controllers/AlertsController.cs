using Microsoft.AspNetCore.Mvc;
using System.ComponentModel.DataAnnotations;
using ServerMonitor.Core.Services;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Controllers;

/// <summary>
/// REST API for submitting external events from other monitoring systems
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class AlertsController : ControllerBase
{
    private readonly AlertManager _alertManager;
    private readonly GlobalSnapshotService _globalSnapshot;
    private readonly ILogger<AlertsController> _logger;

    public AlertsController(
        AlertManager alertManager,
        GlobalSnapshotService globalSnapshot,
        ILogger<AlertsController> logger)
    {
        _alertManager = alertManager;
        _globalSnapshot = globalSnapshot;
        _logger = logger;
    }

    /// <summary>
    /// Submit an external event from another monitoring system or script
    /// </summary>
    /// <param name="request">The external event to submit</param>
    /// <returns>Confirmation that the event was received</returns>
    /// <remarks>
    /// <para>This endpoint allows external systems to submit events that will be:</para>
    /// <list type="number">
    /// <item>Stored in the global snapshot with all metadata</item>
    /// <item>Processed with throttling per externalEventCode (maxOccurrences, timeWindowMinutes)</item>
    /// <item>Distributed to all enabled channels (unless suppressed)</item>
    /// </list>
    /// 
    /// <para><strong>Severity Levels:</strong></para>
    /// <list type="table">
    /// <listheader>
    /// <term>Value</term>
    /// <description>Description</description>
    /// </listheader>
    /// <item>
    /// <term>Informational</term>
    /// <description>Informational events (severity 0)</description>
    /// </item>
    /// <item>
    /// <term>Warning</term>
    /// <description>Warning-level events (severity 1) - default</description>
    /// </item>
    /// <item>
    /// <term>Critical</term>
    /// <description>Critical events requiring immediate attention (severity 2)</description>
    /// </item>
    /// </list>
    /// 
    /// <para><strong>Channel Types (for SuppressedChannels):</strong></para>
    /// <list type="bullet">
    /// <item><term>SMS</term> - SMS text messages</item>
    /// <item><term>Email</term> - Email notifications</item>
    /// <item><term>EventLog</term> - Windows Event Log entries</item>
    /// <item><term>File</term> - File-based logging</item>
    /// <item><term>WKMonitor</term> - WKMonitor integration files</item>
    /// </list>
    /// 
    /// <para><strong>Example Request:</strong></para>
    /// <code>
    /// {
    ///   "severity": "Warning",
    ///   "externalEventCode": "x00d",
    ///   "category": "Database",
    ///   "message": "A Db2 event was detected in the diagnostic log.",
    ///   "alertTimestamp": "2025-12-11T17:35:00.000Z",
    ///   "serverName": "Prod-SQL-01",
    ///   "source": "Db2DiagLog",
    ///   "metadata": {
    ///     "errorId": "x00d",
    ///     "extraDetail": "Auto-generated event from external integration"
    ///   },
    ///   "surveillance": {
    ///     "maxOccurrences": 3,
    ///     "timeWindowMinutes": 60,
    ///     "suppressedChannels": ["SMS"]
    ///   }
    /// }
    /// </code>
    /// 
    /// <para><strong>Throttling Behavior:</strong></para>
    /// <para>With maxOccurrences=3 and timeWindowMinutes=60, the alert will trigger on the 3rd occurrence within 60 minutes. 
    /// Subsequent occurrences within the same time window will be suppressed to prevent alert storms. 
    /// After the time window expires, the counter resets.</para>
    /// </remarks>
    [HttpPost]
    [ProducesResponseType(typeof(ExternalEventResponse), 201)]
    [ProducesResponseType(typeof(ProblemDetails), 400)]
    public IActionResult SubmitExternalEvent([FromBody] ExternalEventRequest request)
    {
        if (request == null)
        {
            return BadRequest(new ProblemDetails
            {
                Title = "Invalid request",
                Detail = "Request body cannot be null",
                Status = 400
            });
        }

        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return BadRequest(new ProblemDetails
            {
                Title = "Invalid request",
                Detail = "Message is required",
                Status = 400
            });
        }

        if (string.IsNullOrWhiteSpace(request.ExternalEventCode))
        {
            return BadRequest(new ProblemDetails
            {
                Title = "Invalid request",
                Detail = "ExternalEventCode is required",
                Status = 400
            });
        }

        // Parse severity
        if (!Enum.TryParse<AlertSeverity>(request.Severity, true, out var severity))
        {
            return BadRequest(new ProblemDetails
            {
                Title = "Invalid severity",
                Detail = $"Severity must be one of: {string.Join(", ", Enum.GetNames<AlertSeverity>())}",
                Status = 400
            });
        }

        // Use serverName from request, or fallback to current machine
        var serverName = !string.IsNullOrWhiteSpace(request.ServerName) 
            ? request.ServerName 
            : Environment.MachineName;

        // Use alert timestamp from request, or use current time
        var alertTimestamp = request.AlertTimestamp.HasValue 
            ? request.AlertTimestamp.Value 
            : DateTime.UtcNow;

        // Build metadata dictionary
        var metadata = new Dictionary<string, object>();
        
        // Add source to metadata if provided
        if (!string.IsNullOrWhiteSpace(request.Source))
        {
            metadata["Source"] = request.Source;
        }

        // Add any custom metadata
        if (request.Metadata != null)
        {
            foreach (var kvp in request.Metadata)
            {
                metadata[kvp.Key] = kvp.Value;
            }
        }

        // Create external event
        var externalEvent = new ExternalEvent
        {
            Id = Guid.NewGuid(),
            ExternalEventCode = request.ExternalEventCode,
            Severity = severity,
            Category = request.Category ?? "External",
            Message = request.Message,
            AlertTimestamp = alertTimestamp, // Event occurrence timestamp (from source)
            RegisteredTimestamp = DateTime.UtcNow, // When this event was registered in the system
            ServerName = serverName,
            Source = request.Source,
            Metadata = metadata,
            Surveillance = new ExternalEventSurveillance
            {
                MaxOccurrences = request.Surveillance?.MaxOccurrences ?? 1,
                TimeWindowMinutes = request.Surveillance?.TimeWindowMinutes ?? 1,
                SuppressedChannels = request.Surveillance?.SuppressedChannels ?? new List<string>()
            }
        };

        _logger.LogInformation("External event received: [{Severity}] {EventCode} - {Category}: {Message} | Alert Time: {AlertTime:yyyy-MM-dd HH:mm:ss} UTC | Registered: {RegisteredTime:yyyy-MM-dd HH:mm:ss} UTC (Source: {Source})",
            severity, externalEvent.ExternalEventCode, externalEvent.Category, externalEvent.Message, 
            externalEvent.AlertTimestamp, externalEvent.RegisteredTimestamp, request.Source ?? "Unknown");

        // Store external event in global snapshot
        _globalSnapshot.AddExternalEvent(externalEvent);

        // Process external event (throttling and alert generation)
        _alertManager.ProcessExternalEventSync(externalEvent);

        // Return simple confirmation (no distribution details)
        var response = new ExternalEventResponse
        {
            EventId = externalEvent.Id,
            ExternalEventCode = externalEvent.ExternalEventCode,
            Severity = externalEvent.Severity.ToString(),
            Category = externalEvent.Category,
            Message = externalEvent.Message,
            AlertTimestamp = externalEvent.AlertTimestamp,
            RegisteredTimestamp = externalEvent.RegisteredTimestamp,
            ServerName = externalEvent.ServerName
        };

        return CreatedAtAction(nameof(GetExternalEvent), new { id = externalEvent.Id }, response);
    }

    /// <summary>
    /// Get a specific external event by ID
    /// </summary>
    /// <param name="id">External event ID</param>
    /// <returns>The external event with full details</returns>
    [HttpGet("events/{id}")]
    [ProducesResponseType(typeof(ExternalEvent), 200)]
    [ProducesResponseType(404)]
    public IActionResult GetExternalEvent(Guid id)
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var externalEvent = snapshot.ExternalEvents.FirstOrDefault(e => e.Id == id);

        if (externalEvent == null)
        {
            return NotFound(new ProblemDetails
            {
                Title = "External event not found",
                Detail = $"No external event found with ID {id}",
                Status = 404
            });
        }

        return Ok(externalEvent);
    }

    /// <summary>
    /// Get a specific alert by ID (legacy endpoint)
    /// </summary>
    /// <param name="id">Alert ID</param>
    /// <returns>The alert with full details</returns>
    [HttpGet("{id}")]
    [ProducesResponseType(typeof(Alert), 200)]
    [ProducesResponseType(404)]
    public IActionResult GetAlert(Guid id)
    {
        var snapshot = _globalSnapshot.GetCurrentSnapshot();
        var alert = snapshot.Alerts.FirstOrDefault(a => a.Id == id);

        if (alert == null)
        {
            return NotFound(new ProblemDetails
            {
                Title = "Alert not found",
                Detail = $"No alert found with ID {id}",
                Status = 404
            });
        }

        return Ok(alert);
    }
}

/// <summary>
/// Request model for submitting external events
/// </summary>
public class ExternalEventRequest
{
    /// <summary>
    /// Alert severity level. Allowed values: Informational (0), Warning (1), Critical (2)
    /// </summary>
    /// <example>Warning</example>
    [Required(ErrorMessage = "Severity is required")]
    [RegularExpression("^(Informational|Warning|Critical)$", ErrorMessage = "Severity must be one of: Informational, Warning, Critical")]
    public string Severity { get; set; } = "Warning";

    /// <summary>
    /// External event code (unique identifier for this type of event). Used for throttling and deduplication.
    /// Examples: "x00d", "DB2_ERROR_001", "APP_CRASH"
    /// </summary>
    /// <example>x00d</example>
    [Required(ErrorMessage = "ExternalEventCode is required")]
    [StringLength(100, MinimumLength = 1, ErrorMessage = "ExternalEventCode must be between 1 and 100 characters")]
    public string ExternalEventCode { get; set; } = string.Empty;

    /// <summary>
    /// Event category. Common values: "Database", "Application", "Security", "Network", "Processor", "Memory", "Disk", "External"
    /// </summary>
    /// <example>Database</example>
    [StringLength(50, ErrorMessage = "Category must not exceed 50 characters")]
    public string? Category { get; set; }

    /// <summary>
    /// Event message describing what happened (required)
    /// </summary>
    /// <example>A Db2 event was detected in the diagnostic log.</example>
    [Required(ErrorMessage = "Message is required")]
    [StringLength(1000, MinimumLength = 1, ErrorMessage = "Message must be between 1 and 1000 characters")]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Alert timestamp - when the event actually occurred (optional, defaults to current UTC time if not provided)
    /// This is the original timestamp from the source system (e.g., log file timestamp)
    /// Format: ISO 8601 (e.g., "2025-12-11T17:35:00.000Z")
    /// Note: The system will also record a RegisteredTimestamp when the event is received
    /// </summary>
    public DateTime? AlertTimestamp { get; set; }

    /// <summary>
    /// Server name where event originated (optional, defaults to current server hostname if not provided)
    /// </summary>
    /// <example>Prod-SQL-01</example>
    [StringLength(255, ErrorMessage = "ServerName must not exceed 255 characters")]
    public string? ServerName { get; set; }

    /// <summary>
    /// Source system or script that generated the event (optional)
    /// Examples: "Db2DiagLog", "CustomScript", "MonitoringTool"
    /// </summary>
    /// <example>Db2DiagLog</example>
    [StringLength(100, ErrorMessage = "Source must not exceed 100 characters")]
    public string? Source { get; set; }

    /// <summary>
    /// Additional custom metadata key-value pairs (optional)
    /// Useful for storing event-specific context like error IDs, resource names, etc.
    /// </summary>
    public Dictionary<string, string>? Metadata { get; set; }

    /// <summary>
    /// Surveillance settings for this external event code (optional, uses defaults if not provided)
    /// </summary>
    public ExternalEventSurveillanceRequest? Surveillance { get; set; }
}

/// <summary>
/// Surveillance settings for external events. Controls throttling and channel suppression per event code.
/// </summary>
public class ExternalEventSurveillanceRequest
{
    /// <summary>
    /// Maximum occurrences before alerting within the time window.
    /// - 0 = alert on any occurrence (immediate alert)
    /// - 1 = alert on first occurrence (default)
    /// - 3 = alert when 3rd occurrence happens within time window
    /// Note: Once threshold is reached, only one alert is sent per time window (prevents alert storms)
    /// </summary>
    /// <example>3</example>
    [Range(0, 1000, ErrorMessage = "MaxOccurrences must be between 0 and 1000")]
    public int MaxOccurrences { get; set; } = 1;

    /// <summary>
    /// Time window in minutes to look back for occurrences when checking MaxOccurrences threshold.
    /// Must be between 1 and 1440 (24 hours).
    /// Example: If TimeWindowMinutes=60 and MaxOccurrences=3, alert triggers when 3 events occur within 60 minutes.
    /// Note: The time window is stored per event code for consistency (first submission sets it).
    /// </summary>
    /// <example>60</example>
    [Range(1, 1440, ErrorMessage = "TimeWindowMinutes must be between 1 and 1440 (24 hours)")]
    public int TimeWindowMinutes { get; set; } = 1;

    /// <summary>
    /// List of channel types to suppress for alerts from this event code.
    /// Allowed channel types: "SMS", "Email", "EventLog", "File", "WKMonitor"
    /// Case-insensitive. Invalid channel names are logged as warnings and ignored.
    /// Example: ["SMS", "Email"] suppresses SMS and Email, but allows EventLog, File, and WKMonitor.
    /// </summary>
    /// <example>["SMS"]</example>
    public List<string>? SuppressedChannels { get; set; }
}

/// <summary>
/// Response model for external event submission
/// </summary>
public class ExternalEventResponse
{
    /// <summary>
    /// Unique event ID
    /// </summary>
    public Guid EventId { get; set; }

    /// <summary>
    /// External event code
    /// </summary>
    public string ExternalEventCode { get; set; } = string.Empty;

    /// <summary>
    /// Event severity
    /// </summary>
    public string Severity { get; set; } = string.Empty;

    /// <summary>
    /// Event category
    /// </summary>
    public string Category { get; set; } = string.Empty;

    /// <summary>
    /// Event message
    /// </summary>
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Alert timestamp - when the event actually occurred (from source system)
    /// </summary>
    public DateTime AlertTimestamp { get; set; }

    /// <summary>
    /// Registered timestamp - when the event was registered in the ServerMonitor system
    /// Used for all logic operations (cleanup, throttling, etc.)
    /// </summary>
    public DateTime RegisteredTimestamp { get; set; }

    /// <summary>
    /// Server name where event was processed
    /// </summary>
    public string ServerName { get; set; } = string.Empty;
}
