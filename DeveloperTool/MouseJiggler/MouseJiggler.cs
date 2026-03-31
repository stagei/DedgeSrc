using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using NLog;
using System.Runtime.Versioning;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Enumeration;
using Microsoft.Win32;
using System.IO;
using System.Threading;
using System.Diagnostics;

namespace MouseJiggler
{
    [SupportedOSPlatform("windows10.0.10240.0")]
    public partial class MouseJiggler : Form
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        [DllImport("user32.dll")]
        static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        static extern bool SetCursorPos(int X, int Y);

        [DllImport("user32.dll")]
        static extern short GetAsyncKeyState(int vKey);

        [DllImport("kernel32.dll")]
        static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);

        [DllImport("user32.dll")]
        static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [Flags]
        public enum EXECUTION_STATE : uint
        {
            ES_AWAYMODE_REQUIRED = 0x00000040,
            ES_CONTINUOUS = 0x80000000,
            ES_DISPLAY_REQUIRED = 0x00000002,
            ES_SYSTEM_REQUIRED = 0x00000001
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
        }

        private System.Windows.Forms.Timer activityCheckTimer = null!;
        private System.Windows.Forms.Timer jiggleTimer = null!;
        private DateTime lastActivityTime;
        private bool isJiggling;
        private POINT lastCursorPosition;
        private NotifyIcon trayIcon = null!;
        private BluetoothLEAdvertisementWatcher? bluetoothWatcher;
        private const string TARGET_DEVICE_NAME = "Geirs iPhone";
        private bool isDeviceInRange;
        private System.Windows.Forms.Timer bluetoothScanTimer = null!;
        private HashSet<string> discoveredDevices = new();
        private const int BLUETOOTH_SCAN_INTERVAL = 10000; // 10 seconds
        private bool isSystemResuming = false;
        private static Mutex? _mutex;
        private const string MutexName = "MouseJigglerSingleInstance";
        private readonly string logFilePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "mousejiggler.log");
        private const byte VK_MENU = 0x12;  // ALT key
        private const byte VK_TAB = 0x09;   // TAB key
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        private System.Windows.Forms.Timer altTabTimer = null!;

        public MouseJiggler()
        {
            try
            {
                // Try to create/open the mutex
                bool createdNew;
                _mutex = new Mutex(true, MutexName, out createdNew);

                if (!createdNew)
                {
                    Logger.Warn("Another instance of MouseJiggler is already running.");
                    MessageBox.Show("MouseJiggler is already running.", "Already Running", 
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    Environment.Exit(1);
                    return;
                }

                Logger.Info("Starting MouseJiggler application...");
                InitializeComponent();

                // Add power event handlers
                SystemEvents.PowerModeChanged += SystemEvents_PowerModeChanged;

                InitializeTrayIcon();
                InitializeBluetoothWatcher();
                lastActivityTime = DateTime.Now;
                isJiggling = false;
                GetCursorPos(out lastCursorPosition);

                // Prevent sleep from the start
                PreventSleep();
                Logger.Info("Sleep prevention enabled at startup");

                // Initialize activity check timer
                activityCheckTimer = new System.Windows.Forms.Timer();
                activityCheckTimer.Interval = 1000; // Check every second
                activityCheckTimer.Tick += ActivityCheckTimer_Tick;
                activityCheckTimer.Start();
                Logger.Info("Activity timer initialized");

                // Initialize jiggle timer
                jiggleTimer = new System.Windows.Forms.Timer();
                jiggleTimer.Interval = 60000; // Jiggle every minute
                jiggleTimer.Tick += JiggleTimer_Tick;
                Logger.Info("Jiggle timer initialized");

                // Initialize Alt+Tab timer
                altTabTimer = new System.Windows.Forms.Timer();
                altTabTimer.Interval = 30000; // 30 seconds
                altTabTimer.Tick += AltTabTimer_Tick;
                Logger.Info("Alt+Tab timer initialized");

                Logger.Info("MouseJiggler initialized successfully.");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error initializing MouseJiggler.");
                MessageBox.Show("Error initializing application. Check the log file for details.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                throw;
            }
        }

        private void InitializeTrayIcon()
        {
            try
            {
                var contextMenuStrip = new ContextMenuStrip();
                
                // Add Open Log menu item
                var openLogMenuItem = new ToolStripMenuItem("Open Log File", null, OpenLogFile);
                contextMenuStrip.Items.Add(openLogMenuItem);
                
                // Add separator
                contextMenuStrip.Items.Add(new ToolStripSeparator());
                
                // Exit menu item
                var exitMenuItem = new ToolStripMenuItem("Exit", null, Exit);
                contextMenuStrip.Items.Add(exitMenuItem);

                // Load custom icon
                string iconPath = Path.Combine(Application.StartupPath, "dEdge.ico");
                Icon customIcon = new Icon(iconPath);

                trayIcon = new NotifyIcon
                {
                    Icon = customIcon,
                    ContextMenuStrip = contextMenuStrip,
                    Visible = true,
                    Text = "Mouse Jiggler"
                };

                Logger.Info($"Custom tray icon loaded successfully from {iconPath}");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Error loading custom tray icon. Falling back to default icon. Path attempted: {Path.Combine(Application.StartupPath, "dEdge.ico")}");
                
                var contextMenuStrip = new ContextMenuStrip();
                
                // Add Open Log menu item
                var openLogMenuItem = new ToolStripMenuItem("Open Log File", null, OpenLogFile);
                contextMenuStrip.Items.Add(openLogMenuItem);
                
                // Add separator
                contextMenuStrip.Items.Add(new ToolStripSeparator());
                
                // Exit menu item
                var exitMenuItem = new ToolStripMenuItem("Exit", null, Exit);
                contextMenuStrip.Items.Add(exitMenuItem);

                trayIcon = new NotifyIcon
                {
                    Icon = SystemIcons.Application,
                    ContextMenuStrip = contextMenuStrip,
                    Visible = true,
                    Text = "Mouse Jiggler"
                };
            }
        }

        private void Exit(object? sender, EventArgs e)
        {
            Logger.Info("User requested to exit the application.");
            trayIcon.Visible = false;
            Application.Exit();
        }

        private void PreventSleep()
        {
            try
            {
                // Only prevent sleep if before 23:50
                if (DateTime.Now.Hour == 23 && DateTime.Now.Minute >= 50)
                {
                    SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
                    Logger.Debug("Sleep prevention disabled - after 23:50");
                }
                else
                {
                    SetThreadExecutionState(
                        EXECUTION_STATE.ES_CONTINUOUS |
                        EXECUTION_STATE.ES_SYSTEM_REQUIRED |
                        EXECUTION_STATE.ES_DISPLAY_REQUIRED |
                        EXECUTION_STATE.ES_AWAYMODE_REQUIRED);
                    Logger.Debug("Sleep prevention maintained (movie mode)");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error setting thread execution state to prevent sleep");
            }
        }

        private void ActivityCheckTimer_Tick(object? sender, EventArgs e)
        {
            try
            {
                // Check if it's time to quit (after 23:50)
                if (DateTime.Now.Hour == 23 && DateTime.Now.Minute >= 50)
                {
                    Logger.Info("Auto-exit triggered - time is after 23:50");
                    Exit(null, EventArgs.Empty);
                    return;
                }

                // Ensure sleep is prevented (in case Windows cleared it)
                PreventSleep();

                if (DetectUserActivity())
                {
                    ResetActivity();
                }
                else if (!isJiggling && (DateTime.Now - lastActivityTime).TotalMinutes >= 3)
                {
                    isJiggling = true;
                    jiggleTimer.Start();
                    altTabTimer.Start();
                    Logger.Info("No activity for 3 minutes. Starting mouse jiggler and Alt+Tab simulation.");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error in ActivityCheckTimer_Tick.");
            }
        }

        private bool DetectUserActivity()
        {
            try
            {
                // Check if target device is in range
                if (isDeviceInRange)
                {
                    Logger.Debug($"Device '{TARGET_DEVICE_NAME}' is in range - considering as activity");
                    return true;
                }

                // Check for mouse movement
                GetCursorPos(out POINT currentPosition);
                if (currentPosition.X != lastCursorPosition.X || currentPosition.Y != lastCursorPosition.Y)
                {
                    lastCursorPosition = currentPosition;
                    Logger.Debug($"Mouse moved to ({currentPosition.X}, {currentPosition.Y})");
                    return true;
                }

                // Check for key presses
                for (int i = 0; i < 256; i++)
                {
                    if (GetAsyncKeyState(i) != 0)
                    {
                        Logger.Debug($"Key press detected: {i}");
                        return true;
                    }
                }

                return false;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error detecting user activity.");
                return false;
            }
        }

        private void JiggleTimer_Tick(object? sender, EventArgs e)
        {
            try
            {
                if (isJiggling)
                {
                    JiggleMouse();
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error in JiggleTimer_Tick.");
            }
        }

        private void JiggleMouse()
        {
            try
            {
                GetCursorPos(out POINT center);
                int radius = 10;

                for (int angle = 0; angle < 360; angle += 10)
                {
                    if (!isJiggling) break;

                    int x = center.X + (int)(radius * Math.Cos(angle * Math.PI / 180));
                    int y = center.Y + (int)(radius * Math.Sin(angle * Math.PI / 180));

                    SetCursorPos(x, y);
                    Logger.Debug($"Mouse jiggled to ({x}, {y})");
                    Thread.Sleep(10);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error jiggling mouse.");
            }
        }

        private void ResetActivity()
        {
            try
            {
                lastActivityTime = DateTime.Now;
                if (isJiggling)
                {
                    isJiggling = false;
                    jiggleTimer.Stop();
                    altTabTimer.Stop();
                    Logger.Info("User activity detected. Stopping mouse jiggler and Alt+Tab simulation.");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error resetting activity.");
            }
        }

        protected override void SetVisibleCore(bool value)
        {
            base.SetVisibleCore(false);
        }

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                SystemEvents.PowerModeChanged -= SystemEvents_PowerModeChanged;
                AllowSleep();
                components?.Dispose();
                trayIcon?.Dispose();
                activityCheckTimer?.Dispose();
                jiggleTimer?.Dispose();
                bluetoothScanTimer?.Dispose();
                altTabTimer?.Dispose();
                
                // Release the mutex
                if (_mutex != null)
                {
                    _mutex.ReleaseMutex();
                    _mutex.Dispose();
                    _mutex = null;
                }
            }
            base.Dispose(disposing);
        }

        private void InitializeBluetoothWatcher()
        {
            try
            {
                Logger.Info("Initializing Bluetooth watcher...");
                
                // Initialize Bluetooth scan timer
                bluetoothScanTimer = new System.Windows.Forms.Timer();
                bluetoothScanTimer.Interval = BLUETOOTH_SCAN_INTERVAL;
                bluetoothScanTimer.Tick += BluetoothScanTimer_Tick;
                bluetoothScanTimer.Start();

                // Trigger an immediate scan
                BluetoothScanTimer_Tick(null, EventArgs.Empty);
                
                Logger.Info($"Bluetooth scanner started - Looking for device: {TARGET_DEVICE_NAME}");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error initializing Bluetooth watcher");

                MessageBox.Show("Error initializing Bluetooth. Check the log file for details.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private async void BluetoothScanTimer_Tick(object? sender, EventArgs e)
        {
            try
            {
                discoveredDevices.Clear();

                // First try classic Bluetooth devices
                string classicSelector = "System.Devices.DevObjectType:=5 AND System.Devices.Aep.ProtocolId:=\"{E0CBF06C-CD8B-4647-BB8A-263B43F0F974}\"";
                var classicDevices = await DeviceInformation.FindAllAsync(classicSelector);

                // Then try BLE devices
                string bleSelector = "System.Devices.DevObjectType:=5 AND System.Devices.Aep.ProtocolId:=\"{BB7BB05E-5972-42B5-94FC-76EAA7084D49}\"";
                var bleDevices = await DeviceInformation.FindAllAsync(bleSelector);

                var allDevices = classicDevices.Concat(bleDevices);
                bool foundTarget = false;

                foreach (var deviceInfo in allDevices)
                {
                    try
                    {
                        // Check if this device has the target name in its properties
                        if (deviceInfo.Name == TARGET_DEVICE_NAME)
                        {
                            foundTarget = true;
                            Logger.Info("==========================================");
                            Logger.Info($"Found target device at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                            Logger.Info($"Device Name: {TARGET_DEVICE_NAME}");
                            Logger.Info($"ID: {deviceInfo.Id}");
                            Logger.Info($"Pairing Status: {deviceInfo.Pairing.IsPaired}");
                            Logger.Info("==========================================");

                            bool wasInRange = isDeviceInRange;
                            isDeviceInRange = true;
                            if (!wasInRange)
                            {
                                ResetActivity();
                            }
                        }
                        //if (deviceInfo.Properties.TryGetValue("Name", out var deviceNameObj) && 
                        //    deviceNameObj?.ToString() == TARGET_DEVICE_NAME)
                        //{
                        //    foundTarget = true;
                        //    Logger.Info("==========================================");
                        //    Logger.Info($"Found target device at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                        //    Logger.Info($"Device Name: {TARGET_DEVICE_NAME}");
                        //    Logger.Info($"ID: {deviceInfo.Id}");
                        //    Logger.Info($"Pairing Status: {deviceInfo.Pairing.IsPaired}");
                        //    Logger.Info("==========================================");

                        //    bool wasInRange = isDeviceInRange;
                        //    isDeviceInRange = true;
                        //    if (!wasInRange)
                        //    {
                        //        ResetActivity();
                        //    }
                        //}
                    }
                    catch (Exception deviceEx)
                    {
                        Logger.Debug($"Error processing device: {deviceEx.Message}");
                    }
                }

                // Only log when device goes out of range
                if (isDeviceInRange && !foundTarget)
                {
                    isDeviceInRange = false;
                    Logger.Info("==========================================");
                    Logger.Info($"Target device is no longer in range at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                    Logger.Info("==========================================");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error during Bluetooth scan");
            }
        }

        private void SystemEvents_PowerModeChanged(object sender, PowerModeChangedEventArgs e)
        {
            switch (e.Mode)
            {
                case PowerModes.Suspend:
                    Logger.Warn($"System entering sleep mode at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                    break;
                case PowerModes.Resume:
                    isSystemResuming = true;
                    Logger.Warn($"System resuming from sleep at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                    // Re-apply sleep prevention after resume
                    PreventSleep();
                    isSystemResuming = false;
                    break;
            }
        }

        private void AllowSleep()
        {
            try
            {
                SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
                Logger.Debug("Sleep prevention disabled during application shutdown");
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error resetting thread execution state");
            }
        }

        private void OpenLogFile(object? sender, EventArgs e)
        {
            try
            {
                if (File.Exists(logFilePath))
                {
                    // Use the default associated program to open the log file
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = logFilePath,
                        UseShellExecute = true
                    });
                    Logger.Info("Log file opened by user");
                }
                else
                {
                    MessageBox.Show("Log file not found.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    Logger.Warn($"Attempted to open non-existent log file at: {logFilePath}");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error opening log file");
                MessageBox.Show($"Error opening log file: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void AltTabTimer_Tick(object? sender, EventArgs e)
        {
            try
            {
                if (isJiggling)
                {
                    SimulateAltTab();
                    Logger.Debug("Alt+Tab simulated");
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error in AltTabTimer_Tick");
            }
        }

        private void SimulateAltTab()
        {
            try
            {
                // Press ALT
                keybd_event(VK_MENU, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
                
                // Press TAB
                keybd_event(VK_TAB, 0, 0, UIntPtr.Zero);
                
                // Small delay
                Thread.Sleep(100);
                
                // Release TAB
                keybd_event(VK_TAB, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                
                // Release ALT
                keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP | KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error simulating Alt+Tab");
            }
        }
    }
}
