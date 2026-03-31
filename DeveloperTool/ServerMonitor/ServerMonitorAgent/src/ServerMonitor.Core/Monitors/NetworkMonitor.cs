using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors network connectivity to baseline hosts.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class NetworkMonitor : IMonitor
{
    private readonly ILogger<NetworkMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private readonly Dictionary<string, int> _consecutiveFailures = new();
    private MonitorResult? _currentState;

    public string Category => "Network";
    public bool IsEnabled => _config.CurrentValue.NetworkMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public NetworkMonitor(
        ILogger<NetworkMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;
    }

    public async Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var alerts = new List<Alert>();
        var networkData = new List<NetworkHostData>();

        try
        {
            if (!IsEnabled)
            {
                return new MonitorResult
                {
                    Category = Category,
                    Success = true,
                    ErrorMessage = "Monitor is disabled"
                };
            }

            var settings = _config.CurrentValue.NetworkMonitoring;

            foreach (var host in settings.BaselineHosts)
            {
                var hostData = await CheckHostAsync(host, cancellationToken);
                networkData.Add(hostData);

                // Track consecutive failures
                var key = host.Hostname;
                if (!_consecutiveFailures.ContainsKey(key))
                    _consecutiveFailures[key] = 0;

                if (!hostData.PingMs.HasValue || hostData.PacketLossPercent > 0)
                {
                    _consecutiveFailures[key]++;
                }
                else
                {
                    _consecutiveFailures[key] = 0;
                }

                var maxOccurrences = settings.Alerts.MaxOccurrences;
                var timeWindowMinutes = settings.Alerts.TimeWindowMinutes;
                
                // Check for alerts (using accumulator for deduplication/cooldown)
                if (_consecutiveFailures[key] >= host.Thresholds.ConsecutiveFailuresBeforeAlert)
                {
                    var alertKey = $"Network:{host.Hostname}:ConnectivityLost";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.ConnectivityLostSeverity, AlertSeverity.Critical),
                            Category = Category,
                            Message = $"Network connectivity lost to {host.Hostname}",
                            Details = $"Failed {_consecutiveFailures[key]} consecutive ping attempts to {host.Description}",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }
                else if (hostData.PingMs.HasValue && hostData.PingMs.Value > host.Thresholds.MaxPingMs)
                {
                    var alertKey = $"Network:{host.Hostname}:HighLatency";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.HighLatencySeverity, AlertSeverity.Warning),
                            Category = Category,
                            Message = $"High latency to {host.Hostname}: {hostData.PingMs.Value:F0}ms",
                            Details = $"Ping time of {hostData.PingMs.Value:F0}ms exceeds threshold of {host.Thresholds.MaxPingMs}ms",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }

                if (hostData.PacketLossPercent > host.Thresholds.MaxPacketLossPercent)
                {
                    var alertKey = $"Network:{host.Hostname}:PacketLoss";
                    
                    // Record occurrence in accumulator
                    _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                    
                    // Check if we should alert
                    if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                    {
                        alerts.Add(new Alert
                        {
                            Severity = ParseAlertSeverity(settings.Alerts.PacketLossSeverity, AlertSeverity.Warning),
                            Category = Category,
                            Message = $"Packet loss to {host.Hostname}: {hostData.PacketLossPercent:F1}%",
                            Details = $"Experiencing {hostData.PacketLossPercent:F1}% packet loss",
                            SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                        });
                        
                        _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                    }
                }

                // Check port status alerts
                foreach (var port in host.PortsToCheck)
                {
                    if (hostData.PortStatus.TryGetValue(port, out var status) && status != "Open")
                    {
                        var alertKey = $"Network:{host.Hostname}:Port{port}";
                        
                        // Record occurrence in accumulator
                        _alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                        
                        // Check if we should alert
                        if (_alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                        {
                            alerts.Add(new Alert
                            {
                                Severity = ParseAlertSeverity(settings.Alerts.PortUnreachableSeverity, AlertSeverity.Critical),
                                Category = Category,
                                Message = $"Port {port} unreachable on {host.Hostname}",
                                Details = $"TCP port {port} is {status} on {host.Description}",
                                SuppressedChannels = settings.SuppressedChannels ?? new List<string>()
                            });
                            
                            _alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                        }
                    }
                }
            }

            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = networkData,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting network metrics");
            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = false,
                ErrorMessage = ex.Message,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
    }

    private async Task<NetworkHostData> CheckHostAsync(BaselineHost host, CancellationToken cancellationToken)
    {
        var result = new NetworkHostData
        {
            Hostname = host.Hostname,
            ConsecutiveFailures = _consecutiveFailures.GetValueOrDefault(host.Hostname, 0)
        };

        try
        {
            // Perform ping check
            if (host.CheckPing)
            {
                var (pingTime, packetLoss) = await PingHostAsync(host.Hostname, cancellationToken);
                result.PingMs = pingTime;
                result.PacketLossPercent = packetLoss;
            }

            // Perform DNS resolution check
            if (host.CheckDns)
            {
                var dnsTime = await CheckDnsAsync(host.Hostname, cancellationToken);
                result.DnsResolutionMs = dnsTime;
            }

            // Check TCP ports
            foreach (var port in host.PortsToCheck)
            {
                var portStatus = await CheckPortAsync(host.Hostname, port, cancellationToken);
                result.PortStatus[port] = portStatus;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error checking host {Hostname}", host.Hostname);
        }

        return result;
    }

    private async Task<(double? pingTime, double packetLoss)> PingHostAsync(string hostname, CancellationToken cancellationToken)
    {
        try
        {
            using var ping = new Ping();
            const int attempts = 4;
            var successCount = 0;
            var totalTime = 0.0;

            for (int i = 0; i < attempts; i++)
            {
                var reply = await ping.SendPingAsync(hostname, 1000);
                if (reply.Status == IPStatus.Success)
                {
                    successCount++;
                    totalTime += reply.RoundtripTime;
                }

                if (i < attempts - 1)
                    await Task.Delay(250, cancellationToken);
            }

            var packetLoss = ((attempts - successCount) / (double)attempts) * 100;
            var avgPing = successCount > 0 ? totalTime / successCount : (double?)null;

            return (avgPing, packetLoss);
        }
        catch
        {
            return (null, 100);
        }
    }

    private async Task<double?> CheckDnsAsync(string hostname, CancellationToken cancellationToken)
    {
        try
        {
            var sw = Stopwatch.StartNew();
            var addresses = await System.Net.Dns.GetHostAddressesAsync(hostname, cancellationToken);
            sw.Stop();
            return addresses.Length > 0 ? sw.Elapsed.TotalMilliseconds : (double?)null;
        }
        catch
        {
            return null;
        }
    }

    private async Task<string> CheckPortAsync(string hostname, int port, CancellationToken cancellationToken)
    {
        try
        {
            using var client = new TcpClient();
            var connectTask = client.ConnectAsync(hostname, port);
            var timeoutTask = Task.Delay(5000, cancellationToken);

            var completedTask = await Task.WhenAny(connectTask, timeoutTask);

            if (completedTask == connectTask && client.Connected)
            {
                return "Open";
            }
            else
            {
                return "Closed";
            }
        }
        catch
        {
            return "Unreachable";
        }
    }
    
    private static AlertSeverity ParseAlertSeverity(string? severityString, AlertSeverity defaultValue)
    {
        if (string.IsNullOrWhiteSpace(severityString))
            return defaultValue;
            
        return severityString.ToLowerInvariant() switch
        {
            "informational" => AlertSeverity.Informational,
            "warning" => AlertSeverity.Warning,
            "critical" => AlertSeverity.Critical,
            _ => defaultValue
        };
    }
}

