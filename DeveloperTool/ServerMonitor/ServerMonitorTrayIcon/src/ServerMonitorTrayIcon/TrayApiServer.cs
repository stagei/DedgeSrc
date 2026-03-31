using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json;

namespace ServerMonitorTrayIcon;

/// <summary>
/// Minimal HTTP API server for the tray application.
/// Allows the Dashboard to directly control the agent service.
/// Runs on port 8997.
/// </summary>
public class TrayApiServer : IDisposable
{
    // Hardcoded authorized users for script execution (security requirement)
    private static readonly HashSet<string> AuthorizedScriptUsers = new(StringComparer.OrdinalIgnoreCase)
    {
        "FKSVEERI",
        "FKGEISTA"
    };

    // Valid execution modes - maps API mode to PowerShell command prefix
    private static readonly Dictionary<string, string> ValidModes = new(StringComparer.OrdinalIgnoreCase)
    {
        { "run", "run-psh" },
        { "install", "inst-psh" }
    };

    private readonly HttpListener _listener;
    private readonly CancellationTokenSource _cts;
    private readonly ServiceManager _serviceManager;
    private readonly TrayAppSettings _settings;
    private readonly Func<Task> _reinstallCallback;
    private readonly int _port;
    private bool _isRunning;
    private Task? _listenTask;

    // Script execution tracking
    private readonly Dictionary<string, RunningScript> _runningScripts = new();
    private readonly object _scriptsLock = new();
    private Action<bool>? _scriptStateCallback;  // Callback when script running state changes

    /// <summary>
    /// Event raised when script running state changes (true = at least one running, false = none running)
    /// </summary>
    public void SetScriptStateCallback(Action<bool> callback) => _scriptStateCallback = callback;

    /// <summary>
    /// Returns true if any scripts are currently running
    /// </summary>
    public bool HasRunningScripts
    {
        get
        {
            lock (_scriptsLock)
            {
                return _runningScripts.Values.Any(s => s.IsRunning);
            }
        }
    }

    public TrayApiServer(
        ServiceManager serviceManager, 
        TrayAppSettings settings,
        Func<Task> reinstallCallback,
        int port = 8997)
    {
        _serviceManager = serviceManager;
        _settings = settings;
        _reinstallCallback = reinstallCallback;
        _port = port;
        _listener = new HttpListener();
        _cts = new CancellationTokenSource();
    }

