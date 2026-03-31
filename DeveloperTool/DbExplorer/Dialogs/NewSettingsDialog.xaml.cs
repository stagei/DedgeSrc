using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using NLog;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class NewSettingsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly PreferencesService _preferencesService;
    private readonly Dictionary<string, FrameworkElement> _contentPanels = new();
    private UserPreferences _workingPreferences = null!;
    private bool _isDirty = false;
    private AppTheme? _originalTheme; // Track original theme to detect customizations

    public NewSettingsDialog(PreferencesService preferencesService)
    {
        InitializeComponent();
        _preferencesService = preferencesService;
        
        // Create working copy of preferences
        ClonePreferences();
        
        // Build all content panels
        BuildContentPanels();
        
        // Select first item
        if (SettingsTreeView.Items.Count > 0 && SettingsTreeView.Items[0] is TreeViewItem firstItem)
        {
            firstItem.IsSelected = true;
        }
        
        Logger.Debug("NewSettingsDialog initialized");
    }

    private void ClonePreferences()
    {
        var json = System.Text.Json.JsonSerializer.Serialize(_preferencesService.Preferences);
        _workingPreferences = System.Text.Json.JsonSerializer.Deserialize<UserPreferences>(json) ?? new UserPreferences();
        
        // Store original theme to detect customizations later
        _originalTheme = UIStyleService.GetCurrentTheme();
    }
    
    /// <summary>
    /// Check if the current working preferences differ from the original theme
    /// </summary>
    private bool HasUnsavedThemeCustomizations()
    {
        if (_originalTheme == null) return false;
        
        // Compare key values between working preferences and original theme
        return _workingPreferences.GridBackgroundColor != _originalTheme.Grid.BackgroundColor ||
               _workingPreferences.GridForegroundColor != _originalTheme.Grid.ForegroundColor ||
               _workingPreferences.GridSelectedBackgroundColor != _originalTheme.Grid.SelectedBackgroundColor ||
               _workingPreferences.GridSelectedForegroundColor != _originalTheme.Grid.SelectedForegroundColor ||
               _workingPreferences.GridFontSize != _originalTheme.Grid.FontSize ||
               _workingPreferences.GridFontFamily != _originalTheme.Grid.FontFamily ||
               _workingPreferences.GridCellHeight != _originalTheme.Grid.CellHeight ||
               _workingPreferences.EditorBackgroundColor != _originalTheme.Editor.BackgroundColor ||
               _workingPreferences.EditorForegroundColor != _originalTheme.Editor.ForegroundColor ||
               _workingPreferences.EditorLineNumberColor != _originalTheme.Editor.LineNumberColor ||
               _workingPreferences.EditorCurrentLineColor != _originalTheme.Editor.CurrentLineColor ||
               _workingPreferences.FontFamily != _originalTheme.Editor.FontFamily ||
               _workingPreferences.FontSize != _originalTheme.Editor.FontSize;
    }
    
    /// <summary>
    /// Prompt user to save customizations before switching themes
    /// Returns true if user wants to proceed with theme switch, false to cancel
    /// </summary>
    private bool PromptToSaveCustomizations(string currentThemeName)
    {
        // Create a dialog to ask user
        var result = MessageBox.Show(
            $"You have customized the '{currentThemeName}' theme.\n\n" +
            "Would you like to save your customizations as a new theme before switching?\n\n" +
            "• Yes - Save customizations and switch\n" +
            "• No - Discard customizations and switch\n" +
            "• Cancel - Stay on current theme",
            "Save Theme Customizations?",
            MessageBoxButton.YesNoCancel,
            MessageBoxImage.Question);
        
        if (result == MessageBoxResult.Cancel)
        {
            return false; // Don't switch
        }
        
        if (result == MessageBoxResult.Yes)
        {
            // Show save dialog with default name
            var defaultName = $"{currentThemeName}-{DateTime.Now:yyyy-MM-dd-HHmm}";
            var saveDialog = new SaveThemeDialog(defaultName);
            saveDialog.Owner = this;
            
            if (saveDialog.ShowDialog() == true && !string.IsNullOrWhiteSpace(saveDialog.ThemeName))
            {
                var themeName = saveDialog.ThemeName.Trim();
                
                // Check for built-in theme names
                if (themeName.Equals("Dark", StringComparison.OrdinalIgnoreCase) || 
                    themeName.Equals("Light", StringComparison.OrdinalIgnoreCase))
                {
                    MessageBox.Show("Cannot overwrite built-in themes. Your customizations were not saved.", 
                        "Save Theme", MessageBoxButton.OK, MessageBoxImage.Warning);
                }
                else if (UIStyleService.SaveAsCustomTheme(themeName))
                {
                    MessageBox.Show($"Theme '{themeName}' saved successfully!", 
                        "Theme Saved", MessageBoxButton.OK, MessageBoxImage.Information);
                }
            }
        }
        
        return true; // Proceed with switch
    }

    #region Content Panel Builders

    private void BuildContentPanels()
    {
        _contentPanels["General"] = BuildGeneralPanel();
        _contentPanels["Startup"] = BuildStartupPanel();
        _contentPanels["Appearance"] = BuildAppearancePanel();
        _contentPanels["Theme"] = BuildThemePanel();
        _contentPanels["ColorsAndFonts"] = BuildColorsAndFontsPanel();
        _contentPanels["ObjectBrowser"] = BuildObjectBrowserPanel();
        _contentPanels["DataGrids"] = BuildDataGridsPanel();
        _contentPanels["WindowBehavior"] = BuildWindowBehaviorPanel();
        _contentPanels["Editor"] = BuildEditorPanel();
        _contentPanels["EditorGeneral"] = BuildEditorGeneralPanel();
        _contentPanels["EditorFormatting"] = BuildEditorFormattingPanel();
        _contentPanels["SyntaxHighlighting"] = BuildSyntaxHighlightingPanel();
        _contentPanels["Database"] = BuildDatabasePanel();
        _contentPanels["DbConnection"] = BuildDbConnectionPanel();
        _contentPanels["QueryExecution"] = BuildQueryExecutionPanel();
        _contentPanels["ResultSets"] = BuildResultSetsPanel();
        _contentPanels["Keys"] = BuildKeysPanel();
        _contentPanels["Logging"] = BuildLoggingPanel();
        _contentPanels["AI"] = BuildAIPanel();
        _contentPanels["AIProviders"] = BuildAIProvidersPanel();
        _contentPanels["AIModels"] = BuildAIModelsPanel();
    }

    private StackPanel BuildGeneralPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("General application settings including startup and system tray options."));
        panel.Children.Add(CreateSubcategoryLink("Startup", "Configure Windows startup and system tray icon"));
        return panel;
    }

    private StackPanel BuildStartupPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure whether DbExplorer starts automatically with Windows and whether to show the system tray icon."));
        
        panel.Children.Add(CreateSectionHeader("Windows Startup"));
        
        var startupManager = new StartupManagerService();
        var isStartupEnabled = startupManager.IsStartupEnabled();
        var startupCheck = new CheckBox { 
            Content = "Start DbExplorer when Windows starts", 
            IsChecked = _workingPreferences.StartupEnabled || isStartupEnabled,
            Margin = new Thickness(0, 10, 0, 5)
        };
        startupCheck.Checked += (s, e) => { 
            _workingPreferences.StartupEnabled = true;
            _isDirty = true;
        };
        startupCheck.Unchecked += (s, e) => { 
            _workingPreferences.StartupEnabled = false;
            _isDirty = true;
        };
        panel.Children.Add(startupCheck);
        
        panel.Children.Add(CreateTip("When enabled, DbExplorer will automatically start when you log in to Windows. The application will be added to the Windows startup registry."));
        
        panel.Children.Add(CreateSectionHeader("System Tray Icon"));
        
        var trayIconCheck = new CheckBox { 
            Content = "Show system tray icon", 
            IsChecked = _workingPreferences.ShowTrayIcon,
            Margin = new Thickness(0, 10, 0, 5)
        };
        trayIconCheck.Checked += (s, e) => { 
            _workingPreferences.ShowTrayIcon = true;
            _isDirty = true;
        };
        trayIconCheck.Unchecked += (s, e) => { 
            _workingPreferences.ShowTrayIcon = false;
            _isDirty = true;
        };
        panel.Children.Add(trayIconCheck);
        
        panel.Children.Add(CreateTip("When enabled, a system tray icon will be available to quickly launch connections and receive notifications. The tray icon app (DbExplorerTray.exe) must be running separately."));
        
        return panel;
    }

    private StackPanel BuildAppearancePanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure the visual appearance of the application including themes, colors, fonts, and UI element styling."));
        panel.Children.Add(CreateSubcategoryLink("Theme", "Choose between Light, Dark, or System theme"));
        panel.Children.Add(CreateSubcategoryLink("Colors and Fonts", "Customize colors and font settings"));
        panel.Children.Add(CreateSubcategoryLink("Object Browser", "Configure the database object browser appearance"));
        panel.Children.Add(CreateSubcategoryLink("Data Grids", "Configure data grid styling and colors"));
        panel.Children.Add(CreateSubcategoryLink("Window Behavior", "Configure how tool windows open (docked or floating)"));
        return panel;
    }

    private StackPanel BuildThemePanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Select from built-in themes or your saved custom themes. You can adjust colors and fonts in the settings, then save as your own theme."));
        
        panel.Children.Add(CreateSectionHeader("Select Theme"));
        
        // Get all available themes
        var availableThemes = UIStyleService.GetAvailableThemes();
        var themeCombo = new ComboBox { Width = 300, Margin = new Thickness(0, 5, 0, 15) };
        
        foreach (var theme in availableThemes)
        {
            var displayName = theme.IsBuiltIn ? $"🎨 {theme.Name} (Built-in)" : $"⭐ {theme.Name}";
            themeCombo.Items.Add(new ComboBoxItem { Content = displayName, Tag = theme.Name });
        }
        
        // Set current selection
        var activeTheme = _workingPreferences.ActiveThemeName ?? "Dark";
        SetComboBoxValue(themeCombo, activeTheme);
        
        themeCombo.SelectionChanged += (s, e) => {
            var newThemeName = GetComboBoxValue(themeCombo);
            var selectedTheme = availableThemes.Find(t => t.Name == newThemeName);
            var currentThemeName = _workingPreferences.ActiveThemeName ?? "Dark";
            
            // Skip if selecting the same theme
            if (newThemeName == currentThemeName || selectedTheme == null)
                return;
            
            // Check if user has customized the current theme
            if (HasUnsavedThemeCustomizations())
            {
                if (!PromptToSaveCustomizations(currentThemeName))
                {
                    // User cancelled - revert combo selection
                    SetComboBoxValue(themeCombo, currentThemeName);
                    return;
                }
                
                // Refresh available themes in case user saved a new one
                var refreshedThemes = UIStyleService.GetAvailableThemes();
                selectedTheme = refreshedThemes.Find(t => t.Name == newThemeName);
                if (selectedTheme == null) return;
            }
            
            // Proceed with theme switch
            _workingPreferences.ActiveThemeName = newThemeName;
            _workingPreferences.DefaultTheme = selectedTheme.BaseTheme;
            
            // Apply theme colors to working preferences
            _workingPreferences.EditorBackgroundColor = selectedTheme.Editor.BackgroundColor;
            _workingPreferences.EditorForegroundColor = selectedTheme.Editor.ForegroundColor;
            _workingPreferences.EditorLineNumberColor = selectedTheme.Editor.LineNumberColor;
            _workingPreferences.EditorCurrentLineColor = selectedTheme.Editor.CurrentLineColor;
            _workingPreferences.FontFamily = selectedTheme.Editor.FontFamily;
            _workingPreferences.FontSize = selectedTheme.Editor.FontSize;
            
            _workingPreferences.GridBackgroundColor = selectedTheme.Grid.BackgroundColor;
            _workingPreferences.GridForegroundColor = selectedTheme.Grid.ForegroundColor;
            _workingPreferences.GridSelectedBackgroundColor = selectedTheme.Grid.SelectedBackgroundColor;
            _workingPreferences.GridSelectedForegroundColor = selectedTheme.Grid.SelectedForegroundColor;
            _workingPreferences.GridFontSize = selectedTheme.Grid.FontSize;
            _workingPreferences.GridFontFamily = selectedTheme.Grid.FontFamily;
            _workingPreferences.GridCellHeight = selectedTheme.Grid.CellHeight;
            
            _workingPreferences.UIFontSize = selectedTheme.UI.ObjectBrowserFontSize;
            
            // IMPORTANT: Apply the theme immediately to all windows
            // This ensures the ModernWpf theme change propagates to all UI elements
            UIStyleService.ApplyTheme(selectedTheme);
            
            // Update original theme to track future customizations against new theme
            _originalTheme = selectedTheme;
            
            _isDirty = true;
            
            // Rebuild colors panel to reflect changes
            _contentPanels["ColorsAndFonts"] = BuildColorsAndFontsPanel();
            _contentPanels["DataGrids"] = BuildDataGridsPanel();
            
            // Rebuild theme panel to refresh available themes
            _contentPanels["Theme"] = BuildThemePanel();
        };
        panel.Children.Add(themeCombo);
        
        panel.Children.Add(CreateSectionHeader("Save Custom Theme"));
        panel.Children.Add(CreateDescription("After customizing colors and fonts, save your settings as a reusable theme."));
        
        var savePanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 10) };
        var themeNameBox = new TextBox { Width = 200, Text = "My Custom Theme" };
        savePanel.Children.Add(themeNameBox);
        
        var saveBtn = new Button { Content = "💾 Save Theme", Margin = new Thickness(10, 0, 0, 0), Width = 120 };
        saveBtn.Click += (s, e) => {
            var themeName = themeNameBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(themeName))
            {
                MessageBox.Show("Please enter a theme name.", "Save Theme", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            if (themeName.Equals("Dark", StringComparison.OrdinalIgnoreCase) || 
                themeName.Equals("Light", StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show("Cannot overwrite built-in themes. Please choose a different name.", "Save Theme", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            
            // Save current preferences as theme
            if (UIStyleService.SaveAsCustomTheme(themeName))
            {
                MessageBox.Show($"Theme '{themeName}' saved successfully!\n\nYou can now select it from the theme dropdown.", "Theme Saved", MessageBoxButton.OK, MessageBoxImage.Information);
                
                // Rebuild the theme panel to show new theme
                _contentPanels["Theme"] = BuildThemePanel();
                ContentPanel.Content = _contentPanels["Theme"];
            }
            else
            {
                MessageBox.Show("Failed to save theme. See log for details.", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        };
        savePanel.Children.Add(saveBtn);
        panel.Children.Add(savePanel);
        
        // Delete custom theme section
        var customThemes = availableThemes.Where(t => !t.IsBuiltIn).ToList();
        if (customThemes.Count > 0)
        {
            panel.Children.Add(CreateSectionHeader("Delete Custom Theme"));
            
            var deletePanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 10) };
            var deleteCombo = new ComboBox { Width = 200 };
            foreach (var theme in customThemes)
            {
                deleteCombo.Items.Add(new ComboBoxItem { Content = theme.Name, Tag = theme.Name });
            }
            if (deleteCombo.Items.Count > 0) deleteCombo.SelectedIndex = 0;
            deletePanel.Children.Add(deleteCombo);
            
            var deleteBtn = new Button { Content = "🗑️ Delete", Margin = new Thickness(10, 0, 0, 0), Width = 80 };
            deleteBtn.Click += (s, e) => {
                var themeName = GetComboBoxValue(deleteCombo);
                if (string.IsNullOrEmpty(themeName)) return;
                
                var result = MessageBox.Show($"Are you sure you want to delete the theme '{themeName}'?", "Delete Theme", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (result == MessageBoxResult.Yes)
                {
                    if (UIStyleService.DeleteCustomTheme(themeName))
                    {
                        MessageBox.Show($"Theme '{themeName}' deleted.", "Theme Deleted", MessageBoxButton.OK, MessageBoxImage.Information);
                        
                        // Rebuild the theme panel
                        _contentPanels["Theme"] = BuildThemePanel();
                        ContentPanel.Content = _contentPanels["Theme"];
                    }
                }
            };
            deletePanel.Children.Add(deleteBtn);
            panel.Children.Add(deletePanel);
        }
        
        panel.Children.Add(CreateTip("Tip: Built-in themes (Dark, Light) cannot be overwritten or deleted. Customize their colors and save as a new theme with a different name."));
        
        return panel;
    }

    private StackPanel BuildColorsAndFontsPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Customize fonts and colors used throughout the application."));
        
        panel.Children.Add(CreateSectionHeader("Global UI Font Size"));
        panel.Children.Add(CreateLabel("Applies to buttons, menus, labels, and all UI elements:"));
        var uiFontSizeSlider = CreateSliderWithValue(8, 24, _workingPreferences.UIFontSize, v => {
            _workingPreferences.UIFontSize = (int)v;
            _workingPreferences.GridFontSize = (int)v; // Keep grid in sync
            _isDirty = true;
        });
        panel.Children.Add(uiFontSizeSlider);
        
        panel.Children.Add(CreateTip("Tip: Use Ctrl++ and Ctrl+- to quickly adjust all font sizes"));
        
        panel.Children.Add(CreateSectionHeader("Editor Font"));
        
        var fontCombo = new ComboBox { Width = 200, Margin = new Thickness(0, 5, 0, 10) };
        foreach (var font in new[] { "Consolas", "Cascadia Code", "Fira Code", "JetBrains Mono", "Source Code Pro", "Courier New" })
        {
            fontCombo.Items.Add(new ComboBoxItem { Content = font, Tag = font });
        }
        SetComboBoxValue(fontCombo, _workingPreferences.FontFamily);
        fontCombo.SelectionChanged += (s, e) => {
            _workingPreferences.FontFamily = GetComboBoxValue(fontCombo);
            _isDirty = true;
        };
        panel.Children.Add(fontCombo);
        
        panel.Children.Add(CreateLabel("Editor Font Size:"));
        var fontSizeSlider = CreateSliderWithValue(8, 36, _workingPreferences.FontSize, v => {
            _workingPreferences.FontSize = (int)v;
            _isDirty = true;
        });
        panel.Children.Add(fontSizeSlider);
        
        panel.Children.Add(CreateSectionHeader("Editor Theme Colors"));
        
        panel.Children.Add(CreateLabel("Background Color:"));
        panel.Children.Add(CreateColorPicker(_workingPreferences.EditorBackgroundColor, c => {
            _workingPreferences.EditorBackgroundColor = c;
            _isDirty = true;
        }));
        
        panel.Children.Add(CreateLabel("Text Color:"));
        panel.Children.Add(CreateColorPicker(_workingPreferences.EditorForegroundColor, c => {
            _workingPreferences.EditorForegroundColor = c;
            _isDirty = true;
        }));
        
        panel.Children.Add(CreateLabel("Line Number Color:"));
        panel.Children.Add(CreateColorPicker(_workingPreferences.EditorLineNumberColor, c => {
            _workingPreferences.EditorLineNumberColor = c;
            _isDirty = true;
        }));
        
        panel.Children.Add(CreateLabel("Current Line Highlight:"));
        panel.Children.Add(CreateColorPicker(_workingPreferences.EditorCurrentLineColor, c => {
            _workingPreferences.EditorCurrentLineColor = c;
            _isDirty = true;
        }));
        
        // Quick preset buttons
        panel.Children.Add(CreateSectionHeader("Editor Color Presets"));
        var presetsPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 10) };
        
        var darkPresetBtn = new Button { Content = "🌙 Dark Mode", Margin = new Thickness(0, 0, 10, 0), Padding = new Thickness(15, 5, 15, 5) };
        darkPresetBtn.Click += (s, e) => {
            _workingPreferences.EditorBackgroundColor = "#1E1E1E";
            _workingPreferences.EditorForegroundColor = "#D4D4D4";
            _workingPreferences.EditorLineNumberColor = "#858585";
            _workingPreferences.EditorCurrentLineColor = "#2D2D30";
            _isDirty = true;
            // Rebuild panel to reflect changes
            _contentPanels["ColorsAndFonts"] = BuildColorsAndFontsPanel();
            if (ContentPanel.Content is StackPanel) ContentPanel.Content = _contentPanels["ColorsAndFonts"];
        };
        presetsPanel.Children.Add(darkPresetBtn);
        
        var lightPresetBtn = new Button { Content = "☀️ Light Mode", Margin = new Thickness(0, 0, 10, 0), Padding = new Thickness(15, 5, 15, 5) };
        lightPresetBtn.Click += (s, e) => {
            _workingPreferences.EditorBackgroundColor = "#FFFFFF";
            _workingPreferences.EditorForegroundColor = "#000000";
            _workingPreferences.EditorLineNumberColor = "#2B91AF";
            _workingPreferences.EditorCurrentLineColor = "#E8F2FF";
            _isDirty = true;
            // Rebuild panel to reflect changes
            _contentPanels["ColorsAndFonts"] = BuildColorsAndFontsPanel();
            if (ContentPanel.Content is StackPanel) ContentPanel.Content = _contentPanels["ColorsAndFonts"];
        };
        presetsPanel.Children.Add(lightPresetBtn);
        
        panel.Children.Add(presetsPanel);
        
        return panel;
    }

    private StackPanel BuildObjectBrowserPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure the appearance of the database object browser tree view."));
        
        panel.Children.Add(CreateSectionHeader("Font Settings"));
        
        panel.Children.Add(CreateLabel("Font Family:"));
        var fontCombo = new ComboBox { Width = 200, Margin = new Thickness(0, 5, 0, 10) };
        foreach (var font in new[] { "Segoe UI", "Consolas", "Cascadia Code", "Arial", "Tahoma" })
        {
            fontCombo.Items.Add(new ComboBoxItem { Content = font, Tag = font });
        }
        SetComboBoxValue(fontCombo, _workingPreferences.GridFontFamily);
        fontCombo.SelectionChanged += (s, e) => {
            _workingPreferences.GridFontFamily = GetComboBoxValue(fontCombo);
            _isDirty = true;
        };
        panel.Children.Add(fontCombo);
        
        panel.Children.Add(CreateLabel("Font Size:"));
        var fontSizeSlider = CreateSliderWithValue(8, 18, _workingPreferences.GridFontSize, v => {
            _workingPreferences.GridFontSize = (int)v;
            _isDirty = true;
        });
        panel.Children.Add(fontSizeSlider);
        
        panel.Children.Add(CreateSectionHeader("Spacing"));
        
        panel.Children.Add(CreateLabel("Item Vertical Spacing (pixels):"));
        var spacingSlider = CreateSliderWithValue(0, 10, _workingPreferences.TreeViewItemSpacing, v => {
            _workingPreferences.TreeViewItemSpacing = (int)v;
            _isDirty = true;
        });
        panel.Children.Add(spacingSlider);
        
        panel.Children.Add(CreateTip("Tip: Use Ctrl+Shift++ and Ctrl+Shift+- to quickly adjust spacing"));
        
        panel.Children.Add(CreateSectionHeader("Auto-Resize"));
        
        var autoResizeCheckbox = new CheckBox
        {
            Content = "Disable auto-resize on tree expansion",
            IsChecked = _workingPreferences.DisableObjectBrowserAutoResize,
            Margin = new Thickness(0, 5, 0, 5),
            Foreground = (System.Windows.Media.Brush)FindResource("SystemControlForegroundBaseHighBrush")
        };
        autoResizeCheckbox.Checked += (s, e) => {
            _workingPreferences.DisableObjectBrowserAutoResize = true;
            _isDirty = true;
        };
        autoResizeCheckbox.Unchecked += (s, e) => {
            _workingPreferences.DisableObjectBrowserAutoResize = false;
            _isDirty = true;
        };
        panel.Children.Add(autoResizeCheckbox);
        
        panel.Children.Add(CreateTip("When enabled, the Object Browser width will not automatically adjust when expanding tree nodes. Use the splitter to resize manually."));
        
        return panel;
    }

    private StackPanel BuildDataGridsPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure the appearance of data grids used for query results and data display."));
        
        panel.Children.Add(CreateSectionHeader("Colors"));
        
        panel.Children.Add(CreateLabel("Background Color:"));
        var bgColor = CreateColorPicker(_workingPreferences.GridBackgroundColor, c => {
            _workingPreferences.GridBackgroundColor = c;
            _isDirty = true;
        });
        panel.Children.Add(bgColor);
        
        panel.Children.Add(CreateLabel("Foreground Color:"));
        var fgColor = CreateColorPicker(_workingPreferences.GridForegroundColor, c => {
            _workingPreferences.GridForegroundColor = c;
            _isDirty = true;
        });
        panel.Children.Add(fgColor);
        
        panel.Children.Add(CreateLabel("Selected Row Background:"));
        var selBgColor = CreateColorPicker(_workingPreferences.GridSelectedBackgroundColor, c => {
            _workingPreferences.GridSelectedBackgroundColor = c;
            _isDirty = true;
        });
        panel.Children.Add(selBgColor);
        
        panel.Children.Add(CreateLabel("Selected Row Foreground:"));
        var selFgColor = CreateColorPicker(_workingPreferences.GridSelectedForegroundColor, c => {
            _workingPreferences.GridSelectedForegroundColor = c;
            _isDirty = true;
        });
        panel.Children.Add(selFgColor);
        
        panel.Children.Add(CreateSectionHeader("Layout"));
        
        panel.Children.Add(CreateLabel("Row Height (pixels):"));
        var heightSlider = CreateSliderWithValue(20, 50, _workingPreferences.GridCellHeight, v => {
            _workingPreferences.GridCellHeight = (int)v;
            _isDirty = true;
        });
        panel.Children.Add(heightSlider);
        
        return panel;
    }

    private StackPanel BuildWindowBehaviorPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure how tool windows and panels are opened."));
        
        panel.Children.Add(CreateSectionHeader("Tool Window Mode"));
        
        var autoDockCheck = new CheckBox { 
            Content = "Auto-dock tools as tabs", 
            IsChecked = _workingPreferences.AutoDockTools,
            Margin = new Thickness(0, 10, 0, 5)
        };
        autoDockCheck.Checked += (s, e) => { _workingPreferences.AutoDockTools = true; _isDirty = true; };
        autoDockCheck.Unchecked += (s, e) => { _workingPreferences.AutoDockTools = false; _isDirty = true; };
        panel.Children.Add(autoDockCheck);
        
        panel.Children.Add(CreateTip("When enabled, tool windows (Database Load Monitor, Lock Monitor, etc.) open as docked tabs in the main window. When disabled (default), tools open as separate floating windows that can be moved independently."));
        
        panel.Children.Add(CreateSectionHeader("Current Behavior"));
        var behaviorText = new TextBlock
        {
            Text = _workingPreferences.AutoDockTools 
                ? "🔒 Tools will open DOCKED as tabs in the main window"
                : "🪟 Tools will open UNDOCKED as floating windows (default)",
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 5, 0, 10)
        };
        panel.Children.Add(behaviorText);
        
        return panel;
    }

    private StackPanel BuildEditorPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure SQL editor behavior and appearance."));
        panel.Children.Add(CreateSubcategoryLink("General", "General editor settings"));
        panel.Children.Add(CreateSubcategoryLink("Formatting", "SQL formatting options"));
        panel.Children.Add(CreateSubcategoryLink("Syntax Highlighting", "Configure syntax colors"));
        return panel;
    }

    private StackPanel BuildEditorGeneralPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("General SQL editor settings."));
        
        panel.Children.Add(CreateSectionHeader("Tab Settings"));
        
        panel.Children.Add(CreateLabel("Tab Size (spaces):"));
        var tabSlider = CreateSliderWithValue(2, 8, _workingPreferences.TabSize, v => {
            _workingPreferences.TabSize = (int)v;
            _isDirty = true;
        });
        panel.Children.Add(tabSlider);
        
        return panel;
    }

    private StackPanel BuildEditorFormattingPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("SQL formatting options."));
        
        var autoFormat = new CheckBox { 
            Content = "Auto-format SQL on execute", 
            IsChecked = _workingPreferences.AutoFormatOnExecute,
            Margin = new Thickness(0, 10, 0, 5)
        };
        autoFormat.Checked += (s, e) => { _workingPreferences.AutoFormatOnExecute = true; _isDirty = true; };
        autoFormat.Unchecked += (s, e) => { _workingPreferences.AutoFormatOnExecute = false; _isDirty = true; };
        panel.Children.Add(autoFormat);
        
        return panel;
    }

    private StackPanel BuildSyntaxHighlightingPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Syntax highlighting colors for SQL editor. (Coming soon)"));
        panel.Children.Add(CreateTip("Syntax highlighting customization will be available in a future update."));
        return panel;
    }

    private StackPanel BuildDatabasePanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure database connection and query execution settings."));
        panel.Children.Add(CreateSubcategoryLink("Connection", "Connection timeout and options"));
        panel.Children.Add(CreateSubcategoryLink("Query Execution", "Query execution settings"));
        panel.Children.Add(CreateSubcategoryLink("Result Sets", "Result set display options"));
        return panel;
    }

    private StackPanel BuildDbConnectionPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Database connection settings."));
        
        panel.Children.Add(CreateSectionHeader("Connection Options"));
        
        var autoRefresh = new CheckBox { 
            Content = "Auto-refresh objects on connect", 
            IsChecked = _workingPreferences.AutoRefreshObjectsOnConnect,
            Margin = new Thickness(0, 10, 0, 5)
        };
        autoRefresh.Checked += (s, e) => { _workingPreferences.AutoRefreshObjectsOnConnect = true; _isDirty = true; };
        autoRefresh.Unchecked += (s, e) => { _workingPreferences.AutoRefreshObjectsOnConnect = false; _isDirty = true; };
        panel.Children.Add(autoRefresh);
        
        return panel;
    }

    private StackPanel BuildQueryExecutionPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Query execution settings and timeouts."));
        
        panel.Children.Add(CreateSectionHeader("Timeouts"));
        
        panel.Children.Add(CreateLabel("Command Timeout (seconds, 0 = no timeout):"));
        var timeoutBox = new TextBox { 
            Text = _workingPreferences.CommandTimeout.ToString(), 
            Width = 100, 
            Margin = new Thickness(0, 5, 0, 15),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        timeoutBox.TextChanged += (s, e) => {
            if (int.TryParse(timeoutBox.Text, out int val) && val >= 0)
            {
                _workingPreferences.CommandTimeout = val;
                _isDirty = true;
            }
        };
        panel.Children.Add(timeoutBox);
        
        panel.Children.Add(CreateSectionHeader("Error Handling"));
        
        var handleDecimal = new CheckBox { 
            Content = "Handle decimal type errors gracefully", 
            IsChecked = _workingPreferences.HandleDecimalErrorsGracefully,
            Margin = new Thickness(0, 10, 0, 5)
        };
        handleDecimal.Checked += (s, e) => { _workingPreferences.HandleDecimalErrorsGracefully = true; _isDirty = true; };
        handleDecimal.Unchecked += (s, e) => { _workingPreferences.HandleDecimalErrorsGracefully = false; _isDirty = true; };
        panel.Children.Add(handleDecimal);
        
        return panel;
    }

    private StackPanel BuildResultSetsPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure how result sets are displayed."));
        
        panel.Children.Add(CreateSectionHeader("Row Limits"));
        
        panel.Children.Add(CreateLabel("Max Rows Per Query:"));
        var maxRowsBox = new TextBox { 
            Text = _workingPreferences.MaxRowsPerQuery.ToString(), 
            Width = 100, 
            Margin = new Thickness(0, 5, 0, 15),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        maxRowsBox.TextChanged += (s, e) => {
            if (int.TryParse(maxRowsBox.Text, out int val) && val > 0)
            {
                _workingPreferences.MaxRowsPerQuery = val;
                _isDirty = true;
            }
        };
        panel.Children.Add(maxRowsBox);
        
        return panel;
    }

    private StackPanel BuildKeysPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure keyboard shortcuts for menu items and commands."));
        
        panel.Children.Add(CreateSectionHeader("Quick Actions"));
        panel.Children.Add(CreateHotkeyRow("Increase Font Size", "Ctrl + Plus"));
        panel.Children.Add(CreateHotkeyRow("Decrease Font Size", "Ctrl + Minus"));
        panel.Children.Add(CreateHotkeyRow("Increase TreeView Spacing", "Ctrl + Shift + Plus"));
        panel.Children.Add(CreateHotkeyRow("Decrease TreeView Spacing", "Ctrl + Shift + Minus"));
        panel.Children.Add(CreateHotkeyRow("Toggle Dark Mode", "Ctrl + D"));
        
        panel.Children.Add(CreateSectionHeader("Connection"));
        panel.Children.Add(CreateHotkeyRow("New Connection", "Ctrl + N"));
        panel.Children.Add(CreateHotkeyRow("Close Tab", "Ctrl + W"));
        panel.Children.Add(CreateHotkeyRow("Next Tab", "Ctrl + Tab"));
        panel.Children.Add(CreateHotkeyRow("Previous Tab", "Ctrl + Shift + Tab"));
        
        panel.Children.Add(CreateSectionHeader("Query Execution"));
        panel.Children.Add(CreateHotkeyRow("Execute Query", "F5"));
        panel.Children.Add(CreateHotkeyRow("Execute Selected", "Ctrl + Enter"));
        panel.Children.Add(CreateHotkeyRow("Format SQL", "Ctrl + Shift + F"));
        panel.Children.Add(CreateHotkeyRow("Query History", "Ctrl + H"));
        
        panel.Children.Add(CreateSectionHeader("Edit"));
        panel.Children.Add(CreateHotkeyRow("Find", "Ctrl + F"));
        panel.Children.Add(CreateHotkeyRow("Replace", "Ctrl + R"));
        panel.Children.Add(CreateHotkeyRow("Comment Line", "Ctrl + /"));
        
        panel.Children.Add(CreateTip("Note: Hotkey customization will be available in a future update. These are the current default shortcuts."));
        
        return panel;
    }

    private StackPanel BuildLoggingPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure application logging level and output."));
        
        panel.Children.Add(CreateSectionHeader("Log Level"));
        
        var logCombo = new ComboBox { Width = 150, Margin = new Thickness(0, 5, 0, 15) };
        logCombo.Items.Add(new ComboBoxItem { Content = "Debug", Tag = "Debug" });
        logCombo.Items.Add(new ComboBoxItem { Content = "Info", Tag = "Info" });
        logCombo.Items.Add(new ComboBoxItem { Content = "Warn", Tag = "Warn" });
        logCombo.Items.Add(new ComboBoxItem { Content = "Error", Tag = "Error" });
        SetComboBoxValue(logCombo, _workingPreferences.LogLevel);
        logCombo.SelectionChanged += (s, e) => {
            _workingPreferences.LogLevel = GetComboBoxValue(logCombo);
            _isDirty = true;
        };
        panel.Children.Add(logCombo);
        
        panel.Children.Add(CreateSectionHeader("Data & Log Locations"));
        var userDataPath = new TextBlock {
            Text = $"User data (connections, preferences, themes, etc.): {UserDataFolderHelper.GetUserDataFolder()}",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 5, 0, 0),
            Foreground = (Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        };
        panel.Children.Add(userDataPath);
        var logPath = new TextBlock {
            Text = "Log files: see application directory or NLog configuration.",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 3, 0, 0),
            Foreground = (Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        };
        panel.Children.Add(logPath);
        
        return panel;
    }

    private StackPanel BuildAIPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure AI assistant settings for code analysis and suggestions."));
        panel.Children.Add(CreateSubcategoryLink("Providers", "Configure AI providers (Ollama, OpenAI, Claude)"));
        panel.Children.Add(CreateSubcategoryLink("Models", "Select and configure AI models"));
        return panel;
    }

    private StackPanel BuildAIProvidersPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Configure AI service providers."));
        panel.Children.Add(CreateTip("AI provider configuration is available in the main Settings dialog. This will be migrated here in a future update."));
        return panel;
    }

    private StackPanel BuildAIModelsPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        panel.Children.Add(CreateDescription("Select and configure AI models."));
        panel.Children.Add(CreateTip("AI model configuration is available in the main Settings dialog. This will be migrated here in a future update."));
        return panel;
    }

    #endregion

    #region UI Helpers

    private TextBlock CreateDescription(string text)
    {
        return new TextBlock {
            Text = text,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 20),
            Foreground = (Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        };
    }

    private TextBlock CreateSectionHeader(string text)
    {
        return new TextBlock {
            Text = text,
            FontWeight = FontWeights.SemiBold,
            FontSize = 14,
            Margin = new Thickness(0, 15, 0, 10)
        };
    }

    private TextBlock CreateLabel(string text)
    {
        return new TextBlock {
            Text = text,
            Margin = new Thickness(0, 5, 0, 3)
        };
    }

    private TextBlock CreateTip(string text)
    {
        return new TextBlock {
            Text = text,
            FontStyle = FontStyles.Italic,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 10, 0, 5),
            Foreground = (Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        };
    }

    private Border CreateSubcategoryLink(string name, string description)
    {
        var border = new Border {
            Margin = new Thickness(0, 5, 0, 5),
            Padding = new Thickness(10),
            Background = (Brush)FindResource("SystemControlBackgroundBaseLowBrush"),
            CornerRadius = new CornerRadius(4),
            Cursor = Cursors.Hand
        };
        
        var stack = new StackPanel();
        stack.Children.Add(new TextBlock { Text = name, FontWeight = FontWeights.SemiBold });
        stack.Children.Add(new TextBlock { 
            Text = description, 
            FontSize = 11,
            Foreground = (Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        });
        border.Child = stack;
        
        border.MouseLeftButtonUp += (s, e) => {
            SelectTreeViewItemByTag(name.Replace(" ", "").Replace("and", "And"));
        };
        
        return border;
    }

    private StackPanel CreateSliderWithValue(int min, int max, int currentValue, Action<double> onChange)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 15) };
        
        var slider = new Slider {
            Minimum = min,
            Maximum = max,
            Value = currentValue,
            Width = 200,
            TickFrequency = 1,
            IsSnapToTickEnabled = true,
            VerticalAlignment = VerticalAlignment.Center
        };
        
        var valueText = new TextBlock {
            Text = currentValue.ToString(),
            Width = 30,
            Margin = new Thickness(10, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            FontWeight = FontWeights.SemiBold
        };
        
        slider.ValueChanged += (s, e) => {
            valueText.Text = ((int)e.NewValue).ToString();
            onChange?.Invoke(e.NewValue);
        };
        
        panel.Children.Add(slider);
        panel.Children.Add(valueText);
        
        return panel;
    }

    private StackPanel CreateColorPicker(string currentColor, Action<string> onChange)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 10) };
        
        var colorBox = new TextBox {
            Text = currentColor,
            Width = 100,
            VerticalAlignment = VerticalAlignment.Center
        };
        
        var colorPreview = new Border {
            Width = 24,
            Height = 24,
            Margin = new Thickness(8, 0, 0, 0),
            BorderBrush = Brushes.Gray,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2)
        };
        
        try
        {
            colorPreview.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(currentColor));
        }
        catch
        {
            colorPreview.Background = Brushes.Gray;
        }
        
        var pickButton = new Button {
            Content = "...",
            Width = 30,
            Height = 24,
            Margin = new Thickness(5, 0, 0, 0)
        };
        
        colorBox.TextChanged += (s, e) => {
            try
            {
                var color = (Color)ColorConverter.ConvertFromString(colorBox.Text);
                colorPreview.Background = new SolidColorBrush(color);
                onChange?.Invoke(colorBox.Text);
            }
            catch { }
        };
        
        pickButton.Click += (s, e) => {
            using var dialog = new System.Windows.Forms.ColorDialog();
            try
            {
                var wpfColor = (Color)ColorConverter.ConvertFromString(colorBox.Text);
                dialog.Color = System.Drawing.Color.FromArgb(wpfColor.A, wpfColor.R, wpfColor.G, wpfColor.B);
            }
            catch { }
            
            if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
            {
                var hex = $"#{dialog.Color.R:X2}{dialog.Color.G:X2}{dialog.Color.B:X2}";
                colorBox.Text = hex;
            }
        };
        
        panel.Children.Add(colorBox);
        panel.Children.Add(colorPreview);
        panel.Children.Add(pickButton);
        
        return panel;
    }

    private Border CreateHotkeyRow(string command, string hotkey)
    {
        var border = new Border {
            Margin = new Thickness(0, 3, 0, 3),
            Padding = new Thickness(10, 8, 10, 8),
            Background = (Brush)FindResource("SystemControlBackgroundBaseLowBrush"),
            CornerRadius = new CornerRadius(3)
        };
        
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new System.Windows.Controls.ColumnDefinition { Width = new GridLength(150) });
        
        var cmdText = new TextBlock { Text = command, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(cmdText, 0);
        
        var hotkeyBorder = new Border {
            Background = (Brush)FindResource("SystemControlBackgroundChromeMediumBrush"),
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(8, 4, 8, 4),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        hotkeyBorder.Child = new TextBlock { 
            Text = hotkey, 
            FontFamily = new FontFamily("Consolas"),
            FontSize = 11
        };
        Grid.SetColumn(hotkeyBorder, 1);
        
        grid.Children.Add(cmdText);
        grid.Children.Add(hotkeyBorder);
        border.Child = grid;
        
        return border;
    }

    private void SetComboBoxValue(ComboBox comboBox, string value)
    {
        foreach (ComboBoxItem item in comboBox.Items)
        {
            if (item.Tag?.ToString() == value)
            {
                comboBox.SelectedItem = item;
                break;
            }
        }
    }

    private string GetComboBoxValue(ComboBox comboBox)
    {
        return (comboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? string.Empty;
    }

    #endregion

    #region Event Handlers

    private void FilterTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        var filter = FilterTextBox.Text.ToLower();
        FilterTreeViewItems(SettingsTreeView.Items, filter);
    }

    private void FilterTreeViewItems(ItemCollection items, string filter)
    {
        foreach (var item in items)
        {
            if (item is TreeViewItem tvi)
            {
                var header = tvi.Header?.ToString()?.ToLower() ?? "";
                var matches = string.IsNullOrEmpty(filter) || header.Contains(filter);
                
                // Check children
                FilterTreeViewItems(tvi.Items, filter);
                var hasVisibleChild = tvi.Items.Cast<TreeViewItem>().Any(c => c.Visibility == Visibility.Visible);
                
                tvi.Visibility = (matches || hasVisibleChild) ? Visibility.Visible : Visibility.Collapsed;
                
                if (!string.IsNullOrEmpty(filter) && (matches || hasVisibleChild))
                {
                    tvi.IsExpanded = true;
                }
            }
        }
    }

    private void SettingsTreeView_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
    {
        if (e.NewValue is TreeViewItem tvi && tvi.Tag is string tag)
        {
            ContentTitleText.Text = tvi.Header?.ToString() ?? tag;
            
            if (_contentPanels.TryGetValue(tag, out var panel))
            {
                ContentPanel.Content = panel;
            }
            else
            {
                ContentPanel.Content = new TextBlock { Text = $"Settings for: {tag}" };
            }
        }
    }

    private void SelectTreeViewItemByTag(string tag)
    {
        var item = FindTreeViewItemByTag(SettingsTreeView.Items, tag);
        if (item != null)
        {
            item.IsSelected = true;
            item.BringIntoView();
        }
    }

    private TreeViewItem? FindTreeViewItemByTag(ItemCollection items, string tag)
    {
        foreach (var item in items)
        {
            if (item is TreeViewItem tvi)
            {
                if (tvi.Tag?.ToString() == tag)
                    return tvi;
                
                var found = FindTreeViewItemByTag(tvi.Items, tag);
                if (found != null)
                    return found;
            }
        }
        return null;
    }

    private void NavigateBack_Click(object sender, RoutedEventArgs e)
    {
        // TODO: Implement navigation history
    }

    private void NavigateForward_Click(object sender, RoutedEventArgs e)
    {
        // TODO: Implement navigation history
    }

    private void RestoreDefaults_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "Reset all settings to their default values?",
            "Restore Defaults",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        
        if (result == MessageBoxResult.Yes)
        {
            _workingPreferences = new UserPreferences();
            _isDirty = true;
            
            // Rebuild panels with new values
            BuildContentPanels();
            
            // Refresh current panel
            if (SettingsTreeView.SelectedItem is TreeViewItem tvi && tvi.Tag is string tag)
            {
                if (_contentPanels.TryGetValue(tag, out var panel))
                {
                    ContentPanel.Content = panel;
                }
            }
            
            MessageBox.Show("Settings restored to defaults.", "Restore Defaults", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        SavePreferences();
        _isDirty = false;
        MessageBox.Show("Settings applied.", "Apply", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void ApplyAndClose_Click(object sender, RoutedEventArgs e)
    {
        SavePreferences();
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (_isDirty)
        {
            var result = MessageBox.Show(
                "You have unsaved changes. Discard them?",
                "Unsaved Changes",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            
            if (result != MessageBoxResult.Yes)
                return;
        }
        
        DialogResult = false;
        Close();
    }

    /// <summary>
    /// Check if Windows system theme is dark
    /// </summary>
    private bool IsSystemDarkTheme()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key != null)
            {
                var value = key.GetValue("AppsUseLightTheme");
                if (value is int intValue)
                {
                    return intValue == 0; // 0 = dark, 1 = light
                }
            }
        }
        catch { }
        return false; // Default to light
    }

    private void SavePreferences()
    {
        // Copy working preferences to actual preferences
        _preferencesService.Preferences.DefaultTheme = _workingPreferences.DefaultTheme;
        _preferencesService.Preferences.FontFamily = _workingPreferences.FontFamily;
        _preferencesService.Preferences.FontSize = _workingPreferences.FontSize;
        _preferencesService.Preferences.TabSize = _workingPreferences.TabSize;
        _preferencesService.Preferences.AutoFormatOnExecute = _workingPreferences.AutoFormatOnExecute;
        _preferencesService.Preferences.MaxRowsPerQuery = _workingPreferences.MaxRowsPerQuery;
        _preferencesService.Preferences.CommandTimeout = _workingPreferences.CommandTimeout;
        _preferencesService.Preferences.HandleDecimalErrorsGracefully = _workingPreferences.HandleDecimalErrorsGracefully;
        _preferencesService.Preferences.StartupEnabled = _workingPreferences.StartupEnabled;
        _preferencesService.Preferences.ShowTrayIcon = _workingPreferences.ShowTrayIcon;
        _preferencesService.Preferences.AutoRefreshObjectsOnConnect = _workingPreferences.AutoRefreshObjectsOnConnect;
        _preferencesService.Preferences.LogLevel = _workingPreferences.LogLevel;
        _preferencesService.Preferences.GridBackgroundColor = _workingPreferences.GridBackgroundColor;
        _preferencesService.Preferences.GridForegroundColor = _workingPreferences.GridForegroundColor;
        _preferencesService.Preferences.GridSelectedBackgroundColor = _workingPreferences.GridSelectedBackgroundColor;
        _preferencesService.Preferences.GridSelectedForegroundColor = _workingPreferences.GridSelectedForegroundColor;
        _preferencesService.Preferences.GridFontSize = _workingPreferences.GridFontSize;
        _preferencesService.Preferences.GridFontFamily = _workingPreferences.GridFontFamily;
        _preferencesService.Preferences.GridCellHeight = _workingPreferences.GridCellHeight;
        _preferencesService.Preferences.TreeViewItemSpacing = _workingPreferences.TreeViewItemSpacing;
        _preferencesService.Preferences.UIFontSize = _workingPreferences.UIFontSize;
        _preferencesService.Preferences.EditorBackgroundColor = _workingPreferences.EditorBackgroundColor;
        _preferencesService.Preferences.EditorForegroundColor = _workingPreferences.EditorForegroundColor;
        _preferencesService.Preferences.EditorLineNumberColor = _workingPreferences.EditorLineNumberColor;
        _preferencesService.Preferences.EditorCurrentLineColor = _workingPreferences.EditorCurrentLineColor;
        _preferencesService.Preferences.AutoDockTools = _workingPreferences.AutoDockTools;
        _preferencesService.Preferences.ActiveThemeName = _workingPreferences.ActiveThemeName;
        _preferencesService.Preferences.StartupEnabled = _workingPreferences.StartupEnabled;
        _preferencesService.Preferences.ShowTrayIcon = _workingPreferences.ShowTrayIcon;

        _preferencesService.SavePreferences();

        // Apply global font size to entire application
        GlobalFontService.ApplyAllPreferences(_preferencesService.Preferences);

        // Refresh all UI styles to ensure theme changes propagate to all windows
        UIStyleService.RefreshAllStyles();

        // Apply startup management
        var startupManager = new StartupManagerService();
        if (_workingPreferences.StartupEnabled)
        {
            startupManager.EnableStartup();
        }
        else
        {
            startupManager.DisableStartup();
        }

        Logger.Info("Preferences saved from new settings dialog");
    }

    #endregion
}
