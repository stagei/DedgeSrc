using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class SqlQueryHistoryDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    public SqlQueryHistoryDialog()
    {
        InitializeComponent();
        
        Logger.Debug("SqlQueryHistoryDialog opened");
        
        // Apply all UI styles from the unified style service
        Loaded += (s, e) => UIStyleService.ApplyStyles(this);
        
        LoadHistory();
    }
    
    private void LoadHistory()
    {
        var history = SqlQueryHistoryService.GetHistory();
        QueryGrid.ItemsSource = history;
        CountText.Text = $" ({history.Count} queries)";
        
        // Select first item if available
        if (history.Count > 0)
        {
            QueryGrid.SelectedIndex = 0;
        }
        
        Logger.Debug("Loaded {Count} queries into history view", history.Count);
    }
    
    private void QueryGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (QueryGrid.SelectedItem is ExecutedQuery query)
        {
            SqlPreviewText.Text = query.Sql;
        }
        else
        {
            SqlPreviewText.Text = string.Empty;
        }
    }
    
    private void CopySql_Click(object sender, RoutedEventArgs e)
    {
        if (QueryGrid.SelectedItem is ExecutedQuery query)
        {
            try
            {
                var header = $"-- Source: {query.Source ?? "Unknown"}\n-- Executed: {query.ExecutedAt:yyyy-MM-dd HH:mm:ss}\n-- Duration: {query.DisplayDuration}, Rows: {query.DisplayRows}\n\n";
                Clipboard.SetText(header + query.Sql);
                
                Logger.Info("SQL copied to clipboard");
                MessageBox.Show("SQL copied to clipboard!", "Copied", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to copy SQL to clipboard");
                MessageBox.Show($"Failed to copy: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
        else
        {
            MessageBox.Show("Please select a query first.", "No Selection", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    
    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show("Clear all query history?", "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (result == MessageBoxResult.Yes)
        {
            SqlQueryHistoryService.Clear();
            LoadHistory();
            SqlPreviewText.Text = string.Empty;
        }
    }
    
    private void Refresh_Click(object sender, RoutedEventArgs e)
    {
        LoadHistory();
    }
    
    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
