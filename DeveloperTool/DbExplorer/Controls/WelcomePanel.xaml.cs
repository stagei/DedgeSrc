using System;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NLog;
using DbExplorer.Data;
using DbExplorer.Dialogs;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class WelcomePanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly ConnectionStorageService _storageService;
    private readonly ConnectionHistoryService _historyService;
    
    // Event to notify parent window of connection requests
    public event EventHandler<DatabaseConnection>? ConnectionRequested;
    public event EventHandler? NewConnectionRequested;
    public event EventHandler? ManageConnectionsRequested;
    
    public WelcomePanel()
    {
        InitializeComponent();
        
        _storageService = new ConnectionStorageService();
        _historyService = new ConnectionHistoryService();
        
        Loaded += WelcomePanel_Loaded;
    }
    
    private void WelcomePanel_Loaded(object sender, RoutedEventArgs e)
    {
        var version = Assembly.GetEntryAssembly()?.GetName().Version;
        var versionStr = version != null ? $"{version.Major}.{version.Minor}.{version.Build}" : "1.0.0";
        VersionText.Text = $"Version {versionStr} - .NET {Environment.Version.Major}";
        
        LoadRecentConnections();
    }
    
    public void LoadRecentConnections()
    {
        try
        {
            Logger.Debug("Loading recent connections");
            
            var recentHistories = _historyService.GetRecentConnections(10);
            
            // Match history with actual saved connections
            var recentConnections = recentHistories
                .Select(history =>
                {
                    // Get full connection with decrypted password
                    var connection = _storageService.GetConnection(history.ProfileName);
                    if (connection != null)
                    {
                        return new RecentConnectionViewModel
                        {
                            Connection = connection,
                            History = history,
                            ProfileName = history.ProfileName,
                            ProviderName = connection.ProviderType ?? "DB2",
                            LastUsedDisplay = history.LastUsedDisplay,
                            LastUsedRelative = history.LastUsedRelative,
                            UseCount = history.UseCount
                        };
                    }
                    return null;
                })
                .Where(vm => vm != null)
                .ToList();
            
            RecentConnectionsList.ItemsSource = recentConnections;
            
            NoConnectionsText.Visibility = recentConnections.Count == 0 
                ? Visibility.Visible 
                : Visibility.Collapsed;
            
            Logger.Info("Loaded {Count} recent connections", recentConnections.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load recent connections");
        }
    }
    
    private void NewConnection_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("New connection button clicked");
        NewConnectionRequested?.Invoke(this, EventArgs.Empty);
    }
    
    private void ManageConnections_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Manage connections button clicked");
        ManageConnectionsRequested?.Invoke(this, EventArgs.Empty);
    }
    
    private void RecentConnection_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Connecting to recent connection: {ProfileName}", vm.ProfileName);
            ConnectionRequested?.Invoke(this, vm.Connection);
        }
    }
    
    private void RecentConnection_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem == null)
        {
            e.Handled = true; // Prevent context menu if no item selected
        }
    }
    
    private void ContextConnect_Click(object sender, RoutedEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Context menu: Connect to {ProfileName}", vm.ProfileName);
            ConnectionRequested?.Invoke(this, vm.Connection);
        }
    }
    
    private void ContextEdit_Click(object sender, RoutedEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Context menu: Edit {ProfileName}", vm.ProfileName);
            
            var dialog = new ConnectionDialog();
            dialog.LoadConnection(vm.Connection);
            
            if (dialog.ShowDialog() == true && dialog.Connection != null)
            {
                // Update the connection - delete old, save new
                if (vm.Connection.Name != dialog.Connection.Name)
                {
                    // Name changed, delete old profile
                    _storageService.DeleteConnection(vm.Connection.Name);
                }
                
                _storageService.SaveConnection(dialog.Connection);
                
                LoadRecentConnections(); // Refresh list
                
                MessageBox.Show(
                    $"Connection '{dialog.Connection.Name}' updated successfully.",
                    "Connection Updated",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
    }
    
    private void ContextCopy_Click(object sender, RoutedEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Context menu: Duplicate {ProfileName}", vm.ProfileName);
            
            var dialog = new ConnectionDialog();
            
            // Create a copy with modified name
            var copy = new DatabaseConnection
            {
                Name = $"{vm.Connection.Name} (Copy)",
                Server = vm.Connection.Server,
                Port = vm.Connection.Port,
                Database = vm.Connection.Database,
                Username = vm.Connection.Username,
                Password = vm.Connection.Password,
                SavePassword = vm.Connection.SavePassword,
                IsReadOnly = vm.Connection.IsReadOnly,
                AutoCommit = vm.Connection.AutoCommit
            };
            
            dialog.LoadConnection(copy);
            
            if (dialog.ShowDialog() == true && dialog.Connection != null)
            {
                _storageService.SaveConnection(dialog.Connection);
                
                LoadRecentConnections(); // Refresh list
                
                MessageBox.Show(
                    $"Connection '{dialog.Connection.Name}' created successfully.",
                    "Connection Duplicated",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
    }
    
    private async void ContextTest_Click(object sender, RoutedEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Context menu: Test connection {ProfileName}", vm.ProfileName);
            
            try
            {
                var connectionManager = ConnectionManagerFactory.CreateConnectionManager(vm.Connection);
                
                // Show progress
                var progressWindow = new Window
                {
                    Title = "Testing Connection",
                    Width = 300,
                    Height = 100,
                    WindowStartupLocation = WindowStartupLocation.CenterScreen,
                    ResizeMode = ResizeMode.NoResize,
                    Content = new StackPanel
                    {
                        VerticalAlignment = VerticalAlignment.Center,
                        Children =
                        {
                            new TextBlock
                            {
                                Text = "Testing connection...",
                                HorizontalAlignment = HorizontalAlignment.Center,
                                Margin = new Thickness(10)
                            },
                            new ProgressBar
                            {
                                IsIndeterminate = true,
                                Width = 250,
                                Height = 20,
                                Margin = new Thickness(10)
                            }
                        }
                    }
                };
                
                progressWindow.Show();
                
                var result = await connectionManager.TestConnectionAsync();
                
                progressWindow.Close();
                
                if (result)
                {
                    MessageBox.Show(
                        $"✅ Connection to '{vm.ProfileName}' successful!",
                        "Connection Test",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                }
                else
                {
                    MessageBox.Show(
                        $"❌ Connection to '{vm.ProfileName}' failed.",
                        "Connection Test",
                        MessageBoxButton.OK,
                        MessageBoxImage.Error);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Connection test failed for {ProfileName}", vm.ProfileName);
                
                MessageBox.Show(
                    $"❌ Connection test failed:\n\n{ex.Message}",
                    "Connection Test Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }
    }
    
    private void ContextRemoveHistory_Click(object sender, RoutedEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Context menu: Remove from history {ProfileName}", vm.ProfileName);
            
            var result = MessageBox.Show(
                $"Remove '{vm.ProfileName}' from recent connections history?\n\n" +
                "The connection profile will not be deleted.",
                "Remove from History",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);
            
            if (result == MessageBoxResult.Yes)
            {
                _historyService.RemoveConnection(vm.ProfileName);
                LoadRecentConnections(); // Refresh list
            }
        }
    }
    
    private void ContextDelete_Click(object sender, RoutedEventArgs e)
    {
        if (RecentConnectionsList.SelectedItem is RecentConnectionViewModel vm)
        {
            Logger.Info("Context menu: Delete connection {ProfileName}", vm.ProfileName);
            
            var result = MessageBox.Show(
                $"Permanently delete connection '{vm.ProfileName}'?\n\n" +
                "This action cannot be undone.",
                "Delete Connection",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            
            if (result == MessageBoxResult.Yes)
            {
                _storageService.DeleteConnection(vm.ProfileName);
                _historyService.RemoveConnection(vm.ProfileName);
                
                LoadRecentConnections(); // Refresh list
                
                MessageBox.Show(
                    $"Connection '{vm.ProfileName}' deleted successfully.",
                    "Connection Deleted",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
    }
}

/// <summary>
/// ViewModel for recent connection display
/// </summary>
public class RecentConnectionViewModel
{
    public DatabaseConnection Connection { get; set; } = new();
    public ConnectionHistoryEntry History { get; set; } = new();
    public string ProfileName { get; set; } = string.Empty;
    public string ProviderName { get; set; } = string.Empty;
    public string LastUsedDisplay { get; set; } = string.Empty;
    public string LastUsedRelative { get; set; } = string.Empty;
    public int UseCount { get; set; }
}

