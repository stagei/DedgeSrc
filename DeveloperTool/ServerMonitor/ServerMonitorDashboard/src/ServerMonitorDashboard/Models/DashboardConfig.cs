namespace ServerMonitorDashboard.Models;

/// <summary>
/// Configuration settings for the Dashboard application
/// </summary>
public class DashboardConfig
{
    public string ComputerInfoPath { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json";
    public string ServerMonitorExePath { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitor.exe";
    public string ReinstallTriggerPath { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\ReinstallServerMonitor.txt";
    public int ServerMonitorPort { get; set; } = 8999;
    public int StatusPollIntervalSeconds { get; set; } = 5;
    public int SnapshotTimeoutSeconds { get; set; } = 10;
    public int MinRefreshIntervalSeconds { get; set; } = 10;
    
    /// <summary>
    /// UNC path to the directory containing historical snapshot JSON files
    /// </summary>
    public string SnapshotDirectory { get; set; } = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServerMonitor";

    /// <summary>
    /// Alert polling configuration for monitoring alerts across servers
    /// </summary>
    public AlertPollingConfig AlertPolling { get; set; } = new();
}
