using DedgeRemoteConnect.Models;

namespace DedgeRemoteConnect;

public partial class BatchImportForm : Form
{
    private readonly TextBox _dataTextBox = null!;
    private readonly CheckBox _useMultiMonitorCheckBox = null!;
    private readonly CheckBox _redirectPrintersCheckBox = null!;
    private readonly CheckBox _redirectClipboardCheckBox = null!;
    private readonly GroupBox _audioGroup = null!;
    private readonly RadioButton _audioRemoteRadio = null!;
    private readonly RadioButton _audioLocalRadio = null!;
    private readonly RadioButton _audioOffRadio = null!;
    private readonly Label _statusLabel = null!;
    private readonly SecureCredentialManager _credentialManager;
    private readonly List<Computer> _activeComputers;

    public int AudioMode
    {
        get
        {
            if (_audioRemoteRadio.Checked) return 0; // Play on remote
            if (_audioLocalRadio.Checked) return 1;  // Play locally
            return 2; // Do not play
        }
    }

    public BatchImportForm(List<Computer> activeComputers)
    {
        _credentialManager = new SecureCredentialManager();
        _activeComputers = activeComputers;
        
        Text = "Batch Import RDP Profiles";
        Size = new Size(600, 700);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;

        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(10),
            RowCount = 8,
            ColumnCount = 2
        };

        // Instructions
        Label instructionsLabel = new()
        {
            Text = "Enter computer names and passwords in the format:\nComputerName[TAB]Username[TAB]Password\nor\nComputerName;Username;Password\n\nOne entry per line:",
            Dock = DockStyle.Top,
            AutoSize = true,
            MaximumSize = new Size(560, 0) // Allow wrapping
        };
        layout.Controls.Add(instructionsLabel, 0, 0);
        layout.SetColumnSpan(instructionsLabel, 2);

