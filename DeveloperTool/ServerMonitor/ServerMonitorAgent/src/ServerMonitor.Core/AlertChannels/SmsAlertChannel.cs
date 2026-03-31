using System.Net.Http;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.AlertChannels;

public class SmsAlertChannel : IAlertChannel
{
    private readonly ILogger<SmsAlertChannel> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly HttpClient _httpClient;
    private readonly NotificationRecipientService? _recipientService;

    public string ChannelType => "SMS";
    public bool IsEnabled { get; private set; }
    public AlertSeverity MinimumSeverity { get; private set; }
    
    private string ApiUrl { get; set; } = "http://sms3.pswin.com/sms";
    private string Client { get; set; } = "fk";
    private string Password { get; set; } = "";
    private string Sender { get; set; } = "23022222";
    private string Receivers { get; set; } = "";
    private string DefaultCountryCode { get; set; } = "+47";
    private int MaxMessageLength { get; set; } = 160;

    public SmsAlertChannel(
        ILogger<SmsAlertChannel> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IHttpClientFactory httpClientFactory,
        NotificationRecipientService? recipientService = null)
    {
        _logger = logger;
        _config = config;
        _httpClient = httpClientFactory.CreateClient();
        _recipientService = recipientService;

        UpdateConfiguration(config.CurrentValue);
        config.OnChange(UpdateConfiguration);
    }

    private void UpdateConfiguration(SurveillanceConfiguration config)
    {
        _logger.LogCritical("========== SMS UpdateConfiguration START ==========");
        _logger.LogCritical("Alerting.Enabled: {Enabled}", config.Alerting.Enabled);
        _logger.LogCritical("Alerting.Channels: {Count} channels", config.Alerting.Channels?.Count ?? 0);
        
        if (config.Alerting.Channels == null || config.Alerting.Channels.Count == 0)
        {
            _logger.LogCritical("❌ CHANNELS IS NULL OR EMPTY!");
            IsEnabled = false;
            return;
        }
        
        // Log all channel types
        for (int i = 0; i < config.Alerting.Channels.Count; i++)
        {
            var ch = config.Alerting.Channels[i];
            _logger.LogCritical("  Channel[{Index}]: Type={Type}, Enabled={Enabled}, MinSeverity={MinSeverity}", 
                i, ch.Type, ch.Enabled, ch.MinSeverity);
        }
        
        var channelConfig = config.Alerting.Channels
            .FirstOrDefault(c => c.Type.Equals("SMS", StringComparison.OrdinalIgnoreCase));

        _logger.LogCritical("SMS channel search result: {Result}", channelConfig != null ? "FOUND" : "NOT FOUND");

        if (channelConfig != null)
        {
            _logger.LogCritical("Found SMS config: Enabled={Enabled}, MinSeverity={MinSeverity}", 
                channelConfig.Enabled, channelConfig.MinSeverity);
            
            IsEnabled = channelConfig.Enabled;
            MinimumSeverity = Enum.TryParse<AlertSeverity>(channelConfig.MinSeverity, out var severity)
                ? severity
                : AlertSeverity.Warning;

            _logger.LogCritical("Set IsEnabled={IsEnabled}, MinimumSeverity={MinSeverity}", IsEnabled, MinimumSeverity);
            _logger.LogCritical("SMS Settings keys: {Keys}", string.Join(", ", channelConfig.Settings.Keys));

            if (channelConfig.Settings.TryGetValue("ApiUrl", out var apiUrl))
                ApiUrl = apiUrl?.ToString() ?? ApiUrl;

            if (channelConfig.Settings.TryGetValue("Client", out var client))
                Client = client?.ToString() ?? Client;

            if (channelConfig.Settings.TryGetValue("Password", out var password))
                Password = password?.ToString() ?? Password;

            if (channelConfig.Settings.TryGetValue("Sender", out var sender))
                Sender = sender?.ToString() ?? Sender;

            if (channelConfig.Settings.TryGetValue("Receivers", out var receivers))
                Receivers = receivers?.ToString() ?? Receivers;

            if (channelConfig.Settings.TryGetValue("DefaultCountryCode", out var countryCode))
                DefaultCountryCode = countryCode?.ToString() ?? DefaultCountryCode;

            if (channelConfig.Settings.TryGetValue("MaxMessageLength", out var maxLen))
            {
                if (int.TryParse(maxLen?.ToString(), out var len))
                    MaxMessageLength = len;
            }
            
            _logger.LogCritical("SMS channel FINAL: Enabled={Enabled}, Receivers={Receivers}, CountryCode={CountryCode}", 
                IsEnabled, Receivers, DefaultCountryCode);
        }
        else
        {
            IsEnabled = false;
            _logger.LogCritical("❌ SMS channel configuration NOT FOUND in appsettings.json");
        }
        
        _logger.LogCritical("========== SMS UpdateConfiguration END ==========");
    }

