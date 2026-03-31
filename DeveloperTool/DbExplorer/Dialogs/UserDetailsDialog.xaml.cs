using System.Data;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class UserDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly SecurityPrincipal _principal;
    
    // Public accessors for GUI testing - allows GuiTestingService to extract form data
    public System.Windows.Controls.DataGrid TablePrivilegesGridPublic => TablePrivilegesGrid;
    public System.Windows.Controls.DataGrid SchemaPrivilegesGridPublic => SchemaPrivilegesGrid;
    public System.Windows.Controls.DataGrid RoutinePrivilegesGridPublic => RoutinePrivilegesGrid;
    public System.Windows.Controls.TextBlock PrincipalNameTextPublic => PrincipalNameText;
    public System.Windows.Controls.TextBlock PrincipalTypeTextPublic => PrincipalTypeText;

    public UserDetailsDialog(IConnectionManager connectionManager, SecurityPrincipal principal)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _principal = principal;
        
        Logger.Debug("UserDetailsDialog opened for: {Principal} ({Type})", principal.Name, principal.Type);
        
        PrincipalNameText.Text = principal.Name;
        PrincipalTypeText.Text = $"{principal.Icon} {principal.Type}";
        
        Title = $"{principal.Type} Details - {principal.Name}";
        
        // Show appropriate tabs based on principal type
        if (principal.Type == SecurityPrincipalType.User)
        {
            RolesTab.Visibility = Visibility.Visible;
        }
        else if (principal.Type == SecurityPrincipalType.Role || principal.Type == SecurityPrincipalType.Group)
        {
            MembersTab.Visibility = Visibility.Visible;
        }
        
        // Apply grid preferences to all grids in this dialog
        this.Loaded += (s, e) =>
        {
            // Apply all UI styles from the unified style service
            UIStyleService.ApplyStyles(this);
        };
        
        _ = LoadDetailsAsync();
    }
    
    /// <summary>
    /// Activates a specific tab by name for automated testing and direct navigation
    /// </summary>
    public void ActivateTab(string? tabName)
    {
        if (string.IsNullOrEmpty(tabName))
            return;
            
        Logger.Debug("Activating tab: {Tab}", tabName);
        
        var tab = tabName.ToLowerInvariant() switch
        {
            "authorities" or "database-authorities" or "dbauth" => AuthoritiesTab,
            "table-privileges" or "tableprivileges" or "tables" => TablePrivilegesTab,
            "schema-privileges" or "schemaprivileges" or "schemas" => SchemaPrivilegesTab,
            "routine-privileges" or "routineprivileges" or "routines" => RoutinePrivilegesTab,
            "roles" => RolesTab,
            "members" => MembersTab,
            _ => null
        };
        
        if (tab != null)
        {
            DetailsTabControl.SelectedItem = tab;
            Logger.Info("Activated tab: {Tab}", tabName);
        }
        else
        {
            Logger.Warn("Unknown tab name: {Tab}", tabName);
        }
    }

    private async Task LoadDetailsAsync()
    {
        Logger.Info("Loading details for {Type}: {Name}", _principal.Type, _principal.Name);
        
        try
        {
            // Load all details in parallel
            var authTask = LoadDatabaseAuthoritiesAsync();
            var tablePrivTask = LoadTablePrivilegesAsync();
            var schemaPrivTask = LoadSchemaPrivilegesAsync();
            var routinePrivTask = LoadRoutinePrivilegesAsync();
            
            Task? rolesTask = null;
            Task? membersTask = null;
            
            if (_principal.Type == SecurityPrincipalType.User)
            {
                rolesTask = LoadRolesAsync();
            }
            else if (_principal.Type == SecurityPrincipalType.Role || _principal.Type == SecurityPrincipalType.Group)
            {
                membersTask = LoadMembersAsync();
            }
            
            await Task.WhenAll(new[] { authTask, tablePrivTask, schemaPrivTask, routinePrivTask, rolesTask, membersTask }.Where(t => t != null)!);
            
            Logger.Info("Details loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load user details");
            MessageBox.Show($"Error loading details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task LoadDatabaseAuthoritiesAsync()
    {
        Logger.Debug("Loading database authorities");
        
        try
        {
            var granteeType = _principal.Type switch
            {
                SecurityPrincipalType.User => "U",
                SecurityPrincipalType.Group => "G",
                SecurityPrincipalType.Role => "R",
                _ => "U"
            };
            
            var sql = @"
                SELECT DBADMAUTH, SECURITYADMAUTH, DATAACCESSAUTH, ACCESSCTRLAUTH,
                       CREATETABAUTH, BINDADDAUTH, CONNECTAUTH, NOFENCEAUTH,
                       IMPLSCHEMAAUTH, LOADAUTH, EXTERNALROUTINEAUTH, QUIESCECONNECTAUTH
                FROM SYSCAT.DBAUTH 
                WHERE GRANTEE = ? AND GRANTEETYPE = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@grantee", _principal.Name));
            command.Parameters.Add(_connectionManager.CreateParameter("@granteetype", granteeType));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                AddAuthority("DBADM", reader.GetString(0));
                AddAuthority("SECADM", reader.GetString(1));
                AddAuthority("DATAACCESS", reader.GetString(2));
                AddAuthority("ACCESSCTRL", reader.GetString(3));
                AddAuthority("CREATETAB", reader.GetString(4));
                AddAuthority("BINDADD", reader.GetString(5));
                AddAuthority("CONNECT", reader.GetString(6));
                AddAuthority("NO_FENCE", reader.GetString(7));
                AddAuthority("IMPLICIT_SCHEMA", reader.GetString(8));
                AddAuthority("LOAD", reader.GetString(9));
                AddAuthority("EXTERNAL_ROUTINE", reader.GetString(10));
                AddAuthority("QUIESCE_CONNECT", reader.GetString(11));
            }
            else
            {
                AddAuthority("No Database Authorities", "This principal has no database-level authorities");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load database authorities");
            AddAuthority("Error", ex.Message);
        }
    }

    private void AddAuthority(string name, string value)
    {
        var panel = new StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 5) };
        
        var nameText = new TextBlock
        {
            Text = name + ":",
            FontWeight = FontWeights.SemiBold,
            Width = 200,
            Foreground = (System.Windows.Media.Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        };
        
        var valueText = new TextBlock
        {
            Text = value,
            Foreground = value == "Y" ? System.Windows.Media.Brushes.LightGreen : 
                        value == "N" ? (System.Windows.Media.Brush)FindResource("SystemControlForegroundBaseMediumBrush") :
                        (System.Windows.Media.Brush)FindResource("SystemControlForegroundBaseHighBrush")
        };
        
        panel.Children.Add(nameText);
        panel.Children.Add(valueText);
        AuthoritiesPanel.Children.Add(panel);
    }

    private async Task LoadTablePrivilegesAsync()
    {
        Logger.Debug("Loading table privileges");
        
        try
        {
            var granteeType = _principal.Type switch
            {
                SecurityPrincipalType.User => "U",
                SecurityPrincipalType.Group => "G",
                SecurityPrincipalType.Role => "R",
                _ => "U"
            };
            
            var sql = @"
                SELECT TABSCHEMA, TABNAME, SELECTAUTH, INSERTAUTH, UPDATEAUTH, DELETEAUTH, ALTERAUTH
                FROM SYSCAT.TABAUTH 
                WHERE GRANTEE = ? AND GRANTEETYPE = ?
                ORDER BY TABSCHEMA, TABNAME";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@grantee", _principal.Name));
            command.Parameters.Add(_connectionManager.CreateParameter("@granteetype", granteeType));
            
            var dataTable = new DataTable();
            using var adapter = _connectionManager.CreateDataAdapter(command);
            await Task.Run(() => adapter.Fill(dataTable));
            
            TablePrivilegesGrid.ItemsSource = dataTable.DefaultView;
            Logger.Info($"Loaded {dataTable.Rows.Count} table privileges");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load table privileges");
        }
    }

    private async Task LoadSchemaPrivilegesAsync()
    {
        Logger.Debug("Loading schema privileges");
        
        try
        {
            var granteeType = _principal.Type switch
            {
                SecurityPrincipalType.User => "U",
                SecurityPrincipalType.Group => "G",
                SecurityPrincipalType.Role => "R",
                _ => "U"
            };
            
            var sql = @"
                SELECT SCHEMANAME, CREATEINAUTH, ALTERINAUTH, DROPINAUTH
                FROM SYSCAT.SCHEMAAUTH 
                WHERE GRANTEE = ? AND GRANTEETYPE = ?
                ORDER BY SCHEMANAME";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@grantee", _principal.Name));
            command.Parameters.Add(_connectionManager.CreateParameter("@granteetype", granteeType));
            
            var dataTable = new DataTable();
            using var adapter = _connectionManager.CreateDataAdapter(command);
            await Task.Run(() => adapter.Fill(dataTable));
            
            SchemaPrivilegesGrid.ItemsSource = dataTable.DefaultView;
            Logger.Info($"Loaded {dataTable.Rows.Count} schema privileges");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load schema privileges");
        }
    }

    private async Task LoadRoutinePrivilegesAsync()
    {
        Logger.Debug("Loading routine privileges");
        
        try
        {
            var granteeType = _principal.Type switch
            {
                SecurityPrincipalType.User => "U",
                SecurityPrincipalType.Group => "G",
                SecurityPrincipalType.Role => "R",
                _ => "U"
            };
            
            var sql = @"
                SELECT SCHEMA, SPECIFICNAME, EXECUTEAUTH
                FROM SYSCAT.ROUTINEAUTH 
                WHERE GRANTEE = ? AND GRANTEETYPE = ?
                ORDER BY SCHEMA, SPECIFICNAME";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@grantee", _principal.Name));
            command.Parameters.Add(_connectionManager.CreateParameter("@granteetype", granteeType));
            
            var dataTable = new DataTable();
            using var adapter = _connectionManager.CreateDataAdapter(command);
            await Task.Run(() => adapter.Fill(dataTable));
            
            RoutinePrivilegesGrid.ItemsSource = dataTable.DefaultView;
            Logger.Info($"Loaded {dataTable.Rows.Count} routine privileges");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load routine privileges");
        }
    }

    private async Task LoadRolesAsync()
    {
        Logger.Debug("Loading roles for user");
        
        try
        {
            var sql = @"
                SELECT ROLENAME
                FROM SYSCAT.ROLEAUTH 
                WHERE GRANTEE = ?
                ORDER BY ROLENAME";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@grantee", _principal.Name));
            
            var dataTable = new DataTable();
            using var adapter = _connectionManager.CreateDataAdapter(command);
            await Task.Run(() => adapter.Fill(dataTable));
            
            RolesList.ItemsSource = dataTable.DefaultView;
            Logger.Info($"Loaded {dataTable.Rows.Count} roles");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load roles");
        }
    }

    private async Task LoadMembersAsync()
    {
        Logger.Debug("Loading members for {Type}", _principal.Type);
        
        try
        {
            string sql;
            if (_principal.Type == SecurityPrincipalType.Role)
            {
                sql = @"
                    SELECT GRANTEE, GRANTEETYPE
                    FROM SYSCAT.ROLEAUTH 
                    WHERE ROLENAME = ?
                    ORDER BY GRANTEE";
            }
            else // Group
            {
                sql = @"
                    SELECT GRANTEE, GRANTEETYPE
                    FROM SYSCAT.TABAUTH 
                    WHERE GRANTEE = ?
                    GROUP BY GRANTEE, GRANTEETYPE
                    ORDER BY GRANTEE";
            }
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@principal", _principal.Name));
            
            var dataTable = new DataTable();
            using var adapter = _connectionManager.CreateDataAdapter(command);
            await Task.Run(() => adapter.Fill(dataTable));
            
            MembersList.ItemsSource = dataTable.DefaultView;
            Logger.Info($"Loaded {dataTable.Rows.Count} members");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load members");
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
    
    // Removed GetDb2Connection() - now using IConnectionManager directly for provider-agnostic operation
}

