# Theme Management System

## Overview

Comprehensive theme management system with support for custom themes, light/dark modes, and per-component color/font customization.

## Architecture

### Components

1. **AppTheme Model** (`Models/AppTheme.cs`)
   - Comprehensive theme configuration
   - Includes Editor, Grid, and UI component settings
   - Serializable to JSON for import/export

2. **ThemeManager Service** (`Services/ThemeManager.cs`)
   - Loads/saves theme files
   - Manages built-in and custom themes
   - Handles theme import/export

3. **Settings Dialog** (`Dialogs/SettingsDialog.xaml`)
   - Now uses theme-aware backgrounds
   - Applies dark/light colors based on theme

4. **New Settings Dialog** (`Dialogs/NewSettingsDialog.xaml`)
   - TreeView-based navigation (like VS Code, Visual Studio)
   - Modern, organized layout
   - Theme import/export buttons

## Theme Structure

```json
{
  "name": "Dark",
  "description": "Built-in dark theme",
  "baseTheme": "Dark",
  "isBuiltIn": true,
  "editor": {
    "fontFamily": "Consolas",
    "fontSize": 14,
    "tabSize": 4,
    "backgroundColor": "#1E1E1E",
    "foregroundColor": "#D4D4D4",
    "lineNumberColor": "#858585",
    "selectionColor": "#264F78",
    "currentLineColor": "#282828"
  },
  "grid": {
    "fontFamily": "Segoe UI",
    "fontSize": 12,
    "cellHeight": 25,
    "backgroundColor": "#2D2D2D",
    "foregroundColor": "#E0E0E0",
    "selectedBackgroundColor": "#0078D4",
    "selectedForegroundColor": "#FFFFFF",
    "headerBackgroundColor": "#252526",
    "headerForegroundColor": "#CCCCCC",
    "alternateRowColor": "#323232"
  },
  "ui": {
    "objectBrowserFontSize": 12,
    "dialogFontSize": 14,
    "menuFontSize": 12,
    "statusBarFontSize": 11,
    "propertyWindowFontSize": 12,
    "windowBackgroundColor": "#1E1E1E",
    "windowForegroundColor": "#E0E0E0",
    "buttonBackgroundColor": "#0E639C",
    "buttonForegroundColor": "#FFFFFF"
  }
}
```

## Theme Locations

### Built-in Themes
- **Location**: `{AppDirectory}/Themes/`
- **Files**: `Dark.theme.json`, `Light.theme.json`
- **Read-only**: Cannot be modified
- **Auto-created**: Generated on first run

### User Custom Themes
- **Location**: `{AppData}/DbExplorer/Themes/`
- **Files**: `{ThemeName}.theme.json`
- **User-editable**: Can be created, modified, deleted
- **Portable**: Can be exported/imported

## Features

### Current Implementation (v1.0)

✅ **Dark Mode Grid Colors**
- Default grid colors now match dark theme
- Background: `#2D2D2D` (dark gray)
- Foreground: `#E0E0E0` (light gray)

✅ **Theme-Aware Dialogs**
- Settings dialog uses dynamic theme brushes
- Adapts to light/dark mode automatically

✅ **Grid Preferences**
- 7 customizable properties:
  - Background color
  - Foreground color
  - Selected background color
  - Selected foreground color
  - Font size
  - Font family
  - Cell height

✅ **Consistent Grid Styling**
- All DataGrids use same color mapping
- Applied to 10+ panel controls
- Applied to 9+ dialog controls

✅ **Theme Models**
- `AppTheme` - Comprehensive theme model
- `EditorTheme` - SQL editor settings
- `GridTheme` - DataGrid settings
- `UITheme` - UI component settings

✅ **ThemeManager Service**
- Load built-in and custom themes
- Save user custom themes
- Export/import theme files
- Delete custom themes

✅ **TreeView Settings Navigation**
- Modern organized layout
- Categories: Appearance, Editor, Grids, Database, Logging, AI
- Expandable tree structure

### Planned Implementation (v2.0)

🚧 **Complete TreeView Panels**
- Implement all setting panels in NewSettingsDialog
- Migrate all settings from old dialog
- Add visual theme preview

🚧 **Theme Editor**
- Visual color picker for all components
- Live preview of theme changes
- "Create Custom Theme" wizard

🚧 **Theme Presets**
- VS Code Dark
- VS Code Light
- Sublime Text
- One Dark
- Solarized Dark/Light
- Monokai

🚧 **Theme Sharing**
- Export themes to share with team
- Import community themes
- Theme gallery/marketplace

## Usage

### For Users

#### Customize Grid Colors
1. Open **Tools → Options**
2. Navigate to **Grids** tab
3. Adjust colors, fonts, cell height
4. Click **Save**
5. All grids update immediately

#### Create Custom Theme
1. Adjust all settings to your preference
2. Click **Export Theme**
3. Save as `MyTheme.theme.json`
4. Share with team or import on other machines

