using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MimeKit;
using DedgeAuth.Core.Models;

namespace DedgeAuth.Services;

/// <summary>
/// Email service for authentication-related emails (magic link, password reset, verification).
/// Supports tenant branding (primary color, logo) when a Tenant is provided.
/// </summary>
public class EmailService
{
    private readonly SmtpConfiguration _smtp;
    private readonly ILogger<EmailService> _logger;

    // Default DedgeAuth blue used when no tenant branding is available
    private const string DefaultPrimaryColor = "#2563eb";
    private const string DefaultPrimaryHoverColor = "#1d4ed8";

    public EmailService(IOptions<SmtpConfiguration> smtp, ILogger<EmailService> logger)
    {
        _smtp = smtp.Value;
        _logger = logger;
    }

    /// <summary>
    /// Resolve the tenant logo URL for use in email templates.
    /// Prefers LogoUrl (external URL), falls back to the /tenants/{domain}/logo endpoint.
    /// </summary>
    private static string? ResolveLogoUrl(Tenant? tenant, string? baseUrl)
    {
        if (tenant == null) return null;
        if (!string.IsNullOrEmpty(tenant.LogoUrl)) return tenant.LogoUrl;
        if (tenant.LogoData != null && tenant.LogoData.Length > 0 && !string.IsNullOrEmpty(baseUrl))
        {
            return $"{baseUrl.TrimEnd('/')}/tenants/{tenant.Domain}/logo";
        }
        return null;
    }

    /// <summary>
    /// Send magic link login email with optional tenant branding.
    /// </summary>
    public async Task SendMagicLinkEmailAsync(string email, string displayName, string loginUrl, int expirationMinutes, Tenant? tenant = null, string? baseUrl = null)
    {
        _logger.LogDebug("Preparing magic link email for {Email}, displayName: {DisplayName}, expires in {Minutes} minutes, tenant: {Tenant}", 
            email, displayName, expirationMinutes, tenant?.Domain ?? "none");

        var primaryColor = tenant?.PrimaryColor ?? DefaultPrimaryColor;
        var tenantName = tenant?.DisplayName;
        var logoUrl = ResolveLogoUrl(tenant, baseUrl);

        var subject = tenantName != null
            ? $"{tenantName} - Login Request"
            : "Your Login Link - DedgeAuth";

        var bodyContent = $@"
            <p>Hello <strong>{displayName}</strong>,</p>
            <p>You requested to log in. Click the button below to complete your login:</p>
            
            <p style='text-align: center;'>
                <a href='{loginUrl}' style='{ButtonStyle(primaryColor)}'>Log In Now</a>
            </p>
            
            <p>Or copy and paste this link into your browser:</p>
            <p style='word-break: break-all; background: #e2e8f0; padding: 10px; border-radius: 4px; font-size: 13px;'>
                {loginUrl}
            </p>
            
            <div style='background: #fef3c7; border: 1px solid #f59e0b; padding: 10px; border-radius: 4px; margin-top: 20px;'>
                <strong>This link expires in {expirationMinutes} minutes.</strong><br/>
                If you didn't request this login, you can safely ignore this email.
            </div>";

        var body = BuildEmailTemplate("Login Request", bodyContent, primaryColor, logoUrl, tenantName);
        await SendEmailAsync(email, subject, body);
    }

    /// <summary>
    /// Send password reset email with optional tenant branding.
    /// </summary>
    public async Task SendPasswordResetEmailAsync(string email, string displayName, string resetUrl, Tenant? tenant = null, string? baseUrl = null)
    {
        _logger.LogDebug("Preparing password reset email for {Email}, tenant: {Tenant}",
            email, tenant?.Domain ?? "none");

        var primaryColor = tenant?.PrimaryColor ?? DefaultPrimaryColor;
        var tenantName = tenant?.DisplayName;
        var logoUrl = ResolveLogoUrl(tenant, baseUrl);

        var subject = tenantName != null
            ? $"{tenantName} - Password Reset"
            : "Password Reset Request - DedgeAuth";

        var bodyContent = $@"
            <p>Hello <strong>{displayName}</strong>,</p>
            <p>We received a request to reset your password. Click the button below to set a new password:</p>
            
            <p style='text-align: center;'>
                <a href='{resetUrl}' style='{ButtonStyle(primaryColor)}'>Reset Password</a>
            </p>
            
            <p>Or copy and paste this link into your browser:</p>
            <p style='word-break: break-all; background: #e2e8f0; padding: 10px; border-radius: 4px; font-size: 13px;'>
                {resetUrl}
            </p>
            
            <div style='background: #fef3c7; border: 1px solid #f59e0b; padding: 10px; border-radius: 4px; margin-top: 20px;'>
                <strong>This link expires in 24 hours.</strong><br/>
                If you didn't request this password reset, please ignore this email. Your password will remain unchanged.
            </div>";

        var body = BuildEmailTemplate("Password Reset", bodyContent, primaryColor, logoUrl, tenantName);
        await SendEmailAsync(email, subject, body);
    }

