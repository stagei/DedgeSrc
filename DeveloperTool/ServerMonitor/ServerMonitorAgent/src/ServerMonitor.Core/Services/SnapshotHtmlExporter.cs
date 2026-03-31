using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Exports system snapshots as interactive HTML files with tabbed interface
/// Matches the design from PowerShell Export-WorkObjectToHtmlFile
/// </summary>
public class SnapshotHtmlExporter
{
    private readonly ILogger<SnapshotHtmlExporter> _logger;

    public SnapshotHtmlExporter(ILogger<SnapshotHtmlExporter> logger)
    {
        _logger = logger;
    }

    public async Task ExportToHtmlAsync(
        SystemSnapshot snapshot,
        string localOutputPath,
        bool saveToServerShare = true,
        bool autoOpen = false,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var html = GenerateHtml(snapshot);

            // Save locally
            var localDirectory = Path.GetDirectoryName(localOutputPath);
            if (!string.IsNullOrEmpty(localDirectory) && !Directory.Exists(localDirectory))
            {
                Directory.CreateDirectory(localDirectory);
            }

            await File.WriteAllTextAsync(localOutputPath, html, cancellationToken).ConfigureAwait(false);
            _logger.LogInformation("HTML snapshot saved to: {Path}", localOutputPath);

            // Save to server share
            if (saveToServerShare)
            {
                try
                {
                    var serverSharePath = $@"dedge-server\FkAdminWebContent\Server\{snapshot.Metadata.ServerName}\";
                    if (!Directory.Exists(serverSharePath))
                    {
                        Directory.CreateDirectory(serverSharePath);
                    }

                    var serverFileName = $"snapshot_{snapshot.Metadata.Timestamp:yyyyMMdd_HHmmss}.html";
                    var serverFullPath = Path.Combine(serverSharePath, serverFileName);

                    await File.WriteAllTextAsync(serverFullPath, html, cancellationToken).ConfigureAwait(false);
                    _logger.LogInformation("HTML snapshot saved to server share: {Path}", serverFullPath);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to save HTML to server share - continuing");
                }
            }

            // Auto-open if requested
            if (autoOpen)
            {
                try
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = localOutputPath,
                        UseShellExecute = true
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to auto-open HTML file");
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to export HTML snapshot");
            throw;
        }
    }

    private string GenerateHtml(SystemSnapshot snapshot)
    {
        var sb = new StringBuilder();

        // HTML Header
        sb.AppendLine("<!DOCTYPE html>");
        sb.AppendLine("<html lang=\"en\">");
        sb.AppendLine("<head>");
        sb.AppendLine("    <meta charset=\"UTF-8\">");
        sb.AppendLine("    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">");
        sb.AppendLine($"    <title>Server Snapshot - {snapshot.Metadata.ServerName} - {snapshot.Metadata.Timestamp:yyyy-MM-dd HH:mm:ss}</title>");
        
        // Add CSS (exact match from PowerShell)
        sb.AppendLine(GenerateCss());
        
        sb.AppendLine("</head>");
        sb.AppendLine("<body>");
        
        // Page Title
        sb.AppendLine($"<h1>Server Snapshot - {snapshot.Metadata.ServerName}</h1>");
        sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>Captured: {snapshot.Metadata.Timestamp:yyyy-MM-dd HH:mm:ss UTC} | Duration: {snapshot.Metadata.CollectionDurationMs}ms | Version: {snapshot.Metadata.ToolVersion}</p>");
        
        // Tab Container
        sb.AppendLine("<div class='tab-container'>");
        
        // Tab Headers
        sb.AppendLine("    <div class='tab-headers'>");
        sb.AppendLine("        <button class='tab-button active' onclick='showTab(0)'>Summary</button>");
        
        int tabIndex = 1;
        var tabs = new List<(string Name, Action<StringBuilder> RenderContent)>();
        
        if (snapshot.Processor != null)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Processor</button>");
            tabs.Add(("Processor", RenderProcessorTab));
            tabIndex++;
        }
        
        if (snapshot.Memory != null)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Memory</button>");
            tabs.Add(("Memory", RenderMemoryTab));
            tabIndex++;
        }
        
