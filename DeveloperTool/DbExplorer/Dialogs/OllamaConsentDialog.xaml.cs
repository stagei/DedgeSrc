using System.Windows;

namespace DbExplorer.Dialogs;

/// <summary>
/// User consent for using Ollama for AI SQL edit (Ctrl+K). Yes / No / Don't ask again.
/// </summary>
public partial class OllamaConsentDialog : Window
{
    /// <summary>User chose Yes (allow Ollama for SQL edit).</summary>
    public bool AllowOllama { get; private set; }
    /// <summary>User chose Don't ask again (do not show this again).</summary>
    public bool DontAskAgain { get; private set; }

    public OllamaConsentDialog()
    {
        InitializeComponent();
    }

    private void Yes_Click(object sender, RoutedEventArgs e)
    {
        AllowOllama = true;
        DontAskAgain = false;
        DialogResult = true;
        Close();
    }

    private void No_Click(object sender, RoutedEventArgs e)
    {
        AllowOllama = false;
        DontAskAgain = false;
        DialogResult = false;
        Close();
    }

    private void DontAsk_Click(object sender, RoutedEventArgs e)
    {
        AllowOllama = false;
        DontAskAgain = true;
        DialogResult = false;
        Close();
    }
}
