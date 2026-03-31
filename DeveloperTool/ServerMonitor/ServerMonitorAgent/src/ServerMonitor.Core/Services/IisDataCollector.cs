using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Extensions.Logging;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Utilities;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Collects IIS site, application pool, and worker process data using Microsoft.Web.Administration.
/// Loads the IIS management DLL dynamically so the agent still runs on servers without IIS.
/// </summary>
public class IisDataCollector
{
    private readonly ILogger<IisDataCollector> _logger;
    private static Assembly? _iisAssembly;
    private static bool _iisAvailable;
    private static bool _iisChecked;
    private static readonly object _initLock = new();

    private const string IisDllPath = @"C:\Windows\System32\inetsrv\Microsoft.Web.Administration.dll";

    public IisDataCollector(ILogger<IisDataCollector> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Check whether IIS is installed on this machine (DLL exists and loads).
    /// </summary>
    public bool IsIisInstalled()
    {
        EnsureInitialized();
        return _iisAvailable;
    }

    /// <summary>
    /// Collect a full IIS snapshot: sites, app pools, worker processes.
    /// Returns a snapshot with IsActive = false if IIS is not installed.
    /// </summary>
    public IisSnapshot Collect()
    {
        if (!IsIisInstalled())
        {
            return new IisSnapshot
            {
                IsActive = false,
                InactiveReason = "IIS is not installed on this server"
            };
        }

        try
        {
            return CollectViaServerManager();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to collect IIS data");
            return new IisSnapshot
            {
                IsActive = true,
                Error = $"Collection failed: {ex.Message}"
            };
        }
    }

    private IisSnapshot CollectViaServerManager()
    {
        // Use reflection to call ServerManager since we load the DLL dynamically
        var smType = _iisAssembly!.GetType("Microsoft.Web.Administration.ServerManager")!;
        using var serverManager = (IDisposable)Activator.CreateInstance(smType)!;

        var snapshot = new IisSnapshot
        {
            IsActive = true,
            CollectedAt = DateTime.UtcNow
        };

        // Get IIS version from registry
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\InetStp");
            if (key != null)
            {
                var major = key.GetValue("MajorVersion")?.ToString() ?? "?";
                var minor = key.GetValue("MinorVersion")?.ToString() ?? "?";
                snapshot.IisVersion = $"{major}.{minor}";
            }
        }
        catch { /* Version detection is optional */ }

        // Collect sites
        var sitesProperty = smType.GetProperty("Sites")!;
        var sites = (System.Collections.IEnumerable)sitesProperty.GetValue(serverManager)!;

        foreach (var site in sites)
        {
            snapshot.Sites.Add(CollectSiteInfo(site));
        }

        // Collect application pools
        var poolsProperty = smType.GetProperty("ApplicationPools")!;
        var pools = (System.Collections.IEnumerable)poolsProperty.GetValue(serverManager)!;

        foreach (var pool in pools)
        {
            snapshot.AppPools.Add(CollectAppPoolInfo(pool));
        }

        return snapshot;
    }

    private IisSiteInfo CollectSiteInfo(object site)
    {
        var siteType = site.GetType();
        var name = GetPropertyValue<string>(site, "Name") ?? "";
        var id = GetPropertyValue<long>(site, "Id");
        var state = GetEnumString(site, "State");
        var bindings = CollectBindings(site);

        var rootPhysicalPath = "";
        var rootAppPoolName = "";
        var virtualApps = new List<IisVirtualAppInfo>();

        var appsProperty = siteType.GetProperty("Applications");
        if (appsProperty != null)
        {
            var apps = (System.Collections.IEnumerable)appsProperty.GetValue(site)!;
            foreach (var app in apps)
            {
                var appPath = GetPropertyValue<string>(app, "Path") ?? "/";
                var appPoolName = GetPropertyValue<string>(app, "ApplicationPoolName") ?? "";
                var enabledProtocols = GetPropertyValue<string>(app, "EnabledProtocols") ?? "http";

                var physicalPath = "";
                var vdirsProperty = app.GetType().GetProperty("VirtualDirectories");
                if (vdirsProperty != null)
                {
                    var vdirs = (System.Collections.IEnumerable)vdirsProperty.GetValue(app)!;
                    foreach (var vdir in vdirs)
                    {
                        physicalPath = GetPropertyValue<string>(vdir, "PhysicalPath") ?? "";
                        break;
                    }
                }

                if (appPath == "/")
                {
                    rootPhysicalPath = physicalPath;
                    rootAppPoolName = appPoolName;
                }
                else
                {
                    virtualApps.Add(EnrichAppInfo(appPath, physicalPath, appPoolName, enabledProtocols));
                }
            }
        }

        return new IisSiteInfo
        {
            Name = name,
            Id = id,
            State = state,
            Bindings = bindings,
            PhysicalPath = rootPhysicalPath,
            PhysicalPathUnc = PathHelper.ToUncPath(rootPhysicalPath),
            AppPoolName = rootAppPoolName,
            VirtualApps = virtualApps
        };
    }

