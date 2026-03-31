namespace DedgeRemoteConnect;

public partial class CredentialForm : Form
{
    private readonly TextBox _usernameTextBox = null!;
    private readonly TextBox _passwordTextBox = null!;
    private readonly CheckBox _saveCredentialsCheckBox = null!;
    private readonly CheckBox _useMultiMonitorCheckBox = null!;
    private readonly CheckBox _redirectPrintersCheckBox = null!;
    private readonly CheckBox _redirectClipboardCheckBox = null!;
    private readonly GroupBox _audioGroup = null!;
    private readonly RadioButton _audioRemoteRadio = null!;
    private readonly RadioButton _audioLocalRadio = null!;
    private readonly RadioButton _audioOffRadio = null!;

    public string Username => _usernameTextBox.Text;
    public string Password => _passwordTextBox.Text;
    public bool SaveCredentials => _saveCredentialsCheckBox.Checked;
    public bool UseMultiMonitor => _useMultiMonitorCheckBox.Checked;
    public bool RedirectPrinters => _redirectPrintersCheckBox.Checked;
    public bool RedirectClipboard => _redirectClipboardCheckBox.Checked;
    public int AudioMode
    {
        get
        {
            if (_audioRemoteRadio.Checked) return 0; // Play on remote
            if (_audioLocalRadio.Checked) return 1;  // Play locally
            return 2; // Do not play
        }
    }

    public CredentialForm(string computerName, bool isNewProfile = true, string? defaultUsername = null)
    {
        Text = $"Enter Credentials - {computerName}";
        Size = new Size(400, isNewProfile ? 500 : 250);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;

        TableLayoutPanel layout = new()
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(10),
            RowCount = isNewProfile ? 10 : 5,
            ColumnCount = 2
        };

        // Credentials section
        GroupBox credentialsGroup = new()
        {
            Text = "Credentials",
            Dock = DockStyle.Fill,
            Padding = new Padding(5)
        };
        TableLayoutPanel credentialsLayout = new()
        {
            Dock = DockStyle.Fill,
            RowCount = 3,
            ColumnCount = 2
        };

        // Username
        credentialsLayout.Controls.Add(new Label { Text = "Username:", Dock = DockStyle.Fill }, 0, 0);
        _usernameTextBox = new TextBox { Dock = DockStyle.Fill };
        
        // Set the default username if provided
        if (!string.IsNullOrEmpty(defaultUsername))
        {
            _usernameTextBox.Text = defaultUsername;
        }
        
        credentialsLayout.Controls.Add(_usernameTextBox, 1, 0);

        // Password
        credentialsLayout.Controls.Add(new Label { Text = "Password:", Dock = DockStyle.Fill }, 0, 1);
        _passwordTextBox = new TextBox { Dock = DockStyle.Fill, UseSystemPasswordChar = false };
        _passwordTextBox.TextChanged += (s, e) =>
        {
            if (_passwordTextBox.Text.Length > 0)
            {
                _passwordTextBox.UseSystemPasswordChar = true;
            }
            else
            {
                _passwordTextBox.UseSystemPasswordChar = false;
            }
        };
        credentialsLayout.Controls.Add(_passwordTextBox, 1, 1);

        credentialsGroup.Controls.Add(credentialsLayout);
        layout.Controls.Add(credentialsGroup, 0, 0);
        layout.SetColumnSpan(credentialsGroup, 2);

        // Save credentials checkbox
        _saveCredentialsCheckBox = new CheckBox
        {
            Text = "Save credentials",
            Checked = true,
            Dock = DockStyle.Fill
        };
        layout.Controls.Add(_saveCredentialsCheckBox, 1, 1);

        if (isNewProfile)
        {
            // Display settings
            _useMultiMonitorCheckBox = new CheckBox
            {
                Text = "Use multiple monitors",
                Checked = false,
                Dock = DockStyle.Fill
            };
            layout.Controls.Add(_useMultiMonitorCheckBox, 1, 2);

            // Redirection settings
            GroupBox redirectGroup = new()
            {
                Text = "Redirection",
                Dock = DockStyle.Fill,
                Padding = new Padding(5)
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
                Padding = new Padding(5)
            };
            FlowLayoutPanel audioLayout = new()
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.TopDown
            };

            _audioRemoteRadio = new RadioButton { Text = "Play on remote computer", Checked = true };
            _audioLocalRadio = new RadioButton { Text = "Play on this computer" };
            _audioOffRadio = new RadioButton { Text = "Don't play" };

            audioLayout.Controls.AddRange(new Control[] { _audioRemoteRadio, _audioLocalRadio, _audioOffRadio });
            _audioGroup.Controls.Add(audioLayout);
            layout.Controls.Add(_audioGroup, 0, 4);
            layout.SetColumnSpan(_audioGroup, 2);
        }

        // Buttons
        FlowLayoutPanel buttonPanel = new()
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft
        };

        Button cancelButton = new()
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel
        };
        cancelButton.Click += (s, e) => Close();

        Button okButton = new()
        {
            Text = "OK",
            DialogResult = DialogResult.OK
        };
        okButton.Click += (s, e) =>
        {
            if (string.IsNullOrWhiteSpace(Username))
            {
                MessageBox.Show("Username is required.", "Validation Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            DialogResult = DialogResult.OK;
            Close();
        };

        buttonPanel.Controls.Add(cancelButton);
        buttonPanel.Controls.Add(okButton);
        layout.Controls.Add(buttonPanel, 1, isNewProfile ? 8 : 3);

        Controls.Add(layout);
        AcceptButton = okButton;
        CancelButton = cancelButton;
    }
}