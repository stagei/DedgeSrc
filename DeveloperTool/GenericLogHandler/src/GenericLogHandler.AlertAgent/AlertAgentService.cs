using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using GenericLogHandler.Core.Interfaces;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Data;
using GenericLogHandler.AlertAgent.Services;
using System.Text.Json;
using System.Diagnostics;
using System.Text;

namespace GenericLogHandler.AlertAgent;

/// <summary>
/// Background service that evaluates saved filters with alerts enabled and triggers configured actions
/// </summary>
public class AlertAgentService : BackgroundService
{
    private readonly ILogger<AlertAgentService> _logger;
    private readonly IServiceProvider _serviceProvider;
    private readonly TimeSpan _evaluationInterval;
    private readonly EmailService? _emailService;

    public AlertAgentService(
        ILogger<AlertAgentService> logger,
        IServiceProvider serviceProvider,
        IConfiguration configuration)
    {
        _logger = logger;
        _serviceProvider = serviceProvider;
        _evaluationInterval = TimeSpan.FromSeconds(60); // Evaluate every 60 seconds
        
        // Initialize email service if SMTP settings are configured
        var smtpSettings = configuration.GetSection("SmtpSettings").Get<SmtpSettings>();
        if (smtpSettings != null && !string.IsNullOrEmpty(smtpSettings.Host))
        {
            _emailService = new EmailService(
                serviceProvider.GetRequiredService<ILoggerFactory>().CreateLogger<EmailService>(),
                smtpSettings);
            _logger.LogInformation("Email service initialized with SMTP host: {Host}", smtpSettings.Host);
        }
        else
        {
            _logger.LogWarning("SMTP settings not configured. Email alerts will not be available.");
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("AlertAgentService starting...");

        // Initial delay to let the system stabilize
        await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await EvaluateAlerts(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during alert evaluation cycle");
            }

            await Task.Delay(_evaluationInterval, stoppingToken);
        }

        _logger.LogInformation("AlertAgentService stopped");
    }

