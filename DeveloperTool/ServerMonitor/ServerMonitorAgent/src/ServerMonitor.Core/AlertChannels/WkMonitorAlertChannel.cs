using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.AlertChannels;

/// <summary>
/// Sends alerts to WKMonitor system by creating .MON files
/// </summary>
public class WkMonitorAlertChannel : IAlertChannel
{
    private readonly ILogger<WkMonitorAlertChannel> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;

    public string ChannelType => "WKMonitor";
    public bool IsEnabled { get; private set; }
    public AlertSeverity MinimumSeverity { get; private set; }
    
    private string ProductionPath { get; set; } = @"\\DEDGE.fk.no\erpprog\cobnt\monitor\";
    private string TestPath { get; set; } = @"\\DEDGE.fk.no\erpprog\cobtst\monitor\";
    private string ProgramName { get; set; } = "ServerMonitor";
    private bool ForceAll { get; set; } = false;

    public WkMonitorAlertChannel(
        ILogger<WkMonitorAlertChannel> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;

        UpdateConfiguration(config.CurrentValue);
        config.OnChange(UpdateConfiguration);
    }

    private void UpdateConfiguration(SurveillanceConfiguration config)
    {
        var channelConfig = config.Alerting.Channels
            .FirstOrDefault(c => c.Type.Equals("WKMonitor", StringComparison.OrdinalIgnoreCase));

        if (channelConfig != null)
        {
            IsEnabled = channelConfig.Enabled;
            MinimumSeverity = Enum.TryParse<AlertSeverity>(channelConfig.MinSeverity, out var severity)
                ? severity
                : AlertSeverity.Warning;

            if (channelConfig.Settings.TryGetValue("ProductionPath", out var prodPath))
                ProductionPath = prodPath?.ToString() ?? ProductionPath;

            if (channelConfig.Settings.TryGetValue("TestPath", out var testPath))
                TestPath = testPath?.ToString() ?? TestPath;

            if (channelConfig.Settings.TryGetValue("ProgramName", out var programName))
                ProgramName = programName?.ToString() ?? "ServerMonitor";

            if (channelConfig.Settings.TryGetValue("ForceAll", out var force))
                ForceAll = Convert.ToBoolean(force);
        }
        else
        {
            IsEnabled = false;
        }
    }

    public async Task SendAlertAsync(Alert alert, CancellationToken cancellationToken = default)
    {
        if (!IsEnabled || alert.Severity < MinimumSeverity)
        {
            return;
        }

        await Task.Run(() =>
        {
            try
            {
                var computerName = Environment.MachineName;
                var code = MapSeverityToCode(alert.Severity);
                var message = $"{alert.Category}: {alert.Message}";

                _logger.LogInformation("Sending alert to WKMonitor with {Program} - {Code} - {Message}", 
                    ProgramName, code, message);

                // Only create monitor file if code is not "0000" or ForceAll is true
                if (code != "0000" || ForceAll)
                {
                    var wkmon = $"{ProgramName} {code} {computerName}: {message}";
                    var wkmonNewMessage = $"Program {ProgramName} completed with exit code {code} on machine {computerName} and reported message: {message}";

                    if (code != "0000")
                    {
                        _logger.LogError("{Message}", wkmonNewMessage);
                    }
                    else
                    {
                        _logger.LogInformation("{Message}", wkmonNewMessage);
                    }

                    // Add timestamp to message (with milliseconds for uniqueness)
                    var timestamp = DateTime.Now.ToString("yyyyMMddHHmmss");
                    wkmon = $"{timestamp} {wkmon}";

                    // Determine path based on environment
                    var environment = GetEnvironmentFromServerName(computerName);
                    var wkmonPath = (environment == "PRD") 
                        ? ProductionPath 
                        : TestPath;

                    _logger.LogInformation("Sending alert to {Environment} monitor path: {Path}", 
                        environment, wkmonPath);

                    // Create filename with milliseconds to ensure uniqueness: [ComputerName][Timestamp][Milliseconds].MON
                    var timestampWithMs = DateTime.Now.ToString("yyyyMMddHHmmssfff");
                    var filename = $"{computerName}{timestampWithMs}.MON";
                    var fullPath = Path.Combine(wkmonPath, filename);

                    // Write monitor file
                    try
                    {
                        Directory.CreateDirectory(wkmonPath);
                        File.WriteAllText(fullPath, wkmon, System.Text.Encoding.ASCII);
                        _logger.LogInformation("Alert sent to monitor path: {Path}", fullPath);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to write monitor file to {Path}", fullPath);
                    }
                }
                else
                {
                    _logger.LogInformation("Alert not sent due to code {Code} and that it was not a forced alert", code);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error sending WKMonitor alert");
            }
        }, cancellationToken);
    }

    private string MapSeverityToCode(AlertSeverity severity)
    {
        return severity switch
        {
            AlertSeverity.Informational => "0000", // Success
            AlertSeverity.Warning => "WARN",
            AlertSeverity.Critical => "ERR1",
            _ => "ERR9"
        };
    }

    private string GetEnvironmentFromServerName(string computerName)
    {
        // Extract environment from server name pattern
        // Typical patterns: p-no1fkmprd-db (PRD), t-no1fkltst-db (TST)
        var name = computerName.ToLowerInvariant();

        if (name.StartsWith("p-") && name.Contains("prd"))
            return "PRD";
        if (name.StartsWith("p-") && name.Contains("rap"))
            return "PRD";
        if (name.StartsWith("t-") && name.Contains("tst"))
            return "TST";
        if (name.StartsWith("t-") && name.Contains("dev"))
            return "DEV";

        // Default to DEV if cannot determine
        return "DEV";
    }
}

