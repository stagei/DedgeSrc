using System.Net;
using System.Net.Mail;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.AlertChannels;

/// <summary>
/// Sends alerts via email (SMTP)
/// </summary>
public class EmailAlertChannel : IAlertChannel
{
    private readonly ILogger<EmailAlertChannel> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly NotificationRecipientService? _recipientService;

    public string ChannelType => "Email";
    public bool IsEnabled { get; private set; }
    public AlertSeverity MinimumSeverity { get; private set; }

    private string SmtpServer { get; set; } = string.Empty;
    private int SmtpPort { get; set; } = 25;
    private string From { get; set; } = string.Empty;
    private List<string> To { get; set; } = new();
    private string? Username { get; set; }
    private string? Password { get; set; }
    private bool EnableSsl { get; set; } = true;

    public EmailAlertChannel(
        ILogger<EmailAlertChannel> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        NotificationRecipientService? recipientService = null)
    {
        _logger = logger;
        _config = config;
        _recipientService = recipientService;

        UpdateConfiguration(config.CurrentValue);
        config.OnChange(UpdateConfiguration);
    }

    private void UpdateConfiguration(SurveillanceConfiguration config)
    {
        var channelConfig = config.Alerting.Channels
            .FirstOrDefault(c => c.Type.Equals("Email", StringComparison.OrdinalIgnoreCase));

        if (channelConfig != null)
        {
            IsEnabled = channelConfig.Enabled;
            MinimumSeverity = Enum.TryParse<AlertSeverity>(channelConfig.MinSeverity, out var severity)
                ? severity
                : AlertSeverity.Warning;

            if (channelConfig.Settings.TryGetValue("SmtpServer", out var smtp))
                SmtpServer = smtp?.ToString() ?? SmtpServer;

            if (channelConfig.Settings.TryGetValue("SmtpPort", out var port))
                SmtpPort = Convert.ToInt32(port);

            if (channelConfig.Settings.TryGetValue("From", out var from))
            {
                var fromAddress = from?.ToString() ?? string.Empty;
                // Replace {ComputerName} placeholder with actual computer name
                From = fromAddress.Replace("{ComputerName}", Environment.MachineName, StringComparison.OrdinalIgnoreCase);
            }

            if (channelConfig.Settings.TryGetValue("To", out var to))
            {
                // Parse comma or semicolon-separated email addresses
                var toStr = to?.ToString() ?? string.Empty;
                To = toStr.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim())
                    .Where(s => !string.IsNullOrEmpty(s))
                    .ToList();
                _logger.LogInformation("Email To parsed: {Count} recipients: {List}", 
                    To.Count, string.Join(", ", To));
            }

            if (channelConfig.Settings.TryGetValue("Username", out var username))
                Username = username?.ToString();

            if (channelConfig.Settings.TryGetValue("Password", out var password))
                Password = password?.ToString();

            if (channelConfig.Settings.TryGetValue("EnableSsl", out var ssl))
                EnableSsl = Convert.ToBoolean(ssl);
            
            var toList = string.Join(",", To);
            _logger.LogInformation("Email channel configured: Enabled={Enabled}, From={From}, To={ToList}, ToCount={Count}", 
                IsEnabled, From, toList, To.Count);
        }
        else
        {
            IsEnabled = false;
            _logger.LogWarning("Email channel configuration not found in appsettings.json");
        }
    }

    public async Task SendAlertAsync(Alert alert, CancellationToken cancellationToken = default)
    {
        try
        {
            if (!IsEnabled || string.IsNullOrEmpty(SmtpServer))
            {
                return;
            }

            // Get recipients from NotificationRecipientService if available
            var recipients = new List<string>();
            var useNotificationRecipients = false;
            
            if (_recipientService != null)
            {
                var recipientInfos = _recipientService.GetRecipientsForAlert("Email", alert.Timestamp);
                recipients = recipientInfos
                    .Where(r => !string.IsNullOrWhiteSpace(r.Email))
                    .Select(r => r.Email)
                    .Distinct()
                    .ToList();
                
                // Check if NotificationRecipients.json file exists
                var notificationRecipientsPath = Path.Combine(AppContext.BaseDirectory, "NotificationRecipients.json");
                useNotificationRecipients = File.Exists(notificationRecipientsPath);
                
                if (recipients.Count > 0)
                {
                    _logger.LogDebug("Using {Count} recipients from NotificationRecipients.json", recipients.Count);
                }
                else if (useNotificationRecipients)
                {
                    _logger.LogDebug("NotificationRecipients.json exists but returned 0 recipients (time range or day restrictions)");
                }
            }

            // Fallback to config ONLY if NotificationRecipients.json doesn't exist
            if (recipients.Count == 0 && !useNotificationRecipients && To.Count > 0)
            {
                recipients = To;
                _logger.LogDebug("Using {Count} recipients from appsettings.json (fallback - NotificationRecipients.json not found)", recipients.Count);
            }

            if (recipients.Count == 0)
            {
                _logger.LogWarning("No email recipients configured - skipping email alert");
                return;
            }

            using var message = new MailMessage
            {
                From = new MailAddress(From),
                Subject = $"[{alert.Severity}] {alert.Category}: {alert.Message}",
                Body = FormatEmailBody(alert),
                IsBodyHtml = true
            };

            foreach (var recipient in recipients)
            {
                message.To.Add(recipient);
            }

            using var client = new SmtpClient(SmtpServer, SmtpPort)
            {
                EnableSsl = EnableSsl
            };

            if (!string.IsNullOrEmpty(Username) && !string.IsNullOrEmpty(Password))
            {
                client.Credentials = new NetworkCredential(Username, Password);
            }

            await client.SendMailAsync(message, cancellationToken);

            _logger.LogDebug("Alert email sent to {Recipients}: {Message}", 
                string.Join(", ", recipients), alert.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send alert email");
            throw;
        }
    }

    private string FormatEmailBody(Alert alert)
    {
        return $@"
<html>
<body>
    <h2 style='color: {GetSeverityColor(alert.Severity)};'>{alert.Severity} Alert</h2>
    <table border='1' cellpadding='5' cellspacing='0'>
        <tr><td><strong>Alert ID:</strong></td><td style='font-family: monospace;'>{alert.Id}</td></tr>
        <tr><td><strong>Server:</strong></td><td>{alert.ServerName}</td></tr>
        <tr><td><strong>Category:</strong></td><td>{alert.Category}</td></tr>
        <tr><td><strong>Timestamp:</strong></td><td>{alert.Timestamp:yyyy-MM-dd HH:mm:ss} UTC</td></tr>
        <tr><td><strong>Message:</strong></td><td>{alert.Message}</td></tr>
        {(string.IsNullOrEmpty(alert.Details) ? "" : $"<tr><td><strong>Details:</strong></td><td>{alert.Details}</td></tr>")}
    </table>
    <br/>
    <p><em>This is an automated alert from Server Health Monitor Check Tool</em></p>
</body>
</html>";
    }

    private string GetSeverityColor(AlertSeverity severity)
    {
        return severity switch
        {
            AlertSeverity.Critical => "#D32F2F",
            AlertSeverity.Warning => "#F57C00",
            AlertSeverity.Informational => "#1976D2",
            _ => "#000000"
        };
    }
}

