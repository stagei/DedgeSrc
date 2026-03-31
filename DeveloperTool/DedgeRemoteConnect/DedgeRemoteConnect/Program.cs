using System.Threading;

namespace DedgeRemoteConnect;

static class Program
{
    // Use a unique identifier for your application
    private static readonly string MutexName = "Global\\DedgeRemoteConnectSingleInstance";
    private static Mutex? _mutex;

    [STAThread]
    static void Main()
    {
        // Try to create a named mutex
        bool createdNew;
        _mutex = new Mutex(true, MutexName, out createdNew);

        // If the mutex already exists, another instance is running
        if (!createdNew)
        {
            MessageBox.Show("FK Remote Connect is already running.", 
                "Application Running", 
                MessageBoxButtons.OK, 
                MessageBoxIcon.Information);
            return; // Exit the application
        }

        try
        {
            // Continue with normal application startup
            ApplicationConfiguration.Initialize();
            
            // Invert the icon
            string sourceIcon = "Resources/dedge.ico";
            
            Application.Run(new DedgeRemoteConnectContext(sourceIcon));
        }
        finally
        {
            // Release the mutex when the application exits
            _mutex.ReleaseMutex();
            _mutex.Dispose();
        }
    }
}