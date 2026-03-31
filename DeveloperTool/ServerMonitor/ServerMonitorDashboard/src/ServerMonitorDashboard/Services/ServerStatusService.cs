using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Options;
using ServerMonitorDashboard.Models;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Background service that polls all servers to check if their agents are alive.
/// Supports Server-Sent Events (SSE) for live status updates.
/// </summary>
public class ServerStatusService : BackgroundService
{
    private readonly ILogger<ServerStatusService> _logger;
    private readonly ComputerInfoService _computerInfoService;
    private readonly VersionService _versionService;
    private readonly DashboardConfig _config;
    private readonly IHttpClientFactory _httpClientFactory;
    
    private readonly ConcurrentDictionary<string, ServerInfo> _serverStatus = new();
    private DateTime _lastRefresh = DateTime.MinValue;
    
    // SSE subscribers
    private readonly ConcurrentDictionary<Guid, Action<ServerStatusEvent>> _subscribers = new();

    public ServerStatusService(
        ILogger<ServerStatusService> logger,
        ComputerInfoService computerInfoService,
        VersionService versionService,
        IOptions<DashboardConfig> config,
        IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _computerInfoService = computerInfoService;
        _versionService = versionService;
        _config = config.Value;
        _httpClientFactory = httpClientFactory;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("ServerStatusService starting...");

        // Initial delay to let the app start
        await Task.Delay(2000, stoppingToken);
        
        // Initialize all servers as Unknown
        await InitializeServerStatusAsync();

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RefreshAllServerStatusAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during server status refresh");
            }

