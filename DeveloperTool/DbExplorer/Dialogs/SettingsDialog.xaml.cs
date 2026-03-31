using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Services;
using DbExplorer.Models;

namespace DbExplorer.Dialogs
{
    public partial class SettingsDialog : Window
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        private readonly PreferencesService _preferencesService;

        public SettingsDialog(PreferencesService preferencesService)
        {
            InitializeComponent();
            Logger.Debug("SettingsDialog initialized");

            _preferencesService = preferencesService;

            // Load current preferences first (before adding event handlers to avoid null reference errors)
            LoadCurrentSettings();
            
            // Set up event handlers AFTER loading settings
            FontSizeSlider.ValueChanged += FontSizeSlider_ValueChanged;
            TabSizeSlider.ValueChanged += TabSizeSlider_ValueChanged;
            
            // Only add grid event handlers if the controls exist
            if (GridFontSizeSlider != null && GridCellHeightSlider != null)
            {
                GridFontSizeSlider.ValueChanged += GridFontSizeSlider_ValueChanged;
                GridCellHeightSlider.ValueChanged += GridCellHeightSlider_ValueChanged;
            }
            
            // TreeView spacing slider
            if (TreeViewSpacingSlider != null)
            {
                TreeViewSpacingSlider.ValueChanged += TreeViewSpacingSlider_ValueChanged;
            }

            // Display user data folder path and structure info
            UpdateDataFolderDisplay();
        }
        
        /// <summary>
        /// Updates the data folder display in the Data Files tab.
        /// </summary>
        private void UpdateDataFolderDisplay()
        {
            var userDataFolder = _preferencesService.Preferences.UserDataFolder;
            UserDataFolderTextBox.Text = userDataFolder;
            
            DataFolderPathText.Text = $"Base: {userDataFolder}\n" +
                $"├── connections.json\n" +
                $"├── preferences.json\n" +
                $"├── query-history.json\n" +
                $"└── MissingFK/\n" +
                $"    ├── IgnorePatterns/\n" +
                $"    └── Projects/";
        }

        private void LoadCurrentSettings()
        {
            try
            {
                Logger.Debug("Loading current settings into dialog");
                var prefs = _preferencesService.Preferences;

                // Editor settings
                SetComboBoxValue(ThemeComboBox, prefs.DefaultTheme);
                SetComboBoxValue(FontFamilyComboBox, prefs.FontFamily);
                FontSizeSlider.Value = prefs.FontSize;
                FontSizeText.Text = prefs.FontSize.ToString();
                TabSizeSlider.Value = prefs.TabSize;
                TabSizeText.Text = prefs.TabSize.ToString();

                // Database settings
                MaxRowsTextBox.Text = prefs.MaxRowsPerQuery.ToString();
                CommandTimeoutTextBox.Text = prefs.CommandTimeout.ToString();
                HandleDecimalErrorsCheckBox.IsChecked = prefs.HandleDecimalErrorsGracefully;
                AutoRefreshObjectsCheckBox.IsChecked = prefs.AutoRefreshObjectsOnConnect;

                // Logging settings
                SetComboBoxValue(LogLevelComboBox, prefs.LogLevel);
                
                // Update current log level display
                if (CurrentLogLevelText != null)
                {
                    CurrentLogLevelText.Text = $"Current level: {LoggingService.GetCurrentLogLevel()}";
                }

                // Grid settings
                GridBackgroundColorTextBox.Text = prefs.GridBackgroundColor;
                GridForegroundColorTextBox.Text = prefs.GridForegroundColor;
                GridSelectedBackgroundColorTextBox.Text = prefs.GridSelectedBackgroundColor;
                GridSelectedForegroundColorTextBox.Text = prefs.GridSelectedForegroundColor;
                GridFontSizeSlider.Value = prefs.GridFontSize;
                GridFontSizeText.Text = prefs.GridFontSize.ToString();
                SetComboBoxValue(GridFontFamilyComboBox, prefs.GridFontFamily);
                GridCellHeightSlider.Value = prefs.GridCellHeight;
                GridCellHeightText.Text = prefs.GridCellHeight.ToString();
                
                // TreeView settings
                TreeViewSpacingSlider.Value = prefs.TreeViewItemSpacing;
                TreeViewSpacingText.Text = prefs.TreeViewItemSpacing.ToString();

                Logger.Info("Settings loaded successfully");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error loading settings");
                MessageBox.Show($"Error loading settings: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
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

        private bool IsValidHexColor(string color)
        {
            if (string.IsNullOrWhiteSpace(color))
                return false;

            var cleanHex = color.TrimStart('#');
            return cleanHex.Length == 6 && System.Text.RegularExpressions.Regex.IsMatch(cleanHex, "^[0-9A-Fa-f]{6}$");
        }

        private void FontSizeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (FontSizeText != null)
            {
                FontSizeText.Text = ((int)e.NewValue).ToString();
            }
        }

        private void TabSizeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (TabSizeText != null)
            {
                TabSizeText.Text = ((int)e.NewValue).ToString();
            }
        }

        private void GridFontSizeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (GridFontSizeText != null)
            {
                GridFontSizeText.Text = ((int)e.NewValue).ToString();
            }
        }

