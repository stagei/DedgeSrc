using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NLog;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ConnectionManagerDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly ConnectionStorageService _storageService;

    public SavedConnection? SelectedConnection { get; private set; }
    public DatabaseConnection? ConnectionToOpen { get; private set; }

    public ConnectionManagerDialog(ConnectionStorageService storageService)
    {
        InitializeComponent();
        _storageService = storageService;
        
        UIStyleService.ApplyStyles(this);
        RefreshList();
    }

    private void RefreshList()
    {
        var connections = _storageService.LoadConnections();
        ConnectionsGrid.ItemsSource = connections;

        if (connections.Count > 0)
            ConnectionsGrid.SelectedIndex = 0;
    }

    private SavedConnection? GetSelected()
    {
        return ConnectionsGrid.SelectedItem as SavedConnection;
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ConnectionDialog { Owner = this };
        if (dialog.ShowDialog() == true && dialog.Connection != null)
        {
            _storageService.SaveConnection(dialog.Connection);
            RefreshList();
        }
    }

    private void Edit_Click(object sender, RoutedEventArgs e)
    {
        var selected = GetSelected();
        if (selected == null) return;

        try
        {
            var decryptedPassword = _storageService.DecryptPassword(selected.EncryptedPassword);
            var dbConn = selected.ToDatabaseConnection(decryptedPassword);

            var dialog = new ConnectionDialog { Owner = this };
            dialog.LoadConnection(dbConn);

            if (dialog.ShowDialog() == true && dialog.Connection != null)
            {
                if (!selected.Name.Equals(dialog.Connection.Name, StringComparison.OrdinalIgnoreCase))
                    _storageService.DeleteConnection(selected.Name);

                _storageService.SaveConnection(dialog.Connection);
                RefreshList();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to edit connection {Name}", selected.Name);
            MessageBox.Show($"Failed to decrypt connection:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Duplicate_Click(object sender, RoutedEventArgs e)
    {
        var selected = GetSelected();
        if (selected == null) return;

        try
        {
            var decryptedPassword = _storageService.DecryptPassword(selected.EncryptedPassword);
            var copy = selected.ToDatabaseConnection(decryptedPassword);
            copy.Name = $"{selected.Name} (Copy)";

            var dialog = new ConnectionDialog { Owner = this };
            dialog.LoadConnection(copy);

            if (dialog.ShowDialog() == true && dialog.Connection != null)
            {
                _storageService.SaveConnection(dialog.Connection);
                RefreshList();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to duplicate connection {Name}", selected.Name);
            MessageBox.Show($"Failed to duplicate connection:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        var selected = GetSelected();
        if (selected == null) return;

        var result = MessageBox.Show(
            $"Permanently delete connection '{selected.Name}'?\n\nThis action cannot be undone.",
            "Delete Connection",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.Yes)
        {
            _storageService.DeleteConnection(selected.Name);
            RefreshList();
        }
    }

    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        OpenSelectedConnection();
    }

    private void ConnectionsGrid_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        OpenSelectedConnection();
    }

    private void OpenSelectedConnection()
    {
        var selected = GetSelected();
        if (selected == null) return;

        try
        {
            var decryptedPassword = _storageService.DecryptPassword(selected.EncryptedPassword);
            ConnectionToOpen = selected.ToDatabaseConnection(decryptedPassword);
            Logger.Info("Connection selected for opening: {Name}", selected.Name);
            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open connection {Name}", selected.Name);
            MessageBox.Show($"Failed to decrypt connection:\n\n{ex.Message}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
