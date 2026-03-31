# Legacy-DarkMode

Apply dark theme colors to legacy Windows components that don't natively support Windows 11 dark mode.

## Description

**Legacy-DarkMode** is a PowerShell utility that modifies Windows registry settings to apply dark mode styling to legacy components, including:

- **MMC snap-ins**: Task Scheduler, Event Viewer, Services, Computer Management, etc.
- **Legacy dialogs and windows**: Classic Win32 controls and system dialogs
- **System components**: Applications using traditional Windows theming

The script provides three modes:
1. **Apply dark theme** (default) - Applies dark colors from a JSON configuration file
2. **Revert** - Restores colors from automatic backup
3. **Reset to default** - Restores Windows 11 factory default light theme

## Features

- ✅ Applies dark mode to legacy Windows components
- ✅ Automatic backup of current theme colors
- ✅ Easy revert to previous theme
- ✅ Reset to Windows 11 factory defaults
- ✅ Configurable via JSON file
- ✅ Broadcasts settings change to running applications
- ✅ No external dependencies (uses built-in PowerShell)

## Requirements

- Windows 10/11
- PowerShell 5.1 or higher
- Administrator privileges recommended (though most settings are user-specific)

## Usage

### Apply Dark Theme

Apply the dark theme using the default configuration:

```powershell
.\Legacy-DarkMode.ps1
```

Apply dark theme using a custom configuration file:

```powershell
.\Legacy-DarkMode.ps1 -ConfigFile "C:\CustomThemes\MyDarkTheme.json"
```

### Revert to Previous Theme

Restore the original theme colors from automatic backup:

```powershell
.\Legacy-DarkMode.ps1 -Revert
```

### Reset to Windows 11 Defaults

Restore Windows 11 factory default light theme colors:

```powershell
.\Legacy-DarkMode.ps1 -ResetToDefault
```

### Additional Options

**Skip automatic backup:**

```powershell
.\Legacy-DarkMode.ps1 -NoBackup
```

**Skip logout prompt:**

```powershell
.\Legacy-DarkMode.ps1 -NoLogout
```

## Configuration File

The theme configuration is stored in `theme-config.json`. You can create custom themes by modifying this file.

### Example Configuration

```json
{
  "ThemeName": "Windows11DarkLegacy",
  "Version": "1.0",
  "Author": "Geir Helge Starholm, www.dEdge.no",
  "Description": "Custom dark theme for legacy Windows components",
  "Notes": [
    "Designed to match Windows 11 dark mode aesthetics",
    "Some MMC components may not fully support theming"
  ],
  "Colors": {
    "Window": {
      "Background": "#202020",
      "Text": "#FFFFFF"
    },
    "Menu": {
      "Background": "#202020",
      "Text": "#FFFFFF"
    },
    "ButtonFace": {
      "Background": "#2B2B2B"
    },
    "ButtonText": {
      "Color": "#FFFFFF"
    }
  }
}
```

### Color Format

Colors can be specified in multiple formats:
- Hex: `#202020`, `#FFFFFF`
- RGB: `32, 32, 32` or `32 32 32`
- RGB space-separated (registry format): `32 32 32`

## Important Notes

### Limitations

- **Not all components are themeable**: Some MMC snap-ins and system dialogs use hardcoded colors
- **Logout required**: Full effect requires logging out and back in
- **Application restart**: Some applications may need to be restarted to pick up changes
- **Windows 11 modern components unaffected**: Modern Windows 11 apps use their own theming system

### Backup and Safety

- The script automatically creates a backup of your current theme colors before making changes
- Backup is saved to `theme-backup.json` in the script directory
- Use `-Revert` to restore from backup
- Use `-ResetToDefault` to restore Windows 11 factory defaults if backup is unavailable

## Examples

### Standard Workflow

1. Apply dark theme:
   ```powershell
   .\Legacy-DarkMode.ps1
   ```

2. Log out and log back in

3. If you don't like it, revert:
   ```powershell
   .\Legacy-DarkMode.ps1 -Revert
   ```

### Custom Theme

1. Copy `theme-config.json` to `my-custom-theme.json`
2. Edit `my-custom-theme.json` with your preferred colors
3. Apply custom theme:
   ```powershell
   .\Legacy-DarkMode.ps1 -ConfigFile "my-custom-theme.json"
   ```

### Emergency Reset

If something goes wrong and you need to restore defaults:

```powershell
.\Legacy-DarkMode.ps1 -ResetToDefault
```

## Troubleshooting

### Colors Don't Apply

- Ensure you logged out and back in
- Restart affected applications
- Some components may require a full system restart

### Can't Find Backup

Use `-ResetToDefault` to restore Windows 11 factory defaults:

```powershell
.\Legacy-DarkMode.ps1 -ResetToDefault
```

### Modern Apps Still Light

This tool only affects legacy Windows components. Modern Windows 11 apps use the system dark mode setting, which you can toggle in:

**Settings** → **Personalization** → **Colors** → **Choose your mode**

## Author

**Geir Helge Starholm**  
Website: [www.dEdge.no](https://www.dEdge.no)

## Version History

- **1.0** - Initial release
  - Apply dark theme from JSON configuration
  - Automatic backup and revert functionality
  - Reset to Windows 11 factory defaults
  - Automatic settings broadcast to applications

## License

This script is provided as-is for educational and administrative purposes.

