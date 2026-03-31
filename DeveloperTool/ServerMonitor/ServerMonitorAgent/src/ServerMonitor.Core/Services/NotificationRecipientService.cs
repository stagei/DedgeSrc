using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Service to manage notification recipients with per-environment, per-person, per-day rules
/// </summary>
public class NotificationRecipientService
{
    private readonly ILogger<NotificationRecipientService> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private NotificationRecipientsConfig? _configCache;
    private DateTime _lastLoadTime = DateTime.MinValue;
    private readonly object _lock = new();
    private readonly string _localConfigPath;

    public NotificationRecipientService(
        ILogger<NotificationRecipientService> logger,
        IOptionsMonitor<SurveillanceConfiguration> config)
    {
        _logger = logger;
        _config = config;
        _localConfigPath = Path.Combine(AppContext.BaseDirectory, "NotificationRecipients.json");
    }

    /// <summary>
    /// Get recipients for a specific alert based on environment, day, time, and channel
    /// </summary>
    public List<RecipientInfo> GetRecipientsForAlert(
        string channel, 
        DateTime? alertTime = null)
    {
        // Use local time for time range comparisons (convert UTC to local if needed)
        var alertTimeUtc = alertTime ?? DateTime.UtcNow;
        var currentTime = alertTimeUtc.Kind == DateTimeKind.Utc 
            ? alertTimeUtc.ToLocalTime() 
            : alertTimeUtc;
        var dayOfWeek = currentTime.DayOfWeek.ToString();
        var environment = DetectEnvironment();

        _logger.LogDebug("Getting recipients for channel={Channel}, environment={Env}, day={Day}, time={Time}",
            channel, environment, dayOfWeek, currentTime.ToString("HH:mm"));

        var config = LoadConfiguration();
        if (config == null)
        {
            _logger.LogWarning("NotificationRecipients config not available - returning empty list");
            return new List<RecipientInfo>();
        }

        var recipients = new List<RecipientInfo>();

        foreach (var person in config.People.Where(p => p.Enabled))
        {
            // Check if person is absent
            if (IsPersonAbsent(person, currentTime.Date))
            {
                // Try to use backup person
                var backupPersonId = GetBackupPerson(person, currentTime.Date);
                if (!string.IsNullOrEmpty(backupPersonId))
                {
                    var backupPerson = config.People.FirstOrDefault(p => p.Id == backupPersonId && p.Enabled);
                    if (backupPerson != null)
                    {
                        _logger.LogDebug("Person {PersonId} is absent, using backup {BackupId}",
                            person.Id, backupPersonId);
                        var backupRecipients = GetRecipientsForPerson(backupPerson, environment, dayOfWeek, currentTime, channel);
                        foreach (var recipient in backupRecipients)
                        {
                            recipient.IsBackup = true;
                            recipient.OriginalPersonId = person.Id;
                        }
                        recipients.AddRange(backupRecipients);
                    }
                    else
                    {
                        _logger.LogWarning("Backup person {BackupId} not found or disabled for absent person {PersonId}",
                            backupPersonId, person.Id);
                    }
                }
                else
                {
                    _logger.LogDebug("Person {PersonId} is absent and has no backup - skipping",
                        person.Id);
                }
                continue;
            }

            // Get recipients for this person
            var personRecipients = GetRecipientsForPerson(person, environment, dayOfWeek, currentTime, channel);
            recipients.AddRange(personRecipients);
        }

        _logger.LogDebug("Found {Count} recipients for channel={Channel}, environment={Env}",
            recipients.Count, channel, environment);

        return recipients;
    }

