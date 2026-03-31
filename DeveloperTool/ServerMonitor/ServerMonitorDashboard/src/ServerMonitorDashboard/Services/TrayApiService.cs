using System.Text.Json;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Service for communicating with ServerMonitorTrayIcon REST API on port 8997.
/// This API allows direct control of the agent service on each server.
/// </summary>
public interface ITrayApiService
{
    /// <summary>Check if the tray app is running on the specified server.</summary>
    Task<TrayApiResponse<bool>> IsAliveAsync(string serverName, CancellationToken ct = default);
    
    /// <summary>Get detailed status of the tray app and agent.</summary>
    Task<TrayApiResponse<TrayStatus>> GetStatusAsync(string serverName, CancellationToken ct = default);
    
    /// <summary>Start the agent service.</summary>
    Task<TrayApiResponse<ActionResult>> StartAgentAsync(string serverName, CancellationToken ct = default);
    
    /// <summary>Stop the agent service.</summary>
    Task<TrayApiResponse<ActionResult>> StopAgentAsync(string serverName, CancellationToken ct = default);
    
    /// <summary>Restart the agent service.</summary>
    Task<TrayApiResponse<ActionResult>> RestartAgentAsync(string serverName, CancellationToken ct = default);
    
    /// <summary>Trigger agent reinstall from distribution source.</summary>
    Task<TrayApiResponse<ActionResult>> ReinstallAgentAsync(string serverName, CancellationToken ct = default);
}

