using System;
using System.IO;
using System.Text;
using Newtonsoft.Json;
namespace DedgeCommon
{
    /// <summary>
    /// Contains global utility functions for accessing common paths and resources
    /// </summary>
    public static class GlobalFunctions
    {
        //public static string[] excemptedClasses = { typeof(GlobalFunctions)?.Name ?? "UNKNOWN", typeof(DedgeNLog).Name, typeof(DedgeConnection).Name };
        internal static string[] excemptedClasses = { typeof(DedgeDbHandler)?.Name ?? "UNKNOWN", typeof(DedgeNLog).Name };


        internal static string[] excemptedNamespaces = { typeof(GlobalFunctions)?.Namespace ?? "UNKNOWN" };
        internal static readonly string wkmonPath = @"C:\Program Files (x86)\WKMon\WKMon.exe";


        public class CallerInfo
        {
            public string Namespace { get; set; } = "Unknown";
            public string ClassName { get; set; } = "Unknown";
            public string MethodName { get; set; } = "Unknown";
            public string TypeName { get; set; } = "Unknown";
        }

        public static CallerInfo GetCallerInfo(bool skipExecempted)
        {
            var stackTrace = new System.Diagnostics.StackTrace();
            for (int i = 1; i < stackTrace.FrameCount; i++)
            {
                var frame = stackTrace.GetFrame(i);
                var method = frame?.GetMethod();
                var declaringType = method?.DeclaringType;
                var callerInfo = new CallerInfo
                {
                    TypeName = declaringType?.Name ?? "Unknown",
                    Namespace = declaringType?.Namespace ?? method?.DeclaringType?.Assembly.GetName().Name ?? "Unknown",
                    ClassName = declaringType?.Name ?? "Unknown",
                    MethodName = method?.Name ?? "Unknown"
                };
                // Handle top-level statements
                if (callerInfo.ClassName == "<Program>$" || callerInfo.ClassName.StartsWith("<"))
                {
                    var fileName = frame?.GetFileName();
                    if (!string.IsNullOrEmpty(fileName))
                    {
                        fileName = Path.GetFileNameWithoutExtension(fileName);
                        callerInfo.ClassName = fileName;
                    }
                }
                //Console.WriteLine($"CallerInfo #{i}:  {callerInfo.Namespace}.{callerInfo.ClassName}.{callerInfo.MethodName}");
                if (skipExecempted || !excemptedNamespaces.Contains(callerInfo.Namespace))
                {
                    return callerInfo;

                }
            }
            return new CallerInfo();
        }

        //new System.Diagnostics.StackFrame(2, true); 
        public static System.Diagnostics.StackFrame GetStackFrame()
        {
            var stackTrace = new System.Diagnostics.StackTrace();
            System.Diagnostics.StackFrame? resultFrame = null;
            for (int i = 1; i < stackTrace.FrameCount; i++)
            {
                resultFrame = stackTrace.GetFrame(i);
                var method = resultFrame?.GetMethod();
                var declaringType = method?.DeclaringType;
                string ns = declaringType?.Namespace ?? method?.DeclaringType?.Assembly.GetName().Name ?? "Unknown";
                if (declaringType != null && !excemptedNamespaces.Contains(ns))
                {
                    break;
                }
            }
            return resultFrame ?? new System.Diagnostics.StackFrame(0, true);
        }

        public static string GetNamespaceName(bool skipExecempted = false)
        {
            var callerInfo = GetCallerInfo(skipExecempted);
            if (callerInfo.ClassName.StartsWith("<"))
            {
                return callerInfo.ClassName; // Return filename as namespace for top-level statements
            }
            return callerInfo.Namespace;
        }

        public static string GetNamespaceClassName(bool skipExecempted = false)
        {
            var callerInfo = GetCallerInfo(skipExecempted);
            return string.IsNullOrEmpty(callerInfo.Namespace) || callerInfo.Namespace == "Unknown"
                ? callerInfo.ClassName
                : $"{callerInfo.Namespace}.{callerInfo.ClassName}";
        }

