using System;
using System.Windows;
using NLog;

namespace DbExplorer.Dialogs;

/// <summary>
/// A user-friendly error dialog with expandable technical details.
/// Shows a compact error message by default with an option to expand
/// and view the full stack trace for troubleshooting.
/// </summary>
public partial class ErrorDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _fullErrorDetails;

    /// <summary>
    /// Create a new error dialog with the given exception details
    /// </summary>
    /// <param name="title">The dialog title (e.g., "Error", "Fatal Error")</param>
    /// <param name="message">The brief error message to display</param>
    /// <param name="details">The full technical details (stack trace)</param>
    /// <param name="exceptionType">Optional exception type name for display</param>
    public ErrorDialog(string title, string message, string? details = null, string? exceptionType = null)
    {
        InitializeComponent();

        Logger.Debug("ErrorDialog created - Title: {Title}, Message length: {Length}", 
            title, message?.Length ?? 0);

        Title = title;
        ErrorTitleText.Text = title;
        ErrorMessageText.Text = message ?? "An unknown error occurred.";

        // Show exception type if provided
        if (!string.IsNullOrWhiteSpace(exceptionType))
        {
            ErrorTypeText.Text = $"Exception: {exceptionType}";
            ErrorTypeText.Visibility = Visibility.Visible;
        }

        // Store full details for copy and expand functionality
        _fullErrorDetails = BuildFullErrorDetails(title, message, details, exceptionType);
        DetailsTextBox.Text = details ?? "No additional details available.";
    }

    /// <summary>
    /// Create an error dialog from an exception
    /// </summary>
    public static ErrorDialog FromException(Exception ex, string title = "Error", bool isFatal = false)
    {
        var dialogTitle = isFatal ? "Fatal Error" : title;
        var message = ex.Message;
        var details = ex.ToString(); // Full exception with stack trace
        var exceptionType = ex.GetType().Name;

        return new ErrorDialog(dialogTitle, message, details, exceptionType);
    }

    /// <summary>
    /// Show the error dialog and return when closed
    /// </summary>
    public static void ShowError(Exception ex, string title = "Error", bool isFatal = false, Window? owner = null)
    {
        try
        {
            var dialog = FromException(ex, title, isFatal);
            if (owner != null)
            {
                dialog.Owner = owner;
            }
            dialog.ShowDialog();
        }
        catch (Exception dialogEx)
        {
            // Fallback to MessageBox if our dialog fails
            Logger.Error(dialogEx, "Failed to show ErrorDialog, falling back to MessageBox");
            MessageBox.Show(
                $"{ex.Message}\n\nDetails: {ex.ToString()}",
                title,
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Show the error dialog with a simple message (no exception)
    /// </summary>
    public static void ShowError(string message, string title = "Error", string? details = null, Window? owner = null)
    {
        try
        {
            var dialog = new ErrorDialog(title, message, details);
            if (owner != null)
            {
                dialog.Owner = owner;
            }
            dialog.ShowDialog();
        }
        catch (Exception dialogEx)
        {
            Logger.Error(dialogEx, "Failed to show ErrorDialog, falling back to MessageBox");
            MessageBox.Show(message, title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private string BuildFullErrorDetails(string title, string? message, string? details, string? exceptionType)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("=== Error Report ===");
        sb.AppendLine($"Time: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        sb.AppendLine($"Title: {title}");
        
        if (!string.IsNullOrWhiteSpace(exceptionType))
        {
            sb.AppendLine($"Exception Type: {exceptionType}");
        }
        
        sb.AppendLine();
        sb.AppendLine("=== Message ===");
        sb.AppendLine(message ?? "(No message)");
        sb.AppendLine();
        
        if (!string.IsNullOrWhiteSpace(details))
        {
            sb.AppendLine("=== Technical Details ===");
            sb.AppendLine(details);
        }

        return sb.ToString();
    }

    private void ExpandDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        var isExpanded = DetailsBorder.Visibility == Visibility.Visible;

        if (isExpanded)
        {
            // Collapse
            DetailsBorder.Visibility = Visibility.Collapsed;
            ExpandDetailsButton.Content = "▶ Show Details";
            Logger.Debug("Error details collapsed");
        }
        else
        {
            // Expand
            DetailsBorder.Visibility = Visibility.Visible;
            ExpandDetailsButton.Content = "▼ Hide Details";
            Logger.Debug("Error details expanded");
        }
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(_fullErrorDetails);
            Logger.Info("Error details copied to clipboard");

            // Provide visual feedback
            var originalContent = CopyButton.Content;
            CopyButton.Content = "✓ Copied!";
            CopyButton.IsEnabled = false;

            // Reset after 2 seconds
            var timer = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(2)
            };
            timer.Tick += (s, args) =>
            {
                CopyButton.Content = originalContent;
                CopyButton.IsEnabled = true;
                timer.Stop();
            };
            timer.Start();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy error details to clipboard");
            MessageBox.Show("Failed to copy to clipboard.", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void OkButton_Click(object sender, RoutedEventArgs e)
    {
        Logger.Debug("ErrorDialog closed via OK button");
        Close();
    }
}
