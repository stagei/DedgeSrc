namespace ServerMonitorTrayIcon;

/// <summary>
/// Entry point for the ServerMonitor Tray Icon application
/// </summary>
static class Program
{
    /// <summary>
    /// The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        // Ensure single instance - silently exit if already running
        using var mutex = new Mutex(true, "ServerMonitorTrayIcon_SingleInstance", out bool createdNew);
        
        if (!createdNew)
        {
            // Already running - exit silently without popup
            return;
        }

        // Enable visual styles for modern UI
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.SystemAware);

        // Run with custom application context (for tray icon support)
        Application.Run(new TrayIconApplicationContext());
    }
}