    /// <summary>
    /// Send email verification email with optional tenant branding.
    /// </summary>
    public async Task SendVerificationEmailAsync(string email, string displayName, string verifyUrl, Tenant? tenant = null, string? baseUrl = null)
    {
        var primaryColor = tenant?.PrimaryColor ?? "#059669";
        var tenantName = tenant?.DisplayName;
        var logoUrl = ResolveLogoUrl(tenant, baseUrl);

        var subject = tenantName != null
            ? $"{tenantName} - Verify Your Email"
            : "Verify Your Email - DedgeAuth";

        var bodyContent = $@"
            <p>Hello <strong>{displayName}</strong>,</p>
            <p>Welcome! Please verify your email address by clicking the button below:</p>
            
            <p style='text-align: center;'>
                <a href='{verifyUrl}' style='{ButtonStyle(primaryColor)}'>Verify Email</a>
            </p>
            
            <p>Or copy and paste this link into your browser:</p>
            <p style='word-break: break-all; background: #e2e8f0; padding: 10px; border-radius: 4px; font-size: 13px;'>
                {verifyUrl}
            </p>";

        var body = BuildEmailTemplate("Verify Your Email", bodyContent, primaryColor, logoUrl, tenantName);
        await SendEmailAsync(email, subject, body);
    }

    // 20260317 GHS Test Ad/Entra Start -->
    /// <summary>
    /// Send welcome email to auto-registered Windows/Kerberos users.
    /// </summary>
    public async Task SendWindowsWelcomeEmailAsync(string email, string displayName, string profileUrl, Tenant? tenant = null, string? baseUrl = null)
    {
        _logger.LogDebug("Preparing Windows welcome email for {Email}", email);

        var primaryColor = tenant?.PrimaryColor ?? DefaultPrimaryColor;
        var tenantName = tenant?.DisplayName;
        var logoUrl = ResolveLogoUrl(tenant, baseUrl);

        var subject = tenantName != null
            ? $"{tenantName} - Welcome to DedgeAuth"
            : "Welcome to DedgeAuth - Automatic Registration";

        var bodyContent = $@"
            <p>Hello <strong>{displayName}</strong>,</p>
            <p>You have been automatically registered in DedgeAuth via Windows/Kerberos authentication. Your account is active and ready to use.</p>
            
            <div style='background: #ecfdf5; border: 1px solid #10b981; padding: 15px; border-radius: 4px; margin: 20px 0;'>
                <strong>Your account details:</strong><br/>
                Email: <strong>{email}</strong><br/>
                Authentication: Windows/Kerberos (no password required)
            </div>

            <p>You may already have basic access to some applications. To request elevated access or see available apps, visit your profile page:</p>
            
            <p style='text-align: center;'>
                <a href='{profileUrl}' style='{ButtonStyle(primaryColor)}'>My Profile &amp; App Access</a>
            </p>
            
            <p style='font-size: 13px; color: #64748b;'>
                You can also log in with email and password if you set one up on your profile page.
            </p>";

        var body = BuildEmailTemplate("Welcome to DedgeAuth", bodyContent, primaryColor, logoUrl, tenantName);

        try
        {
            await SendEmailAsync(email, subject, body);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send Windows welcome email to {Email} — continuing without email", email);
        }
    }
    // <--20260317 GHS Test Ad/Entra End

    /// <summary>
    /// Send account lockout notification email.
    /// </summary>
    public async Task SendLockoutNotificationAsync(string email, string displayName, DateTime lockoutUntil, int failedAttempts, string? ipAddress = null, Tenant? tenant = null, string? baseUrl = null)
    {
        var primaryColor = tenant?.PrimaryColor ?? "#dc2626";
        var tenantName = tenant?.DisplayName;
        var logoUrl = ResolveLogoUrl(tenant, baseUrl);

        var subject = tenantName != null
            ? $"{tenantName} - Account Locked"
            : "Account Locked - DedgeAuth";

        var ipInfo = !string.IsNullOrEmpty(ipAddress)
            ? $"<br/>Last failed attempt from IP: <strong>{ipAddress}</strong>"
            : "";

        var bodyContent = $@"
            <p>Hello <strong>{displayName}</strong>,</p>
            <p>Your account has been <strong>temporarily locked</strong> due to {failedAttempts} failed login attempts.</p>
            
            <div style='background: #fef2f2; border: 1px solid #ef4444; padding: 15px; border-radius: 4px; margin: 20px 0;'>
                <strong>Account locked until:</strong> {lockoutUntil:yyyy-MM-dd HH:mm} UTC
                {ipInfo}
            </div>
            
            <p>If this was you, wait for the lockout period to expire and try again with the correct password.</p>
            <p>If you didn't attempt to log in, someone may be trying to access your account. Consider changing your password after the lockout expires.</p>";

        var body = BuildEmailTemplate("Account Locked", bodyContent, primaryColor, logoUrl, tenantName);

        try
        {
            await SendEmailAsync(email, subject, body);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send lockout notification to {Email} — continuing without email", email);
        }
    }

