using System.Net.Http.Json;
using System.Text.Json;

namespace MyApp;

/// <summary>
/// Fire-and-forget client for the GenericLogHandler ingest API.
/// Thread-safe — register as a singleton in DI.
///
/// Usage:
///   var client = new LogIngestClient("http://dedge-server/GenericLogHandler");
///   await client.SendAsync("Order processed", "INFO", "OrderService");
///   await client.SendAsync(new LogIngestEntry
///   {
///       Message  = "Import failed",
///       Level    = "ERROR",
///       Source   = "ImportJob",
///       JobName  = "NightlyImport",
///       JobStatus = "Failed",
///       ErrorId  = "ERR-9001"
///   });
/// </summary>
public class LogIngestClient : IDisposable
{
    private readonly HttpClient _http;
    private readonly string _singleUrl;
    private readonly string _batchUrl;

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    public LogIngestClient(string baseUrl)
    {
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        var url = baseUrl.TrimEnd('/');
        _singleUrl = $"{url}/api/Logs/ingest";
        _batchUrl  = $"{url}/api/Logs/ingest/batch";
    }

    /// <summary>
    /// Minimal log — message + level + source
    /// </summary>
    public Task SendAsync(string message, string level = "INFO", string? source = null)
        => SendAsync(new LogIngestEntry { Message = message, Level = level, Source = source });

    /// <summary>
    /// Full log entry with all optional fields
    /// </summary>
    public async Task SendAsync(LogIngestEntry entry)
    {
        try
        {
            using var response = await _http.PostAsJsonAsync(_singleUrl, entry, JsonOpts);
            // 202 Accepted = success, entry queued
        }
        catch
        {
            // Fire-and-forget: swallow network errors so logging never crashes the caller
        }
    }

    /// <summary>
    /// Send a batch of entries (up to 200 recommended)
    /// </summary>
    public async Task SendBatchAsync(IEnumerable<LogIngestEntry> entries)
    {
        try
        {
            using var response = await _http.PostAsJsonAsync(_batchUrl, entries, JsonOpts);
        }
        catch
        {
            // Fire-and-forget
        }
    }

    public void Dispose() => _http.Dispose();
}

/// <summary>
/// Log entry payload — only Message is required.
/// </summary>
public class LogIngestEntry
{
    public string Message { get; set; } = string.Empty;
    public string? Level { get; set; }
    public string? Source { get; set; }
    public DateTime? Timestamp { get; set; }
    public string? ComputerName { get; set; }
    public string? UserName { get; set; }
    public string? JobName { get; set; }
    public string? JobStatus { get; set; }
    public string? ErrorId { get; set; }
    public string? ExceptionType { get; set; }
    public string? StackTrace { get; set; }
    public string? FunctionName { get; set; }
    public string? Location { get; set; }
}


// ─────────────────────────────────────────────────────────────
// USAGE EXAMPLES
// ─────────────────────────────────────────────────────────────

// ── 1. Standalone console app ─────────────────────────────
//
// using var logger = new LogIngestClient("http://dedge-server/GenericLogHandler");
//
// await logger.SendAsync("Application started", "INFO", "MyConsoleApp");
// await logger.SendAsync("Processing 1,200 records", "INFO", "MyConsoleApp");
// await logger.SendAsync(new LogIngestEntry
// {
//     Message      = "Database connection lost",
//     Level        = "FATAL",
//     Source       = "MyConsoleApp",
//     ErrorId      = "DB-CONN-001",
//     ComputerName = Environment.MachineName
// });

// ── 2. ASP.NET Core DI registration ──────────────────────
//
// builder.Services.AddSingleton(new LogIngestClient(
//     builder.Configuration["GenericLogHandler:BaseUrl"]
//         ?? "http://dedge-server/GenericLogHandler"));
//
// Then inject into any service or controller:
//
// public class OrderService(LogIngestClient log)
// {
//     public async Task ProcessOrder(int orderId)
//     {
//         await log.SendAsync($"Processing order {orderId}", "INFO", "OrderService");
//         // ... do work ...
//         await log.SendAsync($"Order {orderId} completed", "INFO", "OrderService");
//     }
// }

// ── 3. Batch submission ──────────────────────────────────
//
// var entries = Enumerable.Range(1, 100).Select(i => new LogIngestEntry
// {
//     Message = $"Processed record {i}",
//     Level   = "INFO",
//     Source  = "BulkLoader"
// });
// await logger.SendBatchAsync(entries);
