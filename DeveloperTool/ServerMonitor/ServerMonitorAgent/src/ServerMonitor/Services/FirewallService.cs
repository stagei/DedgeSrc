using System.Diagnostics;
using System.Security.Principal;
using Microsoft.Extensions.Logging;

namespace ServerMonitor.Services;

/// <summary>
/// Manages Windows Firewall rules for the REST API
/// </summary>
public class FirewallService
{
    private readonly ILogger<FirewallService> _logger;

    public FirewallService(ILogger<FirewallService> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Checks if running with administrator privileges
    /// </summary>
    public bool IsAdmin()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to check admin privileges");
            return false;
        }
    }

    /// <summary>
    /// Checks if a port is open in the firewall (any rule allowing inbound TCP on this port)
    /// </summary>
    public bool IsPortOpen(int port)
    {
        try
        {
            // Check if any firewall rule allows inbound TCP traffic on this port
            var checkPort = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall show rule name=all dir=in type=allow protocol=TCP | findstr /C:\"LocalPort:\" /C:\"{port}\"",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var proc = Process.Start(checkPort))
            {
                if (proc != null)
                {
                    var output = proc.StandardOutput.ReadToEnd();
                    proc.WaitForExit();
                    
                    // Check if output contains the port number
                    if (output.Contains(port.ToString()))
                    {
                        _logger.LogDebug("Port {Port} is already open in firewall", port);
                        return true;
                    }
                }
            }
            
            // Also check using PowerShell Get-NetFirewallRule for more reliable detection
            try
            {
                var psCheck = new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = $"-Command \"Get-NetFirewallRule -Direction Inbound -Action Allow | Get-NetFirewallPortFilter | Where-Object {{ $_.LocalPort -eq {port} }} | Select-Object -First 1\"",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var proc = Process.Start(psCheck))
                {
                    if (proc != null)
                    {
                        var output = proc.StandardOutput.ReadToEnd();
                        proc.WaitForExit();
                        
                        if (!string.IsNullOrWhiteSpace(output) && output.Contains("LocalPort"))
                        {
                            _logger.LogDebug("Port {Port} is already open in firewall (verified via PowerShell)", port);
                            return true;
                        }
                    }
                }
            }
            catch
            {
                // PowerShell check failed, continue with netsh result
            }

            return false;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to check if port {Port} is open", port);
            return false; // Assume not open if check fails
        }
    }

    /// <summary>
    /// Creates firewall rule for the REST API port if running as admin and port is not open
    /// </summary>
    public bool ConfigureFirewallRule(int port, string ruleName = "ServerMonitorAPI")
    {
        // First check if port is already open
        if (IsPortOpen(port))
        {
            _logger.LogInformation("✅ Port {Port} is already open in firewall", port);
            return true;
        }

        if (!IsAdmin())
        {
            _logger.LogWarning("⚠️ Not running as administrator - cannot configure firewall rule");
            _logger.LogInformation("💡 To auto-configure firewall, run as administrator");
            _logger.LogInformation("💡 Manual command: netsh advfirewall firewall add rule name=\"{RuleName}\" dir=in action=allow protocol=TCP localport={Port} profile=any", ruleName, port);
            return false;
        }

        try
        {
            // Check if rule with this name already exists
            var checkRule = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall show rule name=\"{ruleName}\"",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var proc = Process.Start(checkRule))
            {
                proc?.WaitForExit();
                if (proc?.ExitCode == 0)
                {
                    _logger.LogInformation("✅ Firewall rule '{RuleName}' already exists", ruleName);
                    return true;
                }
            }

            // Create new firewall rule
            _logger.LogInformation("🔧 Port {Port} is not open - creating firewall rule '{RuleName}'...", port, ruleName);

            var createRule = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall add rule name=\"{ruleName}\" dir=in action=allow protocol=TCP localport={port} profile=any",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var proc = Process.Start(createRule))
            {
                if (proc != null)
                {
                    var output = proc.StandardOutput.ReadToEnd();
                    var error = proc.StandardError.ReadToEnd();
                    proc.WaitForExit();
                    
                    if (proc.ExitCode == 0)
                    {
                        _logger.LogInformation("✅ Firewall rule '{RuleName}' created successfully for port {Port}", ruleName, port);
                        
                        // Verify the port is now open
                        if (IsPortOpen(port))
                        {
                            _logger.LogInformation("✅ Verified: Port {Port} is now open in firewall", port);
                        }
                        else
                        {
                            _logger.LogWarning("⚠️ Firewall rule created but port {Port} verification failed - rule may need time to propagate", port);
                        }
                        
                        return true;
                    }
                    else
                    {
                        _logger.LogError("❌ Failed to create firewall rule. Exit code: {ExitCode}, Error: {Error}", proc.ExitCode, error);
                        return false;
                    }
                }
                else
                {
                    _logger.LogError("❌ Failed to start netsh process");
                    return false;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "❌ Exception while configuring firewall");
            return false;
        }
    }

    /// <summary>
    /// Removes the firewall rule (cleanup)
    /// </summary>
    public void RemoveFirewallRule(string ruleName = "ServerMonitorAPI")
    {
        if (!IsAdmin())
        {
            _logger.LogDebug("Not running as admin, skipping firewall rule removal");
            return;
        }

        try
        {
            var deleteRule = new ProcessStartInfo
            {
                FileName = "netsh",
                Arguments = $"advfirewall firewall delete rule name=\"{ruleName}\"",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var proc = Process.Start(deleteRule);
            proc?.WaitForExit();
            
            _logger.LogInformation("Firewall rule '{RuleName}' removed", ruleName);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to remove firewall rule");
        }
    }
}