    private List<RecipientInfo> GetRecipientsForPerson(
        PersonConfig person,
        string environment,
        string dayOfWeek,
        DateTime currentTime,
        string channel)
    {
        var recipients = new List<RecipientInfo>();

        // Check if person has rules for this environment
        if (!person.Environments.TryGetValue(environment, out var envRules))
        {
            _logger.LogDebug("Person {PersonId} has no rules for environment {Env}",
                person.Id, environment);
            return recipients;
        }

        // Check if person has rules for this day
        if (!envRules.TryGetValue(dayOfWeek, out var dayRule))
        {
            _logger.LogDebug("Person {PersonId} has no rules for {Env} > {Day}",
                person.Id, environment, dayOfWeek);
            return recipients;
        }

        // Check email channel
        if (channel.Equals("Email", StringComparison.OrdinalIgnoreCase))
        {
            if (IsTimeWithinRange(dayRule.Email, currentTime))
            {
                recipients.Add(new RecipientInfo
                {
                    PersonId = person.Id,
                    Name = person.Name,
                    Email = person.Email,
                    Phone = person.Phone
                });
                _logger.LogDebug("Person {PersonId} ({Name}) will receive email - time {Time} is within range {Range}",
                    person.Id, person.Name, currentTime.ToString("HH:mm"),
                    dayRule.Email != null ? $"{dayRule.Email.From}-{dayRule.Email.To}" : "null");
            }
        }

        // Check SMS channel
        if (channel.Equals("SMS", StringComparison.OrdinalIgnoreCase))
        {
            if (IsTimeWithinRange(dayRule.Sms, currentTime))
            {
                recipients.Add(new RecipientInfo
                {
                    PersonId = person.Id,
                    Name = person.Name,
                    Email = person.Email,
                    Phone = person.Phone
                });
                _logger.LogDebug("Person {PersonId} ({Name}) will receive SMS - time {Time} is within range {Range}",
                    person.Id, person.Name, currentTime.ToString("HH:mm"),
                    dayRule.Sms != null ? $"{dayRule.Sms.From}-{dayRule.Sms.To}" : "null");
            }
        }

        return recipients;
    }

    private bool IsTimeWithinRange(TimeRange? range, DateTime currentTime)
    {
        if (range == null)
            return false; // Channel disabled

        var currentTimeStr = currentTime.ToString("HH:mm");
        var fromTime = range.From;
        var toTime = range.To;
        
        // Handle time ranges that span midnight (e.g., 22:00 to 06:00)
        if (string.Compare(fromTime, toTime, StringComparison.Ordinal) > 0)
        {
            // Range spans midnight: current time must be >= from OR <= to
            return string.Compare(currentTimeStr, fromTime, StringComparison.Ordinal) >= 0 ||
                   string.Compare(currentTimeStr, toTime, StringComparison.Ordinal) <= 0;
        }
        else
        {
            // Normal range: current time must be >= from AND <= to
            return string.Compare(currentTimeStr, fromTime, StringComparison.Ordinal) >= 0 &&
                   string.Compare(currentTimeStr, toTime, StringComparison.Ordinal) <= 0;
        }
    }

    private string DetectEnvironment()
    {
        var config = LoadConfiguration();
        if (config == null)
            return "Production"; // Default

        var computerName = Environment.MachineName;
        EnvironmentConfig? defaultEnv = null;

        // First pass: try to match non-default environments (exclude catch-all "*" patterns)
        foreach (var env in config.Environments)
        {
            // Track the default environment for fallback
            if (env.IsDefault)
            {
                defaultEnv = env;
                continue; // Skip default environment in first pass
            }
            
            foreach (var pattern in env.ComputerNamePatterns)
            {
                // Skip catch-all patterns
                if (pattern == "*") continue;
                
                // Convert wildcard pattern to regex
                var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
                if (Regex.IsMatch(computerName, regexPattern, RegexOptions.IgnoreCase))
                {
                    _logger.LogDebug("Detected environment {Env} for computer {Computer} (pattern: {Pattern})",
                        env.Name, computerName, pattern);
                    return env.Name;
                }
            }
        }

        // No specific match - use default environment if available
        if (defaultEnv != null)
        {
            _logger.LogDebug("No specific environment matched for {Computer} - using default: {Env}",
                computerName, defaultEnv.Name);
            return defaultEnv.Name;
        }

        _logger.LogWarning("No environment pattern matched for computer {Computer} - defaulting to Production",
            computerName);
        return "Production"; // Fallback
    }

    private bool IsPersonAbsent(PersonConfig person, DateTime date)
    {
        return person.Absences.Any(a => date >= a.StartDate.Date && date <= a.EndDate.Date);
    }

    private string? GetBackupPerson(PersonConfig person, DateTime date)
    {
        var absence = person.Absences.FirstOrDefault(a => date >= a.StartDate.Date && date <= a.EndDate.Date);
        return absence?.BackupPersonId;
    }

