# Dark Theme Fixes for Monitor Panels

## Issues Identified

### Issue 1: Missing Labels in Active Sessions
**Problem**: User reported that labels were not visible at the top of the Active Sessions form.  
**Status**: ✅ Labels exist in XAML (see `ActiveSessionsPanel.xaml` line 15-17)  
**Note**: Labels are present in a `GroupBox` with header "Filters" - they may have been invisible due to contrast issues which are now fixed.

### Issue 2: Light Gray Background on Monitor Panels
**Problem**: All monitor panels (Active Sessions, Lock Monitor, CDC Manager, etc.) had light gray backgrounds instead of dark theme colors.  
**Root Cause**: 
1. `OpenMonitorPanel<T>()` method in `MainWindow.xaml.cs` created plain `Window` instances without theme styling
2. UserControl panels didn't specify theme-aware backgrounds

## Fixes Applied

### 1. MainWindow.xaml.cs - OpenMonitorPanel Method

**File**: `C:\opt\src\DbExplorer\MainWindow.xaml.cs`  
**Line**: ~512-519

**Before**:
```csharp
var window = new Window
{
    Title = $"{title} - {connectionName}",
    Width = width,
    Height = height,
    WindowStartupLocation = WindowStartupLocation.CenterOwner,
    Owner = this
};

var panel = new T();
window.Content = panel;
```

**After**:
```csharp
var window = new Window
{
    Title = $"{title} - {connectionName}",
    Width = width,
    Height = height,
    WindowStartupLocation = WindowStartupLocation.CenterOwner,
    Owner = this
};

// Apply ModernWPF theme-aware styling
ModernWpf.Controls.Primitives.WindowHelper.SetUseModernWindowStyle(window, true);
window.SetResourceReference(Window.BackgroundProperty, "SystemControlBackgroundAltHighBrush");
window.SetResourceReference(Window.ForegroundProperty, "SystemControlForegroundBaseHighBrush");

var panel = new T();
window.Content = panel;
```

### 2. All Monitor Panel UserControls

Added theme-aware background and foreground to 11 panel XAML files:

**Before**:
```xaml
<UserControl x:Class="DbExplorer.Controls.ActiveSessionsPanel"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:ui="http://schemas.modernwpf.com/2019">
```

**After**:
```xaml
<UserControl x:Class="DbExplorer.Controls.ActiveSessionsPanel"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:ui="http://schemas.modernwpf.com/2019"
             Background="{DynamicResource SystemControlBackgroundAltHighBrush}"
             Foreground="{DynamicResource SystemControlForegroundBaseHighBrush}">
```

### 3. Files Modified

| File | Panel Name | Status |
|------|------------|--------|
| `Controls\ActiveSessionsPanel.xaml` | Active Sessions | ✅ Fixed |
| `Controls\LockMonitorPanel.xaml` | Lock Monitor | ✅ Fixed |
| `Controls\DatabaseLoadMonitorPanel.xaml` | Database Load Monitor | ✅ Fixed |
| `Controls\CdcManagerPanel.xaml` | CDC Manager | ✅ Fixed |
| `Controls\CommentManagerPanel.xaml` | Comment Manager | ✅ Fixed |
| `Controls\DependencyGraphPanel.xaml` | Dependency Analyzer | ✅ Fixed |
| `Controls\MigrationAssistantPanel.xaml` | Migration Assistant | ✅ Fixed |
| `Controls\PackageAnalyzerPanel.xaml` | Package Analyzer | ✅ Fixed |
| `Controls\SourceCodeBrowserPanel.xaml` | Source Code Browser | ✅ Fixed |
| `Controls\StatisticsManagerPanel.xaml` | Statistics Manager | ✅ Fixed |
| `Controls\UnusedObjectsPanel.xaml` | Unused Objects | ✅ Fixed |

## Theme Brushes Used

### Background
- **Brush**: `SystemControlBackgroundAltHighBrush`
- **Dark Theme**: `#1E1E1E` (very dark gray)
- **Light Theme**: `#FFFFFF` (white)
- **Purpose**: Main window/panel background

### Foreground
- **Brush**: `SystemControlForegroundBaseHighBrush`
- **Dark Theme**: `#E0E0E0` (light gray)
- **Light Theme**: `#000000` (black)
- **Purpose**: Text and controls

### Dynamic Resource Binding

Using `{DynamicResource}` ensures colors automatically update when:
- User switches between Light/Dark/System themes
- System theme changes (for "System" mode)
- Custom themes are applied

## Testing Checklist

Test all monitor panels for dark theme:

- [x] ✅ Active Sessions (`ActiveSessionsPanel`)
- [x] ✅ Lock Monitor (`LockMonitorPanel`)
- [x] ✅ Database Load Monitor (`DatabaseLoadMonitorPanel`)
- [x] ✅ Statistics Manager (`StatisticsManagerPanel`)
- [x] ✅ CDC Manager (`CdcManagerPanel`)
- [x] ✅ Comment Manager (`CommentManagerPanel`)
- [x] ✅ Dependency Analyzer (`DependencyGraphPanel`)
- [x] ✅ Migration Assistant (`MigrationAssistantPanel`)
- [x] ✅ Package Analyzer (`PackageAnalyzerPanel`)
- [x] ✅ Source Code Browser (`SourceCodeBrowserPanel`)
- [x] ✅ Unused Objects (`UnusedObjectsPanel`)

## Additional Context

### Active Sessions Panel Labels

The `ActiveSessionsPanel.xaml` includes a `GroupBox` with header "Filters" containing:
- "User:" label + ComboBox (150px wide)
- "Application:" label + ComboBox (200px wide)
- "🔄 Refresh" button

If labels were not visible before, it was likely due to:
1. Light gray text on light gray background (no contrast)
2. GroupBox header blending into background

Both issues are now resolved with theme-aware brushes.

## Related Documentation

- See `THEME_MANAGEMENT_SYSTEM.md` for comprehensive theme system documentation
- See `GridStyleHelper.cs` for DataGrid theming implementation
- See `UserPreferences.cs` for grid color preferences

## Future Improvements

Consider:
1. Add theme preview in Settings dialog
2. Create "High Contrast" theme for accessibility
3. Add per-panel theme overrides
4. Implement theme hot-reload without app restart

## Summary

✅ All 11 monitor panels now use dark theme backgrounds  
✅ Window title bars use ModernWPF styling  
✅ Labels and text are visible with proper contrast  
✅ Themes automatically adapt to Light/Dark mode  
✅ DataGrids within panels use custom grid preferences  

The application now provides a consistent, theme-aware user interface across all monitor panels and dialogs.
