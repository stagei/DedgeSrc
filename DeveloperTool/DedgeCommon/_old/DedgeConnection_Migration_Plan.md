# DedgeConnection.cs Migration Plan: From Hardcoded to JSON Configuration

## Overview

This document outlines the plan to migrate `DedgeConnection.cs` from hardcoded connection data to using the `DatabasesV2.json` configuration file while maintaining backward compatibility and the same function signatures.

## Current State Analysis

### Current Implementation
- **Hardcoded Data**: All connection information is stored in the `ConnectionInfoDict` dictionary
- **Static Dictionary**: Contains 20+ connection entries with version 1.0 and 2.0
- **Manual Maintenance**: Adding new connections requires code changes
- **Version Management**: Uses `CurrentVersions` dictionary to track active versions

### JSON Configuration Structure
The `DatabasesV2.json` file contains:
- **Database**: Database name (e.g., "FKDBQA", "FKMDEV")
- **Provider**: Database provider ("DB2", "SQLSERVER")
- **Application**: Application name (e.g., "FKDBQA", "FKM", "INL")
- **Environment**: Environment type (e.g., "PRD", "DEV", "TST")
- **Version**: Version string (e.g., "2.0")
- **PrimaryCatalogName**: Primary catalog name
- **IsActive**: Boolean flag for active/inactive connections
- **ServerName**: Server name
- **Description**: English description
- **NorwegianDescription**: Norwegian description
- **AccessPoints**: Array of access point configurations

## Migration Strategy

### Phase 1: JSON Configuration Loading
Create a new configuration loader that reads and parses the JSON file.

```csharp
public class FkDatabaseConfig
{
    public string Database { get; set; }
    public string Provider { get; set; }
    public string Application { get; set; }
    public string Environment { get; set; }
    public string Version { get; set; }
    public string PrimaryCatalogName { get; set; }
    public bool IsActive { get; set; }
    public string ServerName { get; set; }
    public string Description { get; set; }
    public string NorwegianDescription { get; set; }
    public List<AccessPoint> AccessPoints { get; set; }
}

public class AccessPoint
{
    public string InstanceName { get; set; }
    public string CatalogName { get; set; }
    public string AccessPointType { get; set; }
    public string Port { get; set; }
    public string ServiceName { get; set; }
    public string NodeName { get; set; }
    public string AuthenticationType { get; set; }
    public string UID { get; set; }
    public string PWD { get; set; }
    public bool IsActive { get; set; }
}
```

### Phase 2: Configuration Manager
Create a configuration manager that loads and caches the JSON data.

```csharp
public static class FkConfigurationManager
{
    private static readonly string ConfigFilePath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json";
    private static List<FkDatabaseConfig> _configurations;
    private static DateTime _lastLoadTime;
    private static readonly TimeSpan CacheExpiry = TimeSpan.FromMinutes(5);

    public static List<FkDatabaseConfig> GetConfigurations()
    {
        if (_configurations == null || DateTime.Now - _lastLoadTime > CacheExpiry)
        {
            LoadConfigurations();
        }
        return _configurations;
    }

    private static void LoadConfigurations()
    {
        try
        {
            var json = File.ReadAllText(ConfigFilePath);
            _configurations = JsonSerializer.Deserialize<List<FkDatabaseConfig>>(json);
            _lastLoadTime = DateTime.Now;
        }
        catch (Exception ex)
        {
            DedgeNLog.Error($"Failed to load configuration from {ConfigFilePath}: {ex.Message}");
            throw;
        }
    }
}
```

### Phase 3: Dynamic Connection Dictionary Generation
Replace the static `ConnectionInfoDict` with a dynamically generated dictionary.

