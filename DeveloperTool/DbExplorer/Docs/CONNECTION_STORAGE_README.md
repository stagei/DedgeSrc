# Connection Storage & Recent Connections

## Overview
The application now **automatically saves all database connections** with **encrypted passwords** and provides quick access through a **Recent Connections menu**.

## Key Features

### 1. Automatic Connection Saving
Every time you successfully connect to a database, the connection details are automatically saved:
- **Connection name**
- **Server address and port**
- **Database name**
- **Username**
- **Password** (encrypted using Windows Data Protection API)
- **Last used timestamp**

### 2. Secure Password Encryption
Passwords are encrypted using **Windows Data Protection API (DPAPI)**:
- ✅ **User-scope encryption** - Only your Windows user account can decrypt
- ✅ **No key management** - Windows handles encryption keys automatically
- ✅ **Base64 encoding** - Encrypted data stored as Base64 in JSON
- ✅ **Cannot be decrypted on other machines** - Security by design
- ✅ **No plain-text storage** - Passwords never stored unencrypted

#### Technical Details:
```csharp
// Encryption: Plain text → Bytes → DPAPI → Base64 → JSON
Password "mypass123" → Encrypted → "AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA..."

// Decryption: JSON → Base64 → DPAPI → Bytes → Plain text
"AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA..." → Decrypted → "mypass123"
```

### 3. Recent Connections Menu
Access recent connections quickly from **File → Recent Connections**:
- Shows up to **10 most recently used** connections
- Sorted by **last used timestamp** (newest first)
- Click any connection to **instantly open a new tab**
- Passwords are **automatically decrypted** when opening

## Storage Location

### Connections File
**Path**: User data folder (default: `Documents\DbExplorer\connections.json`).  
The folder is configurable in **View → Settings → Data Files**.

**Example path**: 
```
C:\Users\<user>\Documents\DbExplorer\connections.json
```

### File Format
```json
{
  "connections": [
    {
      "name": "Production DB",
      "server": "db.company.com",
      "port": 50000,
      "database": "PRODDB",
      "username": "admin",
      "encryptedPassword": "AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA...",
      "lastUsed": "2025-11-12T20:45:30.1234567Z"
    },
    {
      "name": "Test DB",
      "server": "testdb.local",
      "port": 50000,
      "database": "TESTDB",
      "username": "testuser",
      "encryptedPassword": "AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA...",
      "lastUsed": "2025-11-11T15:20:10.9876543Z"
    }
  ]
}
```

## Usage

### Opening Recent Connections

**Method 1: Menu**
1. Click **File** in the menu bar
2. Hover over **Recent Connections**
3. Click the connection you want to open
4. A new tab opens automatically with the connection ready

**Method 2: Manual JSON Edit** (Advanced)
1. Close the application
2. Edit `connections.json` directly
3. Restart the application

### Managing Recent Connections

#### Clear All Recent Connections
1. Go to **File → Recent Connections → Clear Recent Connections**
2. Confirm the deletion
3. **All saved connections and passwords are removed**

#### Remove a Single Connection
Currently, connections are managed automatically:
- Connections are **replaced** if you save with the same name
- **Oldest connections** are removed when you exceed 10 saved connections
- To manually remove a single connection, edit `connections.json` directly

## Security Considerations

### ✅ Secure Practices
- Passwords encrypted with Windows DPAPI (user-scope)
- Encrypted data cannot be read by other users on the same machine
- Encrypted data cannot be decrypted on different machines
- All encryption/decryption operations are logged

### ⚠️ Important Warnings
1. **Do not copy `connections.json` to other machines**
   - The encrypted passwords will not decrypt on other machines
   - You'll get decryption errors

2. **Do not share `connections.json` with others**
   - While passwords are encrypted, server/database/username info is visible
   - Others cannot decrypt your passwords anyway

3. **Backup considerations**
   - If you backup and restore to a different machine, passwords won't work
   - You'll need to re-enter passwords after restore

4. **User profile changes**
   - If you change your Windows user profile, decryption may fail
   - You'll need to re-enter passwords

### 🔒 What's Protected
- ✅ Passwords are encrypted
- ✅ Passwords masked in logs (`PWD=***`)
- ✅ Decryption failures are logged and handled gracefully

### ⚠️ What's NOT Protected
- Connection names (visible in JSON)
- Server addresses (visible in JSON)
- Database names (visible in JSON)
- Usernames (visible in JSON)
- Last used timestamps (visible in JSON)