        public static string GetNamespaceClassMethodName(bool skipExecempted = false)
        {
            var callerInfo = GetCallerInfo(skipExecempted);
            return string.IsNullOrEmpty(callerInfo.Namespace) || callerInfo.Namespace == "Unknown"
                ? $"{callerInfo.ClassName}.{callerInfo.MethodName}"
                : $"{callerInfo.Namespace}.{callerInfo.ClassName}.{callerInfo.MethodName}";
        }
        public static string ClassMethod(bool skipExecempted = false)
        {
            var callerInfo = GetCallerInfo(skipExecempted);
            return $"{callerInfo.ClassName}.{callerInfo.MethodName}";
        }
        public static string GetClassName(bool skipExecempted = false)
        {
            var callerInfo = GetCallerInfo(skipExecempted);
            return $"{callerInfo.ClassName}";
        }
        public static string GetMethodName(bool skipExecempted = false)
        {
            var callerInfo = GetCallerInfo(skipExecempted);
            return $"{callerInfo.MethodName}";
        }

        /// <summary>
        /// Converts a local file path to its UNC equivalent.
        /// </summary>
        /// <param name="filePath">The local file path to convert</param>
        /// <returns>The UNC path equivalent of the input path</returns>
        /// <remarks>
        /// Handles conversion of:
        /// - Paths starting with OptUNCPath environment variable
        /// - Local drive paths (C:, D:, E:)
        /// - Already UNC-formatted paths
        /// </remarks>
        public static string GetUncPath(string filePath)
        {
            string optPathUnc = Environment.GetEnvironmentVariable("OptUncPath") ?? "";
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "";
            if (filePath.StartsWith(optPath))
            {
                string optPathDrive = optPath.Split(':')[0];
                string optPathRest = optPath.Split(':')[1];
                filePath = filePath.Replace(optPathDrive, "").TrimStart(':');
                string uncPath = $@"\\{Environment.MachineName}{filePath}";
                return uncPath;
            }
            else if (filePath.StartsWith("C:") || filePath.StartsWith("D:") || filePath.StartsWith("E:"))
            {
                string uncPath = filePath.Replace(":", "$");
                uncPath = $@"\\{Environment.MachineName}\{uncPath}";
                return uncPath;
            }
            else
            {
                return filePath;
            }
        }

        /// <summary>
        /// Gets the path to the global settings JSON file.
        /// </summary>
        /// <returns>The path to the GlobalSettings.json file.</returns>
        public static string GetGlobalSettingsFilePath()
        {
            return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json";
        }

        // Cache for the global settings to avoid reading the file repeatedly
        private static dynamic? _globalSettings;
        private static DateTime _globalSettingsLastRead = DateTime.MinValue;
        private static readonly TimeSpan _globalSettingsCacheTimeout = TimeSpan.FromMinutes(5);

        /// <summary>
        /// Reads and returns the global settings from the JSON file.
        /// Implements caching to avoid frequent file reads.
        /// </summary>
        /// <param name="forceRefresh">If true, forces a refresh of the cache.</param>
        /// <returns>The global settings as a dynamic object.</returns>
        public static dynamic GetGlobalSettings(bool forceRefresh = false)
        {
            if (_globalSettings == null ||
                forceRefresh ||
                (DateTime.Now - _globalSettingsLastRead) > _globalSettingsCacheTimeout)
            {
                try
                {
                    string settingsPath = GetGlobalSettingsFilePath();

                    // Check if file exists and create with default values if it doesn't
                    if (!System.IO.File.Exists(settingsPath))
                    {
                        CreateDefaultGlobalSettings(settingsPath);
                    }

                    string jsonContent = System.IO.File.ReadAllText(settingsPath);
                    // Use Newtonsoft.Json for dynamic deserialization (System.Text.Json doesn't handle dynamic well)
                    var deserializedSettings = Newtonsoft.Json.JsonConvert.DeserializeObject<dynamic>(jsonContent);
                    _globalSettings = deserializedSettings ?? CreateDefaultGlobalSettingsObject();
                    _globalSettingsLastRead = DateTime.Now;
                }
                catch (Exception ex)
                {
                    // If there's an error reading the file, create a default settings object
                    Console.WriteLine($"Error reading global settings: {ex.Message}");
                    _globalSettings = CreateDefaultGlobalSettingsObject();
                }
            }

            // Ensure we never return null
            return _globalSettings ?? CreateDefaultGlobalSettingsObject();
        }

