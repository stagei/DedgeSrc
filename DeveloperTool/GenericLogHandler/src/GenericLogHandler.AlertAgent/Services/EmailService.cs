using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;
using Microsoft.Extensions.Logging;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using System.Text;

namespace GenericLogHandler.AlertAgent.Services;

/// <summary>
/// SMTP email settings configuration
/// </summary>
public class SmtpSettings
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; } = 587;
    public bool UseSsl { get; set; } = true;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FromAddress { get; set; } = "loghandler@localhost";
    public string FromName { get; set; } = "Generic Log Handler";
    public int TimeoutSeconds { get; set; } = 30;
}

/// <summary>
/// Service for sending email alerts using SMTP
/// </summary>
public class EmailService
{
    private readonly ILogger<EmailService> _logger;
    private readonly SmtpSettings _settings;

    public EmailService(ILogger<EmailService> logger, SmtpSettings settings)
    {
        _logger = logger;
        _settings = settings;
    }

    /// <summary>
    /// Send an alert email
    /// </summary>
    public async Task<string> SendAlertEmailAsync(
        AlertConfig config,
        SavedFilter filter,
        PagedResult<LogEntry> result,
        CancellationToken cancellationToken = default)
    {
        if (_settings == null || string.IsNullOrEmpty(_settings.Host))
        {
            throw new InvalidOperationException("SMTP settings not configured");
        }

        if (config.EmailRecipients == null || config.EmailRecipients.Count == 0)
        {
            throw new ArgumentException("No email recipients specified");
        }

        var message = new MimeMessage();
        message.From.Add(new MailboxAddress(_settings.FromName, _settings.FromAddress));
        
        foreach (var recipient in config.EmailRecipients)
        {
            message.To.Add(MailboxAddress.Parse(recipient));
        }

        message.Subject = BuildSubject(config, filter, result);

        var bodyBuilder = new BodyBuilder();
        bodyBuilder.HtmlBody = BuildHtmlBody(filter, result, config);
        bodyBuilder.TextBody = BuildTextBody(filter, result, config);
        message.Body = bodyBuilder.ToMessageBody();

        _logger.LogInformation("Sending alert email to {Recipients} for filter {FilterName}",
            string.Join(", ", config.EmailRecipients), filter.Name);

        try
        {
            using var client = new SmtpClient();
            client.Timeout = _settings.TimeoutSeconds * 1000;

            var secureSocketOptions = _settings.UseSsl 
                ? SecureSocketOptions.StartTls 
                : SecureSocketOptions.None;

            await client.ConnectAsync(_settings.Host, _settings.Port, secureSocketOptions, cancellationToken);

            if (!string.IsNullOrEmpty(_settings.Username))
            {
                await client.AuthenticateAsync(_settings.Username, _settings.Password, cancellationToken);
            }

            var response = await client.SendAsync(message, cancellationToken);
            await client.DisconnectAsync(true, cancellationToken);

            _logger.LogInformation("Alert email sent successfully to {Count} recipients", config.EmailRecipients.Count);
            return $"Email sent to {config.EmailRecipients.Count} recipients: {response}";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send alert email");
            throw;
        }
    }

    private string BuildSubject(AlertConfig config, SavedFilter filter, PagedResult<LogEntry> result)
    {
        var subject = config.EmailSubject;
        
        if (string.IsNullOrEmpty(subject))
        {
            subject = $"[ALERT] {filter.Name}: {result.TotalCount} matching entries";
        }
        else
        {
            // Replace placeholders
            subject = subject
                .Replace("{{filterName}}", filter.Name)
                .Replace("{{matchCount}}", result.TotalCount.ToString());
        }

        return subject;
    }

