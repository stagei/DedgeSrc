using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.TaskScheduler;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;
using ServerMonitor.Core.Services;

namespace ServerMonitor.Core.Monitors;

/// <summary>
/// Monitors Windows Scheduled Tasks for failures and missed runs.
/// Uses AlertAccumulator for deduplication and cooldown management.
/// </summary>
public class ScheduledTaskMonitor : IMonitor
{
    // Static initializer to register code page encoding provider (for Windows-1252 mojibake fix)
    static ScheduledTaskMonitor()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    private readonly ILogger<ScheduledTaskMonitor> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly IAlertAccumulator _alertAccumulator;
    private MonitorResult? _currentState;
    private static Dictionary<int, string>? _exitCodeDescriptions;
    private static readonly object _exitCodeLock = new object();

    public string Category => "ScheduledTask";
    public bool IsEnabled => _config.CurrentValue.ScheduledTaskMonitoring.Enabled;
    public MonitorResult? CurrentState => _currentState;

    public ScheduledTaskMonitor(
        ILogger<ScheduledTaskMonitor> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        IAlertAccumulator alertAccumulator)
    {
        _logger = logger;
        _config = config;
        _alertAccumulator = alertAccumulator;
    }

    public async System.Threading.Tasks.Task<MonitorResult> CollectAsync(CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var alerts = new List<Alert>();
        var taskData = new List<ScheduledTaskData>();

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

            var settings = _config.CurrentValue.ScheduledTaskMonitoring;

            foreach (var taskConfig in settings.TasksToMonitor)
            {
                var taskResult = await CheckTaskAsync(taskConfig, settings.Alerts, _alertAccumulator, cancellationToken).ConfigureAwait(false);
                // Add all matching tasks (not just the first one)
                taskData.AddRange(taskResult.data);
                alerts.AddRange(taskResult.alerts);
            }

            stopwatch.Stop();

            var result = new MonitorResult
            {
                Category = Category,
                Success = true,
                Data = taskData,
                Alerts = alerts,
                CollectionDurationMs = stopwatch.ElapsedMilliseconds
            };

            _currentState = result;
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting scheduled task metrics");
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

    private async System.Threading.Tasks.Task<(List<ScheduledTaskData> data, List<Alert> alerts)> CheckTaskAsync(
        TaskToMonitor taskConfig,
        ScheduledTaskAlerts alertSettings,
        IAlertAccumulator alertAccumulator,
        CancellationToken cancellationToken)
    {
        return await System.Threading.Tasks.Task.Run(() =>
        {
            var alerts = new List<Alert>();
            var taskDataList = new List<ScheduledTaskData>();

            try
            {
                using var ts = new Microsoft.Win32.TaskScheduler.TaskService();
                
                // Get tasks matching the pattern (wildcard or specific)
                var tasks = GetMatchingTasks(ts, taskConfig);
                
                if (!tasks.Any())
                {
                    // No tasks found - this is not an error condition
                    // Only monitor and alert when tasks actually exist
                    _logger.LogDebug("No scheduled tasks found matching pattern '{TaskPath}' for user filter '{FilterByUser}' - skipping monitoring (this is normal if user has no scheduled tasks)",
                        taskConfig.TaskPath, taskConfig.FilterByUser ?? "none");
                    return (taskDataList, alerts);
                }

                // Process ALL matching tasks for data (not just the first one)
                foreach (var task in tasks)
                {
                    var data = ConvertTaskToData(task);
                    taskDataList.Add(data);
                    
                    // Check each task for issues
                    CheckTaskForIssues(task, taskConfig, alertSettings, alertAccumulator, alerts);
                }

                _logger.LogDebug("Collected {Count} matching tasks for pattern: {TaskPath}", 
                    taskDataList.Count, taskConfig.TaskPath);

                return (taskDataList, alerts);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, $"Failed to check task {taskConfig.TaskPath}: {ex.Message}");
                return (taskDataList, alerts);
            }
        }, cancellationToken);
    }