    private List<IisBindingInfo> CollectBindings(object site)
    {
        var result = new List<IisBindingInfo>();
        var bindingsProperty = site.GetType().GetProperty("Bindings");
        if (bindingsProperty == null) return result;

        var bindings = (System.Collections.IEnumerable)bindingsProperty.GetValue(site)!;
        foreach (var binding in bindings)
        {
            var protocol = GetPropertyValue<string>(binding, "Protocol") ?? "http";
            var bindingInfo = GetPropertyValue<string>(binding, "BindingInformation") ?? "";

            // Parse binding information (format: "IP:Port:Host" e.g. "*:80:" or "*:443:myhost")
            var parts = bindingInfo.Split(':');
            var port = 80;
            var host = "";
            if (parts.Length >= 2 && int.TryParse(parts[1], out var parsedPort))
                port = parsedPort;
            if (parts.Length >= 3)
                host = parts[2];

            result.Add(new IisBindingInfo
            {
                Protocol = protocol,
                Host = host,
                Port = port,
                BindingInformation = bindingInfo
            });
        }

        return result;
    }

    private IisAppPoolInfo CollectAppPoolInfo(object pool)
    {
        var poolType = pool.GetType();
        var name = GetPropertyValue<string>(pool, "Name") ?? "";
        var state = GetEnumString(pool, "State");
        var autoStart = GetPropertyValue<bool>(pool, "AutoStart");
        var enable32Bit = GetPropertyValue<bool>(pool, "Enable32BitAppOnWin64");
        var managedRuntime = GetPropertyValue<string>(pool, "ManagedRuntimeVersion") ?? "";
        var pipelineMode = GetEnumString(pool, "ManagedPipelineMode");

        // Process model settings
        var identityType = "";
        string? identityUsername = null;
        var processModelProp = poolType.GetProperty("ProcessModel");
        if (processModelProp != null)
        {
            var processModel = processModelProp.GetValue(pool);
            if (processModel != null)
            {
                identityType = GetEnumString(processModel, "IdentityType");
                identityUsername = GetPropertyValue<string>(processModel, "UserName");
                if (string.IsNullOrEmpty(identityUsername)) identityUsername = null;
            }
        }

        // Recycling settings
        long privateMemoryLimit = 0;
        long recycleInterval = 0;
        var recyclingProp = poolType.GetProperty("Recycling");
        if (recyclingProp != null)
        {
            var recycling = recyclingProp.GetValue(pool);
            if (recycling != null)
            {
                var periodicRestartProp = recycling.GetType().GetProperty("PeriodicRestart");
                if (periodicRestartProp != null)
                {
                    var periodicRestart = periodicRestartProp.GetValue(recycling);
                    if (periodicRestart != null)
                    {
                        privateMemoryLimit = GetPropertyValue<long>(periodicRestart, "PrivateMemory");
                        var timeSpan = GetPropertyValue<TimeSpan>(periodicRestart, "Time");
                        recycleInterval = (long)timeSpan.TotalMinutes;
                    }
                }
            }
        }

        // CPU settings
        long cpuLimit = 0;
        var cpuProp = poolType.GetProperty("Cpu");
        if (cpuProp != null)
        {
            var cpu = cpuProp.GetValue(pool);
            if (cpu != null)
            {
                cpuLimit = GetPropertyValue<long>(cpu, "Limit");
            }
        }

        // Worker processes
        var workerProcesses = new List<IisWorkerProcessInfo>();
        try
        {
            var wpProperty = poolType.GetProperty("WorkerProcesses");
            if (wpProperty != null)
            {
                var wps = (System.Collections.IEnumerable)wpProperty.GetValue(pool)!;
                foreach (var wp in wps)
                {
                    var pid = GetPropertyValue<int>(wp, "ProcessId");
                    var wpState = GetEnumString(wp, "State");

                    double memoryMB = 0;
                    DateTime? startTime = null;
                    try
                    {
                        var proc = Process.GetProcessById(pid);
                        memoryMB = proc.PrivateMemorySize64 / (1024.0 * 1024.0);
                        startTime = proc.StartTime.ToUniversalTime();
                    }
                    catch { /* Process may have exited */ }

                    workerProcesses.Add(new IisWorkerProcessInfo
                    {
                        ProcessId = pid,
                        State = wpState,
                        AppPoolName = name,
                        PrivateMemoryMB = Math.Round(memoryMB, 1),
                        StartTime = startTime
                    });
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not enumerate worker processes for pool {PoolName}", name);
        }

        return new IisAppPoolInfo
        {
            Name = name,
            State = state,
            ManagedRuntimeVersion = managedRuntime,
            PipelineMode = pipelineMode,
            IdentityType = identityType,
            IdentityUsername = identityUsername,
            AutoStart = autoStart,
            Enable32BitAppOnWin64 = enable32Bit,
            CpuLimit = cpuLimit,
            PrivateMemoryLimitKB = privateMemoryLimit,
            RecyclingTimeIntervalMinutes = recycleInterval,
            WorkerProcesses = workerProcesses
        };
    }

    // Regex: match %OptPath% env var placeholder (case-insensitive)
    private static readonly Regex OptPathEnvVarPattern = new(
        @"%OptPath%", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Regex: match X:\opt\ or X:\opt at end (any drive letter)
    // ^[A-Za-z]   - Drive letter
    // :            - Colon
    // \\           - Backslash
    // opt          - Literal "opt"
    // (?=\\|$)     - Followed by backslash or end-of-string
    private static readonly Regex DriveOptPattern = new(
        @"^[A-Za-z]:\\opt(?=\\|$)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private IisVirtualAppInfo EnrichAppInfo(string appPath, string physicalPath, string appPoolName, string enabledProtocols)
    {
        var physicalPathUnc = PathHelper.ToUncPath(physicalPath);
        var isAspNetCore = false;
        string? dotNetDll = null;
        string? logPath = null;
        string? outputPath = null;

        try
        {
            // Probe web.config for ASP.NET Core detection
            var webConfigPath = System.IO.Path.Combine(physicalPath, "web.config");
            if (File.Exists(webConfigPath))
            {
                (isAspNetCore, dotNetDll) = ParseWebConfig(webConfigPath);
            }

            // Scan appsettings.json for OptPath-based paths
            var appSettingsPath = System.IO.Path.Combine(physicalPath, "appsettings.json");
            if (File.Exists(appSettingsPath))
            {
                (logPath, outputPath) = ScanAppSettingsForPaths(appSettingsPath);
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not enrich app info for {AppPath}", appPath);
        }

        return new IisVirtualAppInfo
        {
            Path = appPath,
            PhysicalPath = physicalPath,
            PhysicalPathUnc = physicalPathUnc,
            AppPoolName = appPoolName,
            EnabledProtocols = enabledProtocols,
            IsAspNetCore = isAspNetCore,
            DotNetDll = dotNetDll,
            LogPath = logPath,
            OutputPath = outputPath
        };
    }

    private (bool isAspNetCore, string? dllName) ParseWebConfig(string webConfigPath)
    {
        try
        {
            var doc = XDocument.Load(webConfigPath);
            var aspNetCoreElement = doc.Descendants("aspNetCore").FirstOrDefault();
            if (aspNetCoreElement == null)
                return (false, null);

            var arguments = aspNetCoreElement.Attribute("arguments")?.Value;
            if (string.IsNullOrEmpty(arguments))
                return (true, null);

            // arguments typically looks like: ".\ServerMonitorDashboard.dll"
            // Extract the .dll filename
            var parts = arguments.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var dllPart = parts.FirstOrDefault(p => p.EndsWith(".dll", StringComparison.OrdinalIgnoreCase));
            if (dllPart != null)
            {
                dllPart = System.IO.Path.GetFileName(dllPart);
            }

            return (true, dllPart);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to parse web.config at {Path}", webConfigPath);
            return (false, null);
        }
    }

    private (string? logPath, string? outputPath) ScanAppSettingsForPaths(string appSettingsPath)
    {
        string? logPath = null;
        string? outputPath = null;

        try
        {
            var json = File.ReadAllText(appSettingsPath);
            using var doc = JsonDocument.Parse(json);
            var matches = new List<(string key, string path)>();
            WalkJsonForOptPaths(doc.RootElement, "", matches);

            foreach (var (key, path) in matches)
            {
                var expanded = Environment.ExpandEnvironmentVariables(path);
                var directory = ExtractDirectoryFromPath(expanded);
                var uncPath = PathHelper.ToUncPath(directory);

                if (logPath == null && key.Contains("log", StringComparison.OrdinalIgnoreCase))
                {
                    logPath = uncPath;
                }
                else if (outputPath == null)
                {
                    outputPath = uncPath;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to scan appsettings.json at {Path}", appSettingsPath);
        }

        return (logPath, outputPath);
    }

    private void WalkJsonForOptPaths(JsonElement element, string currentKey, List<(string key, string path)> matches)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                {
                    WalkJsonForOptPaths(property.Value, property.Name, matches);
                }
                break;

            case JsonValueKind.Array:
                foreach (var item in element.EnumerateArray())
                {
                    WalkJsonForOptPaths(item, currentKey, matches);
                }
                break;

            case JsonValueKind.String:
                var value = element.GetString();
                if (!string.IsNullOrEmpty(value) && IsOptPathValue(value))
                {
                    matches.Add((currentKey, value));
                }
                break;
        }
    }

    private static bool IsOptPathValue(string value)
    {
        return OptPathEnvVarPattern.IsMatch(value) || DriveOptPattern.IsMatch(value);
    }

    private static string ExtractDirectoryFromPath(string path)
    {
        if (string.IsNullOrEmpty(path)) return path;

        // If the path ends with a file extension or contains glob patterns, take the directory
        var fileName = System.IO.Path.GetFileName(path);
        if (fileName.Contains('*') || fileName.Contains('?') || fileName.Contains('.'))
        {
            var dir = System.IO.Path.GetDirectoryName(path);
            return dir ?? path;
        }

        return path;
    }

    private void EnsureInitialized()
    {
        if (_iisChecked) return;
        lock (_initLock)
        {
            if (_iisChecked) return;
            try
            {
                if (File.Exists(IisDllPath))
                {
                    _iisAssembly = Assembly.LoadFrom(IisDllPath);
                    _iisAvailable = true;
                    _logger.LogInformation("IIS management assembly loaded from {Path}", IisDllPath);
                }
                else
                {
                    _iisAvailable = false;
                    _logger.LogInformation("IIS management DLL not found at {Path} — IIS monitoring disabled", IisDllPath);
                }
            }
            catch (Exception ex)
            {
                _iisAvailable = false;
                _logger.LogWarning(ex, "Failed to load IIS management assembly from {Path}", IisDllPath);
            }
            _iisChecked = true;
        }
    }

    private static T GetPropertyValue<T>(object obj, string propertyName)
    {
        var prop = obj.GetType().GetProperty(propertyName);
        if (prop == null) return default!;
        var val = prop.GetValue(obj);
        if (val == null) return default!;
        if (val is T typed) return typed;
        try { return (T)Convert.ChangeType(val, typeof(T)); }
        catch { return default!; }
    }

    private static string GetEnumString(object obj, string propertyName)
    {
        var prop = obj.GetType().GetProperty(propertyName);
        if (prop == null) return "Unknown";
        try
        {
            var val = prop.GetValue(obj);
            return val?.ToString() ?? "Unknown";
        }
        catch
        {
            return "Unknown";
        }
    }
}
