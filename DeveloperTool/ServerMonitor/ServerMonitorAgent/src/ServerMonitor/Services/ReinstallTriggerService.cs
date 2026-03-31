using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System.Diagnostics;

namespace ServerMonitor.Services;

/// <summary>
/// Monitors for reinstall trigger files and launches the install script as a detached process.
/// This allows the service to be updated even when no user is logged in (unlike the tray app).
/// The install script runs completely independently and will stop/update/restart this service.
/// </summary>
public class ReinstallTriggerService : BackgroundService
{
    private readonly ILogger<ReinstallTriggerService> _logger;
    
    // Base path for trigger files (same as tray app)
    private const string ConfigBasePath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor";
    
    // Global reinstall trigger file
    private static readonly string GlobalTriggerPath = Path.Combine(ConfigBasePath, "ReinstallServerMonitor.txt");
    
    // Machine-specific reinstall trigger file (higher priority)
    private static readonly string MachineTriggerPath = Path.Combine(ConfigBasePath, $"ReinstallServerMonitor_{Environment.MachineName}.txt");
    
    // Check interval (same as stop file monitor)
    private const int CheckIntervalSeconds = 10;
    
    // Prevent rapid re-triggering
    private DateTime _lastTriggerTime = DateTime.MinValue;
    private const int CooldownMinutes = 5;
    
    // Track if we've already launched an install
    private bool _installLaunched;

    public ReinstallTriggerService(ILogger<ReinstallTriggerService> logger)
    {
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🔄 Reinstall trigger monitor started for {MachineName}", Environment.MachineName);
        _logger.LogInformation("   Machine-specific: {MachineFile}", MachineTriggerPath);
        _logger.LogInformation("   Global: {GlobalFile}", GlobalTriggerPath);
        _logger.LogInformation("   Check interval: {Interval} seconds", CheckIntervalSeconds);

        // Wait a bit on startup to let other services initialize
        await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(CheckIntervalSeconds), stoppingToken);

                if (_installLaunched)
                {
                    // Already launched install, just wait for service to be stopped
                    continue;
                }