    /// <summary>
    /// Converts a Task Scheduler Task to ScheduledTaskData with all available metadata
    /// </summary>
    private ScheduledTaskData ConvertTaskToData(Microsoft.Win32.TaskScheduler.Task task)
    {
        string? description = null;
        string? runAsUser = null;
        string? author = null;
        DateTime? registrationDate = null;
        string? command = null;
        string? arguments = null;
        string? workingDirectory = null;
        bool runOnlyIfLoggedOn = false;

        try
        {
            var definition = task.Definition;
            
            // Get description (fix encoding issues with Norwegian/Scandinavian characters)
            description = FixMojibakeEncoding(definition.RegistrationInfo?.Description);
            
            // Get author
            author = definition.RegistrationInfo?.Author;
            
            // Get registration date
            if (definition.RegistrationInfo?.Date != null && 
                definition.RegistrationInfo.Date != DateTime.MinValue)
            {
                registrationDate = definition.RegistrationInfo.Date;
            }
            
            // Get run-as user and logon type
            var principal = definition.Principal;
            runAsUser = principal?.UserId ?? principal?.Account ?? principal?.DisplayName;
            
            // Determine if task runs only when user is logged on
            // InteractiveToken / InteractiveTokenOrPassword = Run only when user is logged on
            // Password / S4U / ServiceAccount / Group = Run whether user is logged on or not
            if (principal != null)
            {
                runOnlyIfLoggedOn = principal.LogonType == Microsoft.Win32.TaskScheduler.TaskLogonType.InteractiveToken ||
                                    principal.LogonType == Microsoft.Win32.TaskScheduler.TaskLogonType.InteractiveTokenOrPassword;
            }
            
            // Get command, arguments, and working directory from first ExecAction
            var execAction = definition.Actions
                .OfType<Microsoft.Win32.TaskScheduler.ExecAction>()
                .FirstOrDefault();
            
            if (execAction != null)
            {
                command = execAction.Path;
                arguments = execAction.Arguments;
                workingDirectory = execAction.WorkingDirectory;
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to extract metadata from task {TaskPath}: {Message}", 
                task.Path, ex.Message);
        }

        return new ScheduledTaskData
        {
            TaskPath = task.Path,
            TaskName = task.Name,
            State = task.State.ToString(),
            LastRunTime = task.LastRunTime == DateTime.MinValue ? null : task.LastRunTime,
            LastRunResult = (int)task.LastTaskResult,
            NextRunTime = task.NextRunTime == DateTime.MinValue ? null : task.NextRunTime,
            MissedRuns = task.NumberOfMissedRuns,
            IsEnabled = task.Enabled,
            Description = description,
            RunAsUser = runAsUser,
            RunOnlyIfLoggedOn = runOnlyIfLoggedOn,
            Author = author,
            RegistrationDate = registrationDate,
            Command = command,
            Arguments = arguments,
            WorkingDirectory = workingDirectory
        };
    }

