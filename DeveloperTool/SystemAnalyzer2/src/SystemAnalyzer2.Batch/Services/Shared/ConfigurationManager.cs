using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json;
using SystemAnalyzer2.Core.Models.AutoDoc;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// Configuration Manager - converted from GlobalFunctions.psm1 configuration functions
/// Line-by-line conversion of Get-CachedGlobalConfiguration, Get-CommonLogPath, Get-DevToolsWebPathUrl, etc.
/// </summary>
public static class ConfigurationManager
{
    private static GlobalSettings? _cachedGlobalSettings;
    private static readonly object _lockObject = new object();

    // Line 26-28: Global configuration paths
    private static readonly string RemoteCommonConfigFilesFolder = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles";
    private static readonly string LocalCommonConfigFilesFolder = Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "data", "DedgeCommon", "Configfiles");
    private static readonly string RemoteGlobalSettingsFile = Path.Combine(RemoteCommonConfigFilesFolder, "GlobalSettings.json");

    /// <summary>
    /// Get cached global configuration
    /// Converted from Get-CachedGlobalConfiguration function (line 362-365)
    /// </summary>
    public static GlobalSettings GetGlobalSettings()
    {
        // Line 362-365: return Get-CommonSettings
        return GetCommonSettings();
    }

    /// <summary>
    /// Get common settings
    /// Converted from Get-CommonSettings function (line 149-160)
    /// </summary>
    private static GlobalSettings GetCommonSettings()
    {
        lock (_lockObject)
        {
            // Line 150: Check if cached
            if (_cachedGlobalSettings == null)
            {
                // Line 151: Load GlobalSettings.json
                string globalSettingsFile = GetGlobalSettingsJsonFilename();
                if (File.Exists(globalSettingsFile))
                {
                    string jsonContent = File.ReadAllText(globalSettingsFile);
                    _cachedGlobalSettings = JsonConvert.DeserializeObject<GlobalSettings>(jsonContent);

                    // Line 152-153: Load DatabasesV2.json and add to settings
                    string databasesV2File = GetDatabasesV2JsonFilename();
                    if (File.Exists(databasesV2File))
                    {
                        string dbJsonContent = File.ReadAllText(databasesV2File);
                        var databaseSettings = JsonConvert.DeserializeObject<object[]>(dbJsonContent);
                    if (databaseSettings != null)
                    {
                        // Filter active databases (equivalent to Where-Object { $_.IsActive -eq $true })
                        var activeDatabases = databaseSettings.Where(db =>
                        {
                            if (db is Newtonsoft.Json.Linq.JObject dbObj)
                            {
                                var isActive = dbObj["IsActive"];
                                return isActive != null && isActive.ToObject<bool>();
                            }
                            return false;
                        }).ToArray();

                            if (_cachedGlobalSettings != null)
                            {
                                _cachedGlobalSettings.DatabaseSettings = activeDatabases;
                            }
                        }
                    }
                }
                else
                {
                    // Create default settings if file doesn't exist
                    _cachedGlobalSettings = new GlobalSettings
                    {
                        Paths = new PathsSettings(),
                        Organization = new OrganizationSettings()
                    };
                }
            }

            // Line 156: return $global:FkGlobalSettings
            return _cachedGlobalSettings ?? new GlobalSettings();
        }
    }

    /// <summary>
    /// Get common log path
    /// Converted from Get-CommonLogPath function (line 721-724)
    /// </summary>
    public static string GetCommonLogPath()
    {
        // Line 722-723: $settings = Get-CachedGlobalConfiguration; return $settings.Paths.CommonLog
        GlobalSettings settings = GetGlobalSettings();
        return settings.Paths?.CommonLog ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "data", "AllPwshLog");
    }

    /// <summary>
    /// Get DevTools web URL
    /// Converted from Get-DevToolsWebPathUrl function (line 737-740)
    /// </summary>
    public static string GetDevToolsWebUrl()
    {
        // Line 738-739: $settings = Get-CachedGlobalConfiguration; return $settings.Paths.DevToolsWebUrl
        GlobalSettings settings = GetGlobalSettings();
        return settings.Paths?.DevToolsWebUrl ?? "";
    }

    /// <summary>
    /// Get common path
    /// Converted from Get-CommonPath function (line 753-756)
    /// </summary>
    public static string GetCommonPath()
    {
        // Line 754-755: $settings = Get-CachedGlobalConfiguration; return $settings.Paths.Common
        GlobalSettings settings = GetGlobalSettings();
        return settings.Paths?.Common ?? "";
    }

    /// <summary>
    /// Get temp FK path
    /// Converted from Get-TempFkPath function (line 769-772)
    /// </summary>
    public static string GetTempFkPath()
    {
        // Line 770-771: $settings = Get-CachedGlobalConfiguration; return $settings.Paths.TempFk
        GlobalSettings settings = GetGlobalSettings();
        return settings.Paths?.TempFk ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "data", "TempFk");
    }

    /// <summary>
    /// Get AD info path
    /// Converted from Get-AdInfoPath function (line 784-787)
    /// </summary>
    public static string GetAdInfoPath()
    {
        // Line 785-786: $settings = Get-CachedGlobalConfiguration; return $settings.Paths.AdInfo
        GlobalSettings settings = GetGlobalSettings();
        return settings.Paths?.AdInfo ?? "";
    }

    /// <summary>
    /// Get GlobalSettings.json filename
    /// Converted from Get-GlobalSettingsJsonFilename function (line 3645-3647)
    /// </summary>
    private static string GetGlobalSettingsJsonFilename()
    {
        // Line 3646: return $(Join-Path $global:RemoteCommonConfigFilesFolder "GlobalSettings.json")
        // Try remote first, fallback to local
        if (File.Exists(RemoteGlobalSettingsFile))
        {
            return RemoteGlobalSettingsFile;
        }

        string localFile = Path.Combine(LocalCommonConfigFilesFolder, "GlobalSettings.json");
        if (File.Exists(localFile))
        {
            return localFile;
        }

        return RemoteGlobalSettingsFile; // Return remote path even if doesn't exist (for error handling)
    }

    /// <summary>
    /// Get DatabasesV2.json filename
    /// Converted from Get-DatabasesV2JsonFilename function (line 3634-3636)
    /// </summary>
    private static string GetDatabasesV2JsonFilename()
    {
        // Line 3635: return $(Join-Path $global:RemoteCommonConfigFilesFolder "DatabasesV2.json")
        return Path.Combine(RemoteCommonConfigFilesFolder, "DatabasesV2.json");
    }
}
