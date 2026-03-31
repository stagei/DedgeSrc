using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Creates reinstall trigger files for ServerMonitor agents
/// </summary>
public class ReinstallService
{
    private readonly ILogger<ReinstallService> _logger;
    private readonly DashboardConfig _config;
    private readonly VersionService _versionService;

    public ReinstallService(
        ILogger<ReinstallService> logger,
        IOptions<DashboardConfig> config,
        VersionService versionService)
    {
        _logger = logger;
        _config = config.Value;
        _versionService = versionService;
    }

    /// <summary>
    /// Creates a reinstall trigger file for a specific server
    /// </summary>
    /// <param name="serverName">Target server name (creates server-specific trigger file)</param>
    /// <param name="version">Version to install (null = auto-detect)</param>
    /// <returns>Result with success status and details</returns>
    public async Task<ReinstallResult> CreateTriggerFileAsync(string? serverName = null, string? version = null)
    {
        try
        {
            // Auto-detect version if not specified
            var targetVersion = version ?? _versionService.GetCurrentVersion();
            
            if (targetVersion == "Unknown")
            {
                return new ReinstallResult
                {
                    Success = false,
                    Message = "Could not determine agent version"
                };
            }

            // Determine trigger file path - server-specific or global
            var triggerFilePath = GetTriggerFilePath(serverName);
            
            _logger.LogInformation("Creating reinstall trigger at: {Path}", triggerFilePath);
            
            // Ensure directory exists
            var directory = Path.GetDirectoryName(triggerFilePath);
            if (!string.IsNullOrEmpty(directory))
            {
                if (!Directory.Exists(directory))
                {
                    _logger.LogInformation("Creating directory: {Directory}", directory);
                    Directory.CreateDirectory(directory);
                }
            }

            // Write trigger file with version and target server info
            var content = $"""
                # ServerMonitor Reinstall Trigger File
                # Target: {serverName ?? "ALL SERVERS"}
                Version={targetVersion}
                TargetServer={serverName ?? "*"}
                Created={DateTime.UtcNow:o}
                Source=Dashboard
                """;
            
            // Use synchronous write for UNC paths (more reliable)
            File.WriteAllText(triggerFilePath, content);
            
            // Verify the file was created
            if (!File.Exists(triggerFilePath))
            {
                _logger.LogError("File was not created at {Path} - possible permission issue", triggerFilePath);
                return new ReinstallResult
                {
                    Success = false,
                    Message = $"File write appeared to succeed but file not found at: {triggerFilePath}"
                };
            }
            
            _logger.LogInformation("✅ Created reinstall trigger for {Server} version {Version} at {Path}",
                serverName ?? "ALL", targetVersion, triggerFilePath);

            return new ReinstallResult
            {
                Success = true,
                TriggerFilePath = triggerFilePath,
                Version = targetVersion,
                ServerName = serverName,
                Message = serverName != null 
                    ? $"Reinstall trigger created for {serverName} (v{targetVersion})"
                    : $"Global reinstall trigger created (v{targetVersion})"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating reinstall trigger file for {Server} at path {Path}", 
                serverName ?? "ALL", _config.ReinstallTriggerPath);
            return new ReinstallResult
            {
                Success = false,
                Message = $"Error: {ex.Message}"
            };
        }
    }

    /// <summary>
    /// Gets the trigger file path for a specific server or the global trigger
    /// </summary>
    /// <param name="serverName">Server name, or null for global trigger</param>
    /// <returns>Full path to the trigger file</returns>
    private string GetTriggerFilePath(string? serverName)
    {
        if (string.IsNullOrEmpty(serverName))
        {
            // Global trigger file (affects all servers)
            return _config.ReinstallTriggerPath;
        }
        
        // Server-specific trigger file: ReinstallServerMonitor_SERVERNAME.txt
        var directory = Path.GetDirectoryName(_config.ReinstallTriggerPath) ?? "";
        var fileName = $"ReinstallServerMonitor_{serverName}.txt";
        return Path.Combine(directory, fileName);
    }
}

/// <summary>
/// Result of reinstall trigger creation
/// </summary>
public class ReinstallResult
{
    public bool Success { get; set; }
    public string? TriggerFilePath { get; set; }
    public string? Version { get; set; }
    public string? ServerName { get; set; }
    public string? Message { get; set; }
}