#### Import Theme
1. Open **Tools → Options**
2. Click **Import Theme**
3. Select `.theme.json` file
4. Theme is added to your collection

### For Developers

#### Apply Theme to New DataGrid
```csharp
public MyPanel()
{
    InitializeComponent();
    ApplyGridPreferences();
}

private void ApplyGridPreferences()
{
    if (App.PreferencesService != null)
    {
        GridStyleHelper.ApplyGridStyle(MyDataGrid, App.PreferencesService.Preferences);
    }
}
```

#### Create New Theme Programmatically
```csharp
var theme = new AppTheme
{
    Name = "My Custom Theme",
    Description = "Custom colors for dark environment",
    BaseTheme = "Dark",
    Grid = new GridTheme
    {
        BackgroundColor = "#1A1A1A",
        ForegroundColor = "#FFFFFF",
        // ... other properties
    }
};

var themeManager = new ThemeManager();
themeManager.SaveUserTheme(theme);
```

## Technical Details

### Grid Style Application Flow

```
App Startup
  └─> App.PreferencesService created (loads preferences.json)
      └─> UserPreferences loaded with grid defaults

Panel/Dialog Creation
  └─> Constructor calls ApplyGridPreferences()
      └─> GridStyleHelper.ApplyGridStyle(dataGrid, preferences)
          ├─> Sets background/foreground colors
          ├─> Sets font family/size
          ├─> Sets cell height
          ├─> Creates selected row style
          ├─> Creates hover row style
          └─> Sets header style

Settings Save
  └─> PreferencesService.SavePreferences()
      └─> Saves to preferences.json
          └─> GridStyleHelper.RefreshAllGrids()
              └─> Finds all DataGrids in visual tree
                  └─> Reapplies styles to each grid
```

### Color Parsing

- Supports 6-digit hex: `#RRGGBB`
- Supports 8-digit hex: `#AARRGGBB` (with alpha)
- Validates input before saving
- Falls back to white if parsing fails

### Default Colors

#### Dark Theme (Default)
| Component | Color | Hex |
|-----------|-------|-----|
| Grid Background | Dark Gray | `#2D2D2D` |
| Grid Foreground | Light Gray | `#E0E0E0` |
| Selected Background | Blue | `#0078D4` |
| Selected Foreground | White | `#FFFFFF` |
| Header Background | Darker Gray | `#252526` |
| Header Foreground | Light Gray | `#CCCCCC` |

#### Light Theme
| Component | Color | Hex |
|-----------|-------|-----|
| Grid Background | White | `#FFFFFF` |
| Grid Foreground | Black | `#000000` |
| Selected Background | Blue | `#0078D4` |
| Selected Foreground | White | `#FFFFFF` |
| Header Background | Light Gray | `#F0F0F0` |
| Header Foreground | Black | `#000000` |

## Future Enhancements

1. **Theme Studio**
   - Visual theme editor with live preview
   - Color scheme generator
   - Export to VS Code/Sublime format

2. **Component-Specific Themes**
   - Different themes for different panels
   - Per-connection themes
   - Context-aware theming

3. **Accessibility**
   - High contrast themes
   - Color blind friendly palettes
   - Configurable font scaling

4. **Community Themes**
   - Built-in theme gallery
   - One-click theme download
   - User ratings and reviews

## Migration Guide

### From Old Settings to New Theme System

Old preferences in `preferences.json` are automatically migrated:

```csharp
// Old format (preferences.json)
{
  "gridBackgroundColor": "#FFFFFF",
  "gridForegroundColor": "#000000",
  // ... individual properties
}

// New format (MyTheme.theme.json)
{
  "name": "My Custom Theme",
  "grid": {
    "backgroundColor": "#FFFFFF",
    "foregroundColor": "#000000"
  },
  "editor": { ... },
  "ui": { ... }
}
```

The system maintains backwards compatibility - preferences.json continues to work.

## Troubleshooting

### Grid Colors Not Applying
- Check logs: `logs/DbExplorer_{date}.log`
- Look for: "Grid style applied successfully"
- Verify preferences.json has valid hex colors
- Restart application to reload preferences

### Settings Dialog Error
- Check null references in event handlers
- Verify controls exist before accessing
- Load settings before attaching events

### Theme Files Not Loading
- Check: `{AppData}/DbExplorer/Themes/`
- Verify JSON syntax is valid
- Check file permissions
- View logs for detailed error messages

## Summary

The theme management system provides:
- ✅ Consistent grid colors across all forms
- ✅ Dark mode support with proper contrast
- ✅ Customizable fonts and cell heights
- ✅ Theme export/import for sharing
- ✅ Built-in Dark and Light themes
- ✅ TreeView-based settings organization
- ✅ Immediate application of changes

All changes are saved to `preferences.json` and persist across sessions.
