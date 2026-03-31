using System.Windows;
using NLog;

namespace DbExplorer.Dialogs;

public partial class SqlStatementViewerDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public bool AddToEditor { get; private set; }

    public SqlStatementViewerDialog(string sqlText, string title)
    {
        InitializeComponent();

        StatementTitleText.Text = title;
        SqlTextBox.Text = sqlText;

        Logger.Debug("SqlStatementViewerDialog opened: {Title}", title);
    }

    private void CopyToClipboard_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(SqlTextBox.Text);
            MessageBox.Show("SQL statement copied to clipboard", "Success", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            Logger.Info("SQL statement copied to clipboard");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy to clipboard");
            MessageBox.Show($"Failed to copy:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void AddToEditor_Click(object sender, RoutedEventArgs e)
    {
        AddToEditor = true;
        DialogResult = true;
        Logger.Info("User chose to add SQL to editor");
        Close();
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

