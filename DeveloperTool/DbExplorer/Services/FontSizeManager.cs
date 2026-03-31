using NLog;
using System;
using System.ComponentModel;
using System.Windows;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Centralized font size management service for the application.
/// Allows dynamic font size changes across all UI components.
/// </summary>
public class FontSizeManager : INotifyPropertyChanged
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static FontSizeManager? _instance;
    private static readonly object _lock = new object();

    // Default font sizes
    private double _editorFontSize = 14;
    private double _objectBrowserFontSize = 11;
    private double _dialogFontSize = 12;
    private double _menuFontSize = 12;
    private double _statusBarFontSize = 11;
    private double _propertyWindowFontSize = 12;

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>
    /// Singleton instance
    /// </summary>
    public static FontSizeManager Instance
    {
        get
        {
            if (_instance == null)
            {
                lock (_lock)
                {
                    if (_instance == null)
                    {
                        _instance = new FontSizeManager();
                        Logger.Debug("FontSizeManager singleton instance created");
                    }
                }
            }
            return _instance;
        }
    }

    private FontSizeManager()
    {
        LoadFromSettings();
        Logger.Debug("FontSizeManager initialized with default sizes");
    }

    /// <summary>
    /// SQL editor font size (Consolas, monospace)
    /// </summary>
    public double EditorFontSize
    {
        get => _editorFontSize;
        set
        {
            if (_editorFontSize != value && value >= 8 && value <= 32)
            {
                Logger.Debug("EditorFontSize changing from {Old} to {New}", _editorFontSize, value);
                _editorFontSize = value;
                OnPropertyChanged(nameof(EditorFontSize));
                SaveToSettings();
            }
        }
    }

    /// <summary>
    /// Object browser tree view font size
    /// </summary>
    public double ObjectBrowserFontSize
    {
        get => _objectBrowserFontSize;
        set
        {
            if (_objectBrowserFontSize != value && value >= 8 && value <= 24)
            {
                Logger.Debug("ObjectBrowserFontSize changing from {Old} to {New}", _objectBrowserFontSize, value);
                _objectBrowserFontSize = value;
                OnPropertyChanged(nameof(ObjectBrowserFontSize));
                SaveToSettings();
            }
        }
    }

    /// <summary>
    /// Dialog window font size
    /// </summary>
    public double DialogFontSize
    {
        get => _dialogFontSize;
        set
        {
            if (_dialogFontSize != value && value >= 8 && value <= 24)
            {
                Logger.Debug("DialogFontSize changing from {Old} to {New}", _dialogFontSize, value);
                _dialogFontSize = value;
                OnPropertyChanged(nameof(DialogFontSize));
                SaveToSettings();
            }
        }
    }

    /// <summary>
    /// Menu font size
    /// </summary>
    public double MenuFontSize
    {
        get => _menuFontSize;
        set
        {
            if (_menuFontSize != value && value >= 8 && value <= 20)
            {
                Logger.Debug("MenuFontSize changing from {Old} to {New}", _menuFontSize, value);
                _menuFontSize = value;
                OnPropertyChanged(nameof(MenuFontSize));
                SaveToSettings();
            }
        }
    }

    /// <summary>
    /// Status bar font size
    /// </summary>
    public double StatusBarFontSize
    {
        get => _statusBarFontSize;
        set
        {
            if (_statusBarFontSize != value && value >= 8 && value <= 20)
            {
                Logger.Debug("StatusBarFontSize changing from {Old} to {New}", _statusBarFontSize, value);
                _statusBarFontSize = value;
                OnPropertyChanged(nameof(StatusBarFontSize));
                SaveToSettings();
            }
        }
    }

    /// <summary>
    /// Property window font size (table details, package details, etc.)
    /// </summary>
    public double PropertyWindowFontSize
    {
        get => _propertyWindowFontSize;
        set
        {
            if (_propertyWindowFontSize != value && value >= 8 && value <= 24)
            {
                Logger.Debug("PropertyWindowFontSize changing from {Old} to {New}", _propertyWindowFontSize, value);
                _propertyWindowFontSize = value;
                OnPropertyChanged(nameof(PropertyWindowFontSize));
                SaveToSettings();
            }
        }
    }

    /// <summary>
    /// Reset all font sizes to defaults
    /// </summary>
    public void ResetToDefaults()
    {
        Logger.Info("Resetting all font sizes to defaults");
        
        EditorFontSize = 14;
        ObjectBrowserFontSize = 11;
        DialogFontSize = 12;
        MenuFontSize = 12;
        StatusBarFontSize = 11;
        PropertyWindowFontSize = 12;
    }

    /// <summary>
    /// Increase all font sizes by 1pt
    /// </summary>
    public void IncreaseAll()
    {
        Logger.Info("Increasing all font sizes by 1pt");
        
        EditorFontSize = Math.Min(32, EditorFontSize + 1);
        ObjectBrowserFontSize = Math.Min(24, ObjectBrowserFontSize + 1);
        DialogFontSize = Math.Min(24, DialogFontSize + 1);
        MenuFontSize = Math.Min(20, MenuFontSize + 1);
        StatusBarFontSize = Math.Min(20, StatusBarFontSize + 1);
        PropertyWindowFontSize = Math.Min(24, PropertyWindowFontSize + 1);
    }

    /// <summary>
    /// Decrease all font sizes by 1pt
    /// </summary>
    public void DecreaseAll()
    {
        Logger.Info("Decreasing all font sizes by 1pt");
        
        EditorFontSize = Math.Max(8, EditorFontSize - 1);
        ObjectBrowserFontSize = Math.Max(8, ObjectBrowserFontSize - 1);
        DialogFontSize = Math.Max(8, DialogFontSize - 1);
        MenuFontSize = Math.Max(8, MenuFontSize - 1);
        StatusBarFontSize = Math.Max(8, StatusBarFontSize - 1);
        PropertyWindowFontSize = Math.Max(8, PropertyWindowFontSize - 1);
    }

    private void LoadFromSettings()
    {
        try
        {
            // TODO: Load from appsettings.json or user settings file
            Logger.Debug("Loading font sizes from settings (using defaults for now)");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load font sizes from settings");
        }
    }

    private void SaveToSettings()
    {
        try
        {
            // TODO: Save to appsettings.json or user settings file
            Logger.Debug("Saving font sizes to settings (not implemented yet)");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save font sizes to settings");
        }
    }

    private void OnPropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        Logger.Debug("Font size property changed: {Property}", propertyName);
    }
}