            await Task.Delay(TimeSpan.FromSeconds(_config.StatusPollIntervalSeconds), stoppingToken);
        }
    }

    /// <summary>
    /// Initialize all servers with Unknown status
    /// </summary>
    private async Task InitializeServerStatusAsync()
    {
        var servers = await _computerInfoService.GetServersAsync();
        foreach (var server in servers)
        {
            var serverInfo = new ServerInfo
            {
                Name = server.Name!,
                DisplayName = server.DisplayName ?? server.Name,
                Type = server.Type,
                IpAddress = server.IpAddress,
                Status = ServerStatus.Unknown,
                IsAlive = false
            };
            _serverStatus[server.Name!] = serverInfo;
        }
        
        // Notify subscribers of initial state
        NotifySubscribers(new ServerStatusEvent { Type = "init", Servers = GetAllServerStatus().Servers });
    }

    /// <summary>
    /// Refreshes status for all servers
    /// </summary>
    public async Task RefreshAllServerStatusAsync()
    {
        var servers = await _computerInfoService.GetServersAsync();
        
        _logger.LogDebug("Refreshing status for {Count} servers", servers.Count);

        // Mark all as "Checking" first and notify
        foreach (var server in servers)
        {
            if (_serverStatus.TryGetValue(server.Name!, out var existing))
            {
                existing.Status = ServerStatus.Checking;
                NotifySubscribers(new ServerStatusEvent 
                { 
                    Type = "checking", 
                    ServerName = server.Name!,
                    Server = existing 
                });
            }
        }

        // Check each server in parallel
        var tasks = servers.Select(async server =>
        {
            var status = await CheckServerStatusAsync(server);
            var previousStatus = _serverStatus.TryGetValue(server.Name!, out var prev) ? prev.Status : ServerStatus.Unknown;
            _serverStatus[server.Name!] = status;
            
            // Notify if status changed
            if (status.Status != previousStatus || previousStatus == ServerStatus.Checking)
            {
                NotifySubscribers(new ServerStatusEvent 
                { 
                    Type = "status", 
                    ServerName = server.Name!,
                    Server = status 
                });
            }
        });

        await Task.WhenAll(tasks);
        _lastRefresh = DateTime.UtcNow;

        var online = _serverStatus.Values.Count(s => s.IsAlive);
        _logger.LogInformation("Server status refresh complete: {Online}/{Total} online", online, servers.Count);
    }

    /// <summary>
    /// Checks if a single server's agent is alive
    /// </summary>
    private async Task<ServerInfo> CheckServerStatusAsync(ComputerInfo computer)
    {
        var serverInfo = new ServerInfo
        {
            Name = computer.Name!,
            DisplayName = computer.DisplayName ?? computer.Name,
            Type = computer.Type,
            IpAddress = computer.IpAddress,
            LastChecked = DateTime.UtcNow,
            Status = ServerStatus.Checking
        };

        try
        {
            var client = _httpClientFactory.CreateClient("ServerMonitor");
            client.Timeout = TimeSpan.FromSeconds(_config.SnapshotTimeoutSeconds);

            var stopwatch = Stopwatch.StartNew();
            var url = $"http://{computer.Name}:{_config.ServerMonitorPort}/api/Health/IsAlive";
            
            var response = await client.GetAsync(url);
            stopwatch.Stop();

            serverInfo.IsAlive = response.IsSuccessStatusCode;
            serverInfo.Status = response.IsSuccessStatusCode ? ServerStatus.Online : ServerStatus.Offline;
            serverInfo.ResponseTimeMs = stopwatch.ElapsedMilliseconds;

            if (serverInfo.IsAlive)
            {
                _logger.LogDebug("{Server} is alive ({Ms}ms)", computer.Name, stopwatch.ElapsedMilliseconds);
            }
        }
        catch (TaskCanceledException)
        {
            serverInfo.IsAlive = false;
            serverInfo.Status = ServerStatus.Offline;
            serverInfo.Error = "Connection timeout";
            _logger.LogDebug("{Server} timeout", computer.Name);
        }
        catch (HttpRequestException ex)
        {
            serverInfo.IsAlive = false;
            serverInfo.Status = ServerStatus.Offline;
            serverInfo.Error = ex.Message;
            _logger.LogDebug("{Server} unreachable: {Error}", computer.Name, ex.Message);
        }
        catch (Exception ex)
        {
            serverInfo.IsAlive = false;
            serverInfo.Status = ServerStatus.Offline;
            serverInfo.Error = ex.Message;
            _logger.LogDebug("{Server} error: {Error}", computer.Name, ex.Message);
        }

        return serverInfo;
    }

    /// <summary>
    /// Gets all server statuses
    /// </summary>
    public ServersResponse GetAllServerStatus()
    {
        return new ServersResponse
        {
            Servers = _serverStatus.Values.OrderBy(s => s.Name).ToList(),
            LastRefreshed = _lastRefresh,
            CurrentAgentVersion = _versionService.GetCurrentVersion()
        };
    }

    /// <summary>
    /// Gets status for a specific server
    /// </summary>
    public ServerInfo? GetServerStatus(string serverName)
    {
        _serverStatus.TryGetValue(serverName, out var status);
        return status;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // Server-Sent Events (SSE) Support for Live Updates
    // ═══════════════════════════════════════════════════════════════════════════════
    
    /// <summary>
    /// Subscribe to server status updates
    /// </summary>
    public Guid Subscribe(Action<ServerStatusEvent> callback)
    {
        var id = Guid.NewGuid();
        _subscribers[id] = callback;
        _logger.LogDebug("SSE subscriber added: {Id} (total: {Count})", id, _subscribers.Count);
        return id;
    }
    
    /// <summary>
    /// Unsubscribe from server status updates
    /// </summary>
    public void Unsubscribe(Guid id)
    {
        _subscribers.TryRemove(id, out _);
        _logger.LogDebug("SSE subscriber removed: {Id} (remaining: {Count})", id, _subscribers.Count);
    }
    
    /// <summary>
    /// Notify all subscribers of a status change
    /// </summary>
    private void NotifySubscribers(ServerStatusEvent evt)
    {
        foreach (var subscriber in _subscribers.Values)
        {
            try
            {
                subscriber(evt);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error notifying SSE subscriber");
            }
        }
    }
}

/// <summary>
/// Event sent to SSE subscribers when server status changes
/// </summary>
public class ServerStatusEvent
{
    /// <summary>Type: init, checking, status</summary>
    public string Type { get; set; } = "status";
    /// <summary>Server name (null for init)</summary>
    public string? ServerName { get; set; }
    /// <summary>Single server info (for status/checking)</summary>
    public ServerInfo? Server { get; set; }
    /// <summary>All servers (for init)</summary>
    public List<ServerInfo>? Servers { get; set; }
}
