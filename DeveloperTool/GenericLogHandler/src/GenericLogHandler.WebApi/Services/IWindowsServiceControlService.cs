namespace GenericLogHandler.WebApi.Services;

/// <summary>
/// Abstraction for querying and controlling Windows services (Import Service, Alert Agent).
/// Enables testing and clear separation of concerns. Requires Windows and appropriate permissions.
/// </summary>
public interface IWindowsServiceControlService
{
    /// <summary>
    /// Display name for the Import Service Windows service.
    /// </summary>
    string ImportServiceName { get; }

    /// <summary>
    /// Display name for the Alert Agent Windows service.
    /// </summary>
    string AlertAgentServiceName { get; }

    /// <summary>
    /// Gets the current status of a Windows service by name.
    /// </summary>
    ServiceStatusDto GetServiceStatus(string serviceName);

    /// <summary>
    /// Starts the named Windows service. Returns (Success, Message) and whether the failure is due to access denied or service not found.
    /// </summary>
    ServiceActionResult StartService(string serviceName);

    /// <summary>
    /// Stops the named Windows service. Returns (Success, Message) and whether the failure is due to access denied or service not found.
    /// </summary>
    ServiceActionResult StopService(string serviceName);
}

/// <summary>
/// Result of a start/stop action with optional HTTP status hint for the API layer.
/// </summary>
public class ServiceActionResult
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    /// <summary>
    /// True when the failure is due to insufficient permissions (e.g. access denied).
    /// </summary>
    public bool IsAccessDenied { get; set; }
    /// <summary>
    /// True when the service was not found (e.g. not installed).
    /// </summary>
    public bool IsNotFound { get; set; }
    /// <summary>
    /// True when the operation is not supported (e.g. non-Windows).
    /// </summary>
    public bool IsUnsupported { get; set; }
}
