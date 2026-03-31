# Settings Dialog and AppData Storage

## Overview
This document describes the new comprehensive Settings dialog and the migration to storing user data in the Windows AppData folder following best practices.

## New Features

### 1. Settings Dialog
A comprehensive settings dialog (`SettingsDialog`) has been added to manage all application preferences through a user-friendly interface.

#### Access
- **Menu**: View → Settings
- **Location**: The Settings dialog appears in the View menu with a ⚙ icon

#### Settings Categories (Tabs)

##### 📝 Editor Tab
- **Theme**: Choose between System, Light, or Dark theme
- **Font Family**: Select from common monospace fonts (Consolas, Courier New, Cascadia Code, Cascadia Mono, JetBrains Mono, Fira Code)
- **Font Size**: Adjust editor font size (8-24 pt)
- **Tab Size**: Configure tab spacing (2-8 spaces)

##### 🗄️ Database Tab
- **Max Rows Per Query**: Set the default pagination limit (default: 1000)
- **Command Timeout**: Configure query timeout in seconds (0 = no timeout)
- **Handle Decimal Errors Gracefully**: Automatically fallback to string reading for problematic decimal values
- **Auto-Refresh Objects**: Automatically load database objects when connecting

##### 📋 Logging Tab
- **Log Level**: Choose logging verbosity (Debug, Info, Warn, Error)
- **Open Logs Folder**: Quick access button to view application logs

##### 📁 Data Files Tab
- **Information Display**: Shows the path to your application data folder
- **File List**: Displays all configuration files and their purposes
- **Open Data Folder Button**: Opens Windows Explorer to the data folder location
- **Safety Warning**: Reminds users to backup before manual editing

### 2. User Data Folder (Centralized)

#### Storage Location
All user data is stored in the **user data folder** (configurable in **View → Settings**). Default:
```
%USERPROFILE%\Documents\DbExplorer\
```

Typical path:
```
C:\Users\{YourUsername}\Documents\DbExplorer\
```

#### Benefits
✅ **Best Practice**: Follows Windows application guidelines  
✅ **User-Specific**: Each Windows user has their own settings  
✅ **No Admin Rights**: No UAC prompts for file operations  
✅ **Automatic Cleanup**: Windows can manage disk space  
✅ **Backup-Friendly**: User profile backups include settings  
✅ **Multi-User**: Works seamlessly in terminal server/RDP environments  

#### Files Stored in User Data Folder

##### `preferences.json`
User preferences including:
- Theme, font family, font size, tab size
- Max rows per query, command timeout
- Decimal error handling, auto-refresh options
- Log level

**Example**:
```json
{
  "maxRowsPerQuery": 1000,
  "defaultTheme": "Dark",
  "fontFamily": "Consolas",
  "fontSize": 14,
  "tabSize": 4,
  "commandTimeout": 30,
  "handleDecimalErrorsGracefully": true,
  "autoRefreshObjectsOnConnect": true,
  "logLevel": "Info"
}
```

##### `connections.json`
Saved database connections with encrypted passwords (DPAPI):
```json
[
  {
    "name": "Production DB",
    "server": "db.example.com",
    "port": 50000,
    "database": "PRODDB",
    "username": "dbuser",
    "encryptedPassword": "AQAAANCMnd8BFdERjHo...==",
    "lastUsed": "2025-11-13T10:30:00Z"
  }
]
```

##### `query-history.json`
Encrypted query execution history:
```json
[
  {
    "encryptedSql": "AQAAANCMnd8BFdERjHo...==",
    "connectionName": "Production DB",
    "database": "PRODDB",
    "executedAt": "2025-11-13T14:25:30Z",
    "executionTimeMs": 125.5,
    "success": true,
    "rowCount": 42
  }
]
```

## AppDataHelper Utility

A new utility class `AppDataHelper` has been created in the `DbExplorer.Services` namespace to manage AppData operations.

### Key Methods

#### `GetAppDataFolder()`
Gets the application data folder path, creating it if it doesn't exist.
```csharp
var dataFolder = AppDataHelper.GetAppDataFolder();
// Returns: C:\Users\{Username}\AppData\Local\DbExplorer\
```

#### `GetDataFilePath(string fileName)`
Gets the full path for a data file in the application data folder.
```csharp
var prefsPath = AppDataHelper.GetDataFilePath("preferences.json");
// Returns: C:\Users\{Username}\AppData\Local\DbExplorer\preferences.json
```

#### `EnsureSubDirectory(string subDirectoryName)`
Creates a subdirectory within the application data folder if it doesn't exist.
```csharp
var backupFolder = AppDataHelper.EnsureSubDirectory("backups");
// Returns: C:\Users\{Username}\AppData\Local\DbExplorer\backups\
```

