using System;
using System.Linq;
using System.Windows;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ConnectionDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly ConnectionStorageService _storageService;
    public DatabaseConnection? Connection { get; private set; }

    public ConnectionDialog()
    {
        InitializeComponent();
        _storageService = new ConnectionStorageService();
        Logger.Debug("ConnectionDialog opened");
        
        // Load providers from MetadataHandler
        LoadProviders();
    }
    
    private void LoadProviders()
    {
        if (App.MetadataHandler != null)
        {
            var providers = App.MetadataHandler.GetSupportedProviders();
            ProviderComboBox.ItemsSource = providers;
            // Model property is DisplayName (from supported_providers.json "display_name")
            ProviderComboBox.DisplayMemberPath = "DisplayName";
            ProviderComboBox.SelectedValuePath = "ProviderCode";
            
            if (providers.Count > 0)
            {
                ProviderComboBox.SelectedIndex = 0; // Select DB2 by default
            }
        }
    }
    
    private void ProviderComboBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (ProviderComboBox.SelectedItem is Models.Provider provider)
        {
            // Update version dropdown
            VersionComboBox.ItemsSource = provider.SupportedVersions;
            
            if (provider.SupportedVersions.Count > 0)
            {
                // Select numerically highest version (e.g. 12.1 > 11.5)
                var best = provider.SupportedVersions
                    .OrderByDescending(v => v, StringComparer.OrdinalIgnoreCase) // stable fallback
                    .OrderByDescending(v => ParseVersionForSort(v))
                    .FirstOrDefault();

                VersionComboBox.SelectedItem = best ?? provider.SupportedVersions[0];
            }
            
            // Update default port
            PortTextBox.Text = provider.DefaultPort.ToString();
        }
    }

    private static Version ParseVersionForSort(string versionText)
    {
        // Normalize "12.1" -> Version(12,1), "11" -> Version(11,0)
        // If it's not a numeric dotted version (e.g. "19c"), return 0.0 so it sorts last.
        if (string.IsNullOrWhiteSpace(versionText))
        {
            return new Version(0, 0);
        }

        // Keep only digits and dots; stop at first non [0-9.]
        var cleaned = new string(versionText
            .TakeWhile(c => char.IsDigit(c) || c == '.')
            .ToArray());

        if (string.IsNullOrWhiteSpace(cleaned))
        {
            return new Version(0, 0);
        }

        // Ensure at least major.minor
        if (!cleaned.Contains('.'))
        {
            cleaned = $"{cleaned}.0";
        }

        // System.Version supports up to 4 components; trim extra parts if present.
        var parts = cleaned.Split('.', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length > 4)
        {
            cleaned = string.Join('.', parts.Take(4));
        }

        return Version.TryParse(cleaned, out var v) ? v : new Version(0, 0);
    }
    
    /// <summary>
    /// Constructor for editing existing connection
    /// </summary>
    public ConnectionDialog(DatabaseConnection connection) : this()
    {
        LoadConnection(connection);
    }
    
    /// <summary>
    /// Load an existing connection into the dialog fields
    /// </summary>
    public void LoadConnection(DatabaseConnection connection)
    {
        Logger.Debug("Loading connection into dialog: {Name}", connection.Name);
        
        NameTextBox.Text = connection.Name;
        ServerTextBox.Text = connection.Server;
        PortTextBox.Text = connection.Port.ToString();
        DatabaseTextBox.Text = connection.Database;
        UsernameTextBox.Text = connection.Username;
        PasswordBox.Password = connection.Password;
        ReadOnlyCheckBox.IsChecked = connection.IsReadOnly;
        AutoCommitCheckBox.IsChecked = connection.AutoCommit;
        
        // Set provider selection if available
        if (App.MetadataHandler != null && !string.IsNullOrEmpty(connection.ProviderType))
        {
            var providers = App.MetadataHandler.GetSupportedProviders();
            var matchingProvider = providers.FirstOrDefault(p => 
                p.ProviderCode.Equals(connection.ProviderType, StringComparison.OrdinalIgnoreCase));
            if (matchingProvider != null)
            {
                ProviderComboBox.SelectedItem = matchingProvider;
            }
        }
    }

    private async void TestConnection_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Testing connection");

        var connection = GetConnectionFromInputs();
        if (connection == null || !connection.IsValid())
        {
            Logger.Warn("Invalid connection information");
            MessageBox.Show("Please fill in all required fields.", "Validation Error", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            // Create connection manager based on provider type
            using var manager = ConnectionManagerFactory.CreateConnectionManager(connection);
            var success = await manager.TestConnectionAsync();

            if (success)
            {
                Logger.Info("Connection test successful");
                MessageBox.Show("Connection successful!", "Test Connection",
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                Logger.Warn("Connection test failed");
                MessageBox.Show("Connection failed. Please check your credentials.", "Test Connection",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Connection test error");
            MessageBox.Show($"Connection error: {ex.Message}", "Test Connection",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Connect button clicked");

        var connection = GetConnectionFromInputs();
        if (connection == null || !connection.IsValid())
        {
            Logger.Warn("Invalid connection information");
            MessageBox.Show("Please fill in all required fields.", "Validation Error",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        // Save connection to storage with encrypted password
        try
        {
            _storageService.SaveConnection(connection);
            Logger.Info("Connection saved to storage: {Name}", connection.Name);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save connection");
            // Continue anyway - don't block connection if save fails
        }

        Connection = connection;
        Logger.Info($"Connection created: {connection.GetDisplayName()}");
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("Connection dialog cancelled");
        DialogResult = false;
        Close();
    }

    private DatabaseConnection? GetConnectionFromInputs()
    {
        if (!int.TryParse(PortTextBox.Text, out var port))
        {
            // Get default port for selected provider
            var selectedProvider = ProviderComboBox.SelectedItem as Models.Provider;
            port = selectedProvider?.DefaultPort ?? DatabaseConnection.GetDefaultPort("db2");
        }

        // Get provider type from selected provider
        var providerType = (ProviderComboBox.SelectedItem as Models.Provider)?.ProviderCode?.ToLowerInvariant() ?? "db2";

        return new DatabaseConnection
        {
            Name = NameTextBox.Text.Trim(),
            Server = ServerTextBox.Text.Trim(),
            Port = port,
            Database = DatabaseTextBox.Text.Trim(),
            Username = UsernameTextBox.Text.Trim(),
            Password = PasswordBox.Password,
            SavePassword = !string.IsNullOrEmpty(PasswordBox.Password),
            IsReadOnly = ReadOnlyCheckBox.IsChecked ?? false,  // Feature #2
            AutoCommit = AutoCommitCheckBox.IsChecked ?? true,  // Feature #2
            ProviderType = providerType
        };
    }
    
    /// <summary>
    /// Validates that port input is numeric only
    /// </summary>
    private void NumericOnly_PreviewTextInput(object sender, System.Windows.Input.TextCompositionEventArgs e)
    {
        // Only allow digits
        e.Handled = !IsNumeric(e.Text);
    }
    
    /// <summary>
    /// Checks if text contains only numeric characters
    /// </summary>
    private bool IsNumeric(string text)
    {
        return int.TryParse(text, out _);
    }
}