        if (snapshot.VirtualMemory != null)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Virtual Memory</button>");
            tabs.Add(("VirtualMemory", RenderVirtualMemoryTab));
            tabIndex++;
        }
        
        if (snapshot.Disks != null)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Disks</button>");
            tabs.Add(("Disks", RenderDisksTab));
            tabIndex++;
        }
        
        if (snapshot.Network?.Count > 0)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Network</button>");
            tabs.Add(("Network", RenderNetworkTab));
            tabIndex++;
        }
        
        if (snapshot.Uptime != null)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Uptime</button>");
            tabs.Add(("Uptime", RenderUptimeTab));
            tabIndex++;
        }
        
        if (snapshot.WindowsUpdates != null)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Windows Updates</button>");
            tabs.Add(("WindowsUpdates", RenderWindowsUpdatesTab));
            tabIndex++;
        }
        
        if (snapshot.Events?.Count > 0)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Events</button>");
            tabs.Add(("Events", RenderEventsTab));
            tabIndex++;
        }
        
        if (snapshot.ScheduledTasks?.Count > 0)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Scheduled Tasks</button>");
            tabs.Add(("ScheduledTasks", RenderScheduledTasksTab));
            tabIndex++;
        }
        
        if (snapshot.Db2Diagnostics?.IsActive == true)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>DB2 Diagnostics</button>");
            tabs.Add(("Db2Diagnostics", RenderDb2DiagnosticsTab));
            tabIndex++;
        }
        
        if (snapshot.Alerts?.Count > 0)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>Alerts</button>");
            tabs.Add(("Alerts", RenderAlertsTab));
            tabIndex++;
        }
        
        if (snapshot.ExternalEvents?.Count > 0)
        {
            sb.AppendLine($"        <button class='tab-button' onclick='showTab({tabIndex})'>External Events</button>");
            tabs.Add(("ExternalEvents", RenderExternalEventsTab));
            tabIndex++;
        }
        
        sb.AppendLine("    </div>");
        
        // Tab Contents
        sb.AppendLine("    <div style='flex-grow: 1; position: relative;'>");
        
        // Summary Tab (always first, index 0)
        sb.AppendLine("        <div id='tab-0' class='tab-content' style='display: block;'>");
        RenderSummaryTab(sb, snapshot);
        sb.AppendLine("        </div>");
        
        // Other tabs
        for (int i = 0; i < tabs.Count; i++)
        {
            sb.AppendLine($"        <div id='tab-{i + 1}' class='tab-content' style='display: none;'>");
            tabs[i].RenderContent(sb);
            sb.AppendLine("        </div>");
        }
        
        sb.AppendLine("    </div>");
        sb.AppendLine("</div>");
        
        // JavaScript for tabs
        sb.AppendLine(GenerateJavaScript());
        
        sb.AppendLine("</body>");
        sb.AppendLine("</html>");
        
        return sb.ToString();
        
        // Local render functions with closure over snapshot
        void RenderProcessorTab(StringBuilder content) => RenderProcessorContent(content, snapshot.Processor!);
        void RenderMemoryTab(StringBuilder content) => RenderMemoryContent(content, snapshot.Memory!);
        void RenderVirtualMemoryTab(StringBuilder content) => RenderVirtualMemoryContent(content, snapshot.VirtualMemory!);
        void RenderDisksTab(StringBuilder content) => RenderDisksContent(content, snapshot.Disks!);
        void RenderNetworkTab(StringBuilder content) => RenderNetworkContent(content, snapshot.Network);
        void RenderUptimeTab(StringBuilder content) => RenderUptimeContent(content, snapshot.Uptime!);
        void RenderWindowsUpdatesTab(StringBuilder content) => RenderWindowsUpdatesContent(content, snapshot.WindowsUpdates!);
        void RenderEventsTab(StringBuilder content) => RenderEventsContent(content, snapshot.Events);
        void RenderScheduledTasksTab(StringBuilder content) => RenderScheduledTasksContent(content, snapshot.ScheduledTasks);
        void RenderDb2DiagnosticsTab(StringBuilder content) => RenderDb2DiagnosticsContent(content, snapshot.Db2Diagnostics!);
        void RenderAlertsTab(StringBuilder content) => RenderAlertsContent(content, snapshot.Alerts);
        void RenderExternalEventsTab(StringBuilder content) => RenderExternalEventsContent(content, snapshot.ExternalEvents);
    }

    private string GenerateCss()
    {
        return @"
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
            max-width: 100vw;
            overflow-x: hidden;
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #007acc;
            padding-bottom: 10px;
        }
        h2 {
            color: #007acc;
            margin-top: 20px;
        }
        h3 {
            color: #555;
        }
        .tab-container { 
            display: flex;
            margin: 20px 0;
            min-height: 400px;
            max-width: calc(100vw - 40px);
            background-color: white;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .tab-headers { 
            width: 250px;
            min-width: 250px;
            border-right: 2px solid #ddd;
            padding-right: 0;
            display: flex;
            flex-direction: column;
            background-color: #fafafa;
            border-radius: 5px 0 0 5px;
        }
        .tab-button { 
            background-color: #f1f1f1; 
            border: none; 
            padding: 12px 15px; 
            cursor: pointer; 
            font-size: 14px; 
            margin-bottom: 2px;
            text-align: left;
            border-radius: 5px 0 0 5px;
            white-space: normal;
            word-wrap: break-word;
            transition: background-color 0.2s;
        }
        .tab-button:hover { 
            background-color: #ddd; 
        }
        .tab-button.active { 
            background-color: #007acc; 
            color: white; 
            font-weight: bold;
        }
        .tab-content { 
            display: none; 
            padding: 20px; 
            border: 1px solid #ddd; 
            border-left: none;
            flex-grow: 1;
            overflow-x: auto;
            max-width: calc(100vw - 310px);
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 20px;
            background-color: white;
            table-layout: auto;
            max-width: 100%;
        }
        table td, table th {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
            max-width: 400px;
            word-wrap: break-word;
            overflow-wrap: break-word;
            word-break: break-word;
        }
        table th {
            background-color: #4CAF50;
            color: white;
            font-weight: bold;
        }
        table tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        table tr:nth-child(odd) {
            background-color: #ffffff;
        }
        table tr:hover {
            background-color: #f1f1f1;
        }
        .properties-table td:first-child {
            font-weight: bold;
            background-color: #f2f2f2;
            width: 30%;
        }
        .code-block { 
            background-color: #f8f8f8; 
            border: 1px solid #ddd; 
            padding: 15px; 
            margin: 10px 0; 
            font-family: 'Courier New', monospace; 
            white-space: pre-wrap; 
            overflow-x: auto;
            border-radius: 3px;
            font-size: 13px;
        }
        .alert-box {
            padding: 15px;
            margin: 10px 0;
            border-radius: 5px;
            border-left: 5px solid;
        }
        .alert-info { border-color: #1976D2; background-color: #E3F2FD; }
        .alert-warning { border-color: #F57C00; background-color: #FFF3E0; }
        .alert-critical { border-color: #D32F2F; background-color: #FFEBEE; }
        .metric-good { color: #4CAF50; font-weight: bold; }
        .metric-warning { color: #F57C00; font-weight: bold; }
        .metric-critical { color: #D32F2F; font-weight: bold; }
    </style>";
    }

    private string GenerateJavaScript()
    {
        return @"
    <script>
        function showTab(tabIndex) {
            // Hide all tab contents
            var tabContents = document.querySelectorAll('.tab-content');
            for (var i = 0; i < tabContents.length; i++) {
                tabContents[i].style.display = 'none';
            }
            
            // Remove active class from all buttons
            var tabButtons = document.querySelectorAll('.tab-button');
            for (var i = 0; i < tabButtons.length; i++) {
                tabButtons[i].classList.remove('active');
            }
            
            // Show selected tab content
            document.getElementById('tab-' + tabIndex).style.display = 'block';
            
            // Add active class to selected button
            tabButtons[tabIndex].classList.add('active');
        }
    </script>";
    }

    private void RenderSummaryTab(StringBuilder sb, SystemSnapshot snapshot)
    {
        sb.AppendLine("<h2>Snapshot Summary</h2>");
        sb.AppendLine("<table class='properties-table'>");
        sb.AppendLine("<tr><td>Server Name</td><td>" + HtmlEncode(snapshot.Metadata.ServerName) + "</td></tr>");
        sb.AppendLine("<tr><td>Snapshot ID</td><td>" + snapshot.Metadata.SnapshotId + "</td></tr>");
        sb.AppendLine("<tr><td>Timestamp (UTC)</td><td>" + snapshot.Metadata.Timestamp.ToString("yyyy-MM-dd HH:mm:ss") + "</td></tr>");
        sb.AppendLine("<tr><td>Collection Duration</td><td>" + snapshot.Metadata.CollectionDurationMs + " ms</td></tr>");
        sb.AppendLine("<tr><td>Tool Version</td><td>" + HtmlEncode(snapshot.Metadata.ToolVersion) + "</td></tr>");
        sb.AppendLine("</table>");

        // Quick stats
        sb.AppendLine("<h2>Quick Stats</h2>");
        sb.AppendLine("<table class='properties-table'>");
        
        if (snapshot.Processor != null)
        {
            var cpuClass = snapshot.Processor.OverallUsagePercent > 80 ? "metric-critical" : 
                          snapshot.Processor.OverallUsagePercent > 60 ? "metric-warning" : "metric-good";
            sb.AppendLine($"<tr><td>CPU Usage</td><td class='{cpuClass}'>{snapshot.Processor.OverallUsagePercent:F1}%</td></tr>");
        }
        
        if (snapshot.Memory != null)
        {
            var memClass = snapshot.Memory.UsedPercent > 85 ? "metric-critical" : 
                          snapshot.Memory.UsedPercent > 70 ? "metric-warning" : "metric-good";
            sb.AppendLine($"<tr><td>Memory Usage</td><td class='{memClass}'>{snapshot.Memory.UsedPercent:F1}% ({snapshot.Memory.AvailableGB:F1} GB available)</td></tr>");
        }
        
        if (snapshot.Uptime != null)
        {
            sb.AppendLine($"<tr><td>Uptime</td><td>{snapshot.Uptime.CurrentUptimeDays:F1} days (since {snapshot.Uptime.LastBootTime:yyyy-MM-dd HH:mm})</td></tr>");
        }
        
        if (snapshot.Alerts?.Count > 0)
        {
            var criticalCount = snapshot.Alerts.Count(a => a.Severity == AlertSeverity.Critical);
            var warningCount = snapshot.Alerts.Count(a => a.Severity == AlertSeverity.Warning);
            var alertClass = criticalCount > 0 ? "metric-critical" : warningCount > 0 ? "metric-warning" : "metric-good";
            sb.AppendLine($"<tr><td>Active Alerts</td><td class='{alertClass}'>{snapshot.Alerts.Count} ({criticalCount} critical, {warningCount} warning)</td></tr>");
        }
        
        sb.AppendLine("</table>");
    }

    private void RenderProcessorContent(StringBuilder sb, ProcessorData processor)
    {
        sb.AppendLine("<h2>Processor Metrics</h2>");
        sb.AppendLine("<table class='properties-table'>");
        sb.AppendLine($"<tr><td>Overall Usage</td><td>{processor.OverallUsagePercent:F1}%</td></tr>");
        sb.AppendLine($"<tr><td>Time Above Threshold</td><td>{processor.TimeAboveThresholdSeconds} seconds</td></tr>");
        sb.AppendLine($"<tr><td>1-Minute Average</td><td>{processor.Averages.OneMinute:F1}%</td></tr>");
        sb.AppendLine($"<tr><td>5-Minute Average</td><td>{processor.Averages.FiveMinute:F1}%</td></tr>");
        sb.AppendLine($"<tr><td>15-Minute Average</td><td>{processor.Averages.FifteenMinute:F1}%</td></tr>");
        sb.AppendLine("</table>");

        // Export CPU usage history as JavaScript array
        if (processor.CpuUsageHistory?.Count > 0)
        {
            var periodSeconds = (int)(DateTime.UtcNow - processor.CpuUsageHistory.First().Timestamp).TotalSeconds;
            sb.AppendLine($"<h3>CPU Usage History (last {periodSeconds} seconds)</h3>");
            sb.AppendLine("<script>");
            sb.AppendLine("var cpuUsageHistory = [");
            for (int i = 0; i < processor.CpuUsageHistory.Count; i++)
            {
                var m = processor.CpuUsageHistory[i];
                sb.Append($"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}");
                if (i < processor.CpuUsageHistory.Count - 1) sb.Append(",");
                sb.AppendLine();
            }
            sb.AppendLine("];");
            sb.AppendLine("</script>");
            sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>{processor.CpuUsageHistory.Count} measurements over {periodSeconds} seconds</p>");
        }

        if (processor.PerCoreUsage?.Count > 0)
        {
            sb.AppendLine("<h3>Per-Core Usage</h3>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Core</th><th>Usage %</th></tr>");
            for (int i = 0; i < processor.PerCoreUsage.Count; i++)
            {
                var usage = processor.PerCoreUsage[i];
                var cssClass = usage > 90 ? "metric-critical" : usage > 70 ? "metric-warning" : "";
                sb.AppendLine($"<tr><td>Core {i}</td><td class='{cssClass}'>{usage:F1}%</td></tr>");
            }
            sb.AppendLine("</table>");
        }

        if (processor.TopProcesses?.Count > 0)
        {
            sb.AppendLine("<h3>Top Processes by CPU</h3>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Process Name</th><th>PID</th><th>CPU %</th><th>Memory (MB)</th></tr>");
            foreach (var process in processor.TopProcesses)
            {
                sb.AppendLine($"<tr><td>{HtmlEncode(process.Name)}</td><td>{process.Pid}</td><td>{process.CpuPercent:F1}%</td><td>{process.MemoryMB:N0}</td></tr>");
            }
            sb.AppendLine("</table>");
        }
    }

    private void RenderMemoryContent(StringBuilder sb, MemoryData memory)
    {
        sb.AppendLine("<h2>Memory Metrics</h2>");
        sb.AppendLine("<table class='properties-table'>");
        sb.AppendLine($"<tr><td>Total Memory</td><td>{memory.TotalGB:F2} GB</td></tr>");
        sb.AppendLine($"<tr><td>Available Memory</td><td>{memory.AvailableGB:F2} GB</td></tr>");
        sb.AppendLine($"<tr><td>Used Percent</td><td>{memory.UsedPercent:F1}%</td></tr>");
        sb.AppendLine($"<tr><td>Time Above Threshold</td><td>{memory.TimeAboveThresholdSeconds} seconds</td></tr>");
        sb.AppendLine("</table>");

        // Export memory usage history as JavaScript array
        if (memory.MemoryUsageHistory?.Count > 0)
        {
            var periodSeconds = (int)(DateTime.UtcNow - memory.MemoryUsageHistory.First().Timestamp).TotalSeconds;
            sb.AppendLine($"<h3>Memory Usage History (last {periodSeconds} seconds)</h3>");
            sb.AppendLine("<script>");
            sb.AppendLine("var memoryUsageHistory = [");
            for (int i = 0; i < memory.MemoryUsageHistory.Count; i++)
            {
                var m = memory.MemoryUsageHistory[i];
                sb.Append($"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}");
                if (i < memory.MemoryUsageHistory.Count - 1) sb.Append(",");
                sb.AppendLine();
            }
            sb.AppendLine("];");
            sb.AppendLine("</script>");
            sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>{memory.MemoryUsageHistory.Count} measurements over {periodSeconds} seconds</p>");
        }

        if (memory.TopProcesses?.Count > 0)
        {
            sb.AppendLine("<h3>Top Processes by Memory</h3>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Process Name</th><th>PID</th><th>CPU %</th><th>Memory (MB)</th></tr>");
            foreach (var process in memory.TopProcesses)
            {
                sb.AppendLine($"<tr><td>{HtmlEncode(process.Name)}</td><td>{process.Pid}</td><td>{process.CpuPercent:F1}%</td><td>{process.MemoryMB:N0}</td></tr>");
            }
            sb.AppendLine("</table>");
        }
    }

    private void RenderVirtualMemoryContent(StringBuilder sb, VirtualMemoryData virtualMemory)
    {
        sb.AppendLine("<h2>Virtual Memory (Page File) Metrics</h2>");
        sb.AppendLine("<table class='properties-table'>");
        sb.AppendLine($"<tr><td>Total Page File</td><td>{virtualMemory.TotalGB:F2} GB</td></tr>");
        sb.AppendLine($"<tr><td>Available Page File</td><td>{virtualMemory.AvailableGB:F2} GB</td></tr>");
        sb.AppendLine($"<tr><td>Used Percent</td><td>{virtualMemory.UsedPercent:F1}%</td></tr>");
        sb.AppendLine($"<tr><td>Paging Rate</td><td>{virtualMemory.PagingRatePerSec:F1} pages/sec</td></tr>");
        sb.AppendLine($"<tr><td>Time Above Threshold</td><td>{virtualMemory.TimeAboveThresholdSeconds} seconds</td></tr>");
        sb.AppendLine("</table>");

        // Export virtual memory usage history as JavaScript array
        if (virtualMemory.VirtualMemoryUsageHistory?.Count > 0)
        {
            var periodSeconds = (int)(DateTime.UtcNow - virtualMemory.VirtualMemoryUsageHistory.First().Timestamp).TotalSeconds;
            sb.AppendLine($"<h3>Virtual Memory Usage History (last {periodSeconds} seconds)</h3>");
            sb.AppendLine("<script>");
            sb.AppendLine("var virtualMemoryUsageHistory = [");
            for (int i = 0; i < virtualMemory.VirtualMemoryUsageHistory.Count; i++)
            {
                var m = virtualMemory.VirtualMemoryUsageHistory[i];
                sb.Append($"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}");
                if (i < virtualMemory.VirtualMemoryUsageHistory.Count - 1) sb.Append(",");
                sb.AppendLine();
            }
            sb.AppendLine("];");
            sb.AppendLine("</script>");
            sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>{virtualMemory.VirtualMemoryUsageHistory.Count} measurements over {periodSeconds} seconds</p>");
        }
    }

    private void RenderDisksContent(StringBuilder sb, DiskData disks)
    {
        if (disks.Space?.Count > 0)
        {
            sb.AppendLine("<h2>Disk Space</h2>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Drive</th><th>Total (GB)</th><th>Available (GB)</th><th>Used %</th><th>File System</th></tr>");
            foreach (var disk in disks.Space)
            {
                var cssClass = disk.UsedPercent > 90 ? "metric-critical" : disk.UsedPercent > 80 ? "metric-warning" : "";
                sb.AppendLine($"<tr><td>{HtmlEncode(disk.Drive)}</td><td>{disk.TotalGB:F2}</td><td>{disk.AvailableGB:F2}</td><td class='{cssClass}'>{disk.UsedPercent:F1}%</td><td>{HtmlEncode(disk.FileSystem)}</td></tr>");
            }
            sb.AppendLine("</table>");
        }

        if (disks.Usage?.Count > 0)
        {
            sb.AppendLine("<h2>Disk I/O Performance</h2>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Drive</th><th>Queue Length</th><th>Avg Response Time (ms)</th><th>IOPS</th><th>Time Above Threshold (s)</th></tr>");
            foreach (var disk in disks.Usage)
            {
                sb.AppendLine($"<tr><td>{HtmlEncode(disk.Drive)}</td><td>{disk.QueueLength:F2}</td><td>{disk.AvgResponseTimeMs:F2}</td><td>{disk.Iops:F0}</td><td>{disk.TimeAboveThresholdSeconds}</td></tr>");
            }
            sb.AppendLine("</table>");

            // Export disk usage history as JavaScript arrays
            foreach (var disk in disks.Usage)
            {
                var driveKey = disk.Drive.Replace(":", "").Replace("\\", "_");
                
                if (disk.QueueLengthHistory?.Count > 0)
                {
                    var periodSeconds = (int)(DateTime.UtcNow - disk.QueueLengthHistory.First().Timestamp).TotalSeconds;
                    sb.AppendLine($"<h3>Disk {disk.Drive} Queue Length History (last {periodSeconds} seconds)</h3>");
                    sb.AppendLine("<script>");
                    sb.AppendLine($"var disk_{driveKey}_QueueLengthHistory = [");
                    for (int i = 0; i < disk.QueueLengthHistory.Count; i++)
                    {
                        var m = disk.QueueLengthHistory[i];
                        sb.Append($"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}");
                        if (i < disk.QueueLengthHistory.Count - 1) sb.Append(",");
                        sb.AppendLine();
                    }
                    sb.AppendLine("];");
                    sb.AppendLine("</script>");
                    sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>{disk.QueueLengthHistory.Count} measurements over {periodSeconds} seconds</p>");
                }

                if (disk.ResponseTimeHistory?.Count > 0)
                {
                    var periodSeconds = (int)(DateTime.UtcNow - disk.ResponseTimeHistory.First().Timestamp).TotalSeconds;
                    sb.AppendLine($"<h3>Disk {disk.Drive} Response Time History (last {periodSeconds} seconds)</h3>");
                    sb.AppendLine("<script>");
                    sb.AppendLine($"var disk_{driveKey}_ResponseTimeHistory = [");
                    for (int i = 0; i < disk.ResponseTimeHistory.Count; i++)
                    {
                        var m = disk.ResponseTimeHistory[i];
                        sb.Append($"{{timestamp: new Date('{m.Timestamp:yyyy-MM-ddTHH:mm:ss.fffZ}'), value: {m.Value:F2}}}");
                        if (i < disk.ResponseTimeHistory.Count - 1) sb.Append(",");
                        sb.AppendLine();
                    }
                    sb.AppendLine("];");
                    sb.AppendLine("</script>");
                    sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>{disk.ResponseTimeHistory.Count} measurements over {periodSeconds} seconds</p>");
                }
            }
        }
    }

    private void RenderNetworkContent(StringBuilder sb, List<NetworkHostData> network)
    {
        sb.AppendLine("<h2>Network Connectivity</h2>");
        sb.AppendLine("<table>");
        sb.AppendLine("<tr><th>Hostname</th><th>Ping (ms)</th><th>Packet Loss %</th><th>DNS Resolution (ms)</th><th>Consecutive Failures</th><th>Port Status</th></tr>");
        
        foreach (var host in network)
        {
            var failureClass = host.ConsecutiveFailures > 0 ? "metric-critical" : "";
            var portStatus = host.PortStatus.Count > 0 
                ? string.Join(", ", host.PortStatus.Select(p => $"{p.Key}:{p.Value}"))
                : "N/A";
            
            sb.AppendLine($"<tr><td>{HtmlEncode(host.Hostname)}</td>" +
                         $"<td>{(host.PingMs.HasValue ? $"{host.PingMs.Value:F1}" : "N/A")}</td>" +
                         $"<td>{host.PacketLossPercent:F1}%</td>" +
                         $"<td>{(host.DnsResolutionMs.HasValue ? $"{host.DnsResolutionMs.Value:F1}" : "N/A")}</td>" +
                         $"<td class='{failureClass}'>{host.ConsecutiveFailures}</td>" +
                         $"<td>{HtmlEncode(portStatus)}</td></tr>");
        }
        
        sb.AppendLine("</table>");
    }

    private void RenderUptimeContent(StringBuilder sb, UptimeData uptime)
    {
        sb.AppendLine("<h2>System Uptime</h2>");
        sb.AppendLine("<table class='properties-table'>");
        sb.AppendLine($"<tr><td>Last Boot Time</td><td>{uptime.LastBootTime:yyyy-MM-dd HH:mm:ss}</td></tr>");
        sb.AppendLine($"<tr><td>Current Uptime</td><td>{uptime.CurrentUptimeDays:F2} days</td></tr>");
        sb.AppendLine($"<tr><td>Unexpected Reboot</td><td>{(uptime.UnexpectedReboot ? "<span class='metric-critical'>YES</span>" : "<span class='metric-good'>No</span>")}</td></tr>");
        sb.AppendLine("</table>");
    }

    private void RenderWindowsUpdatesContent(StringBuilder sb, WindowsUpdateData updates)
    {
        sb.AppendLine("<h2>Windows Update Status</h2>");
        sb.AppendLine("<table class='properties-table'>");
        sb.AppendLine($"<tr><td>Pending Updates</td><td>{updates.PendingCount}</td></tr>");
        
        var securityClass = updates.SecurityUpdates > 0 ? "metric-critical" : "metric-good";
        sb.AppendLine($"<tr><td>Security Updates</td><td class='{securityClass}'>{updates.SecurityUpdates}</td></tr>");
        
        var criticalClass = updates.CriticalUpdates > 0 ? "metric-critical" : "metric-good";
        sb.AppendLine($"<tr><td>Critical Updates</td><td class='{criticalClass}'>{updates.CriticalUpdates}</td></tr>");
        
        var failedClass = updates.FailedUpdates > 0 ? "metric-warning" : "metric-good";
        sb.AppendLine($"<tr><td>Failed Updates</td><td class='{failedClass}'>{updates.FailedUpdates}</td></tr>");
        
        sb.AppendLine($"<tr><td>Last Install Date</td><td>{(updates.LastInstallDate.HasValue ? updates.LastInstallDate.Value.ToString("yyyy-MM-dd HH:mm:ss") : "Never")}</td></tr>");
        sb.AppendLine("</table>");
    }

    private void RenderEventsContent(StringBuilder sb, List<EventData> events)
    {
        sb.AppendLine("<h2>Recent Event Log Entries</h2>");
        sb.AppendLine("<table>");
        sb.AppendLine("<tr><th>Event ID</th><th>Source</th><th>Level</th><th>Count</th><th>Last Occurrence</th><th>Message</th></tr>");
        
        foreach (var evt in events.OrderByDescending(e => e.LastOccurrence))
        {
            var levelClass = evt.Level.ToLower() switch
            {
                "critical" => "metric-critical",
                "error" => "metric-critical",
                "warning" => "metric-warning",
                _ => ""
            };
            
            sb.AppendLine($"<tr><td>{evt.EventId}</td>" +
                         $"<td>{HtmlEncode(evt.Source)}</td>" +
                         $"<td class='{levelClass}'>{HtmlEncode(evt.Level)}</td>" +
                         $"<td>{evt.Count}</td>" +
                         $"<td>{(evt.LastOccurrence.HasValue ? evt.LastOccurrence.Value.ToString("yyyy-MM-dd HH:mm:ss") : "N/A")}</td>" +
                         $"<td>{HtmlEncode(TruncateString(evt.Message, 200))}</td></tr>");
        }
        
        sb.AppendLine("</table>");
        sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>Total: {events.Count} event types</p>");
    }

    private void RenderScheduledTasksContent(StringBuilder sb, List<ScheduledTaskData> tasks)
    {
        sb.AppendLine("<h2>Scheduled Tasks Status</h2>");
        sb.AppendLine("<table>");
        sb.AppendLine("<tr><th>Task Path</th><th>Task Name</th><th>State</th><th>Enabled</th><th>Run As User</th><th>Last Run</th><th>Last Result</th><th>Next Run</th><th>Missed Runs</th></tr>");
        
        foreach (var task in tasks)
        {
            var lastRun = task.LastRunTime.HasValue ? task.LastRunTime.Value.ToString("yyyy-MM-dd HH:mm:ss") : "Never";
            var nextRun = task.NextRunTime.HasValue ? task.NextRunTime.Value.ToString("yyyy-MM-dd HH:mm:ss") : "Not scheduled";
            var enabledClass = task.IsEnabled ? "metric-good" : "metric-warning";
            var stateClass = task.State == "Running" ? "metric-good" : 
                            task.State == "Ready" ? "metric-info" : "metric-warning";
            var resultClass = task.LastRunResult.HasValue && task.LastRunResult.Value == 0 ? "metric-good" : 
                            task.LastRunResult.HasValue ? "metric-error" : "metric-info";
            var lastResult = task.LastRunResult.HasValue ? task.LastRunResult.Value.ToString() : "N/A";
            var runAsUser = !string.IsNullOrEmpty(task.RunAsUser) ? HtmlEncode(task.RunAsUser) : "N/A";
            
            sb.AppendLine($"<tr>" +
                         $"<td>{HtmlEncode(task.TaskPath)}</td>" +
                         $"<td>{HtmlEncode(task.TaskName)}</td>" +
                         $"<td class='{stateClass}'>{HtmlEncode(task.State)}</td>" +
                         $"<td class='{enabledClass}'>{(task.IsEnabled ? "Yes" : "No")}</td>" +
                         $"<td>{runAsUser}</td>" +
                         $"<td>{lastRun}</td>" +
                         $"<td class='{resultClass}'>{lastResult}</td>" +
                         $"<td>{nextRun}</td>" +
                         $"<td>{(task.MissedRuns > 0 ? task.MissedRuns.ToString() : "0")}</td>" +
                         $"</tr>");
        }
        
        sb.AppendLine("</table>");
        sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>Total: {tasks.Count} tasks</p>");
    }

    private void RenderDb2DiagnosticsContent(StringBuilder sb, Db2DiagData db2Data)
    {
        sb.AppendLine("<h2>DB2 Diagnostic Log Monitoring</h2>");
        
        // Summary section
        sb.AppendLine("<div class='metric-group'>");
        sb.AppendLine($"<div class='metric'><span class='metric-label'>Status:</span> <span class='metric-value metric-good'>Active</span></div>");
        sb.AppendLine($"<div class='metric'><span class='metric-label'>Last Check:</span> <span class='metric-value'>{db2Data.LastCheck:yyyy-MM-dd HH:mm:ss} UTC</span></div>");
        sb.AppendLine($"<div class='metric'><span class='metric-label'>Instances:</span> <span class='metric-value'>{db2Data.InstanceCount} ({string.Join(", ", db2Data.Instances.Distinct())})</span></div>");
        sb.AppendLine($"<div class='metric'><span class='metric-label'>Entries Last Cycle:</span> <span class='metric-value'>{db2Data.EntriesProcessedLastCycle}</span></div>");
        sb.AppendLine($"<div class='metric'><span class='metric-label'>Alerts Last Cycle:</span> <span class='metric-value'>{db2Data.AlertsGeneratedLastCycle}</span></div>");
        sb.AppendLine($"<div class='metric'><span class='metric-label'>Total In Memory:</span> <span class='metric-value'>{db2Data.TotalEntriesInMemory}</span></div>");
        sb.AppendLine("</div>");
        
        // All entries table (full metadata)
        if (db2Data.AllEntries?.Count > 0)
        {
            sb.AppendLine("<h3>All DB2 Diagnostic Entries</h3>");
            sb.AppendLine("<p style='color: #666; font-size: 0.9em;'>Showing all entries stored in memory since process start</p>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Timestamp</th><th>Instance</th><th>Level</th><th>Database</th><th>Function</th><th>Message</th><th>Return Code</th><th>Description</th></tr>");
            
            foreach (var entry in db2Data.AllEntries.OrderByDescending(e => e.TimestampParsed))
            {
                var levelClass = entry.Level.ToUpperInvariant() switch
                {
                    "CRITICAL" => "metric-error",
                    "SEVERE" => "metric-error",
                    "ERROR" => "metric-error",
                    "WARNING" => "metric-warning",
                    _ => "metric-info"
                };
                
                var timestamp = entry.TimestampParsed?.ToString("yyyy-MM-dd HH:mm:ss") ?? entry.Timestamp;
                var description = entry.Description?.ZrcCode?.Description 
                               ?? entry.Description?.MessageInfo?.Description 
                               ?? entry.Description?.LevelInfo?.Description 
                               ?? "";
                
                sb.AppendLine($"<tr>" +
                             $"<td>{HtmlEncode(timestamp)}</td>" +
                             $"<td>{HtmlEncode(entry.InstanceName)}</td>" +
                             $"<td class='{levelClass}'>{HtmlEncode(entry.Level)}</td>" +
                             $"<td>{HtmlEncode(entry.DatabaseName ?? "N/A")}</td>" +
                             $"<td title='{HtmlEncode(entry.Function ?? "")}'>{HtmlEncode(TruncateString(entry.Function ?? "", 40))}</td>" +
                             $"<td title='{HtmlEncode(entry.Message ?? "")}'>{HtmlEncode(TruncateString(entry.Message ?? "", 80))}</td>" +
                             $"<td>{HtmlEncode(entry.ReturnCode ?? "")}</td>" +
                             $"<td title='{HtmlEncode(description)}'>{HtmlEncode(TruncateString(description, 60))}</td>" +
                             $"</tr>");
            }
            
            sb.AppendLine("</table>");
            sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>Total: {db2Data.AllEntries.Count} entries</p>");
        }
        else if (db2Data.RecentEntries?.Count > 0)
        {
            // Fallback to recent entries if AllEntries not available
            sb.AppendLine("<h3>Recent DB2 Diagnostic Entries (Last 10)</h3>");
            sb.AppendLine("<table>");
            sb.AppendLine("<tr><th>Timestamp</th><th>Instance</th><th>Level</th><th>Database</th><th>Message</th></tr>");
            
            foreach (var entry in db2Data.RecentEntries)
            {
                var levelClass = entry.Level.ToUpperInvariant() switch
                {
                    "CRITICAL" or "SEVERE" or "ERROR" => "metric-error",
                    "WARNING" => "metric-warning",
                    _ => "metric-info"
                };
                
                var timestamp = entry.TimestampParsed?.ToString("yyyy-MM-dd HH:mm:ss") ?? entry.Timestamp;
                
                sb.AppendLine($"<tr>" +
                             $"<td>{HtmlEncode(timestamp)}</td>" +
                             $"<td>{HtmlEncode(entry.InstanceName)}</td>" +
                             $"<td class='{levelClass}'>{HtmlEncode(entry.Level)}</td>" +
                             $"<td>{HtmlEncode(entry.DatabaseName ?? "N/A")}</td>" +
                            $"<td>{HtmlEncode(TruncateString(entry.Message ?? "", 100))}</td>" +
                             $"</tr>");
            }
            
            sb.AppendLine("</table>");
        }
        else
        {
            sb.AppendLine("<p style='color: #666;'>No diagnostic entries recorded yet.</p>");
        }
        
        // Entry details section (expandable metadata)
        if (db2Data.AllEntries?.Count > 0)
        {
            sb.AppendLine("<h3>Entry Details (Full Metadata)</h3>");
            sb.AppendLine("<p style='color: #666; font-size: 0.9em;'>Click to expand entry details</p>");
            
            var entryIndex = 0;
            foreach (var entry in db2Data.AllEntries.OrderByDescending(e => e.TimestampParsed).Take(50))
            {
                var timestamp = entry.TimestampParsed?.ToString("yyyy-MM-dd HH:mm:ss") ?? entry.Timestamp;
                var levelClass = entry.Level.ToUpperInvariant() switch
                {
                    "CRITICAL" or "SEVERE" or "ERROR" => "alert-critical",
                    "WARNING" => "alert-warning",
                    _ => "alert-info"
                };
                
                sb.AppendLine($"<details style='margin-bottom: 10px; border: 1px solid #ddd; padding: 10px; border-radius: 5px;'>");
                sb.AppendLine($"<summary class='{levelClass}' style='cursor: pointer; font-weight: bold;'>");
                sb.AppendLine($"[{entry.Level}] {timestamp} - {entry.InstanceName}/{entry.DatabaseName ?? "N/A"}: {TruncateString(entry.Message ?? "", 60)}");
                sb.AppendLine("</summary>");
                sb.AppendLine("<div style='margin-top: 10px; padding: 10px; background: #f9f9f9; font-family: monospace; font-size: 0.85em;'>");
                sb.AppendLine("<table style='width: 100%; border-collapse: collapse;'>");
                sb.AppendLine($"<tr><td style='width: 150px; font-weight: bold;'>Record ID</td><td>{HtmlEncode(entry.RecordId)}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>DB2 Timestamp</td><td>{HtmlEncode(entry.Timestamp)}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Parsed Time</td><td>{timestamp}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Instance</td><td>{HtmlEncode(entry.InstanceName)}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Database</td><td>{HtmlEncode(entry.DatabaseName ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Level</td><td>{HtmlEncode(entry.Level)} (Priority: {entry.LevelPriority?.ToString() ?? "N/A"})</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Process ID</td><td>{HtmlEncode(entry.ProcessId ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Thread ID</td><td>{HtmlEncode(entry.ThreadId ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Process Name</td><td>{HtmlEncode(entry.ProcessName ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>App Handle</td><td>{HtmlEncode(entry.ApplicationHandle ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>App ID</td><td>{HtmlEncode(entry.ApplicationId ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Auth ID</td><td>{HtmlEncode(entry.AuthorizationId ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Hostname</td><td>{HtmlEncode(entry.HostName ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Function</td><td>{HtmlEncode(entry.Function ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Return Code</td><td>{HtmlEncode(entry.ReturnCode ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Called Function</td><td>{HtmlEncode(entry.CalledFunction ?? "N/A")}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Source Line</td><td>{entry.SourceLineNumber} - {entry.EndLineNumber}</td></tr>");
                sb.AppendLine($"<tr><td style='font-weight: bold;'>Message</td><td style='word-wrap: break-word;'>{HtmlEncode(entry.Message ?? "N/A")}</td></tr>");
                
                // Description info
                if (entry.Description != null)
                {
                    if (entry.Description.ZrcCode != null)
                    {
                        sb.AppendLine($"<tr><td style='font-weight: bold;'>ZRC Description</td><td>{HtmlEncode(entry.Description.ZrcCode.Description ?? "N/A")} (Category: {HtmlEncode(entry.Description.ZrcCode.Category ?? "N/A")})</td></tr>");
                    }
                    if (entry.Description.ProbeCode != null)
                    {
                        sb.AppendLine($"<tr><td style='font-weight: bold;'>Probe Description</td><td>{HtmlEncode(entry.Description.ProbeCode.Description ?? "N/A")} (Component: {HtmlEncode(entry.Description.ProbeCode.Component ?? "N/A")})</td></tr>");
                    }
                    if (entry.Description.MessageInfo != null)
                    {
                        sb.AppendLine($"<tr><td style='font-weight: bold;'>Message Info</td><td>{HtmlEncode(entry.Description.MessageInfo.Description ?? "N/A")}</td></tr>");
                        if (!string.IsNullOrEmpty(entry.Description.MessageInfo.Recommendation))
                        {
                            sb.AppendLine($"<tr><td style='font-weight: bold;'>Recommendation</td><td>{HtmlEncode(entry.Description.MessageInfo.Recommendation)}</td></tr>");
                        }
                    }
                    if (entry.Description.LevelInfo != null)
                    {
                        sb.AppendLine($"<tr><td style='font-weight: bold;'>Level Info</td><td>{HtmlEncode(entry.Description.LevelInfo.Description ?? "N/A")} - Action: {HtmlEncode(entry.Description.LevelInfo.Action ?? "N/A")}</td></tr>");
                    }
                }
                
                sb.AppendLine("</table>");
                sb.AppendLine("</div>");
                sb.AppendLine("</details>");
                
                entryIndex++;
            }
            
            if (db2Data.AllEntries.Count > 50)
            {
                sb.AppendLine($"<p style='color: #666; font-style: italic;'>Showing first 50 of {db2Data.AllEntries.Count} entries. See JSON export for complete data.</p>");
            }
        }
    }

    private void RenderAlertsContent(StringBuilder sb, List<Alert> alerts)
    {
        sb.AppendLine("<h2>Active Alerts</h2>");
        
        var groupedAlerts = alerts.GroupBy(a => a.Severity).OrderByDescending(g => g.Key);
        
        foreach (var group in groupedAlerts)
        {
            var alertClass = group.Key switch
            {
                AlertSeverity.Critical => "alert-critical",
                AlertSeverity.Warning => "alert-warning",
                _ => "alert-info"
            };
            
            sb.AppendLine($"<h3>{group.Key} ({group.Count()})</h3>");
            
            foreach (var alert in group.OrderByDescending(a => a.Timestamp))
            {
                sb.AppendLine($"<div class='alert-box {alertClass}'>");
                sb.AppendLine($"    <strong>{HtmlEncode(alert.Category)}</strong>: {HtmlEncode(alert.Message)}");
                sb.AppendLine($"    <br><small>{alert.Timestamp:yyyy-MM-dd HH:mm:ss UTC} | Server: {HtmlEncode(alert.ServerName)}</small>");
                if (!string.IsNullOrEmpty(alert.Details))
                {
                    sb.AppendLine($"    <br><small>Details: {HtmlEncode(alert.Details)}</small>");
                }
                sb.AppendLine("</div>");
            }
        }
        
        sb.AppendLine($"<p style='color: #666; font-size: 0.9em; margin-top: 20px;'>Total: {alerts.Count} alerts</p>");
    }

    private void RenderExternalEventsContent(StringBuilder sb, List<ExternalEvent> externalEvents)
    {
        sb.AppendLine("<h2>External Events</h2>");
        sb.AppendLine("<table>");
        sb.AppendLine("<tr><th>Event Code</th><th>Severity</th><th>Category</th><th>Message</th><th>Source</th><th>Server</th><th>Alert Timestamp</th><th>Registered Timestamp</th><th>Metadata</th><th>Surveillance</th></tr>");
        
        foreach (var evt in externalEvents.OrderByDescending(e => e.RegisteredTimestamp))
        {
            var severityClass = evt.Severity switch
            {
                AlertSeverity.Critical => "metric-critical",
                AlertSeverity.Warning => "metric-warning",
                _ => ""
            };
            
            var metadataStr = evt.Metadata != null && evt.Metadata.Count > 0
                ? string.Join(", ", evt.Metadata.Select(kvp => $"{kvp.Key}={kvp.Value}"))
                : "None";
            
            var surveillanceStr = $"MaxOccurrences: {evt.Surveillance.MaxOccurrences}, TimeWindow: {evt.Surveillance.TimeWindowMinutes}min";
            if (evt.Surveillance.SuppressedChannels != null && evt.Surveillance.SuppressedChannels.Count > 0)
            {
                surveillanceStr += $", Suppressed: {string.Join(", ", evt.Surveillance.SuppressedChannels)}";
            }
            
            sb.AppendLine($"<tr>" +
                         $"<td><strong>{HtmlEncode(evt.ExternalEventCode)}</strong></td>" +
                         $"<td class='{severityClass}'>{HtmlEncode(evt.Severity.ToString())}</td>" +
                         $"<td>{HtmlEncode(evt.Category)}</td>" +
                         $"<td>{HtmlEncode(TruncateString(evt.Message, 100))}</td>" +
                         $"<td>{HtmlEncode(evt.Source ?? "N/A")}</td>" +
                         $"<td>{HtmlEncode(evt.ServerName)}</td>" +
                         $"<td>{evt.AlertTimestamp:yyyy-MM-dd HH:mm:ss UTC}</td>" +
                         $"<td>{evt.RegisteredTimestamp:yyyy-MM-dd HH:mm:ss UTC}</td>" +
                         $"<td><small>{HtmlEncode(TruncateString(metadataStr, 150))}</small></td>" +
                         $"<td><small>{HtmlEncode(surveillanceStr)}</small></td>" +
                         $"</tr>");
        }
        
        sb.AppendLine("</table>");
        sb.AppendLine($"<p style='color: #666; font-size: 0.9em;'>Total: {externalEvents.Count} external events</p>");
    }

    private static string HtmlEncode(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        return System.Net.WebUtility.HtmlEncode(text);
    }

    private static string TruncateString(string text, int maxLength)
    {
        if (string.IsNullOrEmpty(text) || text.Length <= maxLength)
            return text;
        return text.Substring(0, maxLength) + "...";
    }
}

