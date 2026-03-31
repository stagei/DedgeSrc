using System.Diagnostics;
using System.ServiceProcess;

namespace ServerMonitorTrayIcon;

/// <summary>
/// Manages Windows service operations for the ServerMonitor service
/// </summary>
public class ServiceManager
{
    private readonly string _serviceName;
    private readonly TimeSpan _timeout = TimeSpan.FromSeconds(30);

    public ServiceManager(string serviceName)
    {
        _serviceName = serviceName;
    }

    /// <summary>
    /// Checks if the service is currently running
    /// </summary>
    public bool IsRunning()
    {
        try
        {
            using var sc = new ServiceController(_serviceName);
            return sc.Status == ServiceControllerStatus.Running;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Gets the current status of the service as a string
    /// </summary>
    public string GetStatus()
    {
        try
        {
            using var sc = new ServiceController(_serviceName);
            return sc.Status switch
            {
                ServiceControllerStatus.Running => "Running",
                ServiceControllerStatus.Stopped => "Stopped",
                ServiceControllerStatus.StartPending => "Starting...",
                ServiceControllerStatus.StopPending => "Stopping...",
                ServiceControllerStatus.Paused => "Paused",
                ServiceControllerStatus.PausePending => "Pausing...",
                ServiceControllerStatus.ContinuePending => "Resuming...",
                _ => "Unknown"
            };
        }
        catch (InvalidOperationException)
        {
            return "Not Installed";
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error getting service status: {ex.Message}");
            return "Error";
        }
    }

    /// <summary>
    /// Checks if the service is installed
    /// </summary>
    public bool IsInstalled()
    {
        try
        {
            using var sc = new ServiceController(_serviceName);
            _ = sc.Status; // This will throw if service doesn't exist
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Starts the service
    /// </summary>
    public bool StartService()
    {
        try
        {
            using var sc = new ServiceController(_serviceName);
            
            if (sc.Status == ServiceControllerStatus.Running)
            {
                return true; // Already running
            }
            
            if (sc.Status != ServiceControllerStatus.Stopped)
            {
                // Wait for it to stop first
                sc.WaitForStatus(ServiceControllerStatus.Stopped, _timeout);
            }
            
            sc.Start();
            sc.WaitForStatus(ServiceControllerStatus.Running, _timeout);
            
            return sc.Status == ServiceControllerStatus.Running;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error starting service: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Stops the service. If the service doesn't stop within the timeout, kills the process.
    /// </summary>
    /// <param name="forceKillOnTimeout">If true, kill the process if service doesn't stop in time</param>
    /// <returns>StopResult with success status and whether force kill was used</returns>
    public StopResult StopService(bool forceKillOnTimeout = true)
    {
        var result = new StopResult();
        
        try
        {
            using var sc = new ServiceController(_serviceName);
            
            if (sc.Status == ServiceControllerStatus.Stopped)
            {
                result.Success = true;
                return result; // Already stopped
            }
            
            if (sc.CanStop)
            {
                sc.Stop();
                
                try
                {
                    sc.WaitForStatus(ServiceControllerStatus.Stopped, _timeout);
                    result.Success = sc.Status == ServiceControllerStatus.Stopped;
                }
                catch (System.ServiceProcess.TimeoutException)
                {
                    Debug.WriteLine($"Service stop timed out after {_timeout.TotalSeconds}s");
                    
                    if (forceKillOnTimeout)
                    {
                        // Force kill the process
                        result.ForceKilled = KillServerMonitorProcesses();
                        result.Success = result.ForceKilled;
                        
                        if (result.ForceKilled)
                        {
                            Debug.WriteLine("Service process was force-killed after timeout");
                        }
                    }
                }
            }
            else
            {
                Debug.WriteLine("Service cannot be stopped (CanStop = false)");
                
                if (forceKillOnTimeout)
                {
                    result.ForceKilled = KillServerMonitorProcesses();
                    result.Success = result.ForceKilled;
                }
            }
            
            return result;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error stopping service: {ex.Message}");
            
            if (forceKillOnTimeout)
            {
                // Last resort: try to kill the process
                result.ForceKilled = KillServerMonitorProcesses();
                result.Success = result.ForceKilled;
                result.ErrorMessage = ex.Message;
            }
            
            return result;
        }
    }
    
    /// <summary>
    /// Kills all ServerMonitor processes
    /// </summary>
    /// <returns>True if any processes were killed or none were running</returns>
    private bool KillServerMonitorProcesses()
    {
        try
        {
            var processes = Process.GetProcessesByName("ServerMonitor");
            
            if (processes.Length == 0)
            {
                Debug.WriteLine("No ServerMonitor processes found to kill");
                return true; // Nothing to kill = success
            }
            
            Debug.WriteLine($"Killing {processes.Length} ServerMonitor process(es)...");
            
            foreach (var process in processes)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill();
                        process.WaitForExit(5000); // Wait up to 5 seconds for each process
                        Debug.WriteLine($"Killed ServerMonitor process PID {process.Id}");
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"Failed to kill process PID {process.Id}: {ex.Message}");
                }
                finally
                {
                    process.Dispose();
                }
            }
            
            // Verify all processes are gone
            var remaining = Process.GetProcessesByName("ServerMonitor");
            var allKilled = remaining.Length == 0;
            
            foreach (var p in remaining) p.Dispose();
            
            return allKilled;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error killing ServerMonitor processes: {ex.Message}");
            return false;
        }
    }
    
    /// <summary>
    /// Result of a stop operation
    /// </summary>
    public class StopResult
    {
        public bool Success { get; set; }
        public bool ForceKilled { get; set; }
        public string? ErrorMessage { get; set; }
    }

    /// <summary>
    /// Restarts the service
    /// </summary>
    public bool RestartService()
    {
        try
        {
            var stopResult = StopService();
            if (!stopResult.Success)
            {
                Debug.WriteLine("Failed to stop service during restart");
                return false;
            }
            
            // Brief pause between stop and start
            Thread.Sleep(1000);
            
            return StartService();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error restarting service: {ex.Message}");
            return false;
        }
    }
}
