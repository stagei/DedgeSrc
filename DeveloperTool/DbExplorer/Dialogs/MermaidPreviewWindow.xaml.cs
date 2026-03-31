using System;
using System.IO;
using System.Reflection;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using NLog;

namespace DbExplorer.Dialogs;

/// <summary>
/// Separate preview window for Mermaid diagrams.
/// Receives live updates from the main editor window.
/// </summary>
public partial class MermaidPreviewWindow : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private bool _isWebViewReady;
    private string _pendingMermaidCode = string.Empty;
    private double _currentZoom = 1.0;
    private string _connectionInfo = string.Empty;
    private int _tableCount;
    
    /// <summary>
    /// Event fired when window is closed (for cleanup in parent).
    /// </summary>
    public event EventHandler? PreviewWindowClosed;
    
    public MermaidPreviewWindow()
    {
        InitializeComponent();
        InitializeWebView();
        
        Closed += (s, e) =>
        {
            Logger.Info("Mermaid preview window closed");
            PreviewWindowClosed?.Invoke(this, EventArgs.Empty);
        };
    }
    
    /// <summary>
    /// Set connection info to display.
    /// </summary>
    public void SetConnectionInfo(string info)
    {
        _connectionInfo = info;
        ConnectionInfoText.Text = $"📡 {info}";
    }
    
    /// <summary>
    /// Update preview with new Mermaid code.
    /// Called by parent editor window when content changes.
    /// </summary>
    public void UpdatePreview(string mermaidCode, int tableCount)
    {
        Logger.Debug("UpdatePreview called with {Length} chars, {Tables} tables", mermaidCode.Length, tableCount);
        
        _tableCount = tableCount;
        TableCountStatus.Content = $"Tables: {tableCount}";
        LastUpdateStatus.Content = $"Last update: {DateTime.Now:HH:mm:ss}";
        
        if (!AutoRefreshCheckBox.IsChecked == true)
        {
            Logger.Debug("Auto-refresh disabled, storing pending code");
            _pendingMermaidCode = mermaidCode;
            StatusText.Content = "⏸️ Auto-refresh paused - Click Refresh to update";
            return;
        }
        
        if (_isWebViewReady)
        {
            RenderMermaidAsync(mermaidCode);
        }
        else
        {
            Logger.Debug("WebView not ready, storing pending code");
            _pendingMermaidCode = mermaidCode;
        }
    }
    
    /// <summary>
    /// Force refresh from pending code.
    /// </summary>
    public void ForceRefresh()
    {
        if (_isWebViewReady && !string.IsNullOrEmpty(_pendingMermaidCode))
        {
            RenderMermaidAsync(_pendingMermaidCode);
        }
    }
    
    private async void InitializeWebView()
    {
        try
        {
            Logger.Debug("Initializing WebView2 for preview window");
            
            await PreviewWebView.EnsureCoreWebView2Async();
            
            PreviewWebView.CoreWebView2.Settings.IsScriptEnabled = true;
            PreviewWebView.CoreWebView2.Settings.AreDevToolsEnabled = false;
            
            // Load preview-only HTML (no editor, just rendering)
            var html = GetPreviewHtml();
            PreviewWebView.NavigateToString(html);
            
            PreviewWebView.NavigationCompleted += (s, e) =>
            {
                _isWebViewReady = true;
                Logger.Info("Preview WebView ready");
                
                if (!string.IsNullOrEmpty(_pendingMermaidCode))
                {
                    RenderMermaidAsync(_pendingMermaidCode);
                }
            };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to initialize preview WebView");
            StatusText.Content = $"❌ Error: {ex.Message}";
        }
    }
    
    private async void RenderMermaidAsync(string mermaidCode)
    {
        try
        {
            if (!_isWebViewReady || string.IsNullOrWhiteSpace(mermaidCode))
                return;
            
            var escapedCode = EscapeForJavaScript(mermaidCode);
            var script = $"renderMermaid(`{escapedCode}`);";
            
            await PreviewWebView.ExecuteScriptAsync(script);
            
            StatusText.Content = $"✓ Preview updated - {_tableCount} tables";
            Logger.Debug("Preview rendered successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to render preview");
            StatusText.Content = $"❌ Render error: {ex.Message}";
        }
    }
    
    private string EscapeForJavaScript(string text)
    {
        return text
            .Replace("\\", "\\\\")
            .Replace("`", "\\`")
            .Replace("$", "\\$")
            .Replace("\r\n", "\\n")
            .Replace("\r", "\\n")
            .Replace("\n", "\\n");
    }
    
    private string GetPreviewHtml()
    {
        return @"<!DOCTYPE html>
<html>
<head>
    <meta charset=""UTF-8"">
    <script src=""https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js""></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #1e1e1e;
            color: #d4d4d4;
            font-family: 'Segoe UI', sans-serif;
            overflow: auto;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            min-height: 100vh;
            padding: 20px;
        }
        #preview-container {
            background: #252526;
            border-radius: 8px;
            padding: 20px;
            min-width: 300px;
            max-width: 100%;
        }
        #mermaid-preview {
            display: flex;
            justify-content: center;
        }
        .mermaid {
            background: transparent;
        }
        .error {
            color: #f44336;
            padding: 20px;
            background: #2d1f1f;
            border-radius: 4px;
            border: 1px solid #f44336;
        }
    </style>
</head>
<body>
    <div id=""preview-container"">
        <div id=""mermaid-preview"">
            <p style=""color: #888;"">Waiting for diagram...</p>
        </div>
    </div>
    
    <script>
        mermaid.initialize({
            startOnLoad: false,
            theme: 'dark',
            securityLevel: 'loose',
            er: {
                useMaxWidth: false,
                layoutDirection: 'TB'
            }
        });
        
        async function renderMermaid(code) {
            const container = document.getElementById('mermaid-preview');
            
            try {
                container.innerHTML = '';
                const { svg } = await mermaid.render('mermaid-diagram', code);
                container.innerHTML = svg;
            } catch (error) {
                container.innerHTML = '<div class=""error"">Error: ' + error.message + '</div>';
                console.error('Mermaid error:', error);
            }
        }
    </script>
</body>
</html>";
    }
    
    private void Refresh_Click(object sender, RoutedEventArgs e)
    {
        ForceRefresh();
    }
    
    private async void ZoomIn_Click(object sender, RoutedEventArgs e)
    {
        _currentZoom = Math.Min(_currentZoom + 0.25, 3.0);
        await PreviewWebView.ExecuteScriptAsync($"document.body.style.zoom = '{_currentZoom}';");
    }
    
    private async void ZoomOut_Click(object sender, RoutedEventArgs e)
    {
        _currentZoom = Math.Max(_currentZoom - 0.25, 0.5);
        await PreviewWebView.ExecuteScriptAsync($"document.body.style.zoom = '{_currentZoom}';");
    }
    
    private async void ZoomReset_Click(object sender, RoutedEventArgs e)
    {
        _currentZoom = 1.0;
        await PreviewWebView.ExecuteScriptAsync("document.body.style.zoom = '1';");
    }
}