    private string BuildHtmlBody(SavedFilter filter, PagedResult<LogEntry> result, AlertConfig config)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<!DOCTYPE html>");
        sb.AppendLine("<html><head><style>");
        sb.AppendLine(@"
            body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); padding: 20px; }
            h1 { color: #d32f2f; margin-top: 0; }
            .summary { background: #ffebee; border-left: 4px solid #d32f2f; padding: 15px; margin: 20px 0; border-radius: 4px; }
            .summary strong { font-size: 1.2em; }
            table { width: 100%; border-collapse: collapse; margin: 20px 0; }
            th { background: #1976d2; color: white; padding: 12px; text-align: left; }
            td { padding: 10px; border-bottom: 1px solid #e0e0e0; }
            tr:hover { background: #f5f5f5; }
            .level-error { color: #d32f2f; font-weight: bold; }
            .level-warn { color: #f57c00; font-weight: bold; }
            .level-info { color: #1976d2; }
            .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; color: #757575; font-size: 12px; }
        ");
        sb.AppendLine("</style></head><body>");
        sb.AppendLine("<div class='container'>");
        
        sb.AppendLine($"<h1>Alert: {HtmlEncode(filter.Name)}</h1>");
        
        sb.AppendLine("<div class='summary'>");
        sb.AppendLine($"<strong>{result.TotalCount}</strong> log entries matched your alert criteria.");
        sb.AppendLine($"<br/><small>Threshold: {config.ThresholdCount} | Time: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC</small>");
        sb.AppendLine("</div>");

        if (result.Items.Any() && config.IncludeEntries)
        {
            sb.AppendLine("<h2>Recent Matching Entries</h2>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Timestamp</th><th>Level</th><th>Computer</th><th>Message</th></tr>");
            
            foreach (var entry in result.Items.Take(config.MaxEntriesToInclude))
            {
                var levelClass = entry.Level.ToString().ToLower() switch
                {
                    "error" or "fatal" => "level-error",
                    "warn" or "warning" => "level-warn",
                    _ => "level-info"
                };
                
                var message = entry.Message?.Length > 200 
                    ? entry.Message.Substring(0, 200) + "..." 
                    : entry.Message ?? "";
                
                sb.AppendLine($@"<tr>
                    <td>{entry.Timestamp:yyyy-MM-dd HH:mm:ss}</td>
                    <td class='{levelClass}'>{entry.Level}</td>
                    <td>{HtmlEncode(entry.ComputerName ?? "-")}</td>
                    <td>{HtmlEncode(message)}</td>
                </tr>");
            }
            
            sb.AppendLine("</table>");
            
            if (result.TotalCount > config.MaxEntriesToInclude)
            {
                sb.AppendLine($"<p><em>Showing {config.MaxEntriesToInclude} of {result.TotalCount} entries.</em></p>");
            }
        }

        sb.AppendLine("<div class='footer'>");
        sb.AppendLine("This is an automated alert from Generic Log Handler.<br/>");
        sb.AppendLine($"Filter: {HtmlEncode(filter.Name)} | Alert ID: {filter.Id}");
        sb.AppendLine("</div>");
        
        sb.AppendLine("</div></body></html>");
        return sb.ToString();
    }

    private string BuildTextBody(SavedFilter filter, PagedResult<LogEntry> result, AlertConfig config)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"ALERT: {filter.Name}");
        sb.AppendLine(new string('=', 50));
        sb.AppendLine();
        sb.AppendLine($"Matched Entries: {result.TotalCount}");
        sb.AppendLine($"Threshold: {config.ThresholdCount}");
        sb.AppendLine($"Time: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC");
        sb.AppendLine();

        if (result.Items.Any() && config.IncludeEntries)
        {
            sb.AppendLine("Recent Matching Entries:");
            sb.AppendLine(new string('-', 50));
            
            foreach (var entry in result.Items.Take(config.MaxEntriesToInclude))
            {
                sb.AppendLine($"[{entry.Timestamp:yyyy-MM-dd HH:mm:ss}] [{entry.Level}] {entry.ComputerName}");
                sb.AppendLine($"  {entry.Message?.Substring(0, Math.Min(entry.Message?.Length ?? 0, 200))}");
                sb.AppendLine();
            }
        }

        sb.AppendLine(new string('-', 50));
        sb.AppendLine("This is an automated alert from Generic Log Handler.");
        return sb.ToString();
    }

    private static string HtmlEncode(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        return System.Net.WebUtility.HtmlEncode(text);
    }
}
