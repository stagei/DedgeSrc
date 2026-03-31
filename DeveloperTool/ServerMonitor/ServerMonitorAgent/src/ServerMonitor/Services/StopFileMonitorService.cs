using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Services;

/// <summary>
/// Monitors for a stop file and gracefully shuts down the application when detected.
/// Supports both global stop file and machine-specific stop files.
/// </summary>
public class StopFileMonitorService : BackgroundService
{
    private readonly ILogger<StopFileMonitorService> _logger;
    private readonly IHostApplicationLifetime _applicationLifetime;
    
    // Base path for stop files
    private const string ConfigBasePath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor";
    
    // Global stop file (stops ALL agents)
    private static readonly string GlobalStopFilePath = Path.Combine(ConfigBasePath, "StopServerMonitor.txt");
    
    // Machine-specific stop file (stops only this server's agent)
    private static readonly string MachineStopFilePath = Path.Combine(ConfigBasePath, $"StopServerMonitor_{Environment.MachineName}.txt");
    
    private const int CheckIntervalSeconds = 5; // Check every 5 seconds for faster response

    public StopFileMonitorService(
        ILogger<StopFileMonitorService> logger,
        IHostApplicationLifetime applicationLifetime)
    {
        _logger = logger;
        _applicationLifetime = applicationLifetime;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🛑 Stop file monitor started for {MachineName}", Environment.MachineName);
        _logger.LogInformation("   Machine-specific: {MachineFile}", MachineStopFilePath);
        _logger.LogInformation("   Global: {GlobalFile}", GlobalStopFilePath);
        _logger.LogInformation("   Check interval: {Interval} seconds", CheckIntervalSeconds);

        // Check immediately on startup
        var (found, filePath) = CheckForStopFile();
        if (found)
        {
            HandleStopFileDetected(filePath!, isStartup: true);
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(CheckIntervalSeconds), stoppingToken);

                (found, filePath) = CheckForStopFile();
                if (found)
                {
                    HandleStopFileDetected(filePath!, isStartup: false);
                    break;
                }
            }
            catch (OperationCanceledException)
            {
                // Normal shutdown
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking for stop files");
                // Continue checking even if there's an error (e.g., network issue)
            }
        }

        _logger.LogInformation("🛑 Stop file monitor stopped");
    }

    private void HandleStopFileDetected(string stopFilePath, bool isStartup)
    {
        var isMachineSpecific = stopFilePath.Equals(MachineStopFilePath, StringComparison.OrdinalIgnoreCase);
        
        _logger.LogWarning("═══════════════════════════════════════════════════════");
        _logger.LogWarning("🛑 STOP FILE DETECTED{OnStartup}: {StopFile}", 
            isStartup ? " ON STARTUP" : "", stopFilePath);
        _logger.LogWarning("🛑 Type: {Type}", isMachineSpecific ? "Machine-specific" : "Global");
        _logger.LogWarning("🛑 Initiating graceful shutdown...");
        _logger.LogWarning("═══════════════════════════════════════════════════════");
        
        // Delete the stop file after reading (machine-specific files are always deleted)
        // Global files are left for other machines to process
        if (isMachineSpecific)
        {
            DeleteStopFile(stopFilePath);
        }
        
        // Trigger graceful shutdown
        _applicationLifetime.StopApplication();
    }

    /// <summary>
    /// Checks for stop files. Machine-specific takes priority over global.
    /// </summary>
    /// <returns>Tuple of (found, filePath)</returns>
    private (bool found, string? filePath) CheckForStopFile()
    {
        try
        {
            // Check machine-specific file first (higher priority)
            if (File.Exists(MachineStopFilePath))
            {
                _logger.LogDebug("🛑 Machine-specific stop file found: {Path}", MachineStopFilePath);
                return (true, MachineStopFilePath);
            }
            
            // Check global stop file
            if (File.Exists(GlobalStopFilePath))
            {
                _logger.LogDebug("🛑 Global stop file found: {Path}", GlobalStopFilePath);
                return (true, GlobalStopFilePath);
            }
        }
        catch (Exception ex)
        {
            // Log at debug level to avoid log spam when network is unavailable
            _logger.LogDebug(ex, "Could not check stop files (may be network issue)");
        }

        return (false, null);
    }
    
    private void DeleteStopFile(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                _logger.LogInformation("🗑️ Stop file deleted: {Path}", filePath);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not delete stop file: {Path}", filePath);
        }
    }
}

