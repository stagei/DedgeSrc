using System;
using System.Diagnostics;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using NLog;

namespace DbExplorer.Dialogs;

public partial class ConnectionProgressDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly CancellationTokenSource _cancellationTokenSource;
    private readonly DispatcherTimer _progressTimer;
    private readonly Stopwatch _stopwatch;
    private int _expectedTimeMs;
    private bool _hasHistory;
    
    public CancellationToken CancellationToken => _cancellationTokenSource.Token;
    public bool WasAborted { get; private set; }
    public int ElapsedTimeMs => (int)_stopwatch.ElapsedMilliseconds;

    public ConnectionProgressDialog(string connectionName, int expectedTimeMs, bool hasHistory)
    {
        InitializeComponent();
        
        _cancellationTokenSource = new CancellationTokenSource();
        _stopwatch = new Stopwatch();
        _expectedTimeMs = expectedTimeMs;
        _hasHistory = hasHistory;
        
        ConnectionNameText.Text = connectionName;
        
        // Setup progress timer (updates every 500ms)
        _progressTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _progressTimer.Tick += ProgressTimer_Tick;
        
        Logger.Debug("ConnectionProgressDialog opened for: {ConnectionName}, Expected: {Expected}ms, HasHistory: {HasHistory}", 
            connectionName, expectedTimeMs, hasHistory);
    }

    /// <summary>
    /// Start the connection progress tracking
    /// </summary>
    public void StartProgress()
    {
        _stopwatch.Start();
        _progressTimer.Start();
        Logger.Debug("Progress tracking started");
    }

    /// <summary>
    /// Progress timer tick - updates progress bar every 500ms
    /// </summary>
    private void ProgressTimer_Tick(object? sender, EventArgs e)
    {
        var elapsedMs = _stopwatch.ElapsedMilliseconds;
        double progressPercentage;
        
        if (elapsedMs < _expectedTimeMs)
        {
            // Normal progress: 0-100% based on expected time
            progressPercentage = (elapsedMs / (double)_expectedTimeMs) * 100.0;
            ConnectionProgressBar.Foreground = (Brush)FindResource("SystemControlHighlightAccentBrush");
        }
        else
        {
            // Exceeded expected time: show as 100% with yellow color
            progressPercentage = 100;
            ConnectionProgressBar.Foreground = new SolidColorBrush(Color.FromRgb(255, 193, 7)); // Amber/Yellow
            
            // Update status to indicate taking longer than expected
            if (_hasHistory)
            {
                DetailText.Text = $"Taking longer than usual ({elapsedMs / 1000:F1}s elapsed, expected ~{_expectedTimeMs / 1000:F1}s)";
            }
            else
            {
                DetailText.Text = $"Connecting... ({elapsedMs / 1000:F1}s elapsed)";
            }
        }
        
        ConnectionProgressBar.Value = Math.Min(100, progressPercentage);
        
        Logger.Trace("Progress update: {Elapsed}ms, {Percentage}%", elapsedMs, progressPercentage);
    }

    /// <summary>
    /// Update the status text
    /// </summary>
    public void UpdateStatus(string status)
    {
        Dispatcher.Invoke(() =>
        {
            StatusText.Text = status;
            Logger.Debug("Connection status updated: {Status}", status);
        });
    }

    /// <summary>
    /// Update the detail text
    /// </summary>
    public void UpdateDetail(string detail)
    {
        Dispatcher.Invoke(() =>
        {
            DetailText.Text = detail;
        });
    }

    /// <summary>
    /// Handle abort button click
    /// </summary>
    private void AbortButton_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("User requested connection abort");
        
        WasAborted = true;
        AbortButton.IsEnabled = false;
        AbortButton.Content = "⏳ Aborting...";
        StatusText.Text = "Aborting connection...";
        DetailText.Text = "Please wait while the connection is cancelled.";
        
        try
        {
            _cancellationTokenSource.Cancel();
            Logger.Info("Cancellation token signaled");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during cancellation");
        }
    }

    /// <summary>
    /// Close the dialog with success
    /// </summary>
    public void CloseWithSuccess()
    {
        Dispatcher.Invoke(() =>
        {
            _stopwatch.Stop();
            _progressTimer.Stop();
            ConnectionProgressBar.Value = 100;
            ConnectionProgressBar.Foreground = new SolidColorBrush(Color.FromRgb(76, 175, 80)); // Green
            DialogResult = true;
            Close();
        });
    }

    /// <summary>
    /// Close the dialog with failure
    /// </summary>
    public void CloseWithFailure()
    {
        Dispatcher.Invoke(() =>
        {
            _stopwatch.Stop();
            _progressTimer.Stop();
            ConnectionProgressBar.Foreground = new SolidColorBrush(Color.FromRgb(244, 67, 54)); // Red
            DialogResult = false;
            Close();
        });
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // If user tries to close window (X button), treat as abort
        if (!WasAborted && !_cancellationTokenSource.IsCancellationRequested)
        {
            Logger.Debug("Window closing via X button - treating as abort");
            WasAborted = true;
            _cancellationTokenSource.Cancel();
        }
        
        _stopwatch.Stop();
        _progressTimer.Stop();
        
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _cancellationTokenSource.Dispose();
        _progressTimer.Stop();
        base.OnClosed(e);
    }
}