        /// <summary>
        /// Updates the global settings file with new values.
        /// </summary>
        /// <param name="settings">The settings object to save.</param>
        public static void UpdateGlobalSettings(object settings)
        {
            try
            {
                string jsonContent = System.Text.Json.JsonSerializer.Serialize(settings, new System.Text.Json.JsonSerializerOptions
                {
                    WriteIndented = true,
                    MaxDepth = 100
                });
                File.WriteAllText(GetGlobalSettingsFilePath(), jsonContent);
                _globalSettings = settings;
                _globalSettingsLastRead = DateTime.Now;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error updating global settings: {ex.Message}");
            }
        }

        /// <summary>
        /// Creates the default global settings file if it doesn't exist.
        /// </summary>
        /// <param name="filePath">Path where the settings file should be created.</param>
        private static void CreateDefaultGlobalSettings(string filePath)
        {
            var defaultSettings = CreateDefaultGlobalSettingsObject();
            string jsonContent = System.Text.Json.JsonSerializer.Serialize(defaultSettings, new System.Text.Json.JsonSerializerOptions
            {
                WriteIndented = true,
                MaxDepth = 100
            });

            string? directoryName = System.IO.Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(directoryName))
            {
                System.IO.Directory.CreateDirectory(directoryName);
            }

            System.IO.File.WriteAllText(filePath, jsonContent);
        }

        /// <summary>
        /// Creates a default global settings object with all the current values.
        /// </summary>
        /// <returns>The default settings object.</returns>
        private static object CreateDefaultGlobalSettingsObject()
        {
            // Create an object with the current hardcoded values
            return new
            {
                Organization = new
                {
                    DefaultDomain = "DEDGE.fk.no"
                },
                Paths = new
                {
                    Common = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon",
                    CommonLog = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging",
                    DevToolsWeb = @"\\t-no1batch-vm01\opt\webs\DevTools",
                    DevToolsWebUrl = "http://t-no1batch-vm01//DevTools",
                    TempFk = "C:\\TEMPFK"
                },
                Config = new
                {
                    ComputerInfo = "ComputerInfo.json",
                    PortGroup = "PortGroup.json",
                    ServerTypes = "ServerTypes.json",
                    ServerPortGroupsMapping = "ServerPortGroupsMapping.json",
                    Databases = "Databases.json"
                },
                Directories = new
                {
                    Configfiles = "Configfiles",
                    ConfigResources = "Configfiles\\Resources",
                    Software = "Software",
                    PowerShellApps = "Software\\DedgePshApps",
                    NodeApps = "Software\\FkNodeJsApps",
                    PythonApps = "Software\\FkPythonApps",
                    WindowsApps = "Software\\DedgeWinApps",
                    RexxApps = "Software\\FkRexxApps",
                    WingetApps = "Software\\WingetApps",
                    OtherWindowsApps = "Software\\WindowsApps"
                },
                AzureDevOps = new
                {
                    Organization = "Dedge",
                    Project = "Dedge",
                    Repository = "Dedge",
                    Pat = "1tUXXsW0bstSLZynGlyR5E7C77GKhIi3gyup9IAqOFvQqe0EXKFDJQQJ99AKACAAAAAMSOigAAASAZDOCmX6"

                }
            };
        }