    private List<Microsoft.Win32.TaskScheduler.Task> GetMatchingTasks(
        Microsoft.Win32.TaskScheduler.TaskService ts,
        TaskToMonitor taskConfig)
    {
        var matchingTasks = new List<Microsoft.Win32.TaskScheduler.Task>();
        var currentUser = System.Security.Principal.WindowsIdentity.GetCurrent().Name;
        var targetUser = taskConfig.FilterByUser?.Replace("{CurrentUser}", currentUser, StringComparison.OrdinalIgnoreCase);

        _logger.LogDebug("GetMatchingTasks: TaskPath='{TaskPath}', FilterByUser='{FilterByUser}', CurrentUser='{CurrentUser}', TargetUser='{TargetUser}'",
            taskConfig.TaskPath, taskConfig.FilterByUser, currentUser, targetUser);

        // Check for recursive search pattern (**) - must be checked before single *
        // Pattern can be "\\**" or "**" or any path containing "**"
        var normalizedPath = taskConfig.TaskPath.Replace("\\", "").Trim();
        var isRecursivePattern = taskConfig.TaskPath.Contains("**") || normalizedPath == "**";
        
        if (isRecursivePattern)
        {
            // Recursive search: get all tasks from all folders
            try
            {
                _logger.LogDebug("Using recursive search pattern (**)");
                var allTasks = GetAllTasksRecursive(ts.RootFolder);
                _logger.LogDebug("Found {Count} total tasks recursively", allTasks.Count);
                
                foreach (var task in allTasks)
                {
                    // Skip if task or folder path contains any ignore string
                    if (ShouldIgnoreTask(task, taskConfig))
                    {
                        _logger.LogTrace("Task '{TaskPath}' skipped (matches ignore string)", task.Path);
                        continue;
                    }
                    
                    // Filter by user if specified
                    if (string.IsNullOrEmpty(targetUser))
                    {
                        matchingTasks.Add(task);
                        _logger.LogDebug("Task '{TaskPath}' added (no user filter)", task.Path);
                    }
                    else if (MatchesUser(task, targetUser))
                    {
                        matchingTasks.Add(task);
                        _logger.LogDebug("Task '{TaskPath}' added (matches user filter: {TargetUser})", task.Path, targetUser);
                    }
                    else
                    {
                        _logger.LogTrace("Task '{TaskPath}' skipped (does not match user filter: {TargetUser})", task.Path, targetUser);
                    }
                }
                
                _logger.LogInformation("Recursive search found {Count} matching tasks (filtered by user: {TargetUser})", 
                    matchingTasks.Count, targetUser ?? "none");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to get tasks recursively: {Message}", ex.Message);
            }
        }
        // Check if wildcard pattern (single *)
        else if (taskConfig.TaskPath.Contains("*"))
        {
            // Get folder path and pattern
            var parts = taskConfig.TaskPath.Split('\\', StringSplitOptions.RemoveEmptyEntries);
            var folderPath = "\\" + string.Join("\\", parts.TakeWhile(p => !p.Contains("*")));
            
            try
            {
                var folder = ts.GetFolder(folderPath);
                var allTasks = folder.GetTasks(new System.Text.RegularExpressions.Regex(".*"));
                
                foreach (var task in allTasks)
                {
                    // Match wildcard pattern
                    if (MatchesPattern(task.Path, taskConfig.TaskPath))
                    {
                        // Skip if task or folder path contains any ignore string
                        if (ShouldIgnoreTask(task, taskConfig))
                        {
                            _logger.LogTrace("Task '{TaskPath}' skipped (matches ignore string)", task.Path);
                            continue;
                        }
                        
                        // Filter by user if specified
                        if (string.IsNullOrEmpty(targetUser) || MatchesUser(task, targetUser))
                        {
                            matchingTasks.Add(task);
                        }
                    }
                }
            }
            catch
            {
                // Folder not found or access denied
            }
        }
        else
        {
            // Specific task path
            var task = ts.GetTask(taskConfig.TaskPath);
            if (task != null)
            {
                // Skip if task or folder path contains any ignore string
                if (!ShouldIgnoreTask(task, taskConfig))
                {
                    // Filter by user if specified
                    if (string.IsNullOrEmpty(targetUser) || MatchesUser(task, targetUser))
                    {
                        matchingTasks.Add(task);
                    }
                }
                else
                {
                    _logger.LogTrace("Task '{TaskPath}' skipped (matches ignore string)", task.Path);
                }
            }
        }

        return matchingTasks;
    }