## Troubleshooting

### Connection Won't Open from Recent Menu
**Symptoms**: Click connection in menu, nothing happens or error appears

**Solutions**:
1. Check `logs\db2editor-{date}.log` for error messages
2. Try creating a new connection with the same details
3. If decryption fails, clear recent connections and reconnect

### "Password decryption failed" Error
**Cause**: Encrypted password cannot be decrypted

**Solutions**:
1. **User profile changed**: Delete `connections.json` and re-save connections
2. **File copied from another machine**: Delete and recreate connections locally
3. **Windows reinstalled**: Delete `connections.json` and re-save connections

### Recent Connections Menu is Empty
**Symptoms**: Menu shows "(No recent connections)"

**Solutions**:
1. Connect to a database (it will auto-save)
2. Check if `connections.json` exists in the application directory
3. Check logs for errors during connection save

### Connection File is Corrupted
**Symptoms**: Application errors on startup, recent connections not loading

**Solutions**:
1. Close the application
2. Delete `connections.json`
3. Restart the application (will create new empty file)
4. Reconnect to your databases

## Logging

All connection storage operations are logged:

### Log Levels
- **INFO**: Connection saved, loaded, deleted
- **DEBUG**: Encryption/decryption operations, file paths, JSON contents
- **ERROR**: Encryption/decryption failures, file I/O errors
- **WARN**: Missing connections, decryption issues

### Example Log Entries
```
2025-11-12 20:45:30.1234|INFO|ConnectionStorageService|Saving connection: Production DB
2025-11-12 20:45:30.1235|DEBUG|ConnectionStorageService|Connection details - Server: db.company.com, Database: PRODDB, User: admin
2025-11-12 20:45:30.1236|DEBUG|ConnectionStorageService|Encrypting password using DPAPI
2025-11-12 20:45:30.1237|DEBUG|ConnectionStorageService|Password encrypted successfully (length: 256)
2025-11-12 20:45:30.1238|INFO|ConnectionStorageService|Connection saved successfully: Production DB
```

## Advanced Usage

### Manual JSON Editing
You can manually edit `connections.json`, but **be careful**:

1. **Close the application first** (file is loaded at startup)
2. Edit with any text editor
3. **Do NOT edit `encryptedPassword` fields** (will cause decryption errors)
4. You can edit: name, server, port, database, username
5. You can delete entire connection objects
6. Ensure JSON syntax is valid

### Example: Rename a connection
```json
{
  "connections": [
    {
      "name": "Production DB (OLD)",  // Change this
      "server": "db.company.com",
      ...
    }
  ]
}
```

### Export/Import Connections (Not Secure!)
If you want to move connections to another machine:

**⚠️ WARNING**: This method stores passwords in plain text temporarily!

1. **Export** (on source machine):
   - Open `connections.json`
   - For each connection, note the server, database, username
   - Manually decrypt passwords (by opening a connection and checking)
   - Write down all details

2. **Import** (on target machine):
   - Connect to each database using the normal connection dialog
   - Connections will be auto-saved with encryption on the new machine

## Files Created/Modified

### New Files
- `Models/SavedConnection.cs` - Data model for saved connections
- `Services/ConnectionStorageService.cs` - Encryption and storage service
- `CONNECTION_STORAGE_README.md` - This documentation

### Modified Files
- `Dialogs/ConnectionDialog.xaml` - Increased height to 480px, made resizable
- `Dialogs/ConnectionDialog.xaml.cs` - Auto-save connections on connect
- `MainWindow.xaml` - Added "Recent Connections" submenu
- `MainWindow.xaml.cs` - Populate and handle recent connections menu

## Future Enhancements
Potential future features:
- Connection groups/folders
- Export/import with re-encryption
- Connection profiles (different users for same database)
- Connection tags and search
- Connection settings (timeout, charset, etc.)
- Keyboard shortcuts for recent connections
- Pin favorite connections to top of list

## Related Documentation
- See `DB2_Application_Development_Guide.md` for overall architecture
- See `PAGINATION_AND_PREFERENCES_README.md` for query limits and preferences
- See `nlog.config` for logging configuration

## Support
For issues:
1. Check `logs\db2editor-{date}.log` for error messages
2. Enable DEBUG logging in `nlog.config` for detailed information
3. Try deleting `connections.json` and reconnecting

