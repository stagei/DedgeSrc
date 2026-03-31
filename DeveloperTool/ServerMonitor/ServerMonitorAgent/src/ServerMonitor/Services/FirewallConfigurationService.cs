using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Services;

/// <summary>
/// Hosted service that automatically configures firewall rules for the REST API port
/// Runs once at startup to ensure the port is open
/// </summary>
public class FirewallConfigurationService : IHostedService
{
    private readonly ILogger<FirewallConfigurationService> _logger;
    private readonly FirewallService _firewallService;
    private readonly int _port;

    public FirewallConfigurationService(
        ILogger<FirewallConfigurationService> logger,
        FirewallService firewallService,
        int port)
    {
        _logger = logger;
        _firewallService = firewallService;
        _port = port;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("🔧 Checking firewall configuration for port {Port}...", _port);
        
        try
        {
            // Automatically configure firewall if port is not open
            var configured = _firewallService.ConfigureFirewallRule(_port);
            
            if (configured)
            {
                _logger.LogInformation("✅ Firewall configuration completed for port {Port}", _port);
            }
            else
            {
                _logger.LogWarning("⚠️ Firewall configuration failed or skipped for port {Port}", _port);
                _logger.LogInformation("💡 If the REST API is not accessible, ensure port {Port} is open in Windows Firewall", _port);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "❌ Error during firewall configuration for port {Port}", _port);
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        // No cleanup needed - firewall rule should remain
        return Task.CompletedTask;
    }
}