### Fallback Behavior
If the AppData folder is not accessible (e.g., permissions issue), the application falls back to storing files in the application's installation directory with a warning logged.

## Updated Services

### PreferencesService
- Now stores `preferences.json` in AppData
- Loads preferences on startup
- Saves preferences when modified through the Settings dialog

### ConnectionStorageService
- Now stores `connections.json` in AppData
- Passwords encrypted with DPAPI (Windows Data Protection API)
- Per-user encryption ensures passwords can only be decrypted by the same Windows user

### QueryHistoryService
- Now stores `query-history.json` in AppData
- SQL statements encrypted with DPAPI for privacy
- History is user-specific

## Security Considerations

### DPAPI Encryption
- **Passwords** in `connections.json` are encrypted using Windows DPAPI
- **SQL Statements** in `query-history.json` are encrypted using DPAPI
- Encryption is **user-specific** and **machine-specific**
- Cannot be decrypted by other users or on other machines
- No master password required

### Data Protection
⚠️ **Important**: 
- Encrypted data is tied to your Windows user profile
- If you lose access to your Windows account, the encrypted data cannot be recovered
- Consider exporting connection profiles (without passwords) for backup purposes

### Manual File Editing
Users can manually edit files in the AppData folder:
- `preferences.json` - Safe to edit manually (plain JSON)
- `connections.json` - Can edit metadata, but passwords are encrypted Base64 strings
- `query-history.json` - SQL statements are encrypted, manual editing not recommended

## Migration from Old Versions

If upgrading from a version that stored files in the application directory:

1. **Automatic Creation**: The AppData folder and files are created automatically on first run
2. **Manual Migration** (if needed):
   - Copy `preferences.json` from the app directory to `%LOCALAPPDATA%\DbExplorer\`
   - Copy `connections.json` (passwords will need to be re-entered due to DPAPI user-binding)
   - Query history will start fresh (old history can be manually migrated if needed)

## Opening the Data Folder

### From the Application
1. Go to **View → Settings**
2. Click the **📁 Data Files** tab
3. Click **📂 Open Data Folder** button

### Manually
1. Press **Win+R** to open the Run dialog
2. Type: `%LOCALAPPDATA%\DbExplorer`
3. Press Enter

## Log Files Location
Note: **Log files remain in the application directory** for easier troubleshooting:
```
{AppDirectory}\logs\
```

This allows IT administrators to access logs even if they don't have access to each user's profile.

## Troubleshooting

### Settings Not Saving
1. Check that the AppData folder is writable
2. Review logs in `{AppDirectory}\logs\` for permission errors
3. Try running the application as a different user

### Connections Lost After Migration
- Encrypted passwords are user-specific
- You may need to re-enter passwords after:
  - Changing Windows user
  - Moving to a different computer
  - Windows profile corruption/recreation

### Cannot Access Data Folder
If you see a message about falling back to the application directory:
1. Check Windows User Profile permissions
2. Ensure `%LOCALAPPDATA%` is accessible
3. Check for antivirus or security software blocking access
4. Try running as Administrator (not recommended for regular use)

## Best Practices

### For Users
✅ Regular backups of `%LOCALAPPDATA%\DbExplorer\`  
✅ Export connection profiles periodically  
✅ Use the Settings dialog instead of manual file editing  
✅ Note: Encrypted data cannot be moved to other machines/users  

### For IT Administrators
✅ Include `%LOCALAPPDATA%\DbExplorer\` in user profile backups  
✅ Allow read/write access to this folder in security policies  
✅ Logs remain in application directory for centralized monitoring  
✅ Consider providing a master connections template (without passwords)  

## Technical Details

### Directory Structure
```
%LOCALAPPDATA%\DbExplorer\
├── preferences.json          # User preferences (plain JSON)
├── connections.json          # DB connections (encrypted passwords)
└── query-history.json        # Query history (encrypted SQL)
```

### File Permissions
- Created with current user's permissions
- No special ACLs required
- Standard Windows file security applies

### Encryption Algorithm
- **Algorithm**: Windows Data Protection API (DPAPI)
- **Scope**: Current User
- **Key Management**: Handled by Windows
- **Encoding**: Base64 for storage in JSON

## Future Enhancements

Planned features:
- 📤 Export/Import connection profiles
- 🔄 Backup and restore settings
- 📊 Settings sync across machines (optional)
- 🔐 Optional master password for connections
- 📦 Portable mode (store everything in app directory)

---

**Last Updated**: November 13, 2025  
**Feature Version**: 1.1.0  
**Related Files**:
- `Dialogs/SettingsDialog.xaml` and `.xaml.cs`
- `Utils/AppDataHelper.cs`
- `Models/UserPreferences.cs`
- `Services/PreferencesService.cs`
- `Services/ConnectionStorageService.cs`
- `Services/QueryHistoryService.cs`

