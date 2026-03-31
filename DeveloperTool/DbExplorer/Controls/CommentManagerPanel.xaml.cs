using System;
using System.Collections.Generic;
using System.Data;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls;

public partial class CommentManagerPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly CommentService _commentService;
    private readonly MetadataLoaderService _metadataService;
    private IConnectionManager? _connectionManager;
    private IConnectionInfo? _connection;
    private ObjectComment? _selectedTableForColumnMenu;
    
    public CommentManagerPanel()
    {
        InitializeComponent();
        _commentService = new CommentService();
        _metadataService = new MetadataLoaderService();
        ApplyGridPreferences();
    }
    
    private void ApplyGridPreferences()
    {
        UIStyleService.ApplyStyles(this);
    }
    
    public async Task InitializeAsync(IConnectionManager connectionManager)
    {
        _connectionManager = connectionManager;
        _connection = connectionManager.ConnectionInfo;
        try
        {
            var schemas = await _metadataService.GetAllSchemasAsync(_connectionManager);
            SchemaComboBox.ItemsSource = schemas;
            if (schemas.Count > 0) SchemaComboBox.SelectedIndex = 0;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize");
            MessageBox.Show($"Error:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void SchemaComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        await RefreshDataAsync();
    }
    
    private async Task RefreshDataAsync()
    {
        if (_connectionManager == null || SchemaComboBox.SelectedItem == null) return;
        
        try
        {
            StatusText.Text = "Loading...";
            var schema = SchemaComboBox.SelectedItem.ToString();
            var comments = await _commentService.GetTableCommentsAsync(_connectionManager, schema);
            CommentsDataGrid.ItemsSource = comments;
            StatusText.Text = $"{comments.Count} comments - {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to refresh");
            MessageBox.Show($"Error:\n\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshDataAsync();
    
    private void GenerateScript_Click(object sender, RoutedEventArgs e)
    {
        var comments = CommentsDataGrid.ItemsSource as List<ObjectComment>;
        if (comments == null) return;
        
        // Only export changed comments, not all comments
        var script = _commentService.GenerateCommentScript(comments, changedOnly: true);
        var modifiedCount = comments.Count(c => c.IsModified);
        var tabTitle = modifiedCount > 0 
            ? $"COMMENT Script ({modifiedCount} modified)" 
            : "COMMENT Script";
        
        // Open the generated script in a new editor tab using the stored connection
        if (Window.GetWindow(this) is MainWindow mainWindow && _connection != null)
        {
            mainWindow.CreateNewTabWithSql(script, tabTitle, _connection);
            Logger.Info("COMMENT script opened in new tab with {Count} modified comments", modifiedCount);
        }
        else if (_connection == null)
        {
            Logger.Warn("No connection available for generating script");
            MessageBox.Show("No connection available.", "Error", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        else
        {
            // Fallback to dialog if MainWindow not available
            var window = Services.ThemedWindowHelper.CreateScriptWindow(tabTitle, script, 700, 500, Window.GetWindow(this));
            window.ShowDialog();
        }
    }
    
    private async void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        var comments = CommentsDataGrid.ItemsSource as List<ObjectComment>;
        if (comments == null || comments.Count == 0) return;
        
        var saveDialog = new SaveFileDialog { Filter = "CSV Files (*.csv)|*.csv", FileName = $"comments_{DateTime.Now:yyyyMMdd_HHmmss}.csv" };
        if (saveDialog.ShowDialog() == true)
        {
            var csv = new StringBuilder();
            csv.AppendLine("Type,Schema,Table,Column,Comment");
            foreach (var c in comments)
                csv.AppendLine($"{c.ObjectType},{c.Schema},{c.TableName},{c.ColumnName},{c.Comment}");
            await File.WriteAllTextAsync(saveDialog.FileName, csv.ToString());
            MessageBox.Show("Exported", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
    
    private async void CommentsDataGrid_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        // Get the selected item
        var selectedComment = CommentsDataGrid.SelectedItem as ObjectComment;
        if (selectedComment == null || _connectionManager == null) return;
        
        // Only show column menu for TABLE type rows
        if (selectedComment.ObjectType != "TABLE")
        {
            AddColumnCommentMenuItem.Visibility = Visibility.Collapsed;
            return;
        }
        
        AddColumnCommentMenuItem.Visibility = Visibility.Visible;
        _selectedTableForColumnMenu = selectedComment;
        
        // Clear existing submenu items
        AddColumnCommentMenuItem.Items.Clear();
        
        // Add loading indicator
        var loadingItem = new MenuItem { Header = "Loading columns...", IsEnabled = false };
        AddColumnCommentMenuItem.Items.Add(loadingItem);
        
        try
        {
            // Fetch columns for this table
            var columns = await GetTableColumnsAsync(selectedComment.Schema, selectedComment.TableName);
            
            // Get existing column comments for this table
            var existingComments = (CommentsDataGrid.ItemsSource as List<ObjectComment>)?
                .Where(c => c.ObjectType == "COLUMN" && 
                           c.Schema == selectedComment.Schema && 
                           c.TableName == selectedComment.TableName)
                .Select(c => c.ColumnName)
                .ToHashSet() ?? new HashSet<string?>();
            
            // Clear loading indicator and populate with columns
            AddColumnCommentMenuItem.Items.Clear();
            
            foreach (var column in columns)
            {
                var isExisting = existingComments.Contains(column);
                var menuItem = new MenuItem 
                { 
                    Header = isExisting ? $"✓ {column}" : $"  {column}",
                    Tag = column,
                    IsEnabled = !isExisting // Disable if already has comment row
                };
                menuItem.Click += AddColumnComment_Click;
                AddColumnCommentMenuItem.Items.Add(menuItem);
            }
            
            if (columns.Count == 0)
            {
                AddColumnCommentMenuItem.Items.Add(new MenuItem { Header = "No columns found", IsEnabled = false });
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load columns for context menu");
            AddColumnCommentMenuItem.Items.Clear();
            AddColumnCommentMenuItem.Items.Add(new MenuItem { Header = "Error loading columns", IsEnabled = false });
        }
    }
    
    private async Task<List<string>> GetTableColumnsAsync(string schema, string tableName)
    {
        if (_connectionManager == null) return new List<string>();
        
        var sql = $"SELECT TRIM(COLNAME) AS COLNAME FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '{schema}' AND TABNAME = '{tableName}' ORDER BY COLNO";
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        return result.Rows.Cast<DataRow>()
            .Select(r => r["COLNAME"]?.ToString() ?? "")
            .Where(c => !string.IsNullOrEmpty(c))
            .ToList();
    }
    
    private void AddColumnComment_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuItem menuItem) return;
        if (_selectedTableForColumnMenu == null) return;
        
        var columnName = menuItem.Tag?.ToString();
        if (string.IsNullOrEmpty(columnName)) return;
        
        // Get the current list
        var comments = CommentsDataGrid.ItemsSource as List<ObjectComment>;
        if (comments == null) return;
        
        // Create new column comment row
        var newComment = new ObjectComment
        {
            ObjectType = "COLUMN",
            Schema = _selectedTableForColumnMenu.Schema,
            TableName = _selectedTableForColumnMenu.TableName,
            ColumnName = columnName,
            Comment = "",
            OriginalComment = null // New row, no original
        };
        
        // Find the index of the parent table to insert after it
        var tableIndex = comments.IndexOf(_selectedTableForColumnMenu);
        if (tableIndex >= 0)
        {
            // Find the last column comment for this table (to insert at the end of its columns)
            var insertIndex = tableIndex + 1;
            while (insertIndex < comments.Count && 
                   comments[insertIndex].ObjectType == "COLUMN" &&
                   comments[insertIndex].Schema == _selectedTableForColumnMenu.Schema &&
                   comments[insertIndex].TableName == _selectedTableForColumnMenu.TableName)
            {
                insertIndex++;
            }
            comments.Insert(insertIndex, newComment);
        }
        else
        {
            comments.Add(newComment);
        }
        
        // Refresh the grid
        CommentsDataGrid.ItemsSource = null;
        CommentsDataGrid.ItemsSource = comments;
        
        // Select and focus the new row's comment cell
        CommentsDataGrid.SelectedItem = newComment;
        CommentsDataGrid.ScrollIntoView(newComment);
        
        // Start editing the comment cell (column index 4 is the Comment column)
        CommentsDataGrid.Dispatcher.BeginInvoke(new Action(() =>
        {
            var rowIndex = comments.IndexOf(newComment);
            if (rowIndex >= 0)
            {
                CommentsDataGrid.Focus();
                CommentsDataGrid.CurrentCell = new DataGridCellInfo(newComment, CommentsDataGrid.Columns[4]);
                CommentsDataGrid.BeginEdit();
            }
        }), System.Windows.Threading.DispatcherPriority.Background);
        
        Logger.Info("Added column comment row for {Schema}.{Table}.{Column}", 
            newComment.Schema, newComment.TableName, newComment.ColumnName);
        
        // Update status
        StatusText.Text = $"Added column: {columnName} - {DateTime.Now:HH:mm:ss}";
    }
}