    public async Task SendAlertAsync(Alert alert, CancellationToken cancellationToken = default)
    {
        if (!IsEnabled || alert.Severity < MinimumSeverity)
        {
            return;
        }

        // Get recipients from NotificationRecipientService if available
        var receiverList = new List<string>();
        var useNotificationRecipients = false;
        
        if (_recipientService != null)
        {
            var recipientInfos = _recipientService.GetRecipientsForAlert("SMS", alert.Timestamp);
            receiverList = recipientInfos
                .Where(r => !string.IsNullOrWhiteSpace(r.Phone))
                .Select(r => NormalizePhoneNumber(r.Phone))
                .Where(r => !string.IsNullOrWhiteSpace(r))
                .Distinct()
                .ToList();
            
            // Check if NotificationRecipients.json file exists
            var notificationRecipientsPath = Path.Combine(AppContext.BaseDirectory, "NotificationRecipients.json");
            useNotificationRecipients = File.Exists(notificationRecipientsPath);
            
            if (receiverList.Count > 0)
            {
                _logger.LogDebug("Using {Count} recipients from NotificationRecipients.json", receiverList.Count);
            }
            else if (useNotificationRecipients)
            {
                _logger.LogDebug("NotificationRecipients.json exists but returned 0 recipients (time range or day restrictions)");
            }
        }

        // Fallback to config ONLY if NotificationRecipients.json doesn't exist
        if (receiverList.Count == 0 && !useNotificationRecipients && !string.IsNullOrWhiteSpace(Receivers))
        {
            receiverList = Receivers.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(r => NormalizePhoneNumber(r.Trim()))
                .Where(r => !string.IsNullOrWhiteSpace(r))
                .ToList();
            
            if (receiverList.Count > 0)
            {
                _logger.LogDebug("Using {Count} recipients from appsettings.json (fallback - NotificationRecipients.json not found)", receiverList.Count);
            }
        }

        if (!receiverList.Any())
        {
            _logger.LogWarning("No SMS receivers configured - skipping SMS alert");
            return;
        }

        // Build message
        var message = FormatMessage(alert);

        // Send to each receiver
        foreach (var receiver in receiverList)
        {
            await SendSmsAsync(receiver, message, cancellationToken);
        }
    }


    private string NormalizePhoneNumber(string phoneNumber)
    {
        if (string.IsNullOrWhiteSpace(phoneNumber))
            return string.Empty;

        // Remove all non-numeric characters except '+'
        var cleaned = new string(phoneNumber.Where(c => char.IsDigit(c) || c == '+').ToArray());

        // If it doesn't start with '+', add the default country code
        if (!cleaned.StartsWith("+"))
        {
            // Remove any leading zeros
            cleaned = cleaned.TrimStart('0');
            cleaned = DefaultCountryCode + cleaned;
        }

        return cleaned;
    }

