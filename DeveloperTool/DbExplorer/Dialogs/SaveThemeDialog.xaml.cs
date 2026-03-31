using System.Windows;

namespace DbExplorer.Dialogs;

/// <summary>
/// Dialog for saving a custom theme with a user-specified name
/// </summary>
public partial class SaveThemeDialog : Window
{
    /// <summary>
    /// The theme name entered by the user
    /// </summary>
    public string ThemeName { get; private set; } = string.Empty;

    public SaveThemeDialog(string defaultName = "My Custom Theme")
    {
        InitializeComponent();
        ThemeNameTextBox.Text = defaultName;
        ThemeNameTextBox.SelectAll();
        ThemeNameTextBox.Focus();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var name = ThemeNameTextBox.Text.Trim();
        
        if (string.IsNullOrWhiteSpace(name))
        {
            MessageBox.Show("Please enter a theme name.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            ThemeNameTextBox.Focus();
            return;
        }
        
        // Check for invalid characters in filename
        var invalidChars = System.IO.Path.GetInvalidFileNameChars();
        foreach (var c in invalidChars)
        {
            if (name.Contains(c))
            {
                MessageBox.Show($"Theme name cannot contain the character '{c}'.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                ThemeNameTextBox.Focus();
                return;
            }
        }
        
        ThemeName = name;
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