        // Data input text box
        _dataTextBox = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ScrollBars = ScrollBars.Both,
            Height = 200,
            Font = new Font("Consolas", 9)
        };
        layout.Controls.Add(_dataTextBox, 0, 1);
        layout.SetColumnSpan(_dataTextBox, 2);

        // Display settings
        _useMultiMonitorCheckBox = new CheckBox
        {
            Text = "Use multiple monitors",
            Checked = false,
            Dock = DockStyle.Fill
        };
        layout.Controls.Add(_useMultiMonitorCheckBox, 0, 2);
        layout.SetColumnSpan(_useMultiMonitorCheckBox, 2);

        // Redirection settings
        GroupBox redirectGroup = new()
        {
            Text = "Redirection Settings",
            Dock = DockStyle.Fill,
            Padding = new Padding(5),
            Height = 80
        };
        FlowLayoutPanel redirectLayout = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown
        };

        _redirectPrintersCheckBox = new CheckBox
        {
            Text = "Printers",
            Checked = true
        };
        _redirectClipboardCheckBox = new CheckBox
        {
            Text = "Clipboard",
            Checked = true
        };
        redirectLayout.Controls.AddRange(new Control[] { _redirectPrintersCheckBox, _redirectClipboardCheckBox });
        redirectGroup.Controls.Add(redirectLayout);
        layout.Controls.Add(redirectGroup, 0, 3);
        layout.SetColumnSpan(redirectGroup, 2);

        // Audio settings
        _audioGroup = new GroupBox
        {
            Text = "Audio Settings",
            Dock = DockStyle.Fill,
            Padding = new Padding(5),
            Height = 100
        };
        FlowLayoutPanel audioLayout = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true
        };

        _audioRemoteRadio = new RadioButton { Text = "Play on remote computer", Checked = true, AutoSize = true };
        _audioLocalRadio = new RadioButton { Text = "Play on this computer", AutoSize = true };
        _audioOffRadio = new RadioButton { Text = "Don't play", AutoSize = true };

        audioLayout.Controls.AddRange(new Control[] { _audioRemoteRadio, _audioLocalRadio, _audioOffRadio });
        _audioGroup.Controls.Add(audioLayout);
        layout.Controls.Add(_audioGroup, 0, 4);
        layout.SetColumnSpan(_audioGroup, 2);

        // Status label
        _statusLabel = new Label
        {
            Text = "Ready to import...",
            Dock = DockStyle.Fill,
            ForeColor = Color.Blue,
            Height = 20
        };
        layout.Controls.Add(_statusLabel, 0, 5);
        layout.SetColumnSpan(_statusLabel, 2);

        // Buttons
        FlowLayoutPanel buttonPanel = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            Height = 40
        };

        Button cancelButton = new()
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Width = 80
        };
        cancelButton.Click += (s, e) => Close();

        Button importButton = new()
        {
            Text = "Import",
            DialogResult = DialogResult.None,
            Width = 80
        };
        importButton.Click += ImportButton_Click;

        buttonPanel.Controls.Add(cancelButton);
        buttonPanel.Controls.Add(importButton);
        layout.Controls.Add(buttonPanel, 0, 6);
        layout.SetColumnSpan(buttonPanel, 2);

        Controls.Add(layout);
        AcceptButton = importButton;
        CancelButton = cancelButton;
    }

    private void ImportButton_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_dataTextBox.Text))
        {
            MessageBox.Show("Please enter data to import.", "No Data", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var entries = ParseImportData(_dataTextBox.Text);
        if (entries.Count == 0)
        {
            MessageBox.Show("No valid entries found. Please check the format.", "Invalid Data", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        _statusLabel.Text = "Importing...";
        _statusLabel.ForeColor = Color.Orange;
        Application.DoEvents();

        int successCount = 0;
        int errorCount = 0;
        var errorMessages = new List<string>();

        foreach (var entry in entries)
        {
            try
            {
                _credentialManager.SaveCredentials(
                    entry.ComputerName,
                    entry.Username,
                    entry.Password,
                    _useMultiMonitorCheckBox.Checked,
                    _redirectPrintersCheckBox.Checked,
                    _redirectClipboardCheckBox.Checked,
                    AudioMode
                );
                successCount++;
                _statusLabel.Text = $"Imported {successCount}/{entries.Count}...";
                Application.DoEvents();
            }
            catch (Exception ex)
            {
                errorCount++;
                errorMessages.Add($"{entry.ComputerName}: {ex.Message}");
            }
        }

        _statusLabel.Text = $"Completed: {successCount} successful, {errorCount} errors";
        _statusLabel.ForeColor = errorCount > 0 ? Color.Red : Color.Green;

        if (errorMessages.Count > 0)
        {
            string errorText = string.Join("\n", errorMessages.Take(10));
            if (errorMessages.Count > 10)
                errorText += $"\n... and {errorMessages.Count - 10} more errors";
            
            MessageBox.Show($"Import completed with errors:\n\n{errorText}", 
                "Import Results", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        else
        {
            MessageBox.Show($"Successfully imported {successCount} RDP profiles!", 
                "Import Successful", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        if (successCount > 0)
        {
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    private List<ImportEntry> ParseImportData(string data)
    {
        var entries = new List<ImportEntry>();
        var lines = data.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var line in lines)
        {
            var trimmedLine = line.Trim();
            if (string.IsNullOrEmpty(trimmedLine))
                continue;

            string[]? parts = null;
            if (trimmedLine.Contains('\t'))
            {
                parts = trimmedLine.Split('\t');
            }
            else if (trimmedLine.Contains(';'))
            {
                parts = trimmedLine.Split(';');
            }

            if (parts != null && parts.Length >= 2)
            {
                string computerName = parts[0].Trim();
                string username = null;
                string password;

                if (parts.Length >= 3)
                {
                    username = parts[1].Trim();
                    password = parts[2].Trim();
                }
                else
                {
                    // Only computer and password provided
                    password = parts[1].Trim();
                }

                // Find the computer in the JSON content to get the username if not provided
                var computer = _activeComputers.FirstOrDefault(c => 
                    c.Name.Equals(computerName, StringComparison.OrdinalIgnoreCase));

                if (string.IsNullOrEmpty(username))
                {
                    username = computer?.ServiceUserName ?? "FKDEVADM";
                }

                entries.Add(new ImportEntry
                {
                    ComputerName = computerName,
                    Username = username,
                    Password = password
                });
            }
        }

        return entries;
    }

    private class ImportEntry
    {
        public string ComputerName { get; set; } = "";
        public string Username { get; set; } = "";
        public string Password { get; set; } = "";
    }
} 