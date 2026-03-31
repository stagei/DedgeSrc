using System.Windows;

namespace DbExplorer.Dialogs;

/// <summary>
/// Offer to download recommended Ollama SQL model (defog-llama3-sqlcoder-8b).
/// </summary>
public partial class OllamaModelDownloadDialog : Window
{
    public bool UserChoseDownload { get; private set; }

    public OllamaModelDownloadDialog()
    {
        InitializeComponent();
    }

    public void SetMessage(string message)
    {
        MessageText.Text = message;
    }

    private void Download_Click(object sender, RoutedEventArgs e)
    {
        UserChoseDownload = true;
        DialogResult = true;
        Close();
    }

    private void Skip_Click(object sender, RoutedEventArgs e)
    {
        UserChoseDownload = false;
        DialogResult = false;
        Close();
    }
}
