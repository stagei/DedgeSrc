using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using System.Threading.Channels;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// Server-Sent Events controller for real-time updates
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class EventsController : ControllerBase
{
    private readonly ILogger<EventsController> _logger;
    private static readonly Channel<ServerEvent> _eventChannel = Channel.CreateBounded<ServerEvent>(
        new BoundedChannelOptions(100)
        {
            FullMode = BoundedChannelFullMode.DropOldest
        });

    public EventsController(ILogger<EventsController> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// SSE stream endpoint for real-time updates
    /// </summary>
    [HttpGet("stream")]
    public async Task Stream(CancellationToken cancellationToken)
    {
        Response.Headers.Append("Content-Type", "text/event-stream");
        Response.Headers.Append("Cache-Control", "no-cache");
        Response.Headers.Append("Connection", "keep-alive");
        Response.Headers.Append("X-Accel-Buffering", "no");

        var clientId = Guid.NewGuid().ToString("N")[..8];
        _logger.LogInformation("SSE client connected: {ClientId}", clientId);

        try
        {
            // Send initial connection event
            await WriteEventAsync("connected", new { clientId, serverTime = DateTime.UtcNow });

            // Send heartbeat every 30 seconds to keep connection alive
            using var heartbeatTimer = new PeriodicTimer(TimeSpan.FromSeconds(30));
            
            while (!cancellationToken.IsCancellationRequested)
            {
                // Check for events with timeout
                using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
                using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken, timeoutCts.Token);

                try
                {
                    if (await _eventChannel.Reader.WaitToReadAsync(linkedCts.Token))
                    {
                        while (_eventChannel.Reader.TryRead(out var serverEvent))
                        {
                            await WriteEventAsync(serverEvent.Type, serverEvent.Data);
                        }
                    }
                }
                catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested)
                {
                    // Timeout - send heartbeat
                    await WriteEventAsync("heartbeat", new { timestamp = DateTime.UtcNow });
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "SSE stream error for client {ClientId}", clientId);
        }
        finally
        {
            _logger.LogInformation("SSE client disconnected: {ClientId}", clientId);
        }
    }

    /// <summary>
    /// Publish an event to all connected SSE clients
    /// </summary>
    public static async Task PublishEventAsync(string eventType, object data)
    {
        var serverEvent = new ServerEvent(eventType, data);
        await _eventChannel.Writer.WriteAsync(serverEvent);
    }

    /// <summary>
    /// Publish log imported event
    /// </summary>
    public static Task PublishLogImportedAsync(string sourceName, int count, DateTime timestamp)
        => PublishEventAsync("log-imported", new { sourceName, count, timestamp });

    /// <summary>
    /// Publish import status changed event
    /// </summary>
    public static Task PublishImportStatusChangedAsync(string sourceName, string status, string? filePath = null)
        => PublishEventAsync("import-status-changed", new { sourceName, status, filePath, timestamp = DateTime.UtcNow });

    /// <summary>
    /// Publish alert triggered event
    /// </summary>
    public static Task PublishAlertTriggeredAsync(string filterName, int matchCount, string? action = null)
        => PublishEventAsync("alert-triggered", new { filterName, matchCount, action, timestamp = DateTime.UtcNow });

    /// <summary>
    /// Publish service status changed event
    /// </summary>
    public static Task PublishServiceStatusChangedAsync(string serviceName, string status)
        => PublishEventAsync("service-status-changed", new { serviceName, status, timestamp = DateTime.UtcNow });

    /// <summary>
    /// Publish database stats updated event
    /// </summary>
    public static Task PublishDatabaseStatsAsync(double sizeGb, long entryCount)
        => PublishEventAsync("database-stats", new { sizeGb, entryCount, timestamp = DateTime.UtcNow });

    private async Task WriteEventAsync(string eventType, object data)
    {
        var json = JsonSerializer.Serialize(data, new JsonSerializerOptions 
        { 
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase 
        });
        
        var message = $"event: {eventType}\ndata: {json}\n\n";
        await Response.WriteAsync(message);
        await Response.Body.FlushAsync();
    }

    private record ServerEvent(string Type, object Data);
}
