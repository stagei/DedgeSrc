using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using ICSharpCode.AvalonEdit;
using NLog;

namespace DbExplorer.Dialogs;

/// <summary>
/// Dialog for viewing Missing FK Discovery job log in real-time.
/// Uses AvalonEdit for read-only log display with live updates.
/// </summary>
public partial class MissingFKJobLogViewerDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _logFilePath;
    private readonly string _jobId;
    private FileSystemWatcher? _logFileWatcher;
    private long _lastFilePosition = 0;
    private readonly object _fileLock = new object();
    
    public MissingFKJobLogViewerDialog(string logFilePath, string jobId)
    {
        InitializeComponent();
        
        _logFilePath = logFilePath ?? throw new ArgumentNullException(nameof(logFilePath));
        _jobId = jobId ?? throw new ArgumentNullException(nameof(jobId));
        
        Title = $"Missing FK Discovery Job Log - {jobId}";
        JobStatusText.Text = $"Job ID: {jobId}";
        
        Loaded += MissingFKJobLogViewerDialog_Loaded;
        Closing += MissingFKJobLogViewerDialog_Closing;
    }
    
    private void MissingFKJobLogViewerDialog_Loaded(object sender, RoutedEventArgs e)
    {
        LoadLogFile();
        StartLogMonitoring();
    }
    
    private void MissingFKJobLogViewerDialog_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        StopLogMonitoring();
    }
    
    /// <summary>
    /// Load log file content into the editor.
    /// </summary>
    private void LoadLogFile()
    {
        try
        {
            if (!File.Exists(_logFilePath))
            {
                LogEditor.Text = "Log file not found. Waiting for log file to be created...";
                return;
            }
            
            lock (_fileLock)
            {
                var content = File.ReadAllText(_logFilePath, Encoding.UTF8);
                LogEditor.Text = content;
                _lastFilePosition = new FileInfo(_logFilePath).Length;
                
                // Scroll to end
                AutoScrollToEnd();
            }
            
            Logger.Debug("Loaded log file: {Path} ({Length} bytes)", _logFilePath, _lastFilePosition);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load log file");
            LogEditor.Text = $"Error loading log file: {ex.Message}";
        }
    }
    
    /// <summary>
    /// Start monitoring log file for changes.
    /// </summary>
    private void StartLogMonitoring()
    {
        try
        {
            var directory = Path.GetDirectoryName(_logFilePath);
            var fileName = Path.GetFileName(_logFilePath);
            
            if (string.IsNullOrEmpty(directory) || string.IsNullOrEmpty(fileName))
            {
                Logger.Warn("Invalid log file path for monitoring: {Path}", _logFilePath);
                return;
            }
            
            _logFileWatcher = new FileSystemWatcher(directory, fileName)
            {
                NotifyFilter = NotifyFilters.Size | NotifyFilters.LastWrite
            };
            
            _logFileWatcher.Changed += OnLogFileChanged;
            _logFileWatcher.EnableRaisingEvents = true;
            
            Logger.Info("Started log file monitoring: {Path}", _logFilePath);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to start log file monitoring");
        }
    }
    
    /// <summary>
    /// Stop monitoring log file.
    /// </summary>
    private void StopLogMonitoring()
    {
        try
        {
            if (_logFileWatcher != null)
            {
                _logFileWatcher.EnableRaisingEvents = false;
                _logFileWatcher.Dispose();
                _logFileWatcher = null;
            }
            
            Logger.Debug("Stopped log file monitoring");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error stopping log file monitoring");
        }
    }
    
    /// <summary>
    /// Handle log file change event.
    /// </summary>
    private void OnLogFileChanged(object sender, FileSystemEventArgs e)
    {
        // FileSystemWatcher events can fire multiple times, so we need to handle this carefully
        Dispatcher.BeginInvoke(new Action(() =>
        {
            try
            {
                if (!File.Exists(_logFilePath))
                    return;
                
                lock (_fileLock)
                {
                    var fileInfo = new FileInfo(_logFilePath);
                    if (fileInfo.Length <= _lastFilePosition)
                        return; // File was truncated or no new content
                    
                    // Read only new content
                    using var fileStream = new FileStream(_logFilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    fileStream.Position = _lastFilePosition;
                    
                    using var reader = new StreamReader(fileStream, Encoding.UTF8);
                    var newContent = reader.ReadToEnd();
                    
                    if (!string.IsNullOrEmpty(newContent))
                    {
                        // Append new content to editor
                        LogEditor.AppendText(newContent);
                        _lastFilePosition = fileInfo.Length;
                        
                        // Scroll to end
                        AutoScrollToEnd();
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Error reading new log content");
            }
        }), DispatcherPriority.Background);
    }
    
    /// <summary>
    /// Auto-scroll to end of log.
    /// </summary>
    private void AutoScrollToEnd()
    {
        try
        {
            var lineCount = LogEditor.Document.LineCount;
            if (lineCount > 0)
            {
                var line = LogEditor.Document.GetLineByNumber(lineCount);
                LogEditor.ScrollToLine(lineCount);
                LogEditor.CaretOffset = line.EndOffset;
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error scrolling to end of log");
        }
    }
    
    private void RefreshLog_Click(object sender, RoutedEventArgs e)
    {
        LoadLogFile();
    }
    
    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
