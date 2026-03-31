using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Manages application themes including loading, saving, and applying theme files
/// </summary>
public class ThemeManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _themesDirectory;
    private readonly string _userThemesDirectory;
    
    public ThemeManager()
    {
        // Built-in themes in application directory
        _themesDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Themes");
        
        // User custom themes in user data folder (Documents\DbExplorer\Themes)
        _userThemesDirectory = UserDataFolderHelper.EnsureSubFolder("Themes");
        
        EnsureDirectoriesExist();
        CreateBuiltInThemes();
    }

    private void EnsureDirectoriesExist()
    {
        try
        {
            if (!Directory.Exists(_themesDirectory))
            {
                Directory.CreateDirectory(_themesDirectory);
                Logger.Info("Created themes directory: {Dir}", _themesDirectory);
            }

            if (!Directory.Exists(_userThemesDirectory))
            {
                Directory.CreateDirectory(_userThemesDirectory);
                Logger.Info("Created user themes directory: {Dir}", _userThemesDirectory);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error creating theme directories");
        }
    }

    private void CreateBuiltInThemes()
    {
        try
        {
            // Create Dark theme
            var darkTheme = CreateDarkTheme();
            SaveBuiltInTheme(darkTheme, "Dark.theme.json");

            // Create Light theme
            var lightTheme = CreateLightTheme();
            SaveBuiltInTheme(lightTheme, "Light.theme.json");

            Logger.Info("Built-in themes created successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error creating built-in themes");
        }
    }

    private AppTheme CreateDarkTheme()
    {
        return new AppTheme
        {
            Name = "Dark",
            Description = "Built-in dark theme optimized for low-light environments",
            BaseTheme = "Dark",
            IsBuiltIn = true,
            Editor = new EditorTheme
            {
                FontFamily = "Consolas",
                FontSize = 14,
                TabSize = 4,
                BackgroundColor = "#1E1E1E",
                ForegroundColor = "#D4D4D4",
                LineNumberColor = "#858585",
                SelectionColor = "#264F78",
                CurrentLineColor = "#282828"
            },
            Grid = new GridTheme
            {
                FontFamily = "Segoe UI",
                FontSize = 12,
                CellHeight = 25,
                BackgroundColor = "#2D2D2D",
                ForegroundColor = "#E0E0E0",
                SelectedBackgroundColor = "#0078D4",
                SelectedForegroundColor = "#FFFFFF",
                HeaderBackgroundColor = "#252526",
                HeaderForegroundColor = "#CCCCCC",
                AlternateRowColor = "#323232"
            },
            UI = new UITheme
            {
                ObjectBrowserFontSize = 12,
                DialogFontSize = 14,
                MenuFontSize = 12,
                StatusBarFontSize = 11,
                PropertyWindowFontSize = 12,
                WindowBackgroundColor = "#1E1E1E",
                WindowForegroundColor = "#E0E0E0",
                ButtonBackgroundColor = "#0E639C",
                ButtonForegroundColor = "#FFFFFF"
            }
        };
    }

    private AppTheme CreateLightTheme()
    {
        return new AppTheme
        {
            Name = "Light",
            Description = "Built-in light theme for bright environments",
            BaseTheme = "Light",
            IsBuiltIn = true,
            Editor = new EditorTheme
            {
                FontFamily = "Consolas",
                FontSize = 14,
                TabSize = 4,
                BackgroundColor = "#FFFFFF",
                ForegroundColor = "#000000",
                LineNumberColor = "#2B91AF",
                SelectionColor = "#ADD6FF",
                CurrentLineColor = "#F0F0F0"
            },
            Grid = new GridTheme
            {
                FontFamily = "Segoe UI",
                FontSize = 12,
                CellHeight = 25,
                BackgroundColor = "#FFFFFF",
                ForegroundColor = "#000000",
                SelectedBackgroundColor = "#0078D4",
                SelectedForegroundColor = "#FFFFFF",
                HeaderBackgroundColor = "#F0F0F0",
                HeaderForegroundColor = "#000000",
                AlternateRowColor = "#F8F8F8"
            },
            UI = new UITheme
            {
                ObjectBrowserFontSize = 12,
                DialogFontSize = 14,
                MenuFontSize = 12,
                StatusBarFontSize = 11,
                PropertyWindowFontSize = 12,
                WindowBackgroundColor = "#FFFFFF",
                WindowForegroundColor = "#000000",
                ButtonBackgroundColor = "#0078D4",
                ButtonForegroundColor = "#FFFFFF"
            }
        };
    }

    private void SaveBuiltInTheme(AppTheme theme, string filename)
    {
        try
        {
            var filePath = Path.Combine(_themesDirectory, filename);
            var json = JsonSerializer.Serialize(theme, new JsonSerializerOptions
            {
                WriteIndented = true
            });
            File.WriteAllText(filePath, json);
            Logger.Debug("Built-in theme saved: {File}", filename);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error saving built-in theme: {File}", filename);
        }
    }

    /// <summary>
    /// Load all available themes (built-in + user custom)
    /// </summary>
    public List<AppTheme> LoadAllThemes()
    {
        var themes = new List<AppTheme>();

        try
        {
            // Load built-in themes
            if (Directory.Exists(_themesDirectory))
            {
                foreach (var file in Directory.GetFiles(_themesDirectory, "*.theme.json"))
                {
                    var theme = LoadThemeFromFile(file);
                    if (theme != null)
                    {
                        themes.Add(theme);
                    }
                }
            }

            // Load user custom themes
            if (Directory.Exists(_userThemesDirectory))
            {
                foreach (var file in Directory.GetFiles(_userThemesDirectory, "*.theme.json"))
                {
                    var theme = LoadThemeFromFile(file);
                    if (theme != null)
                    {
                        themes.Add(theme);
                    }
                }
            }

            Logger.Info("Loaded {Count} themes", themes.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading themes");
        }

        return themes;
    }

    /// <summary>
    /// Load a specific theme by name
    /// </summary>
    public AppTheme? LoadTheme(string themeName)
    {
        try
        {
            // Try built-in first
            var builtInPath = Path.Combine(_themesDirectory, $"{themeName}.theme.json");
            if (File.Exists(builtInPath))
            {
                return LoadThemeFromFile(builtInPath);
            }

            // Try user custom
            var userPath = Path.Combine(_userThemesDirectory, $"{themeName}.theme.json");
            if (File.Exists(userPath))
            {
                return LoadThemeFromFile(userPath);
            }

            Logger.Warn("Theme not found: {Name}", themeName);
            return null;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading theme: {Name}", themeName);
            return null;
        }
    }

    private AppTheme? LoadThemeFromFile(string filePath)
    {
        try
        {
            var json = File.ReadAllText(filePath);
            var theme = JsonSerializer.Deserialize<AppTheme>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (theme != null)
            {
                Logger.Debug("Loaded theme from: {File}", Path.GetFileName(filePath));
                return theme;
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading theme file: {File}", filePath);
        }

        return null;
    }

    /// <summary>
    /// Save a user custom theme
    /// </summary>
    public bool SaveUserTheme(AppTheme theme)
    {
        try
        {
            if (theme.IsBuiltIn)
            {
                Logger.Warn("Cannot save built-in theme: {Name}", theme.Name);
                return false;
            }

            var filename = $"{theme.Name}.theme.json";
            var filePath = Path.Combine(_userThemesDirectory, filename);

            var json = JsonSerializer.Serialize(theme, new JsonSerializerOptions
            {
                WriteIndented = true
            });

            File.WriteAllText(filePath, json);
            Logger.Info("User theme saved: {Name}", theme.Name);
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error saving user theme: {Name}", theme.Name);
            return false;
        }
    }

    /// <summary>
    /// Delete a user custom theme
    /// </summary>
    public bool DeleteUserTheme(string themeName)
    {
        try
        {
            var filePath = Path.Combine(_userThemesDirectory, $"{themeName}.theme.json");
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
                Logger.Info("User theme deleted: {Name}", themeName);
                return true;
            }

            Logger.Warn("Theme file not found: {Name}", themeName);
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error deleting user theme: {Name}", themeName);
            return false;
        }
    }

    /// <summary>
    /// Export a theme to a specific location
    /// </summary>
    public bool ExportTheme(AppTheme theme, string exportPath)
    {
        try
        {
            var json = JsonSerializer.Serialize(theme, new JsonSerializerOptions
            {
                WriteIndented = true
            });

            File.WriteAllText(exportPath, json);
            Logger.Info("Theme exported to: {Path}", exportPath);
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error exporting theme to: {Path}", exportPath);
            return false;
        }
    }

    /// <summary>
    /// Import a theme from a file
    /// </summary>
    public AppTheme? ImportTheme(string importPath)
    {
        try
        {
            var theme = LoadThemeFromFile(importPath);
            if (theme != null)
            {
                // Mark as custom theme
                theme.IsBuiltIn = false;
                
                // Save to user themes
                if (SaveUserTheme(theme))
                {
                    Logger.Info("Theme imported successfully: {Name}", theme.Name);
                    return theme;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error importing theme from: {Path}", importPath);
        }

        return null;
    }
}