```csharp
public static class DedgeConnection
{
    private static Dictionary<ConnectionKey, ConnectionInfo> _connectionInfoDict;
    private static readonly object _lockObject = new object();

    private static Dictionary<ConnectionKey, ConnectionInfo> ConnectionInfoDict
    {
        get
        {
            if (_connectionInfoDict == null)
            {
                lock (_lockObject)
                {
                    if (_connectionInfoDict == null)
                    {
                        _connectionInfoDict = GenerateConnectionDictionary();
                    }
                }
            }
            return _connectionInfoDict;
        }
    }

    private static Dictionary<ConnectionKey, ConnectionInfo> GenerateConnectionDictionary()
    {
        var configurations = FkConfigurationManager.GetConfigurations();
        var dictionary = new Dictionary<ConnectionKey, ConnectionInfo>();

        foreach (var config in configurations.Where(c => c.IsActive))
        {
            var key = new ConnectionKey(
                ParseApplication(config.Application),
                ParseEnvironment(config.Environment),
                config.Version
            );

            var connectionInfo = new ConnectionInfo
            {
                Database = config.Database,
                Provider = ParseProvider(config.Provider),
                Server = BuildServerString(config.ServerName, config.AccessPoints),
                UID = config.AccessPoints?.FirstOrDefault()?.UID,
                PWD = config.AccessPoints?.FirstOrDefault()?.PWD,
                Application = key.Application,
                Environment = key.Environment,
                Version = key.Version,
                NorwegianDescription = config.NorwegianDescription
            };

            dictionary[key] = connectionInfo;
        }

        return dictionary;
    }

    private static string BuildServerString(string serverName, List<AccessPoint> accessPoints)
    {
        var primaryAccessPoint = accessPoints?.FirstOrDefault(ap => ap.AccessPointType == "PrimaryDb");
        if (primaryAccessPoint != null)
        {
            return $"{serverName}:{primaryAccessPoint.Port}";
        }
        return serverName;
    }
}
```

### Phase 4: Enum Parsing Helpers
Create helper methods to parse string values to enums.

```csharp
private static FkApplication ParseApplication(string application)
{
    return application?.ToUpper() switch
    {
        "FKM" => FkApplication.FKM,
        "INL" => FkApplication.INL,
        "HST" => FkApplication.HST,
        "VIS" => FkApplication.VIS,
        "VAR" => FkApplication.VAR,
        "AGP" => FkApplication.AGP,
        "AGK" => FkApplication.AGK,
        "DBQA" => FkApplication.DBQA,
        "DOC" => FkApplication.DOC,
        _ => throw new ArgumentException($"Unknown application: {application}")
    };
}

private static FkEnvironment ParseEnvironment(string environment)
{
    return environment?.ToUpper() switch
    {
        "DEV" => FkEnvironment.DEV,
        "TST" => FkEnvironment.TST,
        "PRD" => FkEnvironment.PRD,
        "MIG" => FkEnvironment.MIG,
        "SIT" => FkEnvironment.SIT,
        "VFT" => FkEnvironment.VFT,
        "VFK" => FkEnvironment.VFK,
        "HST" => FkEnvironment.HST,
        "RAP" => FkEnvironment.RAP,
        _ => throw new ArgumentException($"Unknown environment: {environment}")
    };
}

private static DatabaseProvider ParseProvider(string provider)
{
    return provider?.ToUpper() switch
    {
        "DB2" => DatabaseProvider.DB2,
        "SQLSERVER" => DatabaseProvider.SQLSERVER,
        _ => throw new ArgumentException($"Unknown provider: {provider}")
    };
}
```

### Phase 5: Current Versions Management
Update the `CurrentVersions` dictionary to be dynamically generated.

```csharp
private static Dictionary<(FkApplication, FkEnvironment), string> CurrentVersions
{
    get
    {
        var configurations = FkConfigurationManager.GetConfigurations();
        return configurations
            .Where(c => c.IsActive)
            .GroupBy(c => (ParseApplication(c.Application), ParseEnvironment(c.Environment)))
            .ToDictionary(
                g => g.Key,
                g => g.OrderByDescending(c => c.Version).First().Version
            );
    }
}
```

## Implementation Examples

### Example 1: Maintaining GetConnectionStringInfo Signature
```csharp
// This method signature remains exactly the same
public static ConnectionInfo GetConnectionStringInfo(
    FkEnvironment environment,
    FkApplication application = FkApplication.FKM,
    string version = "2.0")
{
    // Implementation now uses JSON configuration instead of hardcoded dictionary
    ConnectionKey key;
    if (string.IsNullOrWhiteSpace(version))
    {
        version = CurrentVersions.TryGetValue((application, environment), out var currentVersion) ? currentVersion : "2.0";
        key = new ConnectionKey(application, environment, version);
    }
    else
    {
        key = new ConnectionKey(application, environment, version);
    }

    return GetConnectionStringInfo(key);
}
```

