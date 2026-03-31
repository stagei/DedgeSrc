using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Background service that polls all online servers for alerts and maintains
/// a summary of active alerts across the monitored infrastructure.
/// </summary>
public class AlertPollingService : BackgroundService
{
    private readonly ILogger<AlertPollingService> _logger;
    private readonly ServerStatusService _serverStatusService;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IOptionsMonitor<DashboardConfig> _configMonitor;

    // Active alerts per server
    private readonly ConcurrentDictionary<string, ServerAlertSummary> _activeAlerts = new();
    
    // Acknowledged servers (won't appear in active alerts until new alerts come in)
    private readonly ConcurrentDictionary<string, DateTime> _acknowledgedServers = new();
    
    private DateTime _lastPolled = DateTime.MinValue;

    public AlertPollingService(
        ILogger<AlertPollingService> logger,
        ServerStatusService serverStatusService,
        IHttpClientFactory httpClientFactory,
        IOptionsMonitor<DashboardConfig> configMonitor)
    {
        _logger = logger;
        _serverStatusService = serverStatusService;
        _httpClientFactory = httpClientFactory;
        _configMonitor = configMonitor;
    }

    private AlertPollingConfig Config => _configMonitor.CurrentValue.AlertPolling;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("AlertPollingService starting...");

        // Initial delay to let ServerStatusService initialize
        await Task.Delay(5000, stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (Config.Enabled)
                {
                    await PollAllServersForAlertsAsync(stoppingToken);
                }
                else
                {
                    _logger.LogDebug("Alert polling is disabled");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during alert polling");
            }

            var intervalSeconds = Math.Max(10, Config.PollingIntervalSeconds);
            await Task.Delay(TimeSpan.FromSeconds(intervalSeconds), stoppingToken);
        }
    }

    /// <summary>
    /// Poll all online servers for alerts
    /// </summary>
    private async Task PollAllServersForAlertsAsync(CancellationToken cancellationToken)
    {
        var serverStatus = _serverStatusService.GetAllServerStatus();
        var onlineServers = serverStatus.Servers
            .Where(s => s.Status == ServerStatus.Online)
            .ToList();

        if (onlineServers.Count == 0)
        {
            _logger.LogDebug("No online servers to poll for alerts");
            return;
        }

        // Filter by configured server patterns
        var patterns = Config.ServerNamePatterns ?? new List<string> { ".*" };
        var compiledPatterns = patterns
            .Select(p => new Regex(p, RegexOptions.IgnoreCase | RegexOptions.Compiled))
            .ToList();

        var matchingServers = onlineServers
            .Where(s => compiledPatterns.Any(p => p.IsMatch(s.Name)))
            .ToList();

        _logger.LogDebug("Polling {Count} servers for alerts (of {Total} online)", 
            matchingServers.Count, onlineServers.Count);

        // Poll each server in parallel
        var tasks = matchingServers.Select(async server =>
        {
            try
            {
                await PollServerForAlertsAsync(server.Name, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error polling {Server} for alerts", server.Name);
            }
        });

        await Task.WhenAll(tasks);
        _lastPolled = DateTime.UtcNow;

        var totalAlerts = _activeAlerts.Values.Sum(s => s.TotalCount);
        _logger.LogInformation("Alert poll complete: {ServersWithAlerts} servers with {TotalAlerts} alerts",
            _activeAlerts.Count, totalAlerts);
    }

    /// <summary>
    /// Poll a single server for alerts
    /// </summary>
    private async Task PollServerForAlertsAsync(string serverName, CancellationToken cancellationToken)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("ServerMonitor");
            client.Timeout = TimeSpan.FromSeconds(10);

            var port = _configMonitor.CurrentValue.ServerMonitorPort;
            var url = $"http://{serverName}:{port}/api/snapshot";

            var response = await client.GetAsync(url, cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogDebug("Failed to get snapshot from {Server}: {Status}", 
                    serverName, response.StatusCode);
                return;
            }

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            using var doc = JsonDocument.Parse(json);

            // Extract alerts from snapshot
            if (doc.RootElement.TryGetProperty("alerts", out var alertsElement) &&
                alertsElement.ValueKind == JsonValueKind.Array)
            {
                var alerts = alertsElement.EnumerateArray().ToList();
                
                if (alerts.Count == 0)
                {
                    // No alerts - remove from active alerts
                    _activeAlerts.TryRemove(serverName, out _);
                    return;
                }

                // Check if server was acknowledged
                if (_acknowledgedServers.TryGetValue(serverName, out var acknowledgedAt))
                {
                    // Only include alerts newer than acknowledgment
                    alerts = alerts.Where(a =>
                    {
                        if (a.TryGetProperty("timestamp", out var ts))
                        {
                            if (DateTime.TryParse(ts.GetString(), out var alertTime))
                            {
                                return alertTime.ToUniversalTime() > acknowledgedAt;
                            }
                        }
                        return true; // Include if we can't parse timestamp
                    }).ToList();

                    if (alerts.Count == 0)
                    {
                        // All alerts were before acknowledgment
                        _activeAlerts.TryRemove(serverName, out _);
                        return;
                    }
                }

                // Count by severity
                var summary = new ServerAlertSummary
                {
                    ServerName = serverName,
                    LastUpdated = DateTime.UtcNow
                };

                var minSeverity = GetSeverityPriority(Config.MinimumSeverity);
                DateTime? latestTimestamp = null;

                foreach (var alert in alerts)
                {
                    var severity = "Informational";
                    if (alert.TryGetProperty("severity", out var sevProp))
                    {
                        // Handle both string and numeric severity
                        if (sevProp.ValueKind == JsonValueKind.String)
                        {
                            severity = sevProp.GetString() ?? "Informational";
                        }
                        else if (sevProp.ValueKind == JsonValueKind.Number)
                        {
                            var sevNum = sevProp.GetInt32();
                            severity = sevNum switch
                            {
                                3 => "Critical",
                                2 => "Error",
                                1 => "Warning",
                                _ => "Informational"
                            };
                        }
                    }

                    // Filter by minimum severity
                    var alertPriority = GetSeverityPriority(severity);
                    if (alertPriority < minSeverity)
                    {
                        continue; // Skip alerts below minimum severity
                    }

                    // Count by severity
                    switch (severity.ToLowerInvariant())
                    {
                        case "critical":
                            summary.CriticalCount++;
                            break;
                        case "error":
                            summary.ErrorCount++;
                            break;
                        case "warning":
                            summary.WarningCount++;
                            break;
                        default:
                            summary.InformationalCount++;
                            break;
                    }

                    // Track latest timestamp
                    if (alert.TryGetProperty("timestamp", out var tsProp))
                    {
                        if (DateTime.TryParse(tsProp.GetString(), out var ts))
                        {
                            if (!latestTimestamp.HasValue || ts > latestTimestamp.Value)
                            {
                                latestTimestamp = ts;
                            }
                        }
                    }
                }

                summary.LatestAlertTimestamp = latestTimestamp;

                // Only add if there are alerts after filtering
                if (summary.TotalCount > 0)
                {
                    _activeAlerts[serverName] = summary;
                }
                else
                {
                    _activeAlerts.TryRemove(serverName, out _);
                }
            }
        }
        catch (TaskCanceledException)
        {
            _logger.LogDebug("Timeout polling {Server} for alerts", serverName);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error polling {Server} for alerts", serverName);
        }
    }

    /// <summary>
    /// Get severity priority (higher = more severe)
    /// </summary>
    private static int GetSeverityPriority(string severity)
    {
        return severity.ToLowerInvariant() switch
        {
            "critical" => 3,
            "error" => 2,
            "warning" => 1,
            "informational" or "info" => 0,
            _ => 0
        };
    }

    /// <summary>
    /// Get all active alerts
    /// </summary>
    public ActiveAlertsResponse GetActiveAlerts()
    {
        return new ActiveAlertsResponse
        {
            Servers = _activeAlerts.Values
                .OrderByDescending(s => s.CriticalCount)
                .ThenByDescending(s => s.WarningCount)
                .ThenByDescending(s => s.LatestAlertTimestamp)
                .ToList(),
            LastPolled = _lastPolled,
            PollingEnabled = Config.Enabled,
            PollingIntervalSeconds = Config.PollingIntervalSeconds,
            ProductionPatterns = Config.ProductionPatterns,
            ShowOnlyProductionDefault = Config.ShowOnlyProductionDefault
        };
    }

    /// <summary>
    /// Acknowledge alerts for a server (removes from active alerts until new alerts arrive)
    /// </summary>
    public bool AcknowledgeServer(string serverName)
    {
        _acknowledgedServers[serverName] = DateTime.UtcNow;
        var removed = _activeAlerts.TryRemove(serverName, out _);
        
        _logger.LogInformation("Acknowledged alerts for {Server}", serverName);
        return removed;
    }

    /// <summary>
    /// Get current alert polling configuration
    /// </summary>
    public AlertPollingConfig GetConfig()
    {
        return Config;
    }
}