    private string FormatMessage(Alert alert)
    {
        // Format: [Severity@ComputerName] Category: Message | Details
        // Similar to email but in a compact SMS-friendly format
        // Example: [Critical@SERVER01] Processor: CPU usage critical: 95.2% (average) | CPU usage average over 300 seconds is 95.2%, exceeding critical threshold of 95%
        var serverName = alert.ServerName ?? Environment.MachineName;
        var severity = alert.Severity.ToString();
        
        // Build message with full context (similar to email)
        var messageBuilder = new StringBuilder();
        messageBuilder.Append($"[{severity}@{serverName}] {alert.Category}: {alert.Message}");
        
        // Add details if present (this is the key context that was missing)
        if (!string.IsNullOrWhiteSpace(alert.Details))
        {
            messageBuilder.Append($" | {alert.Details}");
        }
        
        // Add timestamp for context (DD/MM/YYYY format)
        var timestamp = alert.Timestamp.ToString("dd/MM/yyyy HH:mm");
        messageBuilder.Append($" ({timestamp})");
        
        var message = messageBuilder.ToString();
        
        // Truncate if needed, but try to preserve as much context as possible
        if (message.Length > MaxMessageLength)
        {
            // Priority: Keep prefix, message, then details (truncate details first if needed)
            var prefix = $"[{severity}@{serverName}] {alert.Category}: {alert.Message}";
            var detailsPart = string.IsNullOrWhiteSpace(alert.Details) ? "" : $" | {alert.Details}";
            var timestampPart = $" ({timestamp})";
            
            // Calculate available space
            var reservedLength = prefix.Length + timestampPart.Length + 3; // +3 for "..."
            var availableForDetails = MaxMessageLength - reservedLength;
            
            if (availableForDetails > 0 && !string.IsNullOrWhiteSpace(detailsPart))
            {
                // Truncate details if needed
                if (detailsPart.Length > availableForDetails)
                {
                    detailsPart = detailsPart.Substring(0, availableForDetails - 3) + "...";
                }
                message = prefix + detailsPart + timestampPart;
            }
            else
            {
                // If we can't fit details, try without timestamp
                reservedLength = prefix.Length + 3;
                availableForDetails = MaxMessageLength - reservedLength;
                
                if (availableForDetails > 0 && !string.IsNullOrWhiteSpace(detailsPart))
                {
                    if (detailsPart.Length > availableForDetails)
                    {
                        detailsPart = detailsPart.Substring(0, availableForDetails - 3) + "...";
                    }
                    message = prefix + detailsPart;
                }
                else
                {
                    // Last resort: truncate the main message
                    var maxMainLength = MaxMessageLength - timestampPart.Length - 3;
                    if (maxMainLength > 0)
                    {
                        var truncatedMain = prefix.Substring(0, maxMainLength) + "...";
                        message = truncatedMain + timestampPart;
                    }
                    else
                    {
                        // If even prefix is too long, just truncate everything
                        message = message.Substring(0, MaxMessageLength - 3) + "...";
                    }
                }
            }
        }

        return message;
    }

    private async Task SendSmsAsync(string receiver, string message, CancellationToken cancellationToken)
    {
        try
        {
            _logger.LogInformation("Sending SMS to {Receiver} with message: {Message}", receiver, message);

            // Build XML payload
            var xmlPayload = $@"<?xml version=""1.0""?>
<SESSION>
    <CLIENT>{Client}</CLIENT>
    <PW>{Password}</PW>
    <MSGLST>
        <MSG>
            <TEXT>{System.Security.SecurityElement.Escape(message)}</TEXT>
            <RCV>{System.Security.SecurityElement.Escape(receiver)}</RCV>
            <SND>{System.Security.SecurityElement.Escape(Sender)}</SND>
        </MSG>
    </MSGLST>
</SESSION>";

            var content = new StringContent(xmlPayload, Encoding.UTF8, "application/xml");
            
            var response = await _httpClient.PostAsync(ApiUrl, content, cancellationToken);
            
            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("SMS sent successfully to {Receiver}", receiver);
            }
            else
            {
                _logger.LogWarning("SMS sending failed for {Receiver}. Status: {StatusCode}", 
                    receiver, response.StatusCode);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send SMS to {Receiver}", receiver);
        }
    }
}