        /// <summary>
        /// Gets the default domain name.
        /// </summary>
        /// <returns>The organization's default domain name as a string.</returns>
        public static string GetDefaultDomain()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.DefaultDomain;
            }
            catch
            {
                DedgeNLog.Warn("Unable to read default domain from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read default domain from settings.");
            }
        }

        /// <summary>
        /// Gets the path to the DedgeCommon directory.
        /// </summary>
        /// <returns>The network path to the DedgeCommon directory containing shared resources.</returns>
        public static string GetCommonPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.Common;
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to DevTools web directory.
        /// </summary>
        /// <returns>The network path to the DevTools web directory.</returns>
        public static string GetDevToolsWebPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.DevToolsWeb;
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DevTools web path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to DevTools web content directory (where HTML files are deployed).
        /// </summary>
        /// <returns>The network path to the DevTools web content directory.</returns>
        public static string GetDevToolsWebContent()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.DevToolsWebContent;
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DevTools web content path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the URL for the DevTools web path.
        /// </summary>
        /// <returns>The URL to access the DevTools web directory.</returns>
        public static string GetDevToolsWebPathUrl()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.DevToolsWebUrl;
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DevTools web URL from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        // ══════════════════════════════════════════════════════════
        // Organization Section Methods
        // ══════════════════════════════════════════════════════════
        
        /// <summary>
        /// Gets the organization abbreviation (e.g., "FKA").
        /// </summary>
        public static string GetOrganizationAbbreviation()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.Abbreviation;
            }
            catch { return "FKA"; }
        }

        /// <summary>
        /// Gets the organization full name.
        /// </summary>
        public static string GetOrganizationFullName()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.FullName;
            }
            catch { return "Dedge"; }
        }

        /// <summary>
        /// Gets the organization short name.
        /// </summary>
        public static string GetOrganizationShortName()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.ShortName;
            }
            catch { return "Dedge"; }
        }

        /// <summary>
        /// Gets the organization number.
        /// </summary>
        public static string GetOrganizationNumber()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.OrganizationNumber;
            }
            catch { return "911608103"; }
        }

        /// <summary>
        /// Gets the organization website URL.
        /// </summary>
        public static string GetOrganizationWebsite()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.Website;
            }
            catch { return "https://www.Dedge.no"; }
        }

        /// <summary>
        /// Gets the organization logo URL.
        /// </summary>
        public static string GetOrganizationLogoUrl()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.LogoUrlPath;
            }
            catch { return "https://www.Dedge.no/Features/Shared/img/dedge-logo.svg"; }
        }

        /// <summary>
        /// Gets the organization logo UNC path.
        /// </summary>
        public static string GetOrganizationLogoUncPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.LogoUncPath;
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\Resources\dedge-logo.svg"; }
        }

        /// <summary>
        /// Gets the organization icon UNC path.
        /// </summary>
        public static string GetOrganizationIconUncPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.IconUncPath;
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\Resources\dedge.ico"; }
        }

        /// <summary>
        /// Gets the primary application name.
        /// </summary>
        public static string GetPrimaryApplicationName()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Organization.PrimaryApplicationName;
            }
            catch { return "FK Meny"; }
        }

        // ══════════════════════════════════════════════════════════
        // Additional Paths Section Methods
        // ══════════════════════════════════════════════════════════

        /// <summary>
        /// Gets the CommonLog path.
        /// </summary>
        public static string GetCommonLogPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.CommonLog;
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging"; }
        }

        /// <summary>
        /// Gets the TempFk path.
        /// </summary>
        public static string GetTempFkPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.TempFk;
            }
            catch { return @"C:\TEMPFK"; }
        }

        /// <summary>
        /// Gets the AdInfo path.
        /// </summary>
        public static string GetAdInfoPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return (string)settings.Paths.AdInfo;
            }
            catch { return @"\\p-no1fkmprd-app\opt\DedgePshApps\ad\brukere2.json"; }
        }

        // ══════════════════════════════════════════════════════════
        // Directories Section Methods
        // ══════════════════════════════════════════════════════════

        /// <summary>
        /// Gets the ConfigResources path.
        /// </summary>
        public static string GetConfigFilesResourcesPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetCommonPath()}\\{(string)settings.Directories.ConfigResources}";
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\Resources"; }
        }

        /// <summary>
        /// Gets the Software path.
        /// </summary>
        public static string GetSoftwarePath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetCommonPath()}\\{(string)settings.Directories.Software}";
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software"; }
        }

        /// <summary>
        /// Gets the PowerShell apps path.
        /// </summary>
        public static string GetPowerShellAppsPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetCommonPath()}\\{(string)settings.Directories.PowerShellApps}";
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps"; }
        }

        /// <summary>
        /// Gets the Logfiles path.
        /// </summary>
        public static string GetLogfilesPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetCommonPath()}\\{(string)settings.Directories.Logfiles}";
            }
            catch { return @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Logs"; }
        }

        /// <summary>
        /// Helper extension method to safely get string values from dynamic objects.
        /// </summary>
        private static string GetString(this object dynamicValue, string defaultValue = "")
        {
            if (dynamicValue == null)
                return defaultValue;

            return dynamicValue.ToString() ?? defaultValue;
        }

        /// <summary>
        /// Gets the path to configuration files.
        /// </summary>
        /// <returns>The path to the Configfiles directory within DedgeCommon.</returns>
        public static string GetConfigFilesPath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetCommonPath()}\\{(string)settings.Directories.Configfiles}";
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to the ComputerInfo.json file.
        /// </summary>
        /// <returns>Path to the computer information JSON file.</returns>
        public static string GetFkComputerInfoFilePath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetConfigFilesPath()}\\{(string)settings.Config.ComputerInfo}";
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to the PortGroup.json file.
        /// </summary>
        /// <returns>Path to the port group JSON file.</returns>
        public static string GetFkPortGroupFilePath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetConfigFilesPath()}\\{(string)settings.Config.PortGroup}";
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to the ServerTypes.json file.
        /// </summary>
        /// <returns>Path to the server types JSON file.</returns>
        public static string GetFkServerTypesFilePath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetConfigFilesPath()}\\{(string)settings.Config.ServerTypes}";
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to the ServerPortGroupsMapping.json file.
        /// </summary>
        /// <returns>Path to the server port groups mapping JSON file.</returns>
        public static string GetFkServerPortGroupsMappingFilePath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetConfigFilesPath()}\\{(string)settings.Config.ServerPortGroupsMapping}";
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the path to the Databases.json file.
        /// </summary>
        /// <returns>Path to the databases JSON file.</returns>
        public static string GetFkDatabasesFilePath()
        {
            try
            {
                var settings = GetGlobalSettings();
                return $"{GetConfigFilesPath()}\\{(string)settings.Config.Databases}";
            }
            catch
            {
                DedgeNLog.Warn("Unable to read DedgeCommon path from GlobalSettings (may not be accessible on this server)");
                throw new Exception("Unable to read DedgeCommon path from settings.");
            }
        }

        /// <summary>
        /// Gets the computer info data from ComputerInfo.json file.
        /// </summary>
        /// <returns>The computer info data as a dynamic object.</returns>
        public static dynamic GetFkComputerInfo()
        {
            try
            {
                string filePath = GetFkComputerInfoFilePath();
                string jsonContent = File.ReadAllText(filePath);
                return JsonConvert.DeserializeObject<dynamic>(jsonContent) ?? throw new Exception("Failed to deserialize computer info JSON");
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to read computer info JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Gets the port group data from PortGroup.json file.
        /// </summary>
        /// <returns>The port group data as a dynamic object.</returns>
        public static dynamic GetFkPortGroup()
        {
            try
            {
                string filePath = GetFkPortGroupFilePath();
                string jsonContent = File.ReadAllText(filePath);
                return JsonConvert.DeserializeObject<dynamic>(jsonContent) ?? throw new Exception("Failed to deserialize port group JSON");
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to read port group JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Gets the server types data from ServerTypes.json file.
        /// </summary>
        /// <returns>The server types data as a dynamic object.</returns>
        public static dynamic GetFkServerTypes()
        {
            try
            {
                string filePath = GetFkServerTypesFilePath();
                string jsonContent = File.ReadAllText(filePath);
                return JsonConvert.DeserializeObject<dynamic>(jsonContent) ?? throw new Exception("Failed to deserialize server types JSON");
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to read server types JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Gets the server port groups mapping data from ServerPortGroupsMapping.json file.
        /// </summary>
        /// <returns>The server port groups mapping data as a dynamic object.</returns>
        public static dynamic GetFkServerPortGroupsMapping()
        {
            try
            {
                string filePath = GetFkServerPortGroupsMappingFilePath();
                string jsonContent = File.ReadAllText(filePath);
                return JsonConvert.DeserializeObject<dynamic>(jsonContent) ?? throw new Exception("Failed to deserialize server port groups mapping JSON");
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to read server port groups mapping JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Gets the databases data from Databases.json file.
        /// </summary>
        /// <returns>The databases data as a dynamic object.</returns>
        public static dynamic GetFkDatabases()
        {
            try
            {
                string filePath = GetFkDatabasesFilePath();
                string jsonContent = File.ReadAllText(filePath);
                return JsonConvert.DeserializeObject<dynamic>(jsonContent) ?? throw new Exception("Failed to deserialize databases JSON");
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to read databases JSON: {ex.Message}");
                throw;
            }
        }
        /// <summary>
        /// Sets the computer info data in the ComputerInfo.json file.
        /// </summary>
        /// <param name="data">The computer info data to serialize.</param>
        public static void SetFkComputerInfo(object data)
        {
            try
            {
                string filePath = GetFkComputerInfoFilePath();
                string jsonContent = JsonConvert.SerializeObject(data, Formatting.Indented);
                File.WriteAllText(filePath, jsonContent);
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to write computer info JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Sets the port group data in the PortGroup.json file.
        /// </summary>
        /// <param name="data">The port group data to serialize.</param>
        public static void SetFkPortGroup(object data)
        {
            try
            {
                string filePath = GetFkPortGroupFilePath();
                string jsonContent = JsonConvert.SerializeObject(data, Formatting.Indented);
                File.WriteAllText(filePath, jsonContent);
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to write port group JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Sets the server types data in the ServerTypes.json file.
        /// </summary>
        /// <param name="data">The server types data to serialize.</param>
        public static void SetFkServerTypes(object data)
        {
            try
            {
                string filePath = GetFkServerTypesFilePath();
                string jsonContent = JsonConvert.SerializeObject(data, Formatting.Indented);
                File.WriteAllText(filePath, jsonContent);
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to write server types JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Sets the server port groups mapping data in the ServerPortGroupsMapping.json file.
        /// </summary>
        /// <param name="data">The server port groups mapping data to serialize.</param>
        public static void SetFkServerPortGroupsMapping(object data)
        {
            try
            {
                string filePath = GetFkServerPortGroupsMappingFilePath();
                string jsonContent = JsonConvert.SerializeObject(data, Formatting.Indented);
                File.WriteAllText(filePath, jsonContent);
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to write server port groups mapping JSON: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Sets the databases data in the Databases.json file.
        /// </summary>
        /// <param name="data">The databases data to serialize.</param>
        public static void SetFkDatabases(object data)
        {
            try
            {
                string filePath = GetFkDatabasesFilePath();
                string jsonContent = JsonConvert.SerializeObject(data, Formatting.Indented);
                File.WriteAllText(filePath, jsonContent);
            }
            catch (Exception ex)
            {
                DedgeNLog.Fatal($"Failed to write databases JSON: {ex.Message}");
                throw;
            }
        }


        public static void SendMonitorAlert(string program, string code, string message)
        {
            try
            {
                string timestamp = DateTime.Now.ToString("yyyyMMddHHmmss");
                string computerName = Environment.MachineName;

                // Format the WKMon message
                string wkmonMessage = $"{timestamp} {program} {code} {computerName}: {message}";

                // Log the message
                DedgeNLog.Info(wkmonMessage);

                // Determine monitoring file path
                string monitorPath = wkmonPath;
                if (computerName.Contains("SFKERP13"))
                {
                    monitorPath = @"\\DEDGE.fk.no\erpprog\cobnt\monitor\";
                }

                // Create monitoring file
                string monitorFileName = Path.Combine(monitorPath, $"{computerName}{timestamp}.MON");

                // Write message to file using ASCII encoding
                File.WriteAllText(monitorFileName, wkmonMessage, Encoding.ASCII);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error($"Failed to send WKMon alert: {ex.Message}");
                throw;
            }
        }
    }

}