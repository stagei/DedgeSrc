using System.Diagnostics;

namespace IIS_AutoDeploy.Tray;

static class Program
{
    [STAThread]
    static void Main()
    {
        // Ensure single instance
        using var mutex = new Mutex(true, "IIS-AutoDeploy-Tray_SingleInstance", out bool createdNew);

        if (!createdNew)
        {
            // Already running - exit silently
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.SystemAware);

        try
        {
            Application.Run(new AutoDeployTrayContext());
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Fatal error: {ex}");
            MessageBox.Show($"Fatal error: {ex.Message}", "IIS Auto-Deploy Tray Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
