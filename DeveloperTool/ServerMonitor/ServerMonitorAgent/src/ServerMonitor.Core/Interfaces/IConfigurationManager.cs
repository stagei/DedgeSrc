using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Core.Interfaces;

/// <summary>
/// Interface for configuration management with hot-reload support
/// </summary>
public interface IConfigurationManager
{
    /// <summary>
    /// Gets the current surveillance configuration
    /// </summary>
    SurveillanceConfiguration Configuration { get; }

    /// <summary>
    /// Event raised when configuration is reloaded
    /// </summary>
    event EventHandler<ConfigurationChangedEventArgs>? ConfigurationChanged;

    /// <summary>
    /// Validates the current configuration
    /// </summary>
    /// <returns>Validation result with any errors</returns>
    ConfigurationValidationResult Validate();

    /// <summary>
    /// Reloads configuration from source
    /// </summary>
    Task ReloadAsync(CancellationToken cancellationToken = default);
}

/// <summary>
/// Event args for configuration changed events
/// </summary>
public class ConfigurationChangedEventArgs : EventArgs
{
    public SurveillanceConfiguration NewConfiguration { get; init; } = null!;
    public SurveillanceConfiguration? OldConfiguration { get; init; }
}

/// <summary>
/// Result of configuration validation
/// </summary>
public class ConfigurationValidationResult
{
    public bool IsValid { get; set; }
    public List<string> Errors { get; set; } = new();
    public List<string> Warnings { get; set; } = new();
}