        private void GridCellHeightSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (GridCellHeightText != null)
            {
                GridCellHeightText.Text = ((int)e.NewValue).ToString();
            }
        }

        private void TreeViewSpacingSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (TreeViewSpacingText != null)
            {
                TreeViewSpacingText.Text = ((int)e.NewValue).ToString();
            }
        }

        private void GridBackgroundColorPickerButton_Click(object sender, RoutedEventArgs e)
        {
            ShowColorPicker(GridBackgroundColorTextBox);
        }

        private void GridForegroundColorPickerButton_Click(object sender, RoutedEventArgs e)
        {
            ShowColorPicker(GridForegroundColorTextBox);
        }

        private void GridSelectedBackgroundColorPickerButton_Click(object sender, RoutedEventArgs e)
        {
            ShowColorPicker(GridSelectedBackgroundColorTextBox);
        }

        private void GridSelectedForegroundColorPickerButton_Click(object sender, RoutedEventArgs e)
        {
            ShowColorPicker(GridSelectedForegroundColorTextBox);
        }

        private void ShowColorPicker(TextBox targetTextBox)
        {
            try
            {
                var colorDialog = new System.Windows.Forms.ColorDialog();
                
                // Try to parse current color from textbox
                var currentColor = targetTextBox.Text;
                if (!string.IsNullOrWhiteSpace(currentColor) && currentColor.StartsWith("#"))
                {
                    try
                    {
                        var cleanHex = currentColor.TrimStart('#');
                        if (cleanHex.Length == 6)
                        {
                            var r = Convert.ToByte(cleanHex.Substring(0, 2), 16);
                            var g = Convert.ToByte(cleanHex.Substring(2, 2), 16);
                            var b = Convert.ToByte(cleanHex.Substring(4, 2), 16);
                            colorDialog.Color = System.Drawing.Color.FromArgb(r, g, b);
                        }
                    }
                    catch
                    {
                        // Use default if parsing fails
                    }
                }

                if (colorDialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    var color = colorDialog.Color;
                    var hexColor = $"#{color.R:X2}{color.G:X2}{color.B:X2}";
                    targetTextBox.Text = hexColor;
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error showing color picker");
                MessageBox.Show($"Error opening color picker: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void OpenLogsButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Logger.Info("Opening logs folder");
                var logsFolder = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs");
                
                if (!Directory.Exists(logsFolder))
                {
                    Directory.CreateDirectory(logsFolder);
                    Logger.Info("Created logs folder: {Folder}", logsFolder);
                }

                Process.Start("explorer.exe", logsFolder);
                Logger.Info("Opened logs folder in Explorer");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error opening logs folder");
                MessageBox.Show($"Error opening logs folder: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void OpenDataFolderButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Logger.Info("Opening data folder");
                var dataFolder = _preferencesService.Preferences.UserDataFolder;
                
                if (!Directory.Exists(dataFolder))
                {
                    Directory.CreateDirectory(dataFolder);
                    Logger.Info("Created data folder: {Folder}", dataFolder);
                }

                Process.Start("explorer.exe", dataFolder);
                Logger.Info("Opened data folder in Explorer");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error opening data folder");
                MessageBox.Show($"Error opening data folder: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
        
        private void BrowseUserDataFolderButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Logger.Debug("Opening folder browser for user data folder");
                
                var dialog = new System.Windows.Forms.FolderBrowserDialog
                {
                    Description = "Select User Data Folder",
                    SelectedPath = _preferencesService.Preferences.UserDataFolder,
                    ShowNewFolderButton = true
                };
                
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    var newFolder = dialog.SelectedPath;
                    Logger.Info("User selected new data folder: {Path}", newFolder);
                    
                    // Validate the folder is writable
                    try
                    {
                        if (!Directory.Exists(newFolder))
                        {
                            Directory.CreateDirectory(newFolder);
                        }
                        
                        // Test write access
                        var testFile = Path.Combine(newFolder, ".write_test");
                        File.WriteAllText(testFile, "test");
                        File.Delete(testFile);
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, "Cannot write to selected folder");
                        MessageBox.Show(
                            $"Cannot write to the selected folder:\n{ex.Message}\n\nPlease choose a different location.",
                            "Invalid Folder",
                            MessageBoxButton.OK,
                            MessageBoxImage.Warning);
                        return;
                    }
                    
                    // Warn about existing files not being migrated
                    var oldFolder = _preferencesService.Preferences.UserDataFolder;
                    if (oldFolder != newFolder && Directory.Exists(oldFolder) && Directory.GetFiles(oldFolder).Length > 0)
                    {
                        var result = MessageBox.Show(
                            $"Existing files in:\n{oldFolder}\n\nwill NOT be automatically moved to:\n{newFolder}\n\n" +
                            "You will need to move them manually. Continue?",
                            "Confirm Folder Change",
                            MessageBoxButton.YesNo,
                            MessageBoxImage.Question);
                        
                        if (result != MessageBoxResult.Yes)
                        {
                            return;
                        }
                    }
                    
                    // Update UI
                    UserDataFolderTextBox.Text = newFolder;
                    UpdateDataFolderDisplay();
                    
                    Logger.Info("User data folder will be changed to: {Path}", newFolder);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error selecting user data folder");
                MessageBox.Show($"Error selecting folder: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void ResetToDefaults_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Logger.Info("Resetting settings to defaults");
                
                var result = MessageBox.Show(
                    "Are you sure you want to reset all settings to defaults?", 
                    "Confirm Reset", 
                    MessageBoxButton.YesNo, 
                    MessageBoxImage.Question);

                if (result == MessageBoxResult.Yes)
                {
                    var defaults = new UserPreferences();
                    
                    // Editor settings
                    SetComboBoxValue(ThemeComboBox, defaults.DefaultTheme);
                    SetComboBoxValue(FontFamilyComboBox, defaults.FontFamily);
                    FontSizeSlider.Value = defaults.FontSize;
                    TabSizeSlider.Value = defaults.TabSize;

                    // Database settings
                    MaxRowsTextBox.Text = defaults.MaxRowsPerQuery.ToString();
                    CommandTimeoutTextBox.Text = defaults.CommandTimeout.ToString();
                    HandleDecimalErrorsCheckBox.IsChecked = defaults.HandleDecimalErrorsGracefully;
                    AutoRefreshObjectsCheckBox.IsChecked = defaults.AutoRefreshObjectsOnConnect;

                    // Logging settings
                    SetComboBoxValue(LogLevelComboBox, defaults.LogLevel);

                    // Grid settings
                    GridBackgroundColorTextBox.Text = defaults.GridBackgroundColor;
                    GridForegroundColorTextBox.Text = defaults.GridForegroundColor;
                    GridSelectedBackgroundColorTextBox.Text = defaults.GridSelectedBackgroundColor;
                    GridSelectedForegroundColorTextBox.Text = defaults.GridSelectedForegroundColor;
                    GridFontSizeSlider.Value = defaults.GridFontSize;
                    GridCellHeightSlider.Value = defaults.GridCellHeight;
                    SetComboBoxValue(GridFontFamilyComboBox, defaults.GridFontFamily);
                    
                    // TreeView settings
                    TreeViewSpacingSlider.Value = defaults.TreeViewItemSpacing;

                    Logger.Info("Settings reset to defaults");
                    MessageBox.Show("Settings have been reset to defaults.", "Reset Complete", 
                        MessageBoxButton.OK, MessageBoxImage.Information);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error resetting settings");
                MessageBox.Show($"Error resetting settings: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Logger.Info("Saving settings");

                // Validate inputs
                if (!int.TryParse(MaxRowsTextBox.Text, out int maxRows) || maxRows < 1)
                {
                    MessageBox.Show("Max Rows Per Query must be a positive integer.", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    MaxRowsTextBox.Focus();
                    return;
                }

                if (!int.TryParse(CommandTimeoutTextBox.Text, out int commandTimeout) || commandTimeout < 0)
                {
                    MessageBox.Show("Command Timeout must be a non-negative integer.", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    CommandTimeoutTextBox.Focus();
                    return;
                }

                // Validate grid color inputs
                if (!IsValidHexColor(GridBackgroundColorTextBox.Text))
                {
                    MessageBox.Show("Grid Background Color must be a valid hex color (e.g., #FFFFFF).", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    GridBackgroundColorTextBox.Focus();
                    return;
                }

                if (!IsValidHexColor(GridForegroundColorTextBox.Text))
                {
                    MessageBox.Show("Grid Foreground Color must be a valid hex color (e.g., #000000).", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    GridForegroundColorTextBox.Focus();
                    return;
                }

                if (!IsValidHexColor(GridSelectedBackgroundColorTextBox.Text))
                {
                    MessageBox.Show("Grid Selected Background Color must be a valid hex color (e.g., #0078D4).", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    GridSelectedBackgroundColorTextBox.Focus();
                    return;
                }

                if (!IsValidHexColor(GridSelectedForegroundColorTextBox.Text))
                {
                    MessageBox.Show("Grid Selected Foreground Color must be a valid hex color (e.g., #FFFFFF).", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    GridSelectedForegroundColorTextBox.Focus();
                    return;
                }

                // Validate grid cell height
                if (GridCellHeightSlider.Value < 20 || GridCellHeightSlider.Value > 50)
                {
                    MessageBox.Show("Grid Cell Height must be between 20 and 50 pixels.", "Invalid Input", 
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                // Update preferences
                _preferencesService.Preferences.DefaultTheme = GetComboBoxValue(ThemeComboBox);
                _preferencesService.Preferences.FontFamily = GetComboBoxValue(FontFamilyComboBox);
                _preferencesService.Preferences.FontSize = (int)FontSizeSlider.Value;
                _preferencesService.Preferences.TabSize = (int)TabSizeSlider.Value;
                _preferencesService.Preferences.MaxRowsPerQuery = maxRows;
                _preferencesService.Preferences.CommandTimeout = commandTimeout;
                _preferencesService.Preferences.HandleDecimalErrorsGracefully = HandleDecimalErrorsCheckBox.IsChecked ?? true;
                _preferencesService.Preferences.AutoRefreshObjectsOnConnect = AutoRefreshObjectsCheckBox.IsChecked ?? true;
                _preferencesService.Preferences.LogLevel = GetComboBoxValue(LogLevelComboBox);

                // Grid settings
                _preferencesService.Preferences.GridBackgroundColor = GridBackgroundColorTextBox.Text;
                _preferencesService.Preferences.GridForegroundColor = GridForegroundColorTextBox.Text;
                _preferencesService.Preferences.GridSelectedBackgroundColor = GridSelectedBackgroundColorTextBox.Text;
                _preferencesService.Preferences.GridSelectedForegroundColor = GridSelectedForegroundColorTextBox.Text;
                _preferencesService.Preferences.GridFontSize = (int)GridFontSizeSlider.Value;
                _preferencesService.Preferences.GridFontFamily = GetComboBoxValue(GridFontFamilyComboBox);
                _preferencesService.Preferences.GridCellHeight = (int)GridCellHeightSlider.Value;
                
                // TreeView settings
                _preferencesService.Preferences.TreeViewItemSpacing = (int)TreeViewSpacingSlider.Value;
                
                // User Data Folder - check if changed and update appropriately
                var newUserDataFolder = UserDataFolderTextBox.Text;
                var currentUserDataFolder = _preferencesService.Preferences.UserDataFolder;
                
                if (!string.Equals(newUserDataFolder, currentUserDataFolder, StringComparison.OrdinalIgnoreCase))
                {
                    Logger.Info("User data folder changed from {Old} to {New}", currentUserDataFolder, newUserDataFolder);
                    
                    // Use the special update method that handles the path change
                    _preferencesService.UpdateUserDataFolder(newUserDataFolder);
                    
                    // Clear the cache so other services pick up the new location
                    UserDataFolderHelper.ClearCache();
                    
                    MessageBox.Show(
                        "User data folder has been changed.\n\n" +
                        "Note: Existing files were NOT moved. You may need to manually copy your files " +
                        "(connections.json, query-history.json, etc.) to the new location.",
                        "Folder Changed",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                }
                else
                {
                    // Save to file (normal save when folder hasn't changed)
                    _preferencesService.SavePreferences();
                }

                // Apply log level change immediately (no restart required)
                var newLogLevel = GetComboBoxValue(LogLevelComboBox);
                LoggingService.SetLogLevel(newLogLevel);
                Logger.Debug("Log level applied immediately: {Level}", newLogLevel);

                // Refresh all existing UI with new preferences
                UIStyleService.RefreshAllStyles();

                Logger.Info("Settings saved successfully");
                DialogResult = true;
                Close();
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error saving settings");
                MessageBox.Show($"Error saving settings: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            Logger.Debug("Settings dialog cancelled");
            DialogResult = false;
            Close();
        }
        
        private async void TestAiConnection_Click(object sender, RoutedEventArgs e)
        {
            Logger.Info("Testing AI connection");
            
            try
            {
                TestAiConnectionButton.IsEnabled = false;
                TestAiConnectionButton.Content = "⏳ Testing...";
                
                var provider = GetComboBoxValue(AiProviderComboBox);
                var endpoint = OllamaEndpointTextBox.Text;
                var model = AiModelNameTextBox.Text;
                
                Logger.Debug("Testing AI provider: {Provider}, Endpoint: {Endpoint}, Model: {Model}", provider, endpoint, model);
                
                // Simple test - try to connect to Ollama endpoint
                if (provider == "ollama")
                {
                    using var client = new System.Net.Http.HttpClient();
                    client.Timeout = TimeSpan.FromSeconds(10);
                    
                    var response = await client.GetAsync($"{endpoint}/api/tags");
                    if (response.IsSuccessStatusCode)
                    {
                        var json = await response.Content.ReadAsStringAsync();
                        Logger.Info("Ollama connection successful, response: {Response}", json.Substring(0, Math.Min(200, json.Length)));
                        MessageBox.Show($"✅ Connection successful!\n\nProvider: {provider}\nEndpoint: {endpoint}\nModel: {model}", 
                            "AI Connection Test", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                    else
                    {
                        MessageBox.Show($"❌ Connection failed.\n\nHTTP Status: {response.StatusCode}\n\nMake sure Ollama is running.", 
                            "AI Connection Test", MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                }
                else
                {
                    // For cloud providers, just verify API key is set
                    if (string.IsNullOrWhiteSpace(AiApiKeyPasswordBox.Password))
                    {
                        MessageBox.Show($"⚠️ API key required for {provider}.\n\nPlease enter your API key.", 
                            "AI Connection Test", MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                    else
                    {
                        MessageBox.Show($"✅ API key is configured for {provider}.\n\nActual connection test requires AI provider implementation.", 
                            "AI Connection Test", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "AI connection test failed");
                MessageBox.Show($"❌ Connection failed: {ex.Message}", "AI Connection Test", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                TestAiConnectionButton.IsEnabled = true;
                TestAiConnectionButton.Content = "🧪 Test AI Connection";
            }
        }
        
        private void AiProvider_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            // Guard against event firing during XAML initialization
            if (AutoDetectOllamaButton == null || OllamaStatusBorder == null || AvailableModelsExpander == null)
                return;
            
            var provider = GetComboBoxValue(AiProviderComboBox);
            
            // Show/hide auto-detect button based on provider
            AutoDetectOllamaButton.Visibility = provider == "ollama" ? Visibility.Visible : Visibility.Collapsed;
            
            // Reset status when provider changes
            OllamaStatusBorder.Visibility = Visibility.Collapsed;
            AvailableModelsExpander.Visibility = Visibility.Collapsed;
            
            Logger.Debug("AI provider changed to: {Provider}", provider);
        }
        
        private async void AutoDetectOllama_Click(object sender, RoutedEventArgs e)
        {
            Logger.Info("Auto-detecting Ollama configuration");
            
            try
            {
                AutoDetectOllamaButton.IsEnabled = false;
                AutoDetectOllamaButton.Content = "⏳ Detecting...";
                
                var ollamaService = new OllamaDetectionService();
                var config = await ollamaService.GetFullConfigurationAsync();
                
                // Update endpoint
                OllamaEndpointTextBox.Text = config.Endpoint;
                
                // Show status
                OllamaStatusBorder.Visibility = Visibility.Visible;
                
                if (config.IsRunning)
                {
                    OllamaStatusBorder.Background = new System.Windows.Media.SolidColorBrush(
                        System.Windows.Media.Color.FromRgb(30, 58, 30)); // Dark green
                    OllamaStatusText.Text = "✅ Ollama is running";
                    OllamaStatusDetails.Text = $"Endpoint: {config.Endpoint}\n" +
                                               $"Models path: {config.ModelsPath}\n" +
                                               $"Available models: {config.AvailableModels.Count}";
                }
                else
                {
                    OllamaStatusBorder.Background = new System.Windows.Media.SolidColorBrush(
                        System.Windows.Media.Color.FromRgb(58, 45, 30)); // Dark orange
                    OllamaStatusText.Text = "⚠️ Ollama not running";
                    OllamaStatusDetails.Text = $"Expected endpoint: {config.Endpoint}\n" +
                                               $"Models path: {config.ModelsPath}\n" +
                                               $"Cached models found: {config.AvailableModels.Count}";
                }
                
                // Populate available models
                if (config.AvailableModels.Count > 0)
                {
                    AvailableModelsExpander.Header = $"Available Models ({config.AvailableModels.Count})";
                    AvailableModelsExpander.Visibility = Visibility.Visible;
                    
                    AvailableModelsList.Items.Clear();
                    foreach (var model in config.AvailableModels)
                    {
                        var displayText = $"{model.FullName}";
                        if (model.SizeBytes > 0)
                        {
                            displayText += $" ({model.SizeFormatted})";
                        }
                        AvailableModelsList.Items.Add(new System.Windows.Controls.ListBoxItem 
                        { 
                            Content = displayText,
                            Tag = model.FullName
                        });
                    }
                    
                    // Auto-select first model if no model is set
                    if (string.IsNullOrWhiteSpace(AiModelNameTextBox.Text) || AiModelNameTextBox.Text == "llama3.2")
                    {
                        var firstModel = config.AvailableModels.FirstOrDefault();
                        if (firstModel != null)
                        {
                            AiModelNameTextBox.Text = firstModel.FullName;
                        }
                    }
                }
                else
                {
                    AvailableModelsExpander.Visibility = Visibility.Collapsed;
                }
                
                Logger.Info("Ollama auto-detection complete: Running={Running}, Models={Count}", 
                    config.IsRunning, config.AvailableModels.Count);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Ollama auto-detection failed");
                MessageBox.Show($"Auto-detection failed: {ex.Message}", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                AutoDetectOllamaButton.IsEnabled = true;
                AutoDetectOllamaButton.Content = "🔍 Auto-Detect";
            }
        }
        
        private async void RefreshModels_Click(object sender, RoutedEventArgs e)
        {
            // Trigger auto-detect to refresh models
            await Task.Run(() => { });
            AutoDetectOllama_Click(sender, e);
        }
        
        private void AvailableModelsList_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            if (AvailableModelsList.SelectedItem is System.Windows.Controls.ListBoxItem item && item.Tag is string modelName)
            {
                AiModelNameTextBox.Text = modelName;
                Logger.Debug("Selected model: {Model}", modelName);
            }
        }
    }
}
