using System.Text.Json;

namespace ServerMonitorDashboard.Services;

/// <summary>
/// Service for loading and saving ServerMonitor configuration files with backup support
/// </summary>
public class ConfigEditorService
{
    private readonly ILogger<ConfigEditorService> _logger;
    private readonly string _configBasePath;
    private readonly string _backupPath;

    public ConfigEditorService(ILogger<ConfigEditorService> logger)
    {
        _logger = logger;
        _configBasePath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor";
        _backupPath = Path.Combine(_configBasePath, "Backup");
    }

    /// <summary>
    /// Get the path to the agent appsettings file
    /// </summary>
    public string AgentSettingsPath => Path.Combine(_configBasePath, "appsettings.ServerMonitorAgent.json");
    
    /// <summary>
    /// Get the path to the notification recipients file
    /// </summary>
    public string NotificationRecipientsPath => Path.Combine(_configBasePath, "NotificationRecipients.json");

    /// <summary>
    /// Get the path to the dashboard appsettings file (local to dashboard service)
    /// </summary>
    public string DashboardSettingsPath
    {
        get
        {
            var exePath = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
            return Path.Combine(exePath, "appsettings.json");
        }
    }

    /// <summary>
    /// Load a configuration file as JSON
    /// </summary>
    public async Task<ConfigFileResult> LoadConfigAsync(ConfigFileType fileType)
    {
        var filePath = GetFilePath(fileType);
        
        try
        {
            if (!File.Exists(filePath))
            {
                _logger.LogWarning("Config file not found: {Path}", filePath);
                return new ConfigFileResult
                {
                    Success = false,
                    Error = $"Configuration file not found: {Path.GetFileName(filePath)}",
                    FilePath = filePath
                };
            }

            var content = await File.ReadAllTextAsync(filePath);
            
            // Validate JSON
            try
            {
                using var doc = JsonDocument.Parse(content);
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Invalid JSON in config file: {Path}", filePath);
                return new ConfigFileResult
                {
                    Success = false,
                    Error = $"Invalid JSON format: {ex.Message}",
                    FilePath = filePath,
                    Content = content // Return content anyway so user can fix it
                };
            }

            var fileInfo = new FileInfo(filePath);
            
            return new ConfigFileResult
            {
                Success = true,
                Content = content,
                FilePath = filePath,
                LastModified = fileInfo.LastWriteTimeUtc,
                FileSize = fileInfo.Length
            };
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogError(ex, "Access denied to config file: {Path}", filePath);
            return new ConfigFileResult
            {
                Success = false,
                Error = "Access denied. Check file permissions.",
                FilePath = filePath
            };
        }
        catch (IOException ex)
        {
            _logger.LogError(ex, "IO error reading config file: {Path}", filePath);
            return new ConfigFileResult
            {
                Success = false,
                Error = $"Could not read file: {ex.Message}",
                FilePath = filePath
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading config file: {Path}", filePath);
            return new ConfigFileResult
            {
                Success = false,
                Error = $"Unexpected error: {ex.Message}",
                FilePath = filePath
            };
        }
    }

    /// <summary>
    /// Save a configuration file with backup
    /// </summary>
    public async Task<ConfigSaveResult> SaveConfigAsync(ConfigFileType fileType, string content, string? editedBy = null)
    {
        var filePath = GetFilePath(fileType);
        
        try
        {
            // Validate JSON before saving
            try
            {
                using var doc = JsonDocument.Parse(content);
            }
            catch (JsonException ex)
            {
                _logger.LogWarning("Attempted to save invalid JSON: {Error}", ex.Message);
                return new ConfigSaveResult
                {
                    Success = false,
                    Error = $"Invalid JSON format: {ex.Message}"
                };
            }

            // Create backup directory if it doesn't exist
            if (!Directory.Exists(_backupPath))
            {
                Directory.CreateDirectory(_backupPath);
                _logger.LogInformation("Created backup directory: {Path}", _backupPath);
            }

            // Create backup of existing file
            string? backupFilePath = null;
            if (File.Exists(filePath))
            {
                var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HHmmss");
                var fileName = Path.GetFileNameWithoutExtension(filePath);
                var extension = Path.GetExtension(filePath);
                var backupFileName = $"{timestamp}_{fileName}{extension}";
                backupFilePath = Path.Combine(_backupPath, backupFileName);
                
                File.Copy(filePath, backupFilePath, overwrite: true);
                _logger.LogInformation("Created backup: {BackupPath}", backupFilePath);
            }

            // Format JSON nicely before saving
            string formattedContent;
            try
            {
                using var doc = JsonDocument.Parse(content);
                formattedContent = JsonSerializer.Serialize(doc, new JsonSerializerOptions
                {
                    WriteIndented = true
                });
            }
            catch
            {
                formattedContent = content; // Use original if formatting fails
            }

            // Save the new content
            await File.WriteAllTextAsync(filePath, formattedContent);
            
            var fileInfo = new FileInfo(filePath);
            
            _logger.LogInformation("Saved config file: {Path} (backup: {Backup}, editedBy: {EditedBy})", 
                filePath, backupFilePath ?? "none", editedBy ?? "unknown");

            return new ConfigSaveResult
            {
                Success = true,
                FilePath = filePath,
                BackupPath = backupFilePath,
                LastModified = fileInfo.LastWriteTimeUtc,
                FileSize = fileInfo.Length
            };
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogError(ex, "Access denied saving config file: {Path}", filePath);
            return new ConfigSaveResult
            {
                Success = false,
                Error = "Access denied. Check file permissions."
            };
        }
        catch (IOException ex)
        {
            _logger.LogError(ex, "IO error saving config file: {Path}", filePath);
            return new ConfigSaveResult
            {
                Success = false,
                Error = $"Could not save file: {ex.Message}"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving config file: {Path}", filePath);
            return new ConfigSaveResult
            {
                Success = false,
                Error = $"Unexpected error: {ex.Message}"
            };
        }
    }

    /// <summary>
    /// List all backup files
    /// </summary>
    public List<BackupFileInfo> GetBackupFiles()
    {
        var backups = new List<BackupFileInfo>();
        
        try
        {
            if (!Directory.Exists(_backupPath))
            {
                return backups;
            }

            var files = Directory.GetFiles(_backupPath, "*.json")
                .OrderByDescending(f => f)
                .Take(50); // Limit to 50 most recent

            foreach (var file in files)
            {
                var fileInfo = new FileInfo(file);
                backups.Add(new BackupFileInfo
                {
                    FileName = Path.GetFileName(file),
                    FilePath = file,
                    CreatedAt = fileInfo.CreationTimeUtc,
                    FileSize = fileInfo.Length
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing backup files");
        }

        return backups;
    }

    /// <summary>
    /// Restore a backup file
    /// </summary>
    public async Task<ConfigSaveResult> RestoreBackupAsync(string backupFileName, ConfigFileType fileType)
    {
        var backupFilePath = Path.Combine(_backupPath, backupFileName);
        var targetPath = GetFilePath(fileType);

        try
        {
            if (!File.Exists(backupFilePath))
            {
                return new ConfigSaveResult
                {
                    Success = false,
                    Error = "Backup file not found"
                };
            }

            var content = await File.ReadAllTextAsync(backupFilePath);
            return await SaveConfigAsync(fileType, content, "restore");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restoring backup: {BackupFile}", backupFileName);
            return new ConfigSaveResult
            {
                Success = false,
                Error = $"Restore failed: {ex.Message}"
            };
        }
    }

    private string GetFilePath(ConfigFileType fileType)
    {
        return fileType switch
        {
            ConfigFileType.AgentSettings => AgentSettingsPath,
            ConfigFileType.NotificationRecipients => NotificationRecipientsPath,
            ConfigFileType.DashboardSettings => DashboardSettingsPath,
            _ => throw new ArgumentException($"Unknown config file type: {fileType}")
        };
    }

    /// <summary>
    /// Get the Alert Routing Overview - shows effective channel status per environment with reasons
    /// </summary>
    public async Task<AlertRoutingOverview> GetAlertRoutingOverviewAsync()
    {
        var result = new AlertRoutingOverview();
        
        try
        {
            // Load both config files
            var agentSettingsResult = await LoadConfigAsync(ConfigFileType.AgentSettings);
            var notificationRecipientsResult = await LoadConfigAsync(ConfigFileType.NotificationRecipients);

            if (!agentSettingsResult.Success || string.IsNullOrEmpty(agentSettingsResult.Content))
            {
                result.Error = $"Failed to load agent settings: {agentSettingsResult.Error}";
                return result;
            }

            if (!notificationRecipientsResult.Success || string.IsNullOrEmpty(notificationRecipientsResult.Content))
            {
                result.Error = $"Failed to load notification recipients: {notificationRecipientsResult.Error}";
                return result;
            }

            // Parse JSON files
            using var agentDoc = JsonDocument.Parse(agentSettingsResult.Content);
            using var recipientsDoc = JsonDocument.Parse(notificationRecipientsResult.Content);

            // Get channel base settings from appsettings.json
            var channelBaseSettings = ExtractChannelBaseSettings(agentDoc);

            // Get environment channel overrides from NotificationRecipients.json
            var environments = ExtractEnvironments(recipientsDoc);

            // Get per-monitor SuppressedChannels
            var monitorSuppressions = ExtractMonitorSuppressions(agentDoc);

            // Build the routing overview
            result.Channels = new[] { "SMS", "Email", "EventLog", "File", "WKMonitor" };
            result.Environments = environments.Select(e => new EnvironmentInfo
            {
                Name = e.Name,
                Description = e.Description,
                IsDefault = e.IsDefault,
                Patterns = e.Patterns
            }).ToList();

            result.RoutingMatrix = new List<ChannelRoutingInfo>();

            foreach (var channel in result.Channels)
            {
                var routingInfo = new ChannelRoutingInfo
                {
                    ChannelName = channel,
                    BaseEnabled = channelBaseSettings.TryGetValue(channel, out var baseEnabled) && baseEnabled,
                    EnvironmentStatus = new Dictionary<string, ChannelEnvironmentStatus>()
                };

                // Determine base status reasons
                var baseReasons = new List<string>();
                if (!channelBaseSettings.ContainsKey(channel))
                {
                    baseReasons.Add("Channel not configured in appsettings.json");
                }
                else if (!baseEnabled)
                {
                    baseReasons.Add("Channel disabled in appsettings.json (Alerting.Channels)");
                }
                else
                {
                    baseReasons.Add("Channel enabled in appsettings.json (Alerting.Channels)");
                }
                routingInfo.BaseReasons = baseReasons;

                // Calculate effective status for each environment
                foreach (var env in environments)
                {
                    var status = new ChannelEnvironmentStatus
                    {
                        Reasons = new List<string>()
                    };

                    // Start with base setting
                    var isEnabled = routingInfo.BaseEnabled;
                    status.Reasons.AddRange(baseReasons);

                    // Apply environment override
                    if (env.ChannelSettings.TryGetValue(channel.ToLowerInvariant(), out var envEnabled))
                    {
                        if (!envEnabled)
                        {
                            isEnabled = false;
                            status.Reasons.Add($"Disabled by {env.Name} environment in NotificationRecipients.json");
                        }
                        else if (isEnabled)
                        {
                            status.Reasons.Add($"Allowed by {env.Name} environment in NotificationRecipients.json");
                        }
                    }

                    status.Enabled = isEnabled;
                    routingInfo.EnvironmentStatus[env.Name] = status;
                }

                result.RoutingMatrix.Add(routingInfo);
            }

            // Add monitor suppressions info
            result.MonitorSuppressions = monitorSuppressions;
            result.Success = true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error building alert routing overview");
            result.Error = $"Error: {ex.Message}";
        }

        return result;
    }

    private Dictionary<string, bool> ExtractChannelBaseSettings(JsonDocument doc)
    {
        var settings = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        try
        {
            if (doc.RootElement.TryGetProperty("Alerting", out var alerting) &&
                alerting.TryGetProperty("Channels", out var channels))
            {
                foreach (var channel in channels.EnumerateArray())
                {
                    if (channel.TryGetProperty("Type", out var typeElem) &&
                        channel.TryGetProperty("Enabled", out var enabledElem))
                    {
                        var type = typeElem.GetString();
                        var enabled = enabledElem.GetBoolean();
                        if (!string.IsNullOrEmpty(type))
                        {
                            settings[type] = enabled;
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error extracting channel base settings");
        }

        return settings;
    }

    private List<EnvironmentOverride> ExtractEnvironments(JsonDocument doc)
    {
        var environments = new List<EnvironmentOverride>();

        try
        {
            if (doc.RootElement.TryGetProperty("environments", out var envArray))
            {
                foreach (var env in envArray.EnumerateArray())
                {
                    var envOverride = new EnvironmentOverride
                    {
                        Name = env.TryGetProperty("name", out var nameElem) ? nameElem.GetString() ?? "Unknown" : "Unknown",
                        Description = env.TryGetProperty("description", out var descElem) ? descElem.GetString() : null,
                        IsDefault = env.TryGetProperty("isDefault", out var defaultElem) && defaultElem.GetBoolean(),
                        Patterns = new List<string>(),
                        ChannelSettings = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase)
                    };

                    if (env.TryGetProperty("computerNamePatterns", out var patterns))
                    {
                        foreach (var pattern in patterns.EnumerateArray())
                        {
                            var p = pattern.GetString();
                            if (!string.IsNullOrEmpty(p))
                            {
                                envOverride.Patterns.Add(p);
                            }
                        }
                    }

                    if (env.TryGetProperty("channels", out var channels))
                    {
                        foreach (var prop in channels.EnumerateObject())
                        {
                            if (prop.Name.StartsWith("_")) continue; // Skip notes
                            if (prop.Value.ValueKind == JsonValueKind.True || prop.Value.ValueKind == JsonValueKind.False)
                            {
                                envOverride.ChannelSettings[prop.Name] = prop.Value.GetBoolean();
                            }
                        }
                    }

                    environments.Add(envOverride);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error extracting environments");
        }

        return environments;
    }

    private Dictionary<string, List<string>> ExtractMonitorSuppressions(JsonDocument doc)
    {
        var suppressions = new Dictionary<string, List<string>>();

        try
        {
            if (doc.RootElement.TryGetProperty("Surveillance", out var surveillance))
            {
                foreach (var prop in surveillance.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Object &&
                        prop.Value.TryGetProperty("SuppressedChannels", out var suppressed) &&
                        suppressed.ValueKind == JsonValueKind.Array)
                    {
                        var channels = new List<string>();
                        foreach (var ch in suppressed.EnumerateArray())
                        {
                            var chName = ch.GetString();
                            if (!string.IsNullOrEmpty(chName))
                            {
                                channels.Add(chName);
                            }
                        }
                        if (channels.Count > 0)
                        {
                            suppressions[prop.Name] = channels;
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error extracting monitor suppressions");
        }

        return suppressions;
    }
}

// Helper classes for environment extraction
internal class EnvironmentOverride
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsDefault { get; set; }
    public List<string> Patterns { get; set; } = new();
    public Dictionary<string, bool> ChannelSettings { get; set; } = new();
}

public enum ConfigFileType
{
    AgentSettings,
    NotificationRecipients,
    DashboardSettings
}

public class ConfigFileResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string? Content { get; set; }
    public string? FilePath { get; set; }
    public DateTime? LastModified { get; set; }
    public long? FileSize { get; set; }
}

public class ConfigSaveResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string? FilePath { get; set; }
    public string? BackupPath { get; set; }
    public DateTime? LastModified { get; set; }
    public long? FileSize { get; set; }
}

public class BackupFileInfo
{
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public long FileSize { get; set; }
}

// Alert Routing Overview Models
public class AlertRoutingOverview
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string[] Channels { get; set; } = Array.Empty<string>();
    public List<EnvironmentInfo> Environments { get; set; } = new();
    public List<ChannelRoutingInfo> RoutingMatrix { get; set; } = new();
    public Dictionary<string, List<string>> MonitorSuppressions { get; set; } = new();
}

public class EnvironmentInfo
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsDefault { get; set; }
    public List<string> Patterns { get; set; } = new();
}

public class ChannelRoutingInfo
{
    public string ChannelName { get; set; } = string.Empty;
    public bool BaseEnabled { get; set; }
    public List<string> BaseReasons { get; set; } = new();
    public Dictionary<string, ChannelEnvironmentStatus> EnvironmentStatus { get; set; } = new();
}

public class ChannelEnvironmentStatus
{
    public bool Enabled { get; set; }
    public List<string> Reasons { get; set; } = new();
}