                var (found, filePath, version) = CheckForTriggerFile();
                if (found && !string.IsNullOrEmpty(filePath))
                {
                    await HandleTriggerFileDetected(filePath, version);
                }
            }
            catch (OperationCanceledException)
            {
                // Normal shutdown
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking for reinstall trigger files");
            }
        }

        _logger.LogInformation("🔄 Reinstall trigger monitor stopped");
    }

    /// <summary>
    /// Checks for trigger files. Machine-specific takes priority over global.
    /// </summary>
    private (bool found, string? filePath, string? version) CheckForTriggerFile()
    {
        try
        {
            // Check machine-specific file first (higher priority)
            if (File.Exists(MachineTriggerPath))
            {
                var version = ReadVersionFromTriggerFile(MachineTriggerPath);
                _logger.LogDebug("🔄 Machine-specific trigger file found: {Path}", MachineTriggerPath);
                return (true, MachineTriggerPath, version);
            }
            
            // Check global trigger file
            if (File.Exists(GlobalTriggerPath))
            {
                var version = ReadVersionFromTriggerFile(GlobalTriggerPath);
                _logger.LogDebug("🔄 Global trigger file found: {Path}", GlobalTriggerPath);
                return (true, GlobalTriggerPath, version);
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not check trigger files (may be network issue)");
        }

        return (false, null, null);
    }

    /// <summary>
    /// Reads the Version= line from the trigger file
    /// </summary>
    private string? ReadVersionFromTriggerFile(string filePath)
    {
        try
        {
            var lines = File.ReadAllLines(filePath);
            foreach (var line in lines)
            {
                if (line.StartsWith("Version=", StringComparison.OrdinalIgnoreCase))
                {
                    return line.Substring("Version=".Length).Trim();
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not read version from trigger file");
        }
        return null;
    }

    /// <summary>
    /// Handles trigger file detection - launches install script as detached process
    /// </summary>
    private async Task HandleTriggerFileDetected(string triggerFilePath, string? version)
    {
        // Check cooldown to prevent rapid re-triggering
        if ((DateTime.Now - _lastTriggerTime).TotalMinutes < CooldownMinutes)
        {
            _logger.LogDebug("🔄 Trigger file detected but in cooldown period, skipping");
            return;
        }

        var isMachineSpecific = triggerFilePath.Equals(MachineTriggerPath, StringComparison.OrdinalIgnoreCase);
        
        _logger.LogWarning("═══════════════════════════════════════════════════════");
        _logger.LogWarning("🔄 REINSTALL TRIGGER DETECTED: {TriggerFile}", triggerFilePath);
        _logger.LogWarning("🔄 Type: {Type}", isMachineSpecific ? "Machine-specific" : "Global");
        _logger.LogWarning("🔄 Version: {Version}", version ?? "unknown");
        _logger.LogWarning("🔄 Launching install script as detached process...");
        _logger.LogWarning("═══════════════════════════════════════════════════════");

        _lastTriggerTime = DateTime.Now;

        // Check if we should update based on version comparison
        var currentVersion = GetCurrentVersion();
        if (!string.IsNullOrEmpty(version) && !string.IsNullOrEmpty(currentVersion))
        {
            if (version == currentVersion)
            {
                _logger.LogInformation("🔄 Trigger version {TriggerVersion} matches current version {CurrentVersion}, skipping install", 
                    version, currentVersion);
                return;
            }
            _logger.LogInformation("🔄 Version mismatch: trigger={TriggerVersion}, current={CurrentVersion}, proceeding with install",
                version, currentVersion);
        }

        // Launch the install script as a completely detached process
        var success = LaunchInstallScript();
        
        if (success)
        {
            _installLaunched = true;
            _logger.LogWarning("🔄 Install script launched successfully");
            _logger.LogWarning("🔄 Service will be stopped and updated by the install script");
            
            // Give the install script a moment to start
            await Task.Delay(2000);
        }
        else
        {
            _logger.LogError("🔄 Failed to launch install script");
        }
    }

    /// <summary>
    /// Gets the current version of this application (normalized to 3 parts for comparison)
    /// </summary>
    private string? GetCurrentVersion()
    {
        try
        {
            var assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            if (version == null) return null;
            
            // Return only Major.Minor.Build (3 parts) to match trigger file format
            // Assembly version is 1.0.193.0 but trigger file has Version=1.0.193
            return $"{version.Major}.{version.Minor}.{version.Build}";
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Launches the install script as a completely detached process.
    /// Uses the same pattern as the tray app - UseShellExecute = true for true independence.
    /// </summary>
    private bool LaunchInstallScript()
    {
        try
        {
            // Use full path to PowerShell 7
            const string pwsh7Path = @"C:\Program Files\PowerShell\7\pwsh.exe";
            var pwshPath = File.Exists(pwsh7Path) ? pwsh7Path : "pwsh.exe";

            // Create a PowerShell script that runs both commands
            // Explicitly import modules since service may not have user's PSModulePath
            // Same pattern as tray app - update script then run it
            var installCommands = @"
                # Ensure modules are available (add DedgeCommon to PSModulePath if needed)
                $fkModulePath = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\PowerShellModules'
                if ($env:PSModulePath -notlike ""*$fkModulePath*"") {
                    $env:PSModulePath = ""$fkModulePath;$env:PSModulePath""
                }
                Import-Module GlobalFunctions -Force -ErrorAction Stop
                Import-Module SoftwareUtils -Force -ErrorAction Stop
                 
                # Step 1: Update the install script (copies from DedgeCommon to local DedgePshApps)
                Install-OurPshApp -AppName 'ServerMonitorAgent'
                
                # Step 2: Run the updated install script (this will stop/update/restart the service)
                Start-OurPshApp -AppName 'ServerMonitorAgent'
            ";

            // Escape for command line using Base64 encoding
            var encodedCommands = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(installCommands));

            var startInfo = new ProcessStartInfo
            {
                FileName = pwshPath,
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -EncodedCommand {encodedCommands}",
                // UseShellExecute = true makes it a completely independent process
                UseShellExecute = true,
                // Don't redirect anything - process is detached
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                RedirectStandardInput = false,
                // Run hidden since this is a service (no desktop to show window)
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            _logger.LogInformation("🔄 Launching: {PwshPath} -EncodedCommand ...", pwshPath);

            var process = Process.Start(startInfo);
            if (process == null)
            {
                _logger.LogError("🔄 Failed to start PowerShell process");
                return false;
            }

            _logger.LogInformation("🔄 Install process launched with PID: {PID}", process.Id);
            
            // Don't wait for the process - it's detached
            // The install script will stop this service, update it, and restart it
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "🔄 Exception launching install script");
            return false;
        }
    }
}