    /// <summary>
    /// Build a complete branded email HTML template.
    /// Uses tenant primary color for header/buttons and includes logo when available.
    /// </summary>
    private static string BuildEmailTemplate(string title, string bodyContent, string primaryColor, string? logoUrl, string? tenantName)
    {
        var logoHtml = !string.IsNullOrEmpty(logoUrl)
            ? $@"<img src='{logoUrl}' alt='{tenantName ?? "Logo"}' style='max-width: 150px; max-height: 50px; margin-bottom: 10px;' /><br/>"
            : "";

        var footerName = tenantName ?? "DedgeAuth";

        return $@"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8' />
    <meta name='viewport' content='width=device-width, initial-scale=1.0' />
</head>
<body style='font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background-color: #f1f5f9;'>
    <div style='max-width: 600px; margin: 0 auto; padding: 20px;'>
        <div style='background: {primaryColor}; color: white; padding: 24px 20px; text-align: center; border-radius: 8px 8px 0 0;'>
            {logoHtml}
            <h1 style='margin: 0; font-size: 22px; font-weight: 600;'>{title}</h1>
        </div>
        <div style='background: #ffffff; padding: 30px; border: 1px solid #e2e8f0; border-top: none;'>
            {bodyContent}
        </div>
        <div style='text-align: center; padding: 20px; color: #64748b; font-size: 12px; border-radius: 0 0 8px 8px;'>
            <p style='margin: 0;'>This is an automated message from {footerName}.<br/>
            Please do not reply to this email.</p>
        </div>
    </div>
</body>
</html>";
    }

    /// <summary>
    /// Generate inline button CSS style string for use in email templates.
    /// </summary>
    private static string ButtonStyle(string color)
    {
        return $"display: inline-block; background: {color}; color: white !important; padding: 14px 28px; text-decoration: none; border-radius: 6px; margin: 20px 0; font-weight: bold; font-size: 16px;";
    }

    /// <summary>
    /// Send email using SMTP (MailKit).
    /// </summary>
    private async Task SendEmailAsync(string to, string subject, string htmlBody)
    {
        _logger.LogDebug("SendEmailAsync called - To: {To}, Subject: {Subject}, Body length: {BodyLength}", 
            to, subject, htmlBody?.Length ?? 0);

        if (string.IsNullOrEmpty(_smtp.Host))
        {
            _logger.LogWarning("SMTP not configured (Host is empty) - email not sent to {Email}", to);
            return;
        }

        _logger.LogDebug("SMTP configuration - Host: {Host}, Port: {Port}, UseSsl: {UseSsl}, From: {From}", 
            _smtp.Host, _smtp.Port, _smtp.UseSsl, _smtp.FromEmail);

        try
        {
            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(_smtp.FromName, _smtp.FromEmail));
            message.To.Add(new MailboxAddress(to, to));
            message.Subject = subject;

            var bodyBuilder = new BodyBuilder { HtmlBody = htmlBody };
            message.Body = bodyBuilder.ToMessageBody();

            _logger.LogDebug("Connecting to SMTP server {Host}:{Port}...", _smtp.Host, _smtp.Port);

            using var client = new SmtpClient();

            var secureOption = _smtp.UseSsl ? SecureSocketOptions.StartTls : SecureSocketOptions.None;
            await client.ConnectAsync(_smtp.Host, _smtp.Port, secureOption);
            _logger.LogDebug("Connected to SMTP server successfully");

            if (!string.IsNullOrEmpty(_smtp.Username))
            {
                _logger.LogDebug("Authenticating with SMTP server as {Username}...", _smtp.Username);
                await client.AuthenticateAsync(_smtp.Username, _smtp.Password);
                _logger.LogDebug("SMTP authentication successful");
            }
            else
            {
                _logger.LogDebug("No SMTP authentication required (anonymous relay)");
            }

            _logger.LogDebug("Sending email message...");
            await client.SendAsync(message);
            _logger.LogDebug("Email message sent successfully");

            await client.DisconnectAsync(true);
            _logger.LogDebug("Disconnected from SMTP server");

            _logger.LogInformation("Email sent successfully to {Email}: {Subject}", to, subject);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email to {Email} via {SmtpHost}:{SmtpPort} - {ErrorMessage}", 
                to, _smtp.Host, _smtp.Port, ex.Message);
            throw;
        }
    }
}