    private async Task EvaluateAlerts(CancellationToken cancellationToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<LoggingDbContext>();
        var repository = scope.ServiceProvider.GetRequiredService<ILogRepository>();

        // Get all filters with alerts enabled
        var alertFilters = await context.SavedFilters
            .Where(f => f.IsAlertEnabled)
            .ToListAsync(cancellationToken);

        if (alertFilters.Count == 0)
        {
            _logger.LogDebug("No alert filters configured");
            return;
        }

        _logger.LogDebug("Evaluating {Count} alert filters", alertFilters.Count);

        foreach (var filter in alertFilters)
        {
            if (cancellationToken.IsCancellationRequested)
                break;

            try
            {
                await EvaluateFilter(filter, repository, context, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error evaluating filter: {FilterName} (ID: {FilterId})", filter.Name, filter.Id);
            }
        }
    }

    private async Task EvaluateFilter(SavedFilter filter, ILogRepository repository, LoggingDbContext context, CancellationToken cancellationToken)
    {
        // Parse alert config
        AlertConfig? alertConfig = null;
        if (!string.IsNullOrEmpty(filter.AlertConfig))
        {
            try
            {
                alertConfig = JsonSerializer.Deserialize<AlertConfig>(filter.AlertConfig,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Invalid alert config JSON for filter: {FilterName}", filter.Name);
                return;
            }
        }

        alertConfig ??= new AlertConfig();

        if (!alertConfig.IsActive)
        {
            _logger.LogDebug("Alert is inactive for filter: {FilterName}", filter.Name);
            return;
        }

        // Check cooldown
        if (filter.LastTriggeredAt.HasValue)
        {
            var cooldownEnd = filter.LastTriggeredAt.Value.AddMinutes(alertConfig.CooldownMinutes);
            if (DateTime.UtcNow < cooldownEnd)
            {
                _logger.LogDebug("Filter {FilterName} is in cooldown until {CooldownEnd}", filter.Name, cooldownEnd);
                return;
            }
        }

        // Parse filter criteria
        LogSearchCriteria? criteria = null;
        try
        {
            var searchRequest = JsonSerializer.Deserialize<LogSearchRequest>(filter.FilterJson,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            if (searchRequest != null)
            {
                criteria = BuildSearchCriteria(searchRequest, alertConfig);
            }
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Invalid filter JSON for filter: {FilterName}", filter.Name);
            return;
        }

        if (criteria == null)
        {
            _logger.LogWarning("Could not build search criteria for filter: {FilterName}", filter.Name);
            return;
        }

        // Execute search
        var result = await repository.SearchAsync(criteria, cancellationToken);

        // Update last evaluated timestamp
        filter.LastEvaluatedAt = DateTime.UtcNow;

        // Check if threshold is met
        if (result.TotalCount >= alertConfig.ThresholdCount)
        {
            _logger.LogInformation("Alert triggered for filter {FilterName}: {Count} matches (threshold: {Threshold})",
                filter.Name, result.TotalCount, alertConfig.ThresholdCount);

            // Trigger the action
            await TriggerAlert(filter, alertConfig, result, context, cancellationToken);
        }

        await context.SaveChangesAsync(cancellationToken);
    }

    private LogSearchCriteria BuildSearchCriteria(LogSearchRequest request, AlertConfig alertConfig)
    {
        var criteria = new LogSearchCriteria
        {
            Levels = request.Levels?.Select(l => Enum.TryParse<Core.Models.LogLevel>(l, true, out var lvl) ? lvl : (Core.Models.LogLevel?)null)
                .Where(l => l.HasValue).Select(l => l!.Value).ToList(),
            ComputerName = request.ComputerName,
            UserName = request.UserName,
            MessageText = request.MessageText,
            ExceptionText = request.ExceptionText,
            RegexPattern = request.RegexPattern,
            FunctionName = request.FunctionName,
            SourceFile = request.SourceFile,
            SourceType = request.SourceType,
            AlertId = request.AlertId,
            Ordrenr = request.Ordrenr,
            Avdnr = request.Avdnr,
            JobName = request.JobName,
            Page = 1,
            PageSize = alertConfig.MaxEntriesToInclude,
            SortBy = "Timestamp",
            SortDescending = true
        };

        // Set time window
        if (alertConfig.TimeWindowMinutes > 0)
        {
            criteria.FromDate = DateTime.UtcNow.AddMinutes(-alertConfig.TimeWindowMinutes);
            criteria.ToDate = DateTime.UtcNow;
        }
        else if (request.FromDate.HasValue || request.ToDate.HasValue)
        {
            criteria.FromDate = request.FromDate;
            criteria.ToDate = request.ToDate;
        }
        else
        {
            // Default: last 5 minutes
            criteria.FromDate = DateTime.UtcNow.AddMinutes(-5);
            criteria.ToDate = DateTime.UtcNow;
        }

        return criteria;
    }

    private async Task TriggerAlert(SavedFilter filter, AlertConfig alertConfig, PagedResult<LogEntry> result, LoggingDbContext context, CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        var history = new AlertHistory
        {
            FilterId = filter.Id,
            FilterName = filter.Name,
            TriggeredAt = DateTime.UtcNow,
            MatchCount = (int)result.TotalCount,
            ActionType = alertConfig.Type
        };

        try
        {
            // Execute the appropriate trigger
            var response = alertConfig.Type.ToLower() switch
            {
                "webhook" => await ExecuteWebhook(alertConfig, filter, result, cancellationToken),
                "script" => await ExecuteScript(alertConfig, filter, result, cancellationToken),
                "servermonitor" => await ExecuteServerMonitor(alertConfig, filter, result, cancellationToken),
                "email" => await ExecuteEmail(alertConfig, filter, result, cancellationToken),
                _ => throw new NotSupportedException($"Unknown trigger type: {alertConfig.Type}")
            };

            history.Success = true;
            history.ActionTaken = $"Triggered {alertConfig.Type} to {alertConfig.Endpoint}";
            history.ActionResponse = response;

            filter.LastTriggeredAt = DateTime.UtcNow;

            _logger.LogInformation("Alert action completed for filter {FilterName}: {ActionType}", filter.Name, alertConfig.Type);
        }
        catch (Exception ex)
        {
            history.Success = false;
            history.ErrorMessage = ex.Message;
            _logger.LogError(ex, "Alert action failed for filter {FilterName}", filter.Name);
        }
        finally
        {
            stopwatch.Stop();
            history.ExecutionDurationMs = stopwatch.ElapsedMilliseconds;

            // Store sample entry IDs
            if (result.Items.Any())
            {
                history.SampleEntryIds = JsonSerializer.Serialize(result.Items.Take(10).Select(e => e.Id));
            }

            context.AlertHistories.Add(history);
        }
    }

    private async Task<string> ExecuteWebhook(AlertConfig config, SavedFilter filter, PagedResult<LogEntry> result, CancellationToken cancellationToken)
    {
        using var httpClient = new HttpClient();
        httpClient.Timeout = TimeSpan.FromSeconds(30);

        // Build the payload
        var payload = BuildAlertPayload(config, filter, result);
        var content = new StringContent(payload, Encoding.UTF8, "application/json");

        // Add custom headers
        foreach (var header in config.Headers)
        {
            content.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        HttpResponseMessage response;
        if (config.Method.Equals("GET", StringComparison.OrdinalIgnoreCase))
        {
            response = await httpClient.GetAsync(config.Endpoint, cancellationToken);
        }
        else
        {
            response = await httpClient.PostAsync(config.Endpoint, content, cancellationToken);
        }

        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Webhook returned {response.StatusCode}: {responseBody}");
        }

        return responseBody;
    }

    private async Task<string> ExecuteScript(AlertConfig config, SavedFilter filter, PagedResult<LogEntry> result, CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(config.Endpoint) || !File.Exists(config.Endpoint))
        {
            throw new FileNotFoundException($"Script not found: {config.Endpoint}");
        }

        var payload = BuildAlertPayload(config, filter, result);
        var tempFile = Path.GetTempFileName();
        await File.WriteAllTextAsync(tempFile, payload, cancellationToken);

        try
        {
            var arguments = string.Join(" ", config.ScriptArguments);
            arguments = $"-File \"{config.Endpoint}\" -PayloadFile \"{tempFile}\" {arguments}";

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = arguments,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(startInfo);
            if (process == null)
            {
                throw new InvalidOperationException("Failed to start PowerShell process");
            }

            var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
            var error = await process.StandardError.ReadToEndAsync(cancellationToken);

            await process.WaitForExitAsync(cancellationToken);

            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException($"Script exited with code {process.ExitCode}: {error}");
            }

            return output;
        }
        finally
        {
            if (File.Exists(tempFile))
            {
                File.Delete(tempFile);
            }
        }
    }

    private async Task<string> ExecuteServerMonitor(AlertConfig config, SavedFilter filter, PagedResult<LogEntry> result, CancellationToken cancellationToken)
    {
        // ServerMonitor API integration
        using var httpClient = new HttpClient();
        httpClient.Timeout = TimeSpan.FromSeconds(30);

        var alarmPayload = new
        {
            Source = "GenericLogHandler",
            AlertName = filter.Name,
            Severity = config.ServerMonitorSeverity,
            Message = $"Alert triggered: {result.TotalCount} matching log entries",
            Details = result.Items.Take(5).Select(e => new { e.Timestamp, e.Level, e.ComputerName, e.Message }).ToList()
        };

        var content = new StringContent(JsonSerializer.Serialize(alarmPayload), Encoding.UTF8, "application/json");
        var response = await httpClient.PostAsync(config.Endpoint, content, cancellationToken);

        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private async Task<string> ExecuteEmail(AlertConfig config, SavedFilter filter, PagedResult<LogEntry> result, CancellationToken cancellationToken)
    {
        if (_emailService == null)
        {
            _logger.LogWarning("Email alert requested but SMTP is not configured. Recipients: {Recipients}", 
                string.Join(", ", config.EmailRecipients));
            return "Email not sent - SMTP not configured";
        }

        return await _emailService.SendAlertEmailAsync(config, filter, result, cancellationToken);
    }

    private string BuildAlertPayload(AlertConfig config, SavedFilter filter, PagedResult<LogEntry> result)
    {
        var entries = config.IncludeEntries ? result.Items.Take(config.MaxEntriesToInclude).Select(e => new
        {
            e.Id,
            e.Timestamp,
            Level = e.Level.ToString(),
            e.ComputerName,
            e.UserName,
            e.Message,
            e.ErrorId,
            e.Ordrenr,
            e.Avdnr,
            e.JobName
        }).ToList() : null;

        var payload = new
        {
            FilterId = filter.Id,
            FilterName = filter.Name,
            TriggeredAt = DateTime.UtcNow,
            MatchCount = result.TotalCount,
            Threshold = config.ThresholdCount,
            Entries = entries
        };

        if (!string.IsNullOrEmpty(config.BodyTemplate))
        {
            // Simple template replacement
            return config.BodyTemplate
                .Replace("{{filterName}}", filter.Name)
                .Replace("{{matchCount}}", result.TotalCount.ToString())
                .Replace("{{threshold}}", config.ThresholdCount.ToString())
                .Replace("{{triggeredAt}}", DateTime.UtcNow.ToString("o"))
                .Replace("{{entries}}", JsonSerializer.Serialize(entries));
        }

        return JsonSerializer.Serialize(payload);
    }
}

/// <summary>
/// Log search request model for deserializing saved filter JSON in the Alert Agent
/// </summary>
public class LogSearchRequest
{
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public List<string>? Levels { get; set; }
    public string? ComputerName { get; set; }
    public string? UserName { get; set; }
    public string? MessageText { get; set; }
    public string? ExceptionText { get; set; }
    public string? RegexPattern { get; set; }
    public string? FunctionName { get; set; }
    public string? SourceFile { get; set; }
    public string? SourceType { get; set; }
    public string? AlertId { get; set; }
    public string? Ordrenr { get; set; }
    public string? Avdnr { get; set; }
    public string? JobName { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 50;
    public string SortBy { get; set; } = "Timestamp";
    public bool SortDescending { get; set; } = true;
}
