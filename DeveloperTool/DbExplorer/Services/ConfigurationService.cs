using System.IO;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for loading and managing application configuration
/// </summary>
public class ConfigurationService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConfiguration _configuration;
    private readonly string _configFilePath;
    private AppSettings? _settings;
    private Dictionary<string, object>? _configDictionary;

    public ConfigurationService()
    {
        Logger.Debug("ConfigurationService initializing");

        _configFilePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "appsettings.json");

        try
        {
            _configuration = new ConfigurationBuilder()
                .SetBasePath(AppDomain.CurrentDomain.BaseDirectory)
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                .Build();

            LoadConfigDictionary();
            Logger.Debug("Configuration file appsettings.json loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load configuration file");
            throw;
        }
    }

    /// <summary>
    /// Get application settings
    /// </summary>
    public AppSettings Settings
    {
        get
        {
            if (_settings == null)
            {
                Logger.Debug("Loading application settings");
                _settings = new AppSettings();
                _configuration.Bind(_settings);
                Logger.Info("Application settings loaded successfully");
                Logger.Debug($"Theme: {_settings.Editor.DefaultTheme}, Framework: {_settings.Application.Framework}");
            }
            return _settings;
        }
    }

    /// <summary>
    /// Get a specific configuration value
    /// </summary>
    public string? GetValue(string key)
    {
        Logger.Debug($"Retrieving configuration value for key: {key}");
        return _configuration[key];
    }

    /// <summary>
    /// Get a configuration section
    /// </summary>
    public IConfigurationSection GetSection(string sectionName)
    {
        Logger.Debug($"Retrieving configuration section: {sectionName}");
        return _configuration.GetSection(sectionName);
    }

    /// <summary>
    /// Get a setting value with default fallback
    /// </summary>
    public T GetSetting<T>(string key, T defaultValue)
    {
        try
        {
            var value = _configuration[key];
            if (string.IsNullOrEmpty(value))
            {
                Logger.Debug($"Setting '{key}' not found, using default: {defaultValue}");
                return defaultValue;
            }

            var result = (T)Convert.ChangeType(value, typeof(T));
            Logger.Debug($"Retrieved setting '{key}': {result}");
            return result;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, $"Failed to retrieve setting '{key}', using default: {defaultValue}");
            return defaultValue;
        }
    }

    /// <summary>
    /// Set a setting value and save to file
    /// </summary>
    public void SetSetting(string key, object value)
    {
        try
        {
            Logger.Debug($"Setting '{key}' to: {value}");

            if (_configDictionary == null)
            {
                LoadConfigDictionary();
            }

            // Navigate to the correct nested dictionary
            var parts = key.Split(':');
            var current = _configDictionary;

            for (int i = 0; i < parts.Length - 1; i++)
            {
                if (!current!.ContainsKey(parts[i]))
                {
                    current[parts[i]] = new Dictionary<string, object>();
                }

                if (current[parts[i]] is not Dictionary<string, object> dict)
                {
                    dict = new Dictionary<string, object>();
                    current[parts[i]] = dict;
                }
                current = dict;
            }

            // Set the value
            current![parts[^1]] = value;

            // Save to file
            SaveConfigDictionary();

            // Invalidate cached settings
            _settings = null;

            Logger.Info($"Setting '{key}' saved successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to set setting '{key}'");
            throw;
        }
    }

    private void LoadConfigDictionary()
    {
        try
        {
            Logger.Debug("Loading configuration dictionary");
            var jsonText = File.ReadAllText(_configFilePath);
            _configDictionary = JsonSerializer.Deserialize<Dictionary<string, object>>(jsonText);

            if (_configDictionary == null)
            {
                _configDictionary = new Dictionary<string, object>();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load configuration dictionary");
            _configDictionary = new Dictionary<string, object>();
        }
    }

    private void SaveConfigDictionary()
    {
        try
        {
            Logger.Debug($"Saving configuration to: {_configFilePath}");

            var options = new JsonSerializerOptions
            {
                WriteIndented = true
            };

            var jsonText = JsonSerializer.Serialize(_configDictionary, options);
            File.WriteAllText(_configFilePath, jsonText);

            Logger.Info("Configuration saved successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save configuration");
            throw;
        }
    }
}