### Example 2: Connection String Generation
```csharp
// This method signature remains exactly the same
public static string GetConnectionString(
    FkEnvironment environment,
    FkApplication application = FkApplication.FKM,
    string version = "2.0")
{
    var connectionInfo = GetConnectionStringInfo(environment, application, version);
    return GenerateConnectionString(connectionInfo);
}

// The GenerateConnectionString method remains unchanged
private static string GenerateConnectionString(ConnectionInfo connectionInfo)
{
    string connectionString = "";
    if (connectionInfo.Provider == DatabaseProvider.DB2)
    {
        connectionString = $"Database={connectionInfo.Database};Server={connectionInfo.Server};UID={connectionInfo.UID};PWD={connectionInfo.PWD};";
    }
    else if (connectionInfo.Provider == DatabaseProvider.SQLSERVER)
    {
        connectionString = $"Database={connectionInfo.Database};Server={connectionInfo.Server};User Id={connectionInfo.UID};Password={connectionInfo.PWD};";
    }
    return connectionString;
}
```

### Example 3: Configuration Refresh
```csharp
// New method to refresh configuration without restarting application
public static void RefreshConfiguration()
{
    lock (_lockObject)
    {
        _connectionInfoDict = null;
        FkConfigurationManager.ClearCache();
    }
}
```

## Benefits of This Approach

### 1. **Zero Breaking Changes**
- All existing function signatures remain identical
- Existing code continues to work without modification
- No changes required in consuming applications

### 2. **Dynamic Configuration**
- New connections can be added by updating JSON file
- No code deployment required for connection changes
- Configuration can be refreshed at runtime

### 3. **Better Maintainability**
- Single source of truth for connection data
- Easier to manage multiple environments
- Reduced code duplication

### 4. **Enhanced Flexibility**
- Support for multiple access points per database
- Better handling of inactive connections
- Improved version management

## Migration Steps

### Step 1: Add JSON Dependencies
```xml
<PackageReference Include="System.Text.Json" Version="8.0.0" />
```

### Step 2: Create Configuration Classes
- Add `FkDatabaseConfig` and `AccessPoint` classes
- Add `FkConfigurationManager` class

### Step 3: Update DedgeConnection Class
- Replace static dictionary with dynamic generation
- Add enum parsing helpers
- Update `CurrentVersions` to be dynamic

### Step 4: Testing
- Verify all existing unit tests pass
- Test configuration loading and caching
- Test error handling for invalid configurations

### Step 5: Deployment
- Deploy updated DedgeCommon library
- Update JSON configuration file
- Monitor for any issues

## Error Handling Considerations

### Configuration File Issues
```csharp
private static void LoadConfigurations()
{
    try
    {
        var json = File.ReadAllText(ConfigFilePath);
        _configurations = JsonSerializer.Deserialize<List<FkDatabaseConfig>>(json);
        _lastLoadTime = DateTime.Now;
    }
    catch (FileNotFoundException)
    {
        DedgeNLog.Error($"Configuration file not found: {ConfigFilePath}");
        throw new InvalidOperationException("Database configuration file not found");
    }
    catch (JsonException ex)
    {
        DedgeNLog.Error($"Invalid JSON in configuration file: {ex.Message}");
        throw new InvalidOperationException("Invalid configuration file format");
    }
    catch (Exception ex)
    {
        DedgeNLog.Error($"Failed to load configuration: {ex.Message}");
        throw;
    }
}
```

### Fallback Mechanism
```csharp
private static Dictionary<ConnectionKey, ConnectionInfo> ConnectionInfoDict
{
    get
    {
        if (_connectionInfoDict == null)
        {
            lock (_lockObject)
            {
                if (_connectionInfoDict == null)
                {
                    try
                    {
                        _connectionInfoDict = GenerateConnectionDictionary();
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Error($"Failed to load dynamic configuration, using fallback: {ex.Message}");
                        _connectionInfoDict = GetFallbackConfiguration();
                    }
                }
            }
        }
        return _connectionInfoDict;
    }
}
```

## Conclusion

This migration plan provides a seamless transition from hardcoded connection data to JSON-based configuration while maintaining complete backward compatibility. The approach ensures that existing applications continue to work without any changes while providing the flexibility and maintainability benefits of external configuration management.

The key advantages are:
- **Zero breaking changes** to existing code
- **Dynamic configuration** without code deployment
- **Better maintainability** and single source of truth
- **Enhanced flexibility** for future requirements
- **Robust error handling** and fallback mechanisms