    /// <summary>
    /// Checks if a task should be ignored based on IgnoreStrings configuration
    /// Checks both task name and folder path (case-insensitive)
    /// </summary>
    private bool ShouldIgnoreTask(Microsoft.Win32.TaskScheduler.Task task, TaskToMonitor taskConfig)
    {
        if (taskConfig.IgnoreStrings == null || taskConfig.IgnoreStrings.Count == 0)
        {
            return false;
        }

        var taskPath = task.Path ?? string.Empty;
        var taskName = task.Name ?? string.Empty;
        
        // Get folder path by removing task name from full path
        var folderPath = taskPath;
        if (taskPath.Contains('\\'))
        {
            var lastBackslash = taskPath.LastIndexOf('\\');
            if (lastBackslash >= 0 && lastBackslash < taskPath.Length - 1)
            {
                folderPath = taskPath.Substring(0, lastBackslash);
            }
        }

        // Check if any ignore string is contained in task name, task path, or folder path
        foreach (var ignoreString in taskConfig.IgnoreStrings)
        {
            if (string.IsNullOrWhiteSpace(ignoreString))
                continue;

            if (taskName.Contains(ignoreString, StringComparison.OrdinalIgnoreCase) ||
                taskPath.Contains(ignoreString, StringComparison.OrdinalIgnoreCase) ||
                folderPath.Contains(ignoreString, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogDebug("Task '{TaskPath}' ignored due to ignore string: '{IgnoreString}'", taskPath, ignoreString);
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Recursively gets all tasks from a folder and all its subfolders
    /// </summary>
    private List<Microsoft.Win32.TaskScheduler.Task> GetAllTasksRecursive(
        Microsoft.Win32.TaskScheduler.TaskFolder folder)
    {
        var allTasks = new List<Microsoft.Win32.TaskScheduler.Task>();

        try
        {
            // Get all tasks in current folder
            var tasks = folder.GetTasks(new System.Text.RegularExpressions.Regex(".*"));
            allTasks.AddRange(tasks);

            // Recursively get tasks from all subfolders
            var subfolders = folder.SubFolders;
            foreach (Microsoft.Win32.TaskScheduler.TaskFolder subfolder in subfolders)
            {
                try
                {
                    allTasks.AddRange(GetAllTasksRecursive(subfolder));
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Failed to access subfolder {Path}: {Message}", subfolder.Path, ex.Message);
                    // Continue with other folders even if one fails
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to get tasks from folder {Path}: {Message}", folder.Path, ex.Message);
        }

        return allTasks;
    }

    private bool MatchesPattern(string taskPath, string pattern)
    {
        // Simple wildcard matching (* = any characters)
        var regexPattern = "^" + System.Text.RegularExpressions.Regex.Escape(pattern)
            .Replace("\\*", ".*") + "$";
        return System.Text.RegularExpressions.Regex.IsMatch(taskPath, regexPattern, 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    }

    private bool MatchesUser(Microsoft.Win32.TaskScheduler.Task task, string targetUser)
    {
        try
        {
            var definition = task.Definition;
            var principal = definition.Principal;
            
            // Try multiple properties to find the user
            var taskUser = principal.UserId ?? principal.Account ?? principal.DisplayName ?? string.Empty;
            
            if (string.IsNullOrEmpty(taskUser))
            {
                _logger.LogTrace("Task '{TaskPath}' has no user information", task.Path);
                return false;
            }
            
            // Convert both to uppercase for case-insensitive comparison
            var taskUserUpper = taskUser.ToUpperInvariant();
            var targetUserUpper = targetUser.ToUpperInvariant();
            
            // Extract just the username from targetUser (remove domain if present)
            var targetUsername = NormalizeUserName(targetUserUpper);
            
            // Check if the username is contained in the task user string
            // This handles cases where task has "FKGEISTA" and target is "DEDGE\FKGEISTA"
            var matches = taskUserUpper.Contains(targetUsername) ||
                         targetUserUpper.Contains(taskUserUpper);
            
            if (!matches)
            {
                _logger.LogTrace("User mismatch for task '{TaskPath}': TaskUser='{TaskUser}' vs TargetUser='{TargetUser}' (username: '{TargetUsername}')",
                    task.Path, taskUser, targetUser, targetUsername);
            }
            
            return matches;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to check user for task '{TaskPath}': {Message}", task.Path, ex.Message);
            return false;
        }
    }
    
    /// <summary>
    /// Normalizes a username for comparison (removes domain, handles SID, etc.)
    /// Assumes input is already uppercase
    /// </summary>
    private string NormalizeUserName(string userName)
    {
        if (string.IsNullOrEmpty(userName))
            return string.Empty;
            
        // If it's a SID (starts with S-), return as-is
        if (userName.StartsWith("S-", StringComparison.Ordinal))
            return userName;
            
        // Remove domain prefix (DOMAIN\USERNAME -> USERNAME)
        var parts = userName.Split('\\');
        return parts.Length > 1 ? parts[parts.Length - 1] : userName;
    }

    /// <summary>
    /// Gets the description for an exit code from the JSON file
    /// Tries multiple lookup strategies: direct lookup, hex interpretation, etc.
    /// </summary>
    private string GetExitCodeDescription(int exitCode)
    {
        try
        {
            // Load exit codes if not already loaded
            if (_exitCodeDescriptions == null)
            {
                lock (_exitCodeLock)
                {
                    if (_exitCodeDescriptions == null)
                    {
                        LoadExitCodeDescriptions();
                    }
                }
            }

            if (_exitCodeDescriptions == null || _exitCodeDescriptions.Count == 0)
            {
                _logger.LogWarning("Exit code descriptions dictionary is empty. JSON file may not have loaded. Exit code: {ExitCode}", exitCode);
                return string.Empty;
            }

            // Try direct lookup first
            if (_exitCodeDescriptions.TryGetValue(exitCode, out var description))
            {
                _logger.LogTrace("Found exit code description for {ExitCode}: {Description}", exitCode, description);
                return description;
            }
            
            _logger.LogTrace("Direct lookup failed for exit code {ExitCode}. Dictionary has {Count} entries.", exitCode, _exitCodeDescriptions.Count);

            // Strategy 1: Convert exit code to hex, then look for a code whose decimal value equals that hex
            // Example: exitCode = 267011 (0x41303) -> look for code 41303
            // Example: exitCode = 64 (0x40) -> look for code 40
            try
            {
                var exitCodeHexString = exitCode.ToString("X");
                // Try to parse the hex string as decimal to find matching code
                // For 0x41303, we want to find code 41303
                // For 0x40, we want to find code 40
                if (int.TryParse(exitCodeHexString, out var hexAsDecimal))
                {
                    if (_exitCodeDescriptions.TryGetValue(hexAsDecimal, out var hexDescription))
                    {
                        _logger.LogTrace("Found exit code description via hex-to-decimal match: {ExitCode} (0x{Hex}) matches code {FoundCode}", 
                            exitCode, exitCodeHexString, hexAsDecimal);
                        return hexDescription;
                    }
                }
            }
            catch
            {
                // Ignore parsing errors
            }

            // Strategy 2: Look for codes whose hex representation matches the exit code
            // Example: exitCode = 267011 -> look for code whose hex is 0x41303 (which is code 41303)
            // Example: exitCode = 64 -> look for code whose hex is 0x40 (which is code 40)
            var exitCodeAsHex = exitCode.ToString("X");
            foreach (var kvp in _exitCodeDescriptions)
            {
                var codeAsHex = kvp.Key.ToString("X");
                if (codeAsHex.Equals(exitCodeAsHex, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogTrace("Found exit code description via decimal-to-hex match: {ExitCode} (0x{Hex}) matches code {FoundCode} (0x{FoundHex})", 
                        exitCode, exitCodeAsHex, kvp.Key, codeAsHex);
                    return kvp.Value;
                }
            }

            // Strategy 3: For large codes, try interpreting the hex digits as a decimal code
            // Example: exitCode = 267011 (0x41303) -> try to find code 41303 directly
            if (exitCode > 65535)
            {
                var hexString = exitCode.ToString("X");
                // Remove leading zeros and try to find a code that matches
                var trimmedHex = hexString.TrimStart('0');
                if (!string.IsNullOrEmpty(trimmedHex) && int.TryParse(trimmedHex, out var trimmedValue))
                {
                    if (_exitCodeDescriptions.TryGetValue(trimmedValue, out var trimmedDescription))
                    {
                        _logger.LogTrace("Found exit code description via trimmed hex match: {ExitCode} (0x{Hex}) matches code {FoundCode}", 
                            exitCode, hexString, trimmedValue);
                        return trimmedDescription;
                    }
                }
            }

            _logger.LogTrace("Exit code {ExitCode} (0x{Hex}) not found in descriptions dictionary after all lookup strategies", exitCode, exitCode.ToString("X"));
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to get exit code description for {ExitCode}: {Message}", exitCode, ex.Message);
        }

        return string.Empty;
    }

    /// <summary>
    /// Fallback method: Parses text for exit codes and tries to find descriptions
    /// Used when primary lookup fails but message contains "exit code" or "exitcode"
    /// This does its own lookup without calling GetExitCodeDescription to avoid recursion
    /// </summary>
    private string TryFindExitCodeInText(string text)
    {
        if (string.IsNullOrEmpty(text) || 
            (!text.Contains("exit code", StringComparison.OrdinalIgnoreCase) && 
             !text.Contains("exitcode", StringComparison.OrdinalIgnoreCase)))
        {
            return string.Empty;
        }

        try
        {
            // Load exit codes if not already loaded
            if (_exitCodeDescriptions == null)
            {
                lock (_exitCodeLock)
                {
                    if (_exitCodeDescriptions == null)
                    {
                        LoadExitCodeDescriptions();
                    }
                }
            }

            if (_exitCodeDescriptions == null || _exitCodeDescriptions.Count == 0)
            {
                return string.Empty;
            }

            // Pattern 1: "exit code 123" or "exitcode 123"
            var pattern1 = @"exit\s*code\s+(\d+)";
            var matches1 = System.Text.RegularExpressions.Regex.Matches(text, pattern1, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            foreach (System.Text.RegularExpressions.Match match in matches1)
            {
                if (int.TryParse(match.Groups[1].Value, out var code))
                {
                    // Try direct lookup
                    if (_exitCodeDescriptions.TryGetValue(code, out var description))
                    {
                        return description;
                    }

                    // Try hex conversion strategies
                    var hexString = code.ToString("X");
                    if (int.TryParse(hexString, out var hexAsDecimal) && _exitCodeDescriptions.TryGetValue(hexAsDecimal, out var hexDesc))
                    {
                        return hexDesc;
                    }

                    // Try reverse lookup (find code whose hex matches)
                    foreach (var kvp in _exitCodeDescriptions)
                    {
                        if (kvp.Key.ToString("X").Equals(hexString, StringComparison.OrdinalIgnoreCase))
                        {
                            return kvp.Value;
                        }
                    }
                }
            }

            // Pattern 2: "exit code 123 (0xABC)" - extract both decimal and hex
            var pattern2 = @"exit\s*code\s+(\d+)\s*\(0x([0-9A-Fa-f]+)\)";
            var matches2 = System.Text.RegularExpressions.Regex.Matches(text, pattern2, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            foreach (System.Text.RegularExpressions.Match match in matches2)
            {
                // Try decimal first
                if (int.TryParse(match.Groups[1].Value, out var decimalCode))
                {
                    if (_exitCodeDescriptions.TryGetValue(decimalCode, out var desc))
                    {
                        return desc;
                    }
                }

                // Try hex string as decimal (e.g., "41303" from "0x41303")
                var hexString = match.Groups[2].Value;
                if (int.TryParse(hexString, out var hexAsDecimal))
                {
                    if (_exitCodeDescriptions.TryGetValue(hexAsDecimal, out var hexDesc))
                    {
                        return hexDesc;
                    }
                }

                // Try hex as hex number
                if (int.TryParse(hexString, System.Globalization.NumberStyles.HexNumber, null, out var hexValue))
                {
                    if (_exitCodeDescriptions.TryGetValue(hexValue, out var hexValDesc))
                    {
                        return hexValDesc;
                    }
                }

                // Try reverse lookup
                foreach (var kvp in _exitCodeDescriptions)
                {
                    if (kvp.Key.ToString("X").Equals(hexString, StringComparison.OrdinalIgnoreCase))
                    {
                        return kvp.Value;
                    }
                }
            }

            // Pattern 3: "0xABC" or "(0xABC)" - try to find matching code
            var pattern3 = @"\(?0x([0-9A-Fa-f]+)\)?";
            var matches3 = System.Text.RegularExpressions.Regex.Matches(text, pattern3, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            foreach (System.Text.RegularExpressions.Match match in matches3)
            {
                var hexString = match.Groups[1].Value;
                
                // Try parsing hex string as decimal code
                if (int.TryParse(hexString, out var hexAsDecimal))
                {
                    if (_exitCodeDescriptions.TryGetValue(hexAsDecimal, out var desc))
                    {
                        return desc;
                    }
                }

                // Try converting hex to decimal and looking up
                if (int.TryParse(hexString, System.Globalization.NumberStyles.HexNumber, null, out var hexValue))
                {
                    if (_exitCodeDescriptions.TryGetValue(hexValue, out var hexValDesc))
                    {
                        return hexValDesc;
                    }
                }

                // Try reverse lookup
                foreach (var kvp in _exitCodeDescriptions)
                {
                    if (kvp.Key.ToString("X").Equals(hexString, StringComparison.OrdinalIgnoreCase))
                    {
                        return kvp.Value;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error in fallback exit code parsing: {Message}", ex.Message);
        }

        return string.Empty;
    }

    /// <summary>
    /// Loads exit code descriptions from the JSON file
    /// </summary>
    private void LoadExitCodeDescriptions()
    {
        _exitCodeDescriptions = new Dictionary<int, string>();

        try
        {
            // Try to find the JSON file in the application directory
            var appDirectory = AppContext.BaseDirectory;
            var jsonPath = Path.Combine(appDirectory, "ScheduledTaskExitCodes.json");

            // If not found, try the project root
            if (!File.Exists(jsonPath))
            {
                var projectRoot = Path.GetFullPath(Path.Combine(appDirectory, "..", "..", "..", ".."));
                jsonPath = Path.Combine(projectRoot, "ScheduledTaskExitCodes.json");
            }

            // If still not found, try current directory
            if (!File.Exists(jsonPath))
            {
                jsonPath = Path.Combine(Directory.GetCurrentDirectory(), "ScheduledTaskExitCodes.json");
            }

            if (!File.Exists(jsonPath))
            {
                _logger.LogWarning("ScheduledTaskExitCodes.json not found at {Path}. Exit code descriptions will not be included in alerts.", jsonPath);
                _logger.LogWarning("Searched paths: AppDirectory={AppDir}, ProjectRoot={ProjectRoot}, CurrentDir={CurrentDir}", 
                    AppContext.BaseDirectory, 
                    Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..")),
                    Directory.GetCurrentDirectory());
                return;
            }

            _logger.LogInformation("Loading exit code descriptions from {Path}", jsonPath);
            var jsonContent = File.ReadAllText(jsonPath);
            using var doc = JsonDocument.Parse(jsonContent);

            if (doc.RootElement.TryGetProperty("ExitCodes", out var exitCodesArray))
            {
                foreach (var codeElement in exitCodesArray.EnumerateArray())
                {
                    if (codeElement.TryGetProperty("Code", out var codeProp) &&
                        codeElement.TryGetProperty("Description", out var descProp))
                    {
                        var code = codeProp.GetInt32();
                        var description = descProp.GetString();
                        if (!string.IsNullOrEmpty(description))
                        {
                            _exitCodeDescriptions[code] = description;
                        }
                    }
                }
            }

            _logger.LogInformation("✅ Loaded {Count} exit code descriptions from {Path}", _exitCodeDescriptions.Count, jsonPath);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load ScheduledTaskExitCodes.json: {Message}", ex.Message);
        }
    }

    private void CheckTaskForIssues(
        Microsoft.Win32.TaskScheduler.Task task,
        TaskToMonitor taskConfig,
        ScheduledTaskAlerts alertSettings,
        IAlertAccumulator alertAccumulator,
        List<Alert> alerts)
    {
        var maxOccurrences = alertSettings.MaxOccurrences;
        var timeWindowMinutes = alertSettings.TimeWindowMinutes;
        
        // Use a sanitized version of task path for alert keys
        var safeTaskPath = task.Path.Replace("\\", "_").TrimStart('_');
        
        // Check if task is disabled
        if (taskConfig.AlertIfDisabled && !task.Enabled)
        {
            var alertKey = $"ScheduledTask:{safeTaskPath}:Disabled";
            
            // Record occurrence in accumulator
            alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
            
            // Check if we should alert
            if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
            {
                alerts.Add(new Alert
                {
                    Severity = ParseAlertSeverity(alertSettings.DisabledTaskSeverity, AlertSeverity.Warning),
                    Category = Category,
                    Message = $"Scheduled task is disabled: {task.Path}",
                    Details = $"{taskConfig.Description}: Task '{task.Name}' is currently disabled",
                    SuppressedChannels = taskConfig.SuppressedChannels ?? new List<string>()
                });
                
                alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
            }
        }

        // Check for failed last run (only alert if task is not currently running)
        // If task previously failed but is now running, don't alert about the old failure
        if (taskConfig.AlertOnFailure && 
            task.LastTaskResult != 0 && 
            task.State != Microsoft.Win32.TaskScheduler.TaskState.Running)
        {
            var alertKey = $"ScheduledTask:{safeTaskPath}:Failed";
            
            // Record occurrence in accumulator
            alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
            
            // Check if we should alert
            if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
            {
                // Get the actual numeric exit code from Task Scheduler
                // TaskResult is a uint32 enum, casting to int gives us the actual decimal value
                // Example: If Task Scheduler UI shows (0x41303), the actual value is 267011 (decimal)
                var exitCode = (int)task.LastTaskResult;
                
                // Look up description using the actual numeric code
                // The lookup will try: direct lookup, hex-to-decimal conversion, etc.
                var exitCodeDescription = GetExitCodeDescription(exitCode);
                
                // Format exit code display (show both decimal and hex for clarity)
                var exitCodeDisplay = exitCode.ToString();
                var exitCodeHex = $"0x{exitCode:X}";
                
                // Build alert details with exit code and description
                // This will be included in ALL alert channels (SMS, Email, EventLog, File, WKMonitor)
                var details = $"{taskConfig.Description}: Task '{task.Name}' failed with exit code {exitCodeDisplay} ({exitCodeHex})";
                
                // Append description if found (enriches the alert with human-readable explanation)
                if (!string.IsNullOrEmpty(exitCodeDescription))
                {
                    details += $" - {exitCodeDescription}";
                }
                else
                {
                    // Log if description not found for debugging
                    _logger.LogTrace("No exit code description found for code {ExitCode} (0x{Hex})", exitCode, exitCodeHex);
                    
                    // Fallback: Try to parse exit codes from the details string and look them up
                    var fallbackDescription = TryFindExitCodeInText(details);
                    if (!string.IsNullOrEmpty(fallbackDescription))
                    {
                        details += $" - {fallbackDescription}";
                        _logger.LogTrace("Found exit code description via fallback parsing: {Description}", fallbackDescription);
                    }
                }
                
                alerts.Add(new Alert
                {
                    Severity = ParseAlertSeverity(alertSettings.FailedTaskSeverity, AlertSeverity.Critical),
                    Category = Category,
                    Message = $"Scheduled task failed: {task.Path}",
                    Details = details,
                    SuppressedChannels = taskConfig.SuppressedChannels ?? new List<string>()
                });
                
                alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
            }
        }
        else if (taskConfig.AlertOnFailure && 
                 task.LastTaskResult != 0 && 
                 task.State == Microsoft.Win32.TaskScheduler.TaskState.Running)
        {
            // Task previously failed but is currently running - log but don't alert
            _logger.LogDebug("Task '{TaskPath}' previously failed (exit code: {ExitCode}) but is currently running - skipping alert", 
                task.Path, task.LastTaskResult);
        }

        // Check for missed runs
        if (taskConfig.AlertOnMissedRun && task.NumberOfMissedRuns > 0)
        {
            var alertKey = $"ScheduledTask:{safeTaskPath}:MissedRuns";
            
            // Record occurrence in accumulator
            alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
            
            // Check if we should alert
            if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
            {
                alerts.Add(new Alert
                {
                    Severity = ParseAlertSeverity(alertSettings.MissedRunSeverity, AlertSeverity.Warning),
                    Category = Category,
                    Message = $"Scheduled task has missed runs: {task.Path}",
                    Details = $"{taskConfig.Description}: Task '{task.Name}' has {task.NumberOfMissedRuns} missed run(s)",
                    SuppressedChannels = taskConfig.SuppressedChannels ?? new List<string>()
                });
                
                alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
            }
        }

        // Check if task hasn't run recently
        if (taskConfig.AlertOnMissedRun && 
            task.LastRunTime != DateTime.MinValue && 
            task.Enabled &&
            task.State != Microsoft.Win32.TaskScheduler.TaskState.Running)
        {
            var minutesSinceLastRun = (DateTime.Now - task.LastRunTime).TotalMinutes;
            if (minutesSinceLastRun > taskConfig.MaxMinutesSinceLastRun)
            {
                var alertKey = $"ScheduledTask:{safeTaskPath}:Overdue";
                
                // Record occurrence in accumulator
                alertAccumulator.RecordOccurrence(alertKey, DateTime.UtcNow, timeWindowMinutes);
                
                // Check if we should alert
                if (alertAccumulator.ShouldAlert(alertKey, maxOccurrences, timeWindowMinutes))
                {
                    alerts.Add(new Alert
                    {
                        Severity = ParseAlertSeverity(alertSettings.OverdueTaskSeverity, AlertSeverity.Warning),
                        Category = Category,
                        Message = $"Scheduled task overdue: {task.Path}",
                        Details = $"{taskConfig.Description}: Task '{task.Name}' last run {(int)minutesSinceLastRun} minutes ago (threshold: {taskConfig.MaxMinutesSinceLastRun})",
                        SuppressedChannels = taskConfig.SuppressedChannels ?? new List<string>()
                    });
                    
                    alertAccumulator.ClearAfterAlert(alertKey, timeWindowMinutes);
                }
            }
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
    
    /// <summary>
    /// Fixes mojibake encoding issues (UTF-8 bytes interpreted as Windows-1252/Latin-1).
    /// Common with Norwegian/Scandinavian characters like å, ø, æ.
    /// Example: "Ã¥" -> "å", "Ã¸" -> "ø", "Ã¦" -> "æ"
    /// </summary>
    private static string? FixMojibakeEncoding(string? input)
    {
        if (string.IsNullOrEmpty(input))
            return input;
        
        // Quick check: if the string contains common mojibake patterns, try to fix it
        // UTF-8 Norwegian chars when wrongly interpreted as Windows-1252:
        // å (C3 A5) -> Ã¥, ø (C3 B8) -> Ã¸, æ (C3 A6) -> Ã¦
        // Å (C3 85) -> Ã…, Ø (C3 98) -> Ã˜, Æ (C3 86) -> Ã†
        if (!input.Contains('Ã'))
            return input;
        
        try
        {
            // The string was UTF-8 encoded but read as Windows-1252
            // To fix: encode as Windows-1252 (which gives us the original UTF-8 bytes), 
            // then decode as UTF-8
            var latin1 = Encoding.GetEncoding(1252);
            var utf8Bytes = latin1.GetBytes(input);
            var fixedString = Encoding.UTF8.GetString(utf8Bytes);
            
            // Verify the fix worked (should have fewer bytes and no Ã characters in common patterns)
            if (fixedString.Length < input.Length && !fixedString.Contains("Ã¥") && !fixedString.Contains("Ã¸"))
            {
                return fixedString;
            }
        }
        catch
        {
            // If fix fails, return original
        }
        
        return input;
    }
}

