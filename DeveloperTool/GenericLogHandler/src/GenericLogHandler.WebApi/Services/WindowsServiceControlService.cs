using System.ComponentModel;
using System.ServiceProcess;

namespace GenericLogHandler.WebApi.Services;

/// <summary>
/// Wraps Windows ServiceController for querying and controlling the Import Service and Alert Agent.
/// Requires the Web API process to run with permissions to start/stop these services (e.g. LocalSystem or account with SC_MANAGER and SERVICE_START/SERVICE_STOP).
/// </summary>
public sealed class WindowsServiceControlService : IWindowsServiceControlService
{
    public const string ImportServiceWindowsName = "GenericLogHandler-ImportService";
    public const string AlertAgentWindowsName = "GenericLogHandler-AlertAgent";

    public string ImportServiceName => ImportServiceWindowsName;
    public string AlertAgentServiceName => AlertAgentWindowsName;

    public ServiceStatusDto GetServiceStatus(string serviceName)
    {
        if (!OperatingSystem.IsWindows())
        {
            return new ServiceStatusDto
            {
                Name = serviceName,
                Status = "Unavailable",
                Message = "Service control is only supported on Windows."
            };
        }

        try
        {
            using var sc = new ServiceController(serviceName);
            sc.Refresh();
            return new ServiceStatusDto
            {
                Name = serviceName,
                Status = sc.Status.ToString(),
                DisplayName = sc.DisplayName,
                Message = null
            };
        }
        catch (InvalidOperationException ex)
        {
            return new ServiceStatusDto
            {
                Name = serviceName,
                Status = "NotFound",
                Message = ex.Message
            };
        }
        catch (Exception ex)
        {
            return new ServiceStatusDto
            {
                Name = serviceName,
                Status = "Error",
                Message = ex.Message
            };
        }
    }

    public ServiceActionResult StartService(string serviceName)
    {
        if (!OperatingSystem.IsWindows())
        {
            return new ServiceActionResult
            {
                Success = false,
                Message = "Service control is only supported on Windows.",
                IsUnsupported = true
            };
        }

        try
        {
            using var sc = new ServiceController(serviceName);
            sc.Refresh();
            if (sc.Status == ServiceControllerStatus.Running)
                return new ServiceActionResult { Success = true, Message = "Service is already running." };
            sc.Start();
            sc.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
            return new ServiceActionResult { Success = true, Message = "Service started." };
        }
        catch (InvalidOperationException ex)
        {
            return new ServiceActionResult
            {
                Success = false,
                Message = ex.Message,
                IsNotFound = true
            };
        }
        catch (Win32Exception ex)
        {
            var isAccessDenied = ex.NativeErrorCode == 5; // ERROR_ACCESS_DENIED
            return new ServiceActionResult
            {
                Success = false,
                Message = ex.Message,
                IsAccessDenied = isAccessDenied
            };
        }
        catch (System.ServiceProcess.TimeoutException)
        {
            return new ServiceActionResult
            {
                Success = false,
                Message = "Service did not start within the timeout period."
            };
        }
        catch (Exception ex)
        {
            var isAccessDenied = ex is UnauthorizedAccessException ||
                (ex.InnerException is Win32Exception win32 && win32.NativeErrorCode == 5);
            return new ServiceActionResult
            {
                Success = false,
                Message = ex.Message,
                IsAccessDenied = isAccessDenied
            };
        }
    }

    public ServiceActionResult StopService(string serviceName)
    {
        if (!OperatingSystem.IsWindows())
        {
            return new ServiceActionResult
            {
                Success = false,
                Message = "Service control is only supported on Windows.",
                IsUnsupported = true
            };
        }

        try
        {
            using var sc = new ServiceController(serviceName);
            sc.Refresh();
            if (sc.Status == ServiceControllerStatus.Stopped)
                return new ServiceActionResult { Success = true, Message = "Service is already stopped." };
            sc.Stop();
            sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(30));
            return new ServiceActionResult { Success = true, Message = "Service stopped." };
        }
        catch (InvalidOperationException ex)
        {
            return new ServiceActionResult
            {
                Success = false,
                Message = ex.Message,
                IsNotFound = true
            };
        }
        catch (Win32Exception ex)
        {
            var isAccessDenied = ex.NativeErrorCode == 5; // ERROR_ACCESS_DENIED
            return new ServiceActionResult
            {
                Success = false,
                Message = ex.Message,
                IsAccessDenied = isAccessDenied
            };
        }
        catch (System.ServiceProcess.TimeoutException)
        {
            return new ServiceActionResult
            {
                Success = false,
                Message = "Service did not stop within the timeout period."
            };
        }
        catch (Exception ex)
        {
            var isAccessDenied = ex is UnauthorizedAccessException ||
                (ex.InnerException is Win32Exception win32 && win32.NativeErrorCode == 5);
            return new ServiceActionResult
            {
                Success = false,
                Message = ex.Message,
                IsAccessDenied = isAccessDenied
            };
        }
    }
}

/// <summary>
/// DTO for a single Windows service status
/// </summary>
public class ServiceStatusDto
{
    public string Name { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string? DisplayName { get; set; }
    public string? Message { get; set; }
}

/// <summary>
/// Combined status of Import Service and Alert Agent
/// </summary>
public class ServicesStatusDto
{
    public ServiceStatusDto Import { get; set; } = new();
    public ServiceStatusDto Agent { get; set; } = new();
}

/// <summary>
/// Result of a start/stop service action (API response DTO)
/// </summary>
public class ServiceActionDto
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
}