    public void Start()
    {
        if (_isRunning) return;

        try
        {
            // Listen on all interfaces (requires admin or URL ACL)
            _listener.Prefixes.Add($"http://+:{_port}/");
            _listener.Start();
            _isRunning = true;
            
            _listenTask = Task.Run(() => ListenLoopAsync(_cts.Token));
            
            Debug.WriteLine($"Tray API server started on port {_port}");
        }
        catch (HttpListenerException ex) when (ex.ErrorCode == 5) // Access denied
        {
            Debug.WriteLine($"Access denied for http://+:{_port}/. Trying localhost only...");
            
            // Fall back to localhost only (no admin required)
            try
            {
                _listener.Prefixes.Clear();
                _listener.Prefixes.Add($"http://localhost:{_port}/");
                _listener.Start();
                _isRunning = true;
                
                _listenTask = Task.Run(() => ListenLoopAsync(_cts.Token));
                
                Debug.WriteLine($"Tray API server started on localhost:{_port} (local only)");
            }
            catch (Exception fallbackEx)
            {
                Debug.WriteLine($"Failed to start API server: {fallbackEx.Message}");
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to start API server: {ex.Message}");
        }
    }

    public void Stop()
    {
        if (!_isRunning) return;
        
        _cts.Cancel();
        _listener.Stop();
        _isRunning = false;
        
        Debug.WriteLine("Tray API server stopped");
    }

    private async Task ListenLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _isRunning)
        {
            try
            {
                var context = await _listener.GetContextAsync().ConfigureAwait(false);
                _ = Task.Run(() => HandleRequestAsync(context), ct);
            }
            catch (HttpListenerException) when (ct.IsCancellationRequested)
            {
                // Expected when stopping
                break;
            }
            catch (ObjectDisposedException)
            {
                // Listener was disposed
                break;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"API listen error: {ex.Message}");
            }
        }
    }

    private async Task HandleRequestAsync(HttpListenerContext context)
    {
        var request = context.Request;
        var response = context.Response;
        
        // Add CORS headers for browser access
        response.Headers.Add("Access-Control-Allow-Origin", "*");
        response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response.Headers.Add("Access-Control-Allow-Headers", "Content-Type");
        
        // Handle preflight
        if (request.HttpMethod == "OPTIONS")
        {
            response.StatusCode = 204;
            response.Close();
            return;
        }

        var path = request.Url?.AbsolutePath?.ToLowerInvariant() ?? "";
        var method = request.HttpMethod;
        
        Debug.WriteLine($"API request: {method} {path}");

        try
        {
            // Special handling for script execution (not documented in API)
            if (method == "POST" && path == "/api/script/execute")
            {
                await HandleScriptExecuteAsync(request, response);
                return;
            }

            // Script status polling endpoint
            if (method == "GET" && path.StartsWith("/api/script/status/"))
            {
                var executionId = path.Substring("/api/script/status/".Length);
                await HandleScriptStatusAsync(executionId, response);
                return;
            }

            // List all running scripts
            if (method == "GET" && path == "/api/script/running")
            {
                await HandleListRunningScriptsAsync(response);
                return;
            }

            object? result = (method, path) switch
            {
                // Health check - is tray app running?
                ("GET", "/api/isalive") => new { alive = true, timestamp = DateTime.UtcNow },
                
                // Status - detailed status
                ("GET", "/api/status") => GetStatus(),
                
                // Agent control
                ("POST", "/api/agent/start") => await StartAgentAsync(),
                ("POST", "/api/agent/stop") => await StopAgentAsync(),
                ("POST", "/api/agent/restart") => await RestartAgentAsync(),
                ("POST", "/api/agent/reinstall") => await ReinstallAgentAsync(),
                
                // Unknown endpoint
                _ => null
            };

            if (result == null)
            {
                response.StatusCode = 404;
                await WriteJsonAsync(response, new { error = "Not found", path });
            }
            else
            {
                response.StatusCode = 200;
                await WriteJsonAsync(response, result);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"API error: {ex.Message}");
            response.StatusCode = 500;
            await WriteJsonAsync(response, new { error = ex.Message });
        }
    }

    private object GetStatus()
    {
        var isRunning = _serviceManager.IsRunning();
        var version = GetInstalledVersion();
        
        return new
        {
            trayApp = new
            {
                running = true,
                version = GetTrayAppVersion(),
                machineName = Environment.MachineName
            },
            agent = new
            {
                running = isRunning,
                version = version,
                serviceName = "ServerMonitor"
            }
        };
    }

    private async Task<object> StartAgentAsync()
    {
        try
        {
            // Check if agents are disabled via DisableServerMonitor.txt
            var configDir = Path.GetDirectoryName(_settings.ReinstallTriggerFilePath) ?? "";
            var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
            if (File.Exists(disableFilePath))
            {
                return new { success = false, message = "Cannot start: Agents are DISABLED. Remove DisableServerMonitor.txt to enable.", disabled = true };
            }
            
            if (_serviceManager.IsRunning())
            {
                return new { success = true, message = "Agent is already running" };
            }

            var started = await Task.Run(() => _serviceManager.StartService());
            
            return new
            {
                success = started,
                message = started ? "Agent started successfully" : "Failed to start agent"
            };
        }
        catch (Exception ex)
        {
            return new { success = false, message = ex.Message };
        }
    }

    private async Task<object> StopAgentAsync()
    {
        try
        {
            if (!_serviceManager.IsRunning())
            {
                return new { success = true, message = "Agent is already stopped" };
            }

            var stopResult = await Task.Run(() => _serviceManager.StopService());
            
            return new
            {
                success = stopResult.Success,
                message = stopResult.Success ? "Agent stopped successfully" : (stopResult.ErrorMessage ?? "Failed to stop agent"),
                forceKilled = stopResult.ForceKilled
            };
        }
        catch (Exception ex)
        {
            return new { success = false, message = ex.Message };
        }
    }

    private async Task<object> RestartAgentAsync()
    {
        try
        {
            // Check if agents are disabled via DisableServerMonitor.txt
            var configDir = Path.GetDirectoryName(_settings.ReinstallTriggerFilePath) ?? "";
            var disableFilePath = Path.Combine(configDir, "DisableServerMonitor.txt");
            if (File.Exists(disableFilePath))
            {
                return new { success = false, message = "Cannot restart: Agents are DISABLED. Remove DisableServerMonitor.txt to enable.", disabled = true };
            }
            
            // Stop if running
            if (_serviceManager.IsRunning())
            {
                await Task.Run(() => _serviceManager.StopService());
                await Task.Delay(1000); // Wait for stop
            }

            // Start
            var started = await Task.Run(() => _serviceManager.StartService());
            
            return new
            {
                success = started,
                message = started ? "Agent restarted successfully" : "Failed to restart agent"
            };
        }
        catch (Exception ex)
        {
            return new { success = false, message = ex.Message };
        }
    }

    private async Task<object> ReinstallAgentAsync()
    {
        try
        {
            // Trigger the reinstall callback (runs the install script)
            _ = _reinstallCallback();
            
            return new
            {
                success = true,
                message = "Reinstall initiated. This may take a few minutes."
            };
        }
        catch (Exception ex)
        {
            return new { success = false, message = ex.Message };
        }
    }

    private string GetInstalledVersion()
    {
        try
        {
            if (File.Exists(_settings.ServerMonitorExePath))
            {
                var vi = FileVersionInfo.GetVersionInfo(_settings.ServerMonitorExePath);
                return vi.FileVersion ?? "Unknown";
            }
        }
        catch { }
        return "Unknown";
    }

    private string GetTrayAppVersion()
    {
        try
        {
            var assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            return version?.ToString() ?? "Unknown";
        }
        catch { }
        return "Unknown";
    }

    private static async Task WriteJsonAsync(HttpListenerResponse response, object data)
    {
        response.ContentType = "application/json";
        var json = JsonSerializer.Serialize(data, new JsonSerializerOptions 
        { 
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase 
        });
        var buffer = Encoding.UTF8.GetBytes(json);
        response.ContentLength64 = buffer.Length;
        await response.OutputStream.WriteAsync(buffer);
        response.Close();
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // Script Execution (Hidden API - Not documented)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Handles script execution requests. This endpoint is intentionally NOT documented.
    /// Only authorized users (FKSVEERI, FKGEISTA) can execute scripts.
    /// Only predefined modes (run-psh, inst-psh) are allowed.
    /// Scripts run in background - poll /api/script/status/{executionId} for results.
    /// </summary>
    private async Task HandleScriptExecuteAsync(HttpListenerRequest request, HttpListenerResponse response)
    {
        string? requestedBy = null;
        string? scriptName = null;
        string? mode = null;

        try
        {
            // Read request body
            using var reader = new StreamReader(request.InputStream, request.ContentEncoding);
            var body = await reader.ReadToEndAsync();
            
            var requestData = JsonSerializer.Deserialize<ScriptExecuteRequest>(body, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (requestData == null)
            {
                response.StatusCode = 400;
                await WriteJsonAsync(response, new { success = false, error = "Invalid request body" });
                return;
            }

            requestedBy = requestData.RequestedBy;
            scriptName = requestData.ScriptName;
            mode = requestData.Mode;

            // Validate required fields
            if (string.IsNullOrWhiteSpace(requestedBy))
            {
                LogScriptRequest(requestedBy, scriptName, mode, false, "Missing requestedBy");
                response.StatusCode = 400;
                await WriteJsonAsync(response, new { success = false, error = "requestedBy is required" });
                return;
            }

            if (string.IsNullOrWhiteSpace(scriptName))
            {
                LogScriptRequest(requestedBy, scriptName, mode, false, "Missing scriptName");
                response.StatusCode = 400;
                await WriteJsonAsync(response, new { success = false, error = "scriptName is required" });
                return;
            }

            if (string.IsNullOrWhiteSpace(mode))
            {
                LogScriptRequest(requestedBy, scriptName, mode, false, "Missing mode");
                response.StatusCode = 400;
                await WriteJsonAsync(response, new { success = false, error = "mode is required (run or install)" });
                return;
            }

            // Validate user authorization (hardcoded security check)
            if (!AuthorizedScriptUsers.Contains(requestedBy))
            {
                LogScriptRequest(requestedBy, scriptName, mode, false, "Unauthorized user");
                response.StatusCode = 403;
                await WriteJsonAsync(response, new { success = false, error = "Unauthorized user" });
                return;
            }

            // Validate mode (only run-psh and inst-psh allowed)
            if (!ValidModes.TryGetValue(mode, out var commandPrefix))
            {
                LogScriptRequest(requestedBy, scriptName, mode, false, "Invalid mode");
                response.StatusCode = 400;
                await WriteJsonAsync(response, new { success = false, error = "Invalid mode. Use 'run' or 'install'" });
                return;
            }

            // Start script in background and return execution ID immediately
            var result = StartScriptInBackground(commandPrefix, scriptName, mode, requestedBy);

            if (result.Success)
            {
                LogScriptRequest(requestedBy, scriptName, mode, true, $"Started with ID: {result.ExecutionId}");
                response.StatusCode = 202; // Accepted
                await WriteJsonAsync(response, new
                {
                    success = true,
                    executionId = result.ExecutionId,
                    message = "Script started. Poll /api/script/status/{executionId} for results.",
                    server = Environment.MachineName
                });
            }
            else
            {
                LogScriptRequest(requestedBy, scriptName, mode, false, result.Error);
                response.StatusCode = 500;
                await WriteJsonAsync(response, new
                {
                    success = false,
                    error = result.Error,
                    server = Environment.MachineName
                });
            }
        }
        catch (Exception ex)
        {
            LogScriptRequest(requestedBy, scriptName, mode, false, ex.Message);
            response.StatusCode = 500;
            await WriteJsonAsync(response, new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// Handles script status polling requests
    /// </summary>
    private async Task HandleScriptStatusAsync(string executionId, HttpListenerResponse response)
    {
        try
        {
            RunningScript? script;
            lock (_scriptsLock)
            {
                _runningScripts.TryGetValue(executionId, out script);
            }

            if (script == null)
            {
                response.StatusCode = 404;
                await WriteJsonAsync(response, new { success = false, error = "Execution not found" });
                return;
            }

            // Read new output from log file
            var newOutput = ReadNewLogContent(script);
            var durationSeconds = ((script.EndTime ?? DateTime.UtcNow) - script.StartTime).TotalSeconds;

            response.StatusCode = 200;
            await WriteJsonAsync(response, new
            {
                executionId = script.ExecutionId,
                scriptName = script.ScriptName,
                mode = script.Mode,
                requestedBy = script.RequestedBy,
                isRunning = script.IsRunning,
                startTime = script.StartTime.ToString("o"),
                endTime = script.EndTime?.ToString("o"),
                exitCode = script.ExitCode,
                success = script.IsRunning ? (bool?)null : script.ExitCode == 0,
                output = newOutput,
                durationSeconds = Math.Round(durationSeconds, 1),
                server = Environment.MachineName
            });
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            await WriteJsonAsync(response, new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// Lists all running scripts
    /// </summary>
    private async Task HandleListRunningScriptsAsync(HttpListenerResponse response)
    {
        try
        {
            List<object> scripts;
            lock (_scriptsLock)
            {
                scripts = _runningScripts.Values
                    .OrderByDescending(s => s.StartTime)
                    .Take(20) // Limit to recent 20
                    .Select(s => new
                    {
                        executionId = s.ExecutionId,
                        scriptName = s.ScriptName,
                        mode = s.Mode,
                        requestedBy = s.RequestedBy,
                        isRunning = s.IsRunning,
                        startTime = s.StartTime.ToString("o"),
                        endTime = s.EndTime?.ToString("o"),
                        exitCode = s.ExitCode,
                        durationSeconds = Math.Round(((s.EndTime ?? DateTime.UtcNow) - s.StartTime).TotalSeconds, 1)
                    })
                    .Cast<object>()
                    .ToList();
            }

            response.StatusCode = 200;
            await WriteJsonAsync(response, new
            {
                server = Environment.MachineName,
                runningCount = scripts.Count(s => ((dynamic)s).isRunning),
                scripts
            });
        }
        catch (Exception ex)
        {
            response.StatusCode = 500;
            await WriteJsonAsync(response, new { success = false, error = ex.Message });
        }
    }

    /// <summary>
    /// Reads new content from log file since last read
    /// </summary>
    private string ReadNewLogContent(RunningScript script)
    {
        try
        {
            if (!File.Exists(script.LogFilePath))
                return string.Empty;

            using var fs = new FileStream(script.LogFilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            fs.Seek(script.LastReadPosition, SeekOrigin.Begin);
            
            using var reader = new StreamReader(fs);
            var newContent = reader.ReadToEnd();
            
            script.LastReadPosition = fs.Position;
            
            return newContent;
        }
        catch
        {
            return string.Empty;
        }
    }

    /// <summary>
    /// Starts a script in background thread with output redirected to a log file.
    /// Returns immediately with an execution ID for status polling.
    /// </summary>
    private ScriptExecuteResult StartScriptInBackground(string commandPrefix, string scriptName, string mode, string requestedBy)
    {
        try
        {
            // Split scriptName into script name and parameters
            var parts = scriptName.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
            var baseScriptName = parts[0];
            var scriptParams = parts.Length > 1 ? parts[1] : string.Empty;

            // Get OPTPATH from environment variable (typically C:\opt)
            var optPath = Environment.GetEnvironmentVariable("OPTPATH") ?? @"C:\opt";
            var DedgePshAppsPath = Path.Combine(optPath, "DedgePshApps");

            // Search for the script file recursively
            var scriptFileName = baseScriptName.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase) 
                ? baseScriptName 
                : $"{baseScriptName}.ps1";

            string? foundScriptPath = null;
            string? scriptDirectory = null;

            if (Directory.Exists(DedgePshAppsPath))
            {
                var matchingFiles = Directory.GetFiles(DedgePshAppsPath, scriptFileName, SearchOption.AllDirectories);
                if (matchingFiles.Length > 0)
                {
                    foundScriptPath = matchingFiles[0]; // Take first match
                    scriptDirectory = Path.GetDirectoryName(foundScriptPath);
                }
            }

            if (foundScriptPath == null)
            {
                return new ScriptExecuteResult
                {
                    Success = false,
                    Error = $"Script '{scriptFileName}' not found in {DedgePshAppsPath}",
                    ExitCode = -1
                };
            }

            // Build the command based on mode
            string scriptToExecute;

            if (commandPrefix == "inst-psh")
            {
                // For install mode: run _install.ps1 in the script's folder
                var installScript = Path.Combine(scriptDirectory!, "_install.ps1");
                if (!File.Exists(installScript))
                {
                    return new ScriptExecuteResult
                    {
                        Success = false,
                        Error = $"Install script not found: {installScript}",
                        ExitCode = -1
                    };
                }
                scriptToExecute = installScript;
            }
            else
            {
                // For run mode: execute the script with parameters
                scriptToExecute = foundScriptPath;
            }

            // Generate execution ID and log file path
            var executionId = $"{Environment.MachineName}_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}"[..50];
            var logDir = Path.Combine(optPath, "data", "ServerMonitorTrayIcon", "script-logs");
            Directory.CreateDirectory(logDir);
            var logFilePath = Path.Combine(logDir, $"{executionId}.log");

            // Create running script tracker
            var runningScript = new RunningScript
            {
                ExecutionId = executionId,
                ScriptName = scriptName,
                Mode = mode,
                RequestedBy = requestedBy,
                StartTime = DateTime.UtcNow,
                LogFilePath = logFilePath,
                IsRunning = true
            };

            // Build pwsh command that redirects all output to log file
            // Use *>> to append both stdout and stderr
            var pwshCommand = commandPrefix == "inst-psh"
                ? $"& '{scriptToExecute}' *>> '{logFilePath}'"
                : string.IsNullOrEmpty(scriptParams)
                    ? $"& '{scriptToExecute}' *>> '{logFilePath}'"
                    : $"& '{scriptToExecute}' {scriptParams} *>> '{logFilePath}'";

            var startInfo = new ProcessStartInfo
            {
                FileName = "pwsh.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{pwshCommand}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = scriptDirectory
            };

            var process = new Process { StartInfo = startInfo };
            runningScript.Process = process;

            // Add to tracking
            lock (_scriptsLock)
            {
                _runningScripts[executionId] = runningScript;
                
                // Clean up old completed scripts (keep last 50)
                var toRemove = _runningScripts
                    .Where(kv => !kv.Value.IsRunning && kv.Value.EndTime < DateTime.UtcNow.AddHours(-24))
                    .Select(kv => kv.Key)
                    .ToList();
                foreach (var key in toRemove)
                {
                    _runningScripts.Remove(key);
                }
            }

            // Write initial log entry
            File.WriteAllText(logFilePath, $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Script started by {requestedBy}\n" +
                                           $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Mode: {mode}\n" +
                                           $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Script: {scriptToExecute}\n" +
                                           $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Params: {scriptParams}\n" +
                                           $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] ========================================\n");

            // Start process
            process.Start();

            // Notify that we have a running script
            NotifyScriptStateChanged();

            // Monitor process completion in background
            _ = Task.Run(() => MonitorScriptCompletion(runningScript));

            return new ScriptExecuteResult
            {
                Success = true,
                ExecutionId = executionId
            };
        }
        catch (Exception ex)
        {
            return new ScriptExecuteResult
            {
                Success = false,
                Error = ex.Message,
                ExitCode = -1
            };
        }
    }

    /// <summary>
    /// Monitors a script for completion and updates status
    /// </summary>
    private void MonitorScriptCompletion(RunningScript script)
    {
        try
        {
            script.Process?.WaitForExit();
            
            script.EndTime = DateTime.UtcNow;
            script.ExitCode = script.Process?.ExitCode ?? -1;
            script.IsRunning = false;

            // Append completion message to log
            try
            {
                File.AppendAllText(script.LogFilePath,
                    $"\n[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] ========================================\n" +
                    $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Script completed with exit code: {script.ExitCode}\n" +
                    $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Duration: {(script.EndTime.Value - script.StartTime).TotalSeconds:F1} seconds\n");
            }
            catch { /* Ignore */ }

            LogScriptRequest(script.RequestedBy, script.ScriptName, script.Mode, 
                script.ExitCode == 0, $"Completed with exit code {script.ExitCode}");

            // Dispose process
            script.Process?.Dispose();
            script.Process = null;

            // Notify state changed
            NotifyScriptStateChanged();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error monitoring script completion: {ex.Message}");
        }
    }

    /// <summary>
    /// Notifies the callback about script state changes
    /// </summary>
    private void NotifyScriptStateChanged()
    {
        try
        {
            var hasRunning = HasRunningScripts;
            _scriptStateCallback?.Invoke(hasRunning);
        }
        catch { /* Ignore callback errors */ }
    }

    private static void LogScriptRequest(string? user, string? script, string? mode, bool success, string? details)
    {
        var status = success ? "SUCCESS" : "FAILED";
        var logMessage = $"[ScriptExec] {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} | User: {user ?? "null"} | Mode: {mode ?? "null"} | Script: {script ?? "null"} | {status} | {details}";
        Debug.WriteLine(logMessage);
        
        // Also log to file for audit trail
        try
        {
            var logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData)
                .Replace("ProgramData", "opt"), "data", "ServerMonitorTrayIcon");
            Directory.CreateDirectory(logDir);
            var logFile = Path.Combine(logDir, $"script-audit-{DateTime.Now:yyyyMMdd}.log");
            File.AppendAllText(logFile, logMessage + Environment.NewLine);
        }
        catch { /* Ignore logging errors */ }
    }

    public void Dispose()
    {
        Stop();
        _cts.Dispose();
        _listener.Close();
    }
}

// Request/Response models for script execution (hidden API)
internal class ScriptExecuteRequest
{
    public string? Mode { get; set; }
    public string? ScriptName { get; set; }
    public string? RequestedBy { get; set; }
    public int? TimeoutSeconds { get; set; }
}

internal class ScriptExecuteResult
{
    public bool Success { get; set; }
    public string? ExecutionId { get; set; }  // For async tracking
    public string? Output { get; set; }
    public string? Error { get; set; }
    public int ExitCode { get; set; }
}

/// <summary>
/// Tracks a running script execution
/// </summary>
internal class RunningScript
{
    public string ExecutionId { get; set; } = string.Empty;
    public string ScriptName { get; set; } = string.Empty;
    public string Mode { get; set; } = string.Empty;
    public string RequestedBy { get; set; } = string.Empty;
    public DateTime StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public string LogFilePath { get; set; } = string.Empty;
    public long LastReadPosition { get; set; }
    public bool IsRunning { get; set; } = true;
    public int? ExitCode { get; set; }
    public Process? Process { get; set; }
}