public class TrayApiService : ITrayApiService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<TrayApiService> _logger;
    private const int TrayApiPort = 8997;
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

    public TrayApiService(IHttpClientFactory httpClientFactory, ILogger<TrayApiService> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    public async Task<TrayApiResponse<bool>> IsAliveAsync(string serverName, CancellationToken ct = default)
    {
        try
        {
            var url = BuildUrl(serverName, "/api/isalive");
            var client = CreateClient();
            
            var response = await client.GetAsync(url, ct);
            
            if (response.IsSuccessStatusCode)
            {
                return TrayApiResponse<bool>.Success(true);
            }
            
            return TrayApiResponse<bool>.Fail($"Tray app returned {(int)response.StatusCode}");
        }
        catch (HttpRequestException ex)
        {
            _logger.LogDebug("Tray API not reachable on {Server}: {Message}", serverName, ex.Message);
            return TrayApiResponse<bool>.Fail($"Tray app not reachable: {ex.Message}");
        }
        catch (TaskCanceledException)
        {
            return TrayApiResponse<bool>.Fail("Request timed out");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking tray API on {Server}", serverName);
            return TrayApiResponse<bool>.Fail(ex.Message);
        }
    }

    public async Task<TrayApiResponse<TrayStatus>> GetStatusAsync(string serverName, CancellationToken ct = default)
    {
        try
        {
            var url = BuildUrl(serverName, "/api/status");
            var client = CreateClient();
            
            var response = await client.GetAsync(url, ct);
            
            if (response.IsSuccessStatusCode)
            {
                var json = await response.Content.ReadAsStringAsync(ct);
                var status = JsonSerializer.Deserialize<TrayStatus>(json, JsonOptions);
                return TrayApiResponse<TrayStatus>.Success(status ?? new TrayStatus());
            }
            
            return TrayApiResponse<TrayStatus>.Fail($"Status request failed: {(int)response.StatusCode}");
        }
        catch (HttpRequestException ex)
        {
            return TrayApiResponse<TrayStatus>.Fail($"Tray app not reachable: {ex.Message}");
        }
        catch (TaskCanceledException)
        {
            return TrayApiResponse<TrayStatus>.Fail("Request timed out");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting status from {Server}", serverName);
            return TrayApiResponse<TrayStatus>.Fail(ex.Message);
        }
    }

    public async Task<TrayApiResponse<ActionResult>> StartAgentAsync(string serverName, CancellationToken ct = default)
    {
        return await PostActionAsync(serverName, "/api/agent/start", "Start", ct);
    }

    public async Task<TrayApiResponse<ActionResult>> StopAgentAsync(string serverName, CancellationToken ct = default)
    {
        return await PostActionAsync(serverName, "/api/agent/stop", "Stop", ct);
    }

    public async Task<TrayApiResponse<ActionResult>> RestartAgentAsync(string serverName, CancellationToken ct = default)
    {
        return await PostActionAsync(serverName, "/api/agent/restart", "Restart", ct);
    }

    public async Task<TrayApiResponse<ActionResult>> ReinstallAgentAsync(string serverName, CancellationToken ct = default)
    {
        return await PostActionAsync(serverName, "/api/agent/reinstall", "Reinstall", ct);
    }

    private async Task<TrayApiResponse<ActionResult>> PostActionAsync(
        string serverName, 
        string endpoint, 
        string actionName,
        CancellationToken ct)
    {
        try
        {
            var url = BuildUrl(serverName, endpoint);
            var client = CreateClient();
            
            _logger.LogInformation("Sending {Action} command to {Server} via Tray API", actionName, serverName);
            
            var response = await client.PostAsync(url, null, ct);
            var json = await response.Content.ReadAsStringAsync(ct);
            
            if (response.IsSuccessStatusCode)
            {
                var result = JsonSerializer.Deserialize<ActionResult>(json, JsonOptions);
                _logger.LogInformation("{Action} on {Server}: {Success} - {Message}", 
                    actionName, serverName, result?.IsSuccess, result?.Message);
                return TrayApiResponse<ActionResult>.Success(result ?? new ActionResult { IsSuccess = true });
            }
            
            _logger.LogWarning("{Action} on {Server} failed with status {Status}", 
                actionName, serverName, (int)response.StatusCode);
            return TrayApiResponse<ActionResult>.Fail($"{actionName} failed: {(int)response.StatusCode}");
        }
        catch (HttpRequestException ex)
        {
            _logger.LogWarning("Tray API not reachable on {Server} for {Action}: {Message}", 
                serverName, actionName, ex.Message);
            return TrayApiResponse<ActionResult>.Fail($"Tray app not reachable: {ex.Message}");
        }
        catch (TaskCanceledException)
        {
            return TrayApiResponse<ActionResult>.Fail("Request timed out");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error executing {Action} on {Server}", actionName, serverName);
            return TrayApiResponse<ActionResult>.Fail(ex.Message);
        }
    }

    private HttpClient CreateClient()
    {
        var client = _httpClientFactory.CreateClient("TrayApi");
        client.Timeout = DefaultTimeout;
        return client;
    }

    private static string BuildUrl(string serverName, string path)
    {
        // Strip any domain suffix if present (e.g., "server.domain.com" -> "server")
        // Keep the full name for DNS resolution
        return $"http://{serverName}:{TrayApiPort}{path}";
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };
}

/// <summary>Response wrapper for Tray API calls.</summary>
public class TrayApiResponse<T>
{
    public bool IsSuccess { get; set; }
    public string? Error { get; set; }
    public T? Data { get; set; }

    public static TrayApiResponse<T> Success(T data) => new() { IsSuccess = true, Data = data };
    public static TrayApiResponse<T> Fail(string error) => new() { IsSuccess = false, Error = error };
}

/// <summary>Status information from the Tray API.</summary>
public class TrayStatus
{
    public TrayAppInfo? TrayApp { get; set; }
    public AgentInfo? Agent { get; set; }
}

public class TrayAppInfo
{
    public bool Running { get; set; }
    public string? Version { get; set; }
    public string? MachineName { get; set; }
}

public class AgentInfo
{
    public bool Running { get; set; }
    public string? Version { get; set; }
    public string? ServiceName { get; set; }
}

/// <summary>Action result from the Tray API.</summary>
public class ActionResult
{
    public bool IsSuccess { get; set; }
    public string? Message { get; set; }
}
