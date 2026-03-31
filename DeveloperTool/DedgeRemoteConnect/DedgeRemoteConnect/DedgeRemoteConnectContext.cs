using DedgeRemoteConnect.Models;
using Newtonsoft.Json;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;
using System.Windows.Forms;
using NLog;

namespace DedgeRemoteConnect;

public class DedgeRemoteConnectContext : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly ContextMenuStrip _contextMenu;
    private string _jsonPath;
    private DateTime _lastJsonModified = DateTime.MinValue;
    private const string DEFAULT_JSON_PATH = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json";
    private const string REGISTRY_KEY = @"Software\DedgeRemoteConnect";
    private const string JSON_PATH_VALUE = "JsonPath";
    private readonly SecureCredentialManager _credentialManager = new();
    private List<Computer> _activeComputers = new();
    private readonly System.Windows.Forms.Timer _refreshTimer;
    private const string SAMPLE_JSON_FILE = "ComputerInfo.json";
    private const string FK_DOMAIN = "DEDGE";

    public DedgeRemoteConnectContext(string iconPath)
    {
        // Load the JSON path first, before any other initialization
        _jsonPath = LoadJsonPathFromRegistry();

        // Create the tray icon and context menu
        _contextMenu = new ContextMenuStrip();
        _contextMenu.Renderer = new DarkModeRenderer();

        _trayIcon = new NotifyIcon()
        {
            Icon = new Icon(iconPath),
            ContextMenuStrip = _contextMenu,
            Visible = true,
            Text = "FK Remote Connect"
        };

        // Set up refresh timer (every 1 minute)
        _refreshTimer = new System.Windows.Forms.Timer
        {
            Interval = 1 * 60 * 1000 // 1 minute
        };
        _refreshTimer.Tick += (s, e) => RefreshComputerList();

        // Initial load - this will now use the correct path
        RefreshComputerList();
        _refreshTimer.Start();

        Logger.Info("Starting application");
    }

    private string LoadJsonPathFromRegistry()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(REGISTRY_KEY);
            var savedPath = key.GetValue(JSON_PATH_VALUE) as string;
            Logger.Debug($"LoadJsonPathFromRegistry - Saved path: {savedPath}");

            if (!string.IsNullOrEmpty(savedPath) && File.Exists(savedPath))
            {
                Logger.Debug($"Using saved JSON path: {savedPath}");
                return savedPath;
            }

            // If no saved path and we're in FK domain, use the network path
            if (Environment.UserDomainName.Equals(FK_DOMAIN, StringComparison.OrdinalIgnoreCase))
            {
                Logger.Debug($"Using default network path: {DEFAULT_JSON_PATH}");
                SaveJsonPathToRegistry(DEFAULT_JSON_PATH); // Save the default path
                return DEFAULT_JSON_PATH;
            }

            Logger.Debug("No existing path found, prompting for new location");
            return DeploySampleFileAndPrompt();
        }
        catch (Exception ex)
        {
            Logger.Error($"Error in LoadJsonPathFromRegistry: {ex}");
            return DeploySampleFileAndPrompt();
        }
    }

    private string DeploySampleFileAndPrompt()
    {
        string previousPath = _jsonPath; // Store the previous path for fallback
        string defaultLocalPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "DedgeRemoteConnect",
            SAMPLE_JSON_FILE
        );

        try
        {
            // Show file dialog first
            using var dialog = new OpenFileDialog
            {
                Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
                FilterIndex = 1,
                InitialDirectory = Path.GetDirectoryName(defaultLocalPath),
                FileName = SAMPLE_JSON_FILE,
                Title = "Select Computer List File",
                CheckFileExists = false // Allow selecting non-existent files
            };

            if (dialog.ShowDialog() == DialogResult.OK)
            {
                string selectedPath = dialog.FileName;
                string selectedDir = Path.GetDirectoryName(selectedPath)!;

                // Create directory if it doesn't exist
                Directory.CreateDirectory(selectedDir);

                // If the file doesn't exist, create it from the embedded resource
                if (!File.Exists(selectedPath))
                {
                    using var resourceStream = GetType().Assembly.GetManifestResourceStream($"DedgeRemoteConnect.{SAMPLE_JSON_FILE}");
                    if (resourceStream != null)
                    {
                        using var fileStream = File.Create(selectedPath);
                        resourceStream.CopyTo(fileStream);
                    }
                    else
                    {
                        throw new Exception("Could not load sample configuration file from resources.");
                    }
                }

                // Try to validate the JSON file
                try
                {
                    string jsonContent = File.ReadAllText(selectedPath);
                    var computers = JsonConvert.DeserializeObject<List<Computer>>(jsonContent);
                    if (computers == null)
                    {
                        throw new Exception("Invalid computer list format");
                    }

                    // If we get here, the JSON is valid
                    SaveJsonPathToRegistry(selectedPath);
                    _jsonPath = selectedPath; // Update current path
                    RefreshComputerList(); // Refresh the menu with new path
                    return selectedPath;
                }
                catch (Exception ex)
                {
                    Logger.Error($"Invalid JSON format: {ex}");
                    MessageBox.Show(
                        "The selected file is not in the correct format.\nReverting to previous configuration.",
                        "Invalid Configuration",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning
                    );

                    // If this was a newly created file, delete it
                    if (!File.Exists(selectedPath))
                    {
                        try { File.Delete(selectedPath); } catch { }
                    }

                    // Revert to previous path
                    if (!string.IsNullOrEmpty(previousPath))
                    {
                        _jsonPath = previousPath; // Update current path
                        RefreshComputerList(); // Refresh with previous path
                        return previousPath;
                    }
                }
            }

            // If we get here, either the user cancelled or validation failed
            // and there was no previous path. Use the default local path.
            Directory.CreateDirectory(Path.GetDirectoryName(defaultLocalPath)!);
            if (!File.Exists(defaultLocalPath))
            {
                using var resourceStream = GetType().Assembly.GetManifestResourceStream($"DedgeRemoteConnect.{SAMPLE_JSON_FILE}");
                if (resourceStream != null)
                {
                    using var fileStream = File.Create(defaultLocalPath);
                    resourceStream.CopyTo(fileStream);
                }
            }
            SaveJsonPathToRegistry(defaultLocalPath);
            _jsonPath = defaultLocalPath; // Update current path
            RefreshComputerList(); // Refresh with default path
            return defaultLocalPath;
        }
        catch (Exception ex)
        {
            Logger.Error($"Error in DeploySampleFileAndPrompt: {ex}");
            MessageBox.Show(
                "Error setting up the computer list file. Using default location.",
                "Setup Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning
            );

            // If we have a previous path, use it
            if (!string.IsNullOrEmpty(previousPath))
            {
                _jsonPath = previousPath; // Update current path
                RefreshComputerList(); // Refresh with previous path
                return previousPath;
            }

            _jsonPath = defaultLocalPath; // Update current path
            RefreshComputerList(); // Refresh with default path
            return defaultLocalPath;
        }
    }

    private void SaveJsonPathToRegistry(string path)
    {
        try
        {
            Logger.Debug($"Saving path to registry: {path}");
            using var key = Registry.CurrentUser.CreateSubKey(REGISTRY_KEY);
            key.SetValue(JSON_PATH_VALUE, path);

            // Verify the save
            var savedPath = key.GetValue(JSON_PATH_VALUE) as string;
            Logger.Debug($"Verified saved path: {savedPath}");
        }
        catch (Exception ex)
        {
            Logger.Error($"Error saving to registry: {ex}");
        }
    }

    private bool CreateSampleFile(string filePath)
    {
        try
        {
            using var resourceStream = GetType().Assembly.GetManifestResourceStream($"DedgeRemoteConnect.{SAMPLE_JSON_FILE}");
            if (resourceStream == null)
            {
                Logger.Debug("Could not find embedded resource");
                return false;
            }

            using var fileStream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None);
            resourceStream.CopyTo(fileStream);
            fileStream.Flush();
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error($"Error creating sample file: {ex}");
            return false;
        }
    }

    private void RefreshComputerList()
    {
        Logger.Debug($"RefreshComputerList - JSON path: {_jsonPath}");
        
        List<Computer> computers = new();
        bool jsonFileLoaded = false;

        try
        {
            if (!string.IsNullOrEmpty(_jsonPath) && File.Exists(_jsonPath))
            {
                var fileInfo = new FileInfo(_jsonPath);
                
                // Only reload if file has been modified since last check
                if (fileInfo.LastWriteTime > _lastJsonModified)
                {
                    Logger.Debug($"JSON file modified since last check. Reloading...");
                    _lastJsonModified = fileInfo.LastWriteTime;
                    
                    string jsonContent = File.ReadAllText(_jsonPath);
                    computers = JsonConvert.DeserializeObject<List<Computer>>(jsonContent) ?? new List<Computer>();
                    jsonFileLoaded = true;
                    Logger.Debug($"Loaded {computers.Count} computers from JSON");
                }
                else
                {
                    // JSON file hasn't changed, skip update unless it's the first load
                    if (_lastJsonModified != DateTime.MinValue)
                    {
                        Logger.Debug("JSON file unchanged, skipping update");
                        return;
                    }
                    else
                    {
                        // First load
                        _lastJsonModified = fileInfo.LastWriteTime;
                        string jsonContent = File.ReadAllText(_jsonPath);
                        computers = JsonConvert.DeserializeObject<List<Computer>>(jsonContent) ?? new List<Computer>();
                        jsonFileLoaded = true;
                        Logger.Debug($"First load: {computers.Count} computers from JSON");
                    }
                }
            }
            else
            {
                Logger.Debug("JSON file not found or path not set");
            }
        }
        catch (Exception ex)
        {
            Logger.Error($"Error loading JSON file: {ex}");
            ShowBalloonTip("Error", "Failed to load computer list");
        }

        UpdateActiveComputers(computers, jsonFileLoaded);
        UpdateContextMenu();
    }

    private void UpdateActiveComputers(List<Computer> computers, bool jsonFileLoaded)
    {
        // Clear the active computers list
        _activeComputers.Clear();
        
        Logger.Debug($"UpdateActiveComputers - Received {computers.Count} computers from JSON");
        
        if (jsonFileLoaded)
        {
            // Get current Windows username
            string currentUser = Environment.UserName;
            Logger.Debug($"Current user: {currentUser}");

            // Debug: Log all computers before filtering
            foreach (var comp in computers)
            {
                Logger.Debug($"Before filter: {comp.Name}, Active: {comp.IsActive}, SingleUser: {comp.SingleUser}");
            }

            // Filter active computers and those matching SingleUser if specified
            _activeComputers = computers.Where(c =>
                c.IsActive &&
                (string.IsNullOrEmpty(c.SingleUser) || c.SingleUser.Equals(currentUser, StringComparison.OrdinalIgnoreCase))
            ).ToList();

            Logger.Debug($"Filtered to {_activeComputers.Count} active computers");
            
            // Debug: Log all active computers after filtering
            foreach (var comp in _activeComputers)
            {
                Logger.Debug($"After filter: {comp.Name}, Environments: {string.Join(", ", comp.Environments)}");
            }
        }
        else
        {
            Logger.Debug("JSON file not loaded, only processing local RDP profiles");
        }

        // Get existing RDP files from the new folder structure
        string rdpBaseFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "RDP",
            Environment.MachineName
        );

        if (Directory.Exists(rdpBaseFolder))
        {
            List<string> existingRdpFiles = Directory.GetFiles(rdpBaseFolder, "*.rdp")
                .Select(path => Path.GetFileNameWithoutExtension(path).ToLower())
                .ToList();

            Logger.Debug($"Found {existingRdpFiles.Count} existing RDP files in {rdpBaseFolder}");

            // Mark computers that have existing RDP files
            foreach (Computer computer in _activeComputers)
            {
                string cleanName = computer.Name.ToLower();
                computer.HasExistingRdp = existingRdpFiles.Contains(cleanName);
            }

            // Add custom RDP files that aren't in the JSON
            List<string> knownComputers = _activeComputers.Select(c =>
                c.Name.ToLower()).ToList();

            string currentComputerName = Environment.MachineName;
            IEnumerable<Computer> customRdpFiles = existingRdpFiles
                .Where(rdp => !knownComputers.Contains(rdp) && rdp.ToLower() != currentComputerName.ToLower())
                .Select(rdp => new Computer
                {
                    Name = rdp,
                    DomainName = rdp,
                    IsActive = true,
                    IsCustom = true,
                    HasExistingRdp = true,
                    Environment = "N/A"
                });

            _activeComputers.AddRange(customRdpFiles);
            Logger.Debug($"Final _activeComputers count: {_activeComputers.Count}");
        }

        // Also check for old RDP files directly in Documents and migrate them
        string documentsFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var oldRdpFiles = Directory.GetFiles(documentsFolder, "*.rdp");
        
        if (oldRdpFiles.Length > 0)
        {
            Logger.Debug($"Found {oldRdpFiles.Length} RDP files in Documents folder that need migration");
            
            // Use credential manager to trigger migration
            var migratedFiles = new List<string>();
            foreach (var oldFile in oldRdpFiles)
            {
                string machineName = Path.GetFileNameWithoutExtension(oldFile);
                try
                {
                    // This will trigger migration if the file exists in old location
                    var rdpPath = _credentialManager.LoadCredentials(machineName);
                    if (rdpPath != null)
                    {
                        migratedFiles.Add(machineName);
                    }
                }
                catch (Exception ex)
                {
                    Logger.Error($"Error migrating RDP file {machineName}: {ex}");
                }
            }
            
            if (migratedFiles.Count > 0)
            {
                Logger.Info($"Migrated {migratedFiles.Count} RDP files to new folder structure");
                ShowBalloonTip("Migration Complete", $"Moved {migratedFiles.Count} RDP profiles to new folder structure");
                
                // Re-scan the new folder after migration
                if (Directory.Exists(rdpBaseFolder))
                {
                    var newRdpFiles = Directory.GetFiles(rdpBaseFolder, "*.rdp")
                        .Select(path => Path.GetFileNameWithoutExtension(path).ToLower())
                        .ToList();

                    // Add any newly migrated custom files
                    List<string> knownComputers = _activeComputers.Select(c => c.Name.ToLower()).ToList();
                    var additionalCustomFiles = newRdpFiles
                        .Where(rdp => !knownComputers.Contains(rdp))
                        .Select(rdp => new Computer
                        {
                            Name = rdp,
                            DomainName = rdp,
                            IsActive = true,
                            IsCustom = true,
                            HasExistingRdp = true,
                            Environment = "N/A"
                        });

                    _activeComputers.AddRange(additionalCustomFiles);
                }
            }
        }
    }

    private void ComputerMenuItem_Click(object? sender, EventArgs e)
    {
        if (sender is not ToolStripMenuItem menuItem || menuItem.Tag is not Computer computer)
            return;
        
        string? rdpPath = _credentialManager.LoadCredentials(computer.DomainName);

        try
        {
            if (rdpPath == null)
            {
                // Show credential input form with ServiceUserName if available
                using CredentialForm credForm = new(
                    computer.DomainName, 
                    true,
                    defaultUsername: computer.ServiceUserName); // Pass the ServiceUserName if available
                    
                if (credForm.ShowDialog() == DialogResult.OK)
                {
                    // Save credentials if user chose to
                    if (credForm.SaveCredentials)
                    {
                        rdpPath = _credentialManager.SaveCredentials(
                            computer.DomainName,
                            credForm.Username,
                            credForm.Password,
                            credForm.UseMultiMonitor,
                            credForm.RedirectPrinters,
                            credForm.RedirectClipboard,
                            credForm.AudioMode
                        );
                    }
                }
                else
                {
                    return; // User cancelled
                }
            }

            // Start the RDP process with the .rdp file
            ProcessStartInfo startInfo = new()
            {
                FileName = "mstsc.exe",
                Arguments = $"\"{rdpPath}\" /admin",
                UseShellExecute = true
            };

            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            _trayIcon.ShowBalloonTip(3000, "Error",
                $"Failed to connect to {computer.Name}",
                ToolTipIcon.Error);
            Logger.Error($"Error connecting to computer: {ex}");
            // open the rdp file for editing in Remote Desktop Connection
            Process.Start("mstsc.exe", $"\"{rdpPath}\" /edit");
        }
    }

    private bool HasPassword(string rdpPath)
    {
        if (!File.Exists(rdpPath)) return false;
        string content = File.ReadAllText(rdpPath);
        return content.Contains("password 51:b:");
    }

    private void AddPasswordToRdpFile(Computer computer)
    {
        using Form passwordForm = new()
        {
            Text = $"Add Password - {computer.Name}",
            Size = new Size(300, 150),
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterScreen,
            MaximizeBox = false,
            MinimizeBox = false
        };

        Label passwordLabel = new()
        {
            Text = "Password:",
            Location = new Point(10, 20),
            AutoSize = true
        };

        TextBox passwordBox = new()
        {
            Location = new Point(10, 40),
            Width = 260,
            UseSystemPasswordChar = true
        };

        Button okButton = new()
        {
            Text = "OK",
            DialogResult = DialogResult.OK,
            Location = new Point(110, 70)
        };

        Button cancelButton = new()
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location = new Point(190, 70)
        };

        passwordForm.Controls.AddRange(new Control[] { passwordLabel, passwordBox, okButton, cancelButton });
        passwordForm.AcceptButton = okButton;
        passwordForm.CancelButton = cancelButton;

        if (passwordForm.ShowDialog() == DialogResult.OK && !string.IsNullOrEmpty(passwordBox.Text))
        {
            string? rdpPath = _credentialManager.LoadCredentials(computer.DomainName);
            if (rdpPath != null)
            {
                List<string> lines = File.ReadAllLines(rdpPath).ToList();
                // Remove existing password if present
                lines.RemoveAll(line => line.StartsWith("password 51:b:"));

                // Add new encrypted password
                string encryptedPassword = EncryptPassword(passwordBox.Text);
                lines.Add($"password 51:b:{encryptedPassword}");

                File.WriteAllLines(rdpPath, lines);
                _trayIcon.ShowBalloonTip(2000, "Success", "Password added to RDP file", ToolTipIcon.Info);
            }
        }
    }

    private string EncryptPassword(string password)
    {
        // Use Unicode encoding like in PowerShell
        Encoding encoding = Encoding.Unicode;
        byte[] passwordAsBytes = encoding.GetBytes(password);
        byte[] encryptedBytes = ProtectedData.Protect(
            passwordAsBytes,
            null,
            DataProtectionScope.CurrentUser
        );

        // Convert to hex string like in PowerShell
        return BitConverter.ToString(encryptedBytes).Replace("-", "");
    }
    private void AddContextMenuItems()
    {
        Logger.Debug($"AddContextMenuItems - Starting with {_activeComputers.Count} active computers");
        
        // Count how many are custom and non-custom
        int customCount = _activeComputers.Count(c => c.IsCustom);
        int nonCustomCount = _activeComputers.Count(c => !c.IsCustom);
        Logger.Debug($"Custom computers: {customCount}, Non-custom computers: {nonCustomCount}");

        // First add custom RDP files (local only)
        IOrderedEnumerable<Computer> customFiles = _activeComputers.Where(c => c.IsCustom).OrderBy(c => c.Name);
        Logger.Debug($"Found {customFiles.Count()} custom files");
        
        if (customFiles.Any())
        {
            ToolStripMenuItem customHeader = new("Local RDP profiles");
            _contextMenu.Items.Add(customHeader);

            foreach (Computer computer in customFiles)
            {
                ToolStripMenuItem menuItem = new(computer.ToString())
                {
                    Tag = computer,
                    ForeColor = Color.White,
                    Font = new Font(_contextMenu.Font, FontStyle.Bold)
                };

                // Add submenu for right-click
                var submenu = BuildComputerSubMenu(computer);
                menuItem.DropDownItems.AddRange(submenu.DropDownItems.Cast<ToolStripItem>().ToArray());

                // Handle both left and right clicks
                menuItem.MouseDown += (s, e) => {
                    if (e.Button == MouseButtons.Right)
                    {
                        menuItem.ShowDropDown();
                    }
                    else if (e.Button == MouseButtons.Left)
                    {
                        ComputerMenuItem_Click(s, e);
                    }
                };

                customHeader.DropDownItems.Add(menuItem);
            }
        }

        // Create a dictionary to hold all environment menus
        Dictionary<string, ToolStripMenuItem> environmentMenus = new();
        
        // Process all non-custom computers
        var nonCustomComputers = _activeComputers.Where(c => !c.IsCustom).ToList();
        Logger.Debug($"Processing {nonCustomComputers.Count} non-custom computers");
        
        // Log environments of all non-custom computers
        foreach (var comp in nonCustomComputers)
        {
            Logger.Debug($"Computer: {comp.Name}, Environments: {string.Join(", ", comp.Environments)}");
        }
        
        // First create all environment menus
        foreach (var computer in nonCustomComputers)
        {
            // If no environments defined, add to "Other"
            if (computer.Environments.Count == 0)
            {
                if (!environmentMenus.ContainsKey("Other"))
                {
                    environmentMenus["Other"] = new ToolStripMenuItem("Other")
                    {
                        ForeColor = Color.White
                    };
                }
            }
            else
            {
                // Add to each environment the computer belongs to
                foreach (var env in computer.Environments)
                {
                    if (!environmentMenus.ContainsKey(env))
                    {
                        environmentMenus[env] = new ToolStripMenuItem(env)
                        {
                            ForeColor = Color.White
                        };
                    }
                }
            }
        }
        
        // Add all environment menus to context menu in alphabetical order
        foreach (var envName in environmentMenus.Keys.OrderBy(k => k))
        {
            _contextMenu.Items.Add(environmentMenus[envName]);
        }
        
        // Add computers to their respective environment menus
        foreach (var computer in nonCustomComputers)
        {
            // Create the menu item for this computer
            ToolStripMenuItem menuItem = new(computer.ToString())
            {
                Tag = computer,
                ForeColor = Color.White,
                Font = computer.HasExistingRdp
                    ? new Font(_contextMenu.Font, FontStyle.Bold)
                    : _contextMenu.Font
            };

            // Add submenu for right-click
            var submenu = BuildComputerSubMenu(computer);
            menuItem.DropDownItems.AddRange(submenu.DropDownItems.Cast<ToolStripItem>().ToArray());

            // Handle both left and right clicks
            menuItem.MouseDown += (s, e) => {
                if (e.Button == MouseButtons.Right)
                {
                    menuItem.ShowDropDown();
                }
                else if (e.Button == MouseButtons.Left)
                {
                    ComputerMenuItem_Click(s, e);
                }
            };

            // If no environments, add to "Other"
            if (computer.Environments.Count == 0)
            {
                environmentMenus["Other"].DropDownItems.Add(menuItem);
            }
            else
            {
                // Add to each environment it belongs to
                foreach (var env in computer.Environments)
                {
                    // Clone the menu item for each additional environment
                    if (env != computer.Environments.First())
                    {
                        var menuItemClone = new ToolStripMenuItem(menuItem.Text)
                        {
                            Tag = computer,
                            ForeColor = menuItem.ForeColor,
                            Font = menuItem.Font
                        };
                        // Add submenu for right-click
                        var submenuClone = BuildComputerSubMenu(computer);
                        menuItemClone.DropDownItems.AddRange(submenuClone.DropDownItems.Cast<ToolStripItem>().ToArray());
                        // Handle both left and right clicks for clone
                        menuItemClone.MouseDown += (s, e) => {
                            if (e.Button == MouseButtons.Right)
                            {
                                menuItemClone.ShowDropDown();
                            }
                            else if (e.Button == MouseButtons.Left)
                            {
                                ComputerMenuItem_Click(s, e);
                            }
                        };
                        environmentMenus[env].DropDownItems.Add(menuItemClone);
                    }
                    else
                    {
                        // Use the original menu item for the first environment
                        environmentMenus[env].DropDownItems.Add(menuItem);
                    }
                }
            }
        }
        
        // Sort computers within each environment menu
        foreach (var menu in environmentMenus.Values)
        {
            menu.DropDownItems.Cast<ToolStripMenuItem>()
                .OrderBy(item => item.Text)
                .ToList()
                .ForEach(item => {
                    menu.DropDownItems.Remove(item);
                    menu.DropDownItems.Add(item);
                });
        }
    }

    // Helper to build the submenu for a computer
    private ToolStripMenuItem BuildComputerSubMenu(Computer computer)
    {
        var submenu = new ToolStripMenuItem();
        submenu.DropDownItems.Add(new ToolStripMenuItem("Show profile in Explorer", null, (s, e) => OpenRdpFileInExplorer(computer)) { ForeColor = Color.White });
        submenu.DropDownItems.Add(new ToolStripMenuItem("Open UNC path in Explorer", null, (s, e) => OpenUncPath(computer)) { ForeColor = Color.White });
        submenu.DropDownItems.Add(new ToolStripMenuItem("Edit profile", null, (s, e) => EditRdpProfile(computer)) { ForeColor = Color.White });
        submenu.DropDownItems.Add(new ToolStripMenuItem("Delete profile", null, (s, e) => DeleteRdpProfile(computer)) { ForeColor = Color.White });
        return submenu;
    }

    private void OpenRdpFileInExplorer(Computer computer)
    {
        try
        {
            string? rdpPath = _credentialManager.LoadCredentials(computer.DomainName);
            if (rdpPath != null && File.Exists(rdpPath))
            {
                // Select the file in Explorer
                Process.Start("explorer.exe", $"/select,\"{rdpPath}\"");
            }
            else
            {
                ShowBalloonTip("Error", $"No RDP file found for {computer.Name}");
            }
        }
        catch (Exception ex)
        {
            Logger.Error($"Error opening RDP file in Explorer: {ex}");
            ShowBalloonTip("Error", "Failed to open RDP file in Explorer");
        }
    }

    private void EditRdpProfile(Computer computer)
    {
        try
        {
            string? rdpPath = _credentialManager.LoadCredentials(computer.DomainName);
            if (rdpPath != null)
            {
                using CredentialForm credForm = new(
                    computer.DomainName,
                    true,
                    defaultUsername: computer.ServiceUserName);

                if (credForm.ShowDialog() == DialogResult.OK)
                {
                    // Save credentials and overwrite existing RDP file
                    _credentialManager.SaveCredentials(
                        computer.DomainName,
                        credForm.Username,
                        credForm.Password,
                        credForm.UseMultiMonitor,
                        credForm.RedirectPrinters,
                        credForm.RedirectClipboard,
                        credForm.AudioMode
                    );
                    ShowBalloonTip("Success", "RDP profile updated successfully");
                }
            }
            else
            {
                ShowBalloonTip("Error", $"No RDP file found for {computer.Name}");
            }
        }
        catch (Exception ex)
        {
            Logger.Error($"Error editing RDP profile: {ex}");
            ShowBalloonTip("Error", "Failed to edit RDP profile");
        }
    }

    private void DeleteRdpProfile(Computer computer)
    {
        try
        {
            string? rdpPath = _credentialManager.LoadCredentials(computer.DomainName);
            if (rdpPath != null && File.Exists(rdpPath))
            {
                var result = MessageBox.Show(
                    $"Are you sure you want to delete the RDP profile for {computer.Name}?",
                    "Confirm Delete",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);

                if (result == DialogResult.Yes)
                {
                    _credentialManager.ClearCredentials(computer.DomainName);
                    ShowBalloonTip("Success", "RDP profile deleted successfully");
                    ForceRefreshComputerList(); // Refresh the menu
                }
            }
            else
            {
                ShowBalloonTip("Error", $"No RDP file found for {computer.Name}");
            }
        }
        catch (Exception ex)
        {
            Logger.Error($"Error deleting RDP profile: {ex}");
            ShowBalloonTip("Error", "Failed to delete RDP profile");
        }
    }

    private void OpenUncPath(Computer computer)
    {
        try
        {
            string uncPath = $"\\\\{computer.Name}\\opt";
            Process.Start("explorer.exe", uncPath);
        }
        catch (Exception ex)
        {
            Logger.Error($"Error opening UNC path: {ex}");
            ShowBalloonTip("Error", "Failed to open UNC path");
        }
    }

    private void UpdateContextMenu()
    {
        _contextMenu.Items.Clear();
        AddContextMenuItems();
        
        // Add separator
        _contextMenu.Items.Add(new ToolStripSeparator());
        
        // Add batch import option
        ToolStripMenuItem batchImportItem = new("Batch Import RDP Profiles...")
        {
            ForeColor = Color.White
        };
        batchImportItem.Click += (s, e) => ShowBatchImportForm();
        _contextMenu.Items.Add(batchImportItem);
        
        // Add separator
        _contextMenu.Items.Add(new ToolStripSeparator());
        
        // Add other menu items
        ToolStripMenuItem changePathItem = new("Change Computer List Path...")
        {
            ForeColor = Color.White
        };
        changePathItem.Click += (s, e) => ChangeJsonPath();
        _contextMenu.Items.Add(changePathItem);

        ToolStripMenuItem refreshItem = new("Refresh List")
        {
            ForeColor = Color.White
        };
        refreshItem.Click += (s, e) => ForceRefreshComputerList();
        _contextMenu.Items.Add(refreshItem);

        ToolStripMenuItem exitItem = new("Exit")
        {
            ForeColor = Color.White
        };
        exitItem.Click += (s, e) => ExitApplication();
        _contextMenu.Items.Add(exitItem);
    }

    private void ShowBatchImportForm()
    {
        try
        {
            using var batchImportForm = new BatchImportForm(_activeComputers);
            if (batchImportForm.ShowDialog() == DialogResult.OK)
            {
                // Force refresh the menu after batch import
                ForceRefreshComputerList();
                ShowBalloonTip("Import Complete", "RDP profiles have been imported and menu refreshed");
            }
        }
        catch (Exception ex)
        {
            Logger.Error($"Error showing batch import form: {ex}");
            MessageBox.Show("Error opening batch import form.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ForceRefreshComputerList()
    {
        Logger.Debug("Force refresh requested");
        _lastJsonModified = DateTime.MinValue; // Force reload on next refresh
        RefreshComputerList();
    }

    private void ExitApplication()
    {
        _trayIcon.Visible = false;
        Application.Exit();
    }

    private void ChangeJsonPath()
    {
        string previousPath = _jsonPath;

        using OpenFileDialog openFileDialog = new()
        {
            Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
            FilterIndex = 1,
            InitialDirectory = Path.GetDirectoryName(_jsonPath),
            FileName = Path.GetFileName(_jsonPath),
            CheckFileExists = false
        };

        if (openFileDialog.ShowDialog() == DialogResult.OK)
        {
            string selectedPath = openFileDialog.FileName;
            string selectedDir = Path.GetDirectoryName(selectedPath)!;

            try
            {
                Directory.CreateDirectory(selectedDir);

                if (!File.Exists(selectedPath))
                {
                    if (!CreateSampleFile(selectedPath))
                    {
                        throw new Exception("Failed to create sample file");
                    }
                }

                // Update path before refresh
                _jsonPath = selectedPath;
                SaveJsonPathToRegistry(selectedPath);

                // Force a delay to ensure file is ready
                Thread.Sleep(100);

                // Force refresh the list with new path
                ForceRefreshComputerList();

                ShowBalloonTip("Path Changed", "Computer list path updated successfully");
            }
            catch (Exception ex)
            {
                Logger.Error($"Error changing JSON path: {ex}");
                MessageBox.Show(
                    "The selected file is not in the correct format.\nReverting to previous configuration.",
                    "Invalid Configuration",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );

                _jsonPath = previousPath;
                SaveJsonPathToRegistry(previousPath);
                ForceRefreshComputerList();
            }
        }
    }

    // Helper method to show balloon tips
    private void ShowBalloonTip(string title, string message)
    {
        if (_contextMenu.InvokeRequired)
        {
            _contextMenu.Invoke(() => _trayIcon.ShowBalloonTip(3000, title, message, ToolTipIcon.Warning));
        }
        else
        {
            _trayIcon.ShowBalloonTip(3000, title, message, ToolTipIcon.Warning);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _trayIcon.Dispose();
            _refreshTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}

public class DarkModeRenderer : ToolStripProfessionalRenderer
{
    public DarkModeRenderer() : base(new DarkModeColors()) { }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        if (e.Item is ToolStripMenuItem menuItem && !menuItem.Enabled)
        {
            e.TextColor = Color.Gray;
        }
        base.OnRenderItemText(e);
    }
}

public class DarkModeColors : ProfessionalColorTable
{
    public override Color MenuItemSelected => Color.FromArgb(65, 65, 65);
    public override Color MenuItemBorder => Color.FromArgb(45, 45, 45);
    public override Color MenuBorder => Color.FromArgb(45, 45, 45);
    public override Color MenuItemSelectedGradientBegin => Color.FromArgb(65, 65, 65);
    public override Color MenuItemSelectedGradientEnd => Color.FromArgb(65, 65, 65);
    public override Color MenuItemPressedGradientBegin => Color.FromArgb(65, 65, 65);
    public override Color MenuItemPressedGradientEnd => Color.FromArgb(65, 65, 65);
    public override Color MenuStripGradientBegin => Color.FromArgb(45, 45, 45);
    public override Color MenuStripGradientEnd => Color.FromArgb(45, 45, 45);
    public override Color ToolStripDropDownBackground => Color.FromArgb(45, 45, 45);
    public override Color ImageMarginGradientBegin => Color.FromArgb(45, 45, 45);
    public override Color ImageMarginGradientMiddle => Color.FromArgb(45, 45, 45);
    public override Color ImageMarginGradientEnd => Color.FromArgb(45, 45, 45);
}