    private NotificationRecipientsConfig? LoadConfiguration()
    {
        lock (_lock)
        {
            // Check if file was modified (always reload if cache is null or file changed)
            if (File.Exists(_localConfigPath))
            {
                var lastWriteTime = File.GetLastWriteTime(_localConfigPath);
                if (_configCache != null && lastWriteTime <= _lastLoadTime)
                {
                    return _configCache; // Use cached version
                }
                // File was modified or cache is null - will reload below
            }
            else if (_configCache != null)
            {
                // File doesn't exist but we have cache - return cache
                return _configCache;
            }

            try
            {
                if (!File.Exists(_localConfigPath))
                {
                    _logger.LogWarning("NotificationRecipients.json not found at {Path} - returning null",
                        _localConfigPath);
                    return null;
                }

                var json = File.ReadAllText(_localConfigPath);
                var config = JsonSerializer.Deserialize<NotificationRecipientsConfig>(json, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });

                if (config == null)
                {
                    _logger.LogError("Failed to deserialize NotificationRecipients.json");
                    return null;
                }

                _configCache = config;
                _lastLoadTime = File.GetLastWriteTime(_localConfigPath);
                _logger.LogInformation("Loaded NotificationRecipients config: {PeopleCount} people, {EnvCount} environments",
                    config.People.Count, config.Environments.Count);

                return config;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading NotificationRecipients.json from {Path}",
                    _localConfigPath);
                return _configCache; // Return cached version on error
            }
        }
    }

    /// <summary>
    /// Force reload of configuration (useful after sync)
    /// </summary>
    public void ReloadConfiguration()
    {
        lock (_lock)
        {
            _configCache = null;
            _lastLoadTime = DateTime.MinValue;
        }
    }
    
    /// <summary>
    /// Check if a channel is enabled for the current environment based on machine name.
    /// Returns true if channel is enabled, false if disabled.
    /// If no environment matches or no channel config is set, defaults to true (enabled).
    /// </summary>
    public bool IsChannelEnabledForEnvironment(string channelType)
    {
        var env = GetMatchingEnvironment();
        if (env == null)
        {
            _logger.LogDebug("No NotificationRecipients config - all channels enabled by default");
            return true;
        }
        
        if (env.Channels == null)
        {
            _logger.LogDebug("Environment {Env} has no channel config - all channels enabled", env.Name);
            return true;
        }
        
        var isEnabled = env.Channels.IsChannelEnabled(channelType);
        _logger.LogDebug("Channel {Channel} is {Status} for environment {Env} (computer: {Computer})",
            channelType, isEnabled ? "enabled" : "disabled", env.Name, Environment.MachineName);
        return isEnabled;
    }
    
    /// <summary>
    /// Get the current detected environment name for the machine
    /// </summary>
    public string GetCurrentEnvironment()
    {
        return DetectEnvironment();
    }
    
    /// <summary>
    /// Get the channel settings for the current environment (or null if not configured)
    /// </summary>
    public EnvironmentChannelConfig? GetCurrentEnvironmentChannelConfig()
    {
        return GetMatchingEnvironment()?.Channels;
    }
    
    /// <summary>
    /// Get the matching environment configuration for the current machine
    /// </summary>
    public EnvironmentConfig? GetMatchingEnvironment()
    {
        var config = LoadConfiguration();
        if (config == null) return null;
        
        var computerName = Environment.MachineName;
        EnvironmentConfig? defaultEnv = null;
        
        // First pass: try to match non-default environments
        foreach (var env in config.Environments)
        {
            if (env.IsDefault)
            {
                defaultEnv = env;
                continue;
            }
            
            foreach (var pattern in env.ComputerNamePatterns)
            {
                if (pattern == "*") continue;
                
                var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
                if (Regex.IsMatch(computerName, regexPattern, RegexOptions.IgnoreCase))
                {
                    return env;
                }
            }
        }
        
        // Return default environment if no specific match
        return defaultEnv;
    }
    
    /// <summary>
    /// Get all configured environments (for UI display)
    /// </summary>
    public List<EnvironmentConfig> GetAllEnvironments()
    {
        var config = LoadConfiguration();
        return config?.Environments ?? new List<EnvironmentConfig>();
    }
}

