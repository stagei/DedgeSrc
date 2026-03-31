using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

/// <summary>
/// Dialog for editing ignore rules for Missing FK Discovery.
/// Provides a dedicated window with more space for editing patterns and columns.
/// </summary>
public partial class MissingFKIgnoreRulesDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly MissingFKIgnoreHistoryService _ignoreHistoryService;
    private MissingFKIgnoreModel _ignoreModel;
    private ObservableCollection<MissingFKIgnoreColumn> _ignoreColumnsCollection;
    
    public MissingFKIgnoreModel IgnoreModel => _ignoreModel;
    
    public MissingFKIgnoreRulesDialog(MissingFKIgnoreModel? initialModel = null)
    {
        InitializeComponent();
        
        _ignoreHistoryService = new MissingFKIgnoreHistoryService();
        _ignoreModel = initialModel ?? new MissingFKIgnoreModel();
        _ignoreColumnsCollection = new ObservableCollection<MissingFKIgnoreColumn>();
        
        // Initialize UI
        IgnoreColumnsGrid.ItemsSource = _ignoreColumnsCollection;
        UpdateUIFromModel();
        
        Loaded += MissingFKIgnoreRulesDialog_Loaded;
        Closing += MissingFKIgnoreRulesDialog_Closing;
    }
    
    private async void MissingFKIgnoreRulesDialog_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await LoadIgnoreHistoryAsync();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load ignore history");
        }
    }
    
    private void MissingFKIgnoreRulesDialog_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        // Auto-save current configuration when closing
        try
        {
            SaveCurrentConfiguration();
            Logger.Debug("Auto-saved ignore configuration on dialog close");
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to auto-save ignore configuration");
        }
    }
    
    private void UpdateUIFromModel()
    {
        _ignoreColumnsCollection.Clear();
        foreach (var col in _ignoreModel.IgnoreColumns)
        {
            _ignoreColumnsCollection.Add(col);
        }
        
        IgnorePatternsTextBox.Text = string.Join(Environment.NewLine, _ignoreModel.IgnoreColumnPatterns);
        IgnoreDataTypesTextBox.Text = string.Join(", ", _ignoreModel.IgnoreDataTypes);
        
        UpdateStatusText();
    }
    
    private void UpdateStatusText()
    {
        var columnCount = _ignoreColumnsCollection.Count;
        var patternCount = IgnorePatternsTextBox.Text
            .Split(new[] { Environment.NewLine, "\n", "\r" }, StringSplitOptions.RemoveEmptyEntries)
            .Count(p => !string.IsNullOrWhiteSpace(p));
        var dataTypeCount = IgnoreDataTypesTextBox.Text
            .Split(',')
            .Count(d => !string.IsNullOrWhiteSpace(d));
        
        StatusText.Text = $"Current configuration: {columnCount} column(s), {patternCount} pattern(s), {dataTypeCount} data type(s)";
    }
    
    private void SaveCurrentConfiguration()
    {
        _ignoreModel.IgnoreColumns = _ignoreColumnsCollection.ToList();
        _ignoreModel.IgnoreColumnPatterns = IgnorePatternsTextBox.Text
            .Split(new[] { Environment.NewLine, "\n", "\r" }, StringSplitOptions.RemoveEmptyEntries)
            .Select(p => p.Trim())
            .Where(p => !string.IsNullOrEmpty(p))
            .ToList();
        _ignoreModel.IgnoreDataTypes = IgnoreDataTypesTextBox.Text
            .Split(',')
            .Select(d => d.Trim())
            .Where(d => !string.IsNullOrEmpty(d))
            .ToList();
    }
    
    private async Task LoadIgnoreHistoryAsync()
    {
        try
        {
            var history = _ignoreHistoryService.GetHistory();
            var historyItems = history.Select(item =>
            {
                var config = _ignoreHistoryService.LoadIgnoreConfig(item.Name);
                var preview = string.Empty;
                
                if (config != null)
                {
                    var parts = new List<string>();
                    if (config.IgnoreColumns.Count > 0)
                        parts.Add($"{config.IgnoreColumns.Count} columns");
                    if (config.IgnoreColumnPatterns.Count > 0)
                        parts.Add($"{config.IgnoreColumnPatterns.Count} patterns");
                    if (config.IgnoreDataTypes.Count > 0)
                        parts.Add($"{config.IgnoreDataTypes.Count} data types");
                    
                    preview = parts.Count > 0 ? string.Join(", ", parts) : "Empty configuration";
                }
                
                return new
                {
                    Name = item.Name,
                    SavedAt = item.SavedAt,
                    Preview = preview
                };
            }).ToList();
            
            IgnoreHistoryComboBox.ItemsSource = historyItems;
            Logger.Debug("Loaded {Count} ignore configurations from history", history.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load ignore history");
        }
    }
    
    private void IgnoreHistoryComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (IgnoreHistoryComboBox.SelectedItem == null) return;
        
        try
        {
            var selectedItem = (dynamic)IgnoreHistoryComboBox.SelectedItem;
            var ignoreModel = _ignoreHistoryService.LoadIgnoreConfig(selectedItem.Name);
            
            if (ignoreModel != null)
            {
                _ignoreModel = ignoreModel;
                UpdateUIFromModel();
                Logger.Info("Loaded ignore configuration from history: {Name}", selectedItem.Name);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load ignore configuration from history");
            MessageBox.Show($"Failed to load ignore configuration:\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    
    private async void SaveIgnoreConfig_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveCurrentConfiguration();
            
            // Prompt for name
            var inputDialog = new Window
            {
                Title = "Save Ignore Configuration",
                Width = 400,
                Height = 150,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = this
            };
            
            var textBox = new TextBox
            {
                Text = $"Ignore_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}",
                Margin = new Thickness(10),
                VerticalContentAlignment = VerticalAlignment.Center
            };
            
            var okButton = new Button
            {
                Content = "OK",
                Width = 75,
                Height = 25,
                Margin = new Thickness(5),
                IsDefault = true
            };
            
            var cancelButton = new Button
            {
                Content = "Cancel",
                Width = 75,
                Height = 25,
                Margin = new Thickness(5),
                IsCancel = true
            };
            
            okButton.Click += (s, args) =>
            {
                inputDialog.DialogResult = true;
                inputDialog.Close();
            };
            
            var stackPanel = new StackPanel
            {
                Orientation = Orientation.Vertical,
                Margin = new Thickness(15)
            };
            
            stackPanel.Children.Add(new TextBlock
            {
                Text = "Configuration name:",
                Margin = new Thickness(0,0,0,5)
            });
            stackPanel.Children.Add(textBox);
            
            var buttonPanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(0,15,0,0)
            };
            buttonPanel.Children.Add(okButton);
            buttonPanel.Children.Add(cancelButton);
            stackPanel.Children.Add(buttonPanel);
            
            inputDialog.Content = stackPanel;
            textBox.Focus();
            textBox.SelectAll();
            
            if (inputDialog.ShowDialog() == true && !string.IsNullOrWhiteSpace(textBox.Text))
            {
                var name = textBox.Text.Trim();
                _ignoreHistoryService.SaveIgnoreConfig(_ignoreModel, name);
                await LoadIgnoreHistoryAsync();
                await LoadIgnoreHistoryAsync();
                
                MessageBox.Show($"Ignore configuration saved: {name}", "Success",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                
                UpdateStatusText();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save ignore configuration");
            MessageBox.Show($"Failed to save ignore configuration:\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void OK_Click(object sender, RoutedEventArgs e)
    {
        SaveCurrentConfiguration();
        DialogResult = true;
        Close();
    }
    
    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
    
    private void IgnorePatternsTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdateStatusText();
    }
    
    private void IgnoreDataTypesTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdateStatusText();
    }
}
