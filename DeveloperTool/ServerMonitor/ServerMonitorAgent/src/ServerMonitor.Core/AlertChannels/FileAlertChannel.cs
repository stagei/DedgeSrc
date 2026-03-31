using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.AlertChannels;

/// <summary>
/// Sends alerts to a file log
/// </summary>
public class FileAlertChannel : IAlertChannel
{
    private readonly ILogger<FileAlertChannel> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly SemaphoreSlim _fileLock = new(1, 1);

    public string ChannelType => "File";
    public bool IsEnabled { get; private set; }
    public AlertSeverity MinimumSeverity { get; private set; }
    private string LogPath { get; set; } = string.Empty;

    public FileAlertChannel(
        ILogger<FileAlertChannel> logger,
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
            .FirstOrDefault(c => c.Type.Equals("File", StringComparison.OrdinalIgnoreCase));

        if (channelConfig != null)
        {
            IsEnabled = channelConfig.Enabled;
            MinimumSeverity = Enum.TryParse<AlertSeverity>(channelConfig.MinSeverity, out var severity)
                ? severity
                : AlertSeverity.Warning;

            if (channelConfig.Settings.TryGetValue("LogPath", out var logPath))
            {
                LogPath = logPath?.ToString() ?? string.Empty;
            }
        }
        else
        {
            IsEnabled = false;
            MinimumSeverity = AlertSeverity.Warning;
        }
    }

    public async Task SendAlertAsync(Alert alert, CancellationToken cancellationToken = default)
    {
        try
        {
            if (!IsEnabled || string.IsNullOrEmpty(LogPath))
            {
                return;
            }

            var logPath = GenerateLogPath();
            var logDir = Path.GetDirectoryName(logPath);
            if (!string.IsNullOrEmpty(logDir) && !Directory.Exists(logDir))
            {
                Directory.CreateDirectory(logDir);
            }

            var logEntry = FormatLogEntry(alert);

            await _fileLock.WaitAsync(cancellationToken);
            try
            {
                await File.AppendAllTextAsync(logPath, logEntry + Environment.NewLine, cancellationToken);
            }
            finally
            {
                _fileLock.Release();
            }

            _logger.LogDebug("Alert written to file {LogPath}: {Message}", logPath, alert.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write alert to file");
            throw;
        }
    }

    private string GenerateLogPath()
    {
        var path = LogPath
            .Replace("{Date}", DateTime.Now.ToString("yyyyMMdd"))
            .Replace("{ServerName}", Environment.MachineName);

        return Environment.ExpandEnvironmentVariables(path);
    }

    private string FormatLogEntry(Alert alert)
    {
        var timestamp = alert.Timestamp.ToString("yyyy-MM-dd HH:mm:ss");
        var severity = alert.Severity.ToString().ToUpper();
        var entry = $"[{timestamp}] [{severity}] [{alert.Category}] [{alert.Id}] {alert.Message}";
        
        if (!string.IsNullOrEmpty(alert.Details))
        {
            entry += $" | Details: {alert.Details}";
        }

        return entry;
    }
}

