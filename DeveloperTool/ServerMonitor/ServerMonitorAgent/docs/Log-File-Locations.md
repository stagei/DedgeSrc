# ServerMonitor Log File Locations

## Summary

All log files are written to: **`C:\opt\data\ServerMonitor\`** (default)

---

## 1. Main Application Logs (NLog)

### Primary Log File
- **Location**: `C:\opt\data\ServerMonitor\ServerMonitor_{date}.log`
- **Format**: `ServerMonitor_20251209.log` (date format: yyyyMMdd)
- **Content**: All application logs (Debug, Info, Warning, Error)
- **Layout**: `{timestamp}|{level}|{logger}|{message}`

### Configuration
- **Default Directory**: `${OptPath}\data\ServerMonitor` (uses `OptPath` environment variable)
- **Fallback**: `C:\opt\data\ServerMonitor` (if `OptPath` not set)
- **Configurable via**: `Surveillance:Logging:LogDirectory` in `appsettings.json` (if section exists)
- **Environment Variables**: 
  - `OptPath`: Base path (e.g., `C:\opt`) - used by NLog config
  - `LOG_DIRECTORY`: Overrides log directory (set by application at startup)
  - `LOG_APPNAME`: Application name (default: `ServerMonitor`)

### Archive Logs
- **Location**: `C:\opt\data\ServerMonitor\archive\ServerMonitor_{date}.log`
- **Retention**: 30 days (maxArchiveFiles="30")
- **Archive Frequency**: Daily (archiveEvery="Day")

### NLog Internal Log
- **Location**: `${OptPath}\data\ServerMonitor\ServerMonitor_nlog-internal.log`
- **Default**: `C:\opt\data\ServerMonitor\ServerMonitor_nlog-internal.log` (if OptPath not set)
- **Content**: NLog framework internal logs (for debugging NLog itself)
- **Uses**: `OptPath` environment variable (same as other log files)

---

## 2. Alert Logs (File Alert Channel)

### Alert Log File
- **Location**: `%OptPath%\data\ServerMonitor\ServerMonitor_Alerts_{Date}.log`
- **Format**: `ServerMonitor_Alerts_20251209.log` (date format: yyyyMMdd)
- **Content**: All alerts at or above configured MinSeverity (default: Informational)
- **Layout**: `[timestamp] [SEVERITY] [Category] Message | Details: ...`

### Configuration
- **Path Setting**: `Alerting:Channels[File]:Settings:LogPath` in `appsettings.json`
- **Current Value**: `%OptPath%\data\ServerMonitor\ServerMonitor_Alerts_{Date}.log`
- **Environment Variable**: `%OptPath%` must be set, or path will be used as-is
- **Default if OptPath not set**: Path will contain literal `%OptPath%` string

### Note on %OptPath%
- `%OptPath%` is an environment variable that should be set to the base path (e.g., `C:\opt`)
- If not set, the path will contain the literal string `%OptPath%`
- **Recommended**: Set `OptPath` environment variable to `C:\opt` for proper expansion

---

## 3. Snapshot Export Files

### Snapshot Directory
- **Location**: `%OptPath%\data\ServerMonitor\Snapshots\`
- **Default**: `C:\opt\data\ServerMonitor\Snapshots\` (if OptPath=C:\opt)
- **File Format**: `{ServerName}_{Timestamp:yyyyMMdd_HHmmss}.json`
- **Example**: `t-no1inltst-db_20251209_095820334.json`

### Configuration
- **Path Setting**: `ExportSettings:OutputDirectory` in `appsettings.json`
- **Current Value**: `%OptPath%\data\ServerMonitor\Snapshots`
- **Compression**: JSON files are compressed to `.gz` format if `CompressionEnabled: true`

---

## 4. Windows Event Log

### Event Log Location
- **Log Name**: Application
- **Source**: ServerMonitor
- **Level**: Error and above (minlevel="Error")
- **View**: Windows Event Viewer → Windows Logs → Application

---

## Configuration Summary

### Default Log Directory
```
C:\opt\data\ServerMonitor\
```

### All Log Files in Default Location

1. **Main Application Log**: `C:\opt\data\ServerMonitor\ServerMonitor_{date}.log`
2. **Alert Log**: `C:\opt\data\ServerMonitor\ServerMonitor_Alerts_{date}.log` (if OptPath is set)
3. **NLog Internal Log**: `C:\opt\data\ServerMonitor\ServerMonitor_nlog-internal.log`
4. **Archive Logs**: `C:\opt\data\ServerMonitor\archive\ServerMonitor_{date}.log`
5. **Snapshots**: `C:\opt\data\ServerMonitor\Snapshots\{ServerName}_{Timestamp}.json`

### Configuration Files

- **NLog Configuration**: `NLog.config` (in application directory)
- **Application Settings**: `appsettings.json` (in application directory)
- **Log Directory Config**: `Surveillance:Logging:LogDirectory` (optional, defaults to `C:\opt\data\ServerMonitor`)

---

## Environment Variables

### Required/Recommended
- **`OptPath`**: Should be set to `C:\opt` for proper path expansion in config files
- **`LOG_DIRECTORY`**: Set automatically by application (default: `C:\opt\data\ServerMonitor`)
- **`LOG_APPNAME`**: Set automatically by application (default: `ServerMonitor`)

### How to Set OptPath
```powershell
# System-wide (requires admin)
[System.Environment]::SetEnvironmentVariable("OptPath", "C:\opt", "Machine")

# User-level
[System.Environment]::SetEnvironmentVariable("OptPath", "C:\opt", "User")
```

---

## Verification

To verify log file locations, check the application startup logs:
- Look for: `LOG_DIRECTORY set to: C:\opt\data\ServerMonitor`
- Check first log entry in: `C:\opt\data\ServerMonitor\ServerMonitor_{today}.log`

---

## Production Server Location

Based on the repository rules, production logs are located at:
- **Network Path**: `\\t-no1inltst-db\opt\data\ServerMonitor\`
- **Log Files**: `ServerMonitor_*.log` and `ServerMonitor_Alerts_*.log`
- **Snapshots**: `Snapshots\*.json` and `Snapshots\*.html`

