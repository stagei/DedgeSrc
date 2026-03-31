using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;

namespace ServerMonitor.Services;

/// <summary>
/// Logs REST API and OpenAPI/Scalar URLs on startup
/// </summary>
public class RestApiStartupLogger : IHostedService
{
    private readonly ILogger<RestApiStartupLogger> _logger;
    private readonly IConfiguration _configuration;

    public RestApiStartupLogger(
        ILogger<RestApiStartupLogger> logger,
        IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        var apiConfig = _configuration.GetSection("RestApi");
        var enabled = apiConfig.GetValue<bool>("Enabled");
        var port = apiConfig.GetValue<int>("Port", 5000);
        var enableSwagger = apiConfig.GetValue<bool>("EnableSwagger", true);

        if (enabled)
        {
            var baseUrl = $"http://localhost:{port}";

            _logger.LogInformation("══════════════════════════════════════════════════════");
            _logger.LogInformation("  🌐 REST API STARTED");
            _logger.LogInformation("══════════════════════════════════════════════════════");
            _logger.LogInformation("");
            _logger.LogInformation("📡 Base URL: {BaseUrl}", baseUrl);
            _logger.LogInformation("");

            if (enableSwagger)
            {
                _logger.LogInformation("📚 API Docs (Scalar): {ScalarUrl}", $"{baseUrl}/scalar/v1");
                _logger.LogInformation("📄 OpenAPI Spec: {SpecUrl}", $"{baseUrl}/openapi/v1.json");
                _logger.LogInformation("");
            }

            _logger.LogInformation("🔗 API Endpoints:");
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot           - Full system snapshot (live)", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/CachedSnapshot     - Cached snapshot (faster)", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/health    - Health summary", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/alerts    - All alerts", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/processor - CPU data", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/memory    - Memory data", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/disks     - Disk data", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/network   - Network data", baseUrl);
            _logger.LogInformation("   GET {BaseUrl}/api/snapshot/updates   - Windows updates", baseUrl);
            _logger.LogInformation("");
            _logger.LogInformation("💡 TIP: Open {ScalarUrl} in your browser for interactive API documentation!", $"{baseUrl}/scalar/v1");
            _logger.LogInformation("══════════════════════════════════════════════════════");
        }
        else
        {
            _logger.LogInformation("REST API is disabled in configuration");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}

