using System.Data;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Dialogs;

public partial class ObjectDetailsDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly DatabaseConnection _connection;
    private readonly DatabaseObject _object;
    
    // Public accessors for GUI testing - allows GuiTestingService to extract form data
    public System.Windows.Controls.TextBox SourceCodeTextBoxPublic => SourceCodeTextBox;
    public System.Windows.Controls.TextBox CreateDdlTextBoxPublic => CreateDdlTextBox;
    public System.Windows.Controls.TextBox DropDdlTextBoxPublic => DropDdlTextBox;
    public System.Windows.Controls.DataGrid DependenciesGridPublic => DependenciesGrid;
    public System.Windows.Controls.TextBlock ObjectNameTextPublic => ObjectNameText;
    public System.Windows.Controls.TextBlock ObjectTypeTextPublic => ObjectTypeText;

    public ObjectDetailsDialog(IConnectionManager connectionManager, DatabaseObject databaseObject, DatabaseConnection connection)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _connection = connection;
        _object = databaseObject;
        
        Logger.Debug("ObjectDetailsDialog opened for: {Object}", databaseObject.FullName);
        
        ObjectNameText.Text = databaseObject.Name;
        ObjectTypeText.Text = $"{databaseObject.Icon} {databaseObject.Type} • Schema: {databaseObject.SchemaName}";
        
        Title = $"{databaseObject.Type} Details - {databaseObject.Name}";
        
        // Apply all UI styles from the unified style service
        this.Loaded += (s, e) => UIStyleService.ApplyStyles(this);
        
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
            "properties" or "props" => PropertiesTab,
            "source-code" or "sourcecode" or "source" => SourceCodeTab,
            "create-ddl" or "createddl" or "create" => CreateDdlTab,
            "drop-ddl" or "dropddl" or "drop" => DropDdlTab,
            "dependencies" or "deps" => DependenciesTab,
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
        Logger.Info("Loading details for {Type}: {Name}", _object.Type, _object.FullName);
        
        try
        {
            // Load properties
            LoadBasicProperties();
            
            // Load type-specific details
            switch (_object.Type)
            {
                case ObjectType.Views:
                    await LoadViewDetailsAsync();
                    break;
                case ObjectType.Procedures:
                case ObjectType.Functions:
                    await LoadRoutineDetailsAsync();
                    break;
                case ObjectType.Indexes:
                    await LoadIndexDetailsAsync();
                    break;
                case ObjectType.Triggers:
                    await LoadTriggerDetailsAsync();
                    break;
                case ObjectType.Sequences:
                    await LoadSequenceDetailsAsync();
                    break;
                case ObjectType.Synonyms:
                    await LoadSynonymDetailsAsync();
                    break;
                case ObjectType.Types:
                    await LoadTypeDetailsAsync();
                    break;
            }
            
            // Load DDL (for Advanced/DBA users only)
            await LoadDdlAsync();
            
            Logger.Info("Details loaded successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load object details");
            MessageBox.Show($"Error loading details:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    /// <summary>
    /// Load CREATE and DROP DDL (only for Advanced/DBA users)
    /// </summary>
    private async Task LoadDdlAsync()
    {
        try
        {
            // Check user access level
            var userAccessLevel = _connection.Permissions?.AccessLevel ?? UserAccessLevel.Standard;
            
            if (userAccessLevel < UserAccessLevel.Advanced)
            {
                Logger.Debug("DDL tabs hidden - user is Standard level");
                CreateDdlTab.Visibility = Visibility.Collapsed;
                DropDdlTab.Visibility = Visibility.Collapsed;
                return;
            }
            
            Logger.Debug("Generating DDL for {Type}: {Name}", _object.Type, _object.FullName);
            
            var ddlService = new Services.DdlGeneratorService(_connectionManager);
            var (createDdl, dropDdl) = await ddlService.GenerateDdlAsync(_object);
            
            CreateDdlTextBox.Text = createDdl;
            DropDdlTextBox.Text = dropDdl;
            
            CreateDdlTab.Visibility = Visibility.Visible;
            DropDdlTab.Visibility = Visibility.Visible;
            
            Logger.Debug("DDL generated successfully");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate DDL");
            CreateDdlTextBox.Text = $"-- Error generating CREATE DDL:\n-- {ex.Message}";
            DropDdlTextBox.Text = $"-- Error generating DROP DDL:\n-- {ex.Message}";
        }
    }

    private void LoadBasicProperties()
    {
        Logger.Debug("Loading basic properties");
        
        AddProperty("Full Name", _object.FullName);
        AddProperty("Schema", _object.SchemaName);
        AddProperty("Name", _object.Name);
        AddProperty("Type", _object.Type.ToString());
        
        if (!string.IsNullOrEmpty(_object.Owner))
            AddProperty("Owner", _object.Owner);
        
        if (_object.CreatedAt.HasValue)
            AddProperty("Created", _object.CreatedAt.Value.ToString("yyyy-MM-dd HH:mm:ss"));
        
        if (_object.RowCount.HasValue)
            AddProperty("Row Count", _object.RowCount.Value.ToString("N0"));
        
        if (_object.ParameterCount.HasValue)
            AddProperty("Parameter Count", _object.ParameterCount.Value.ToString());
        
        if (!string.IsNullOrEmpty(_object.TableSpace))
            AddProperty("Tablespace", _object.TableSpace);
        
        if (!string.IsNullOrEmpty(_object.Language))
            AddProperty("Language", _object.Language);
        
        if (!string.IsNullOrEmpty(_object.Remarks))
            AddProperty("Remarks", _object.Remarks);
    }

    private void AddProperty(string name, string value)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 10) };
        
        var nameText = new TextBlock
        {
            Text = name,
            FontWeight = FontWeights.SemiBold,
            Foreground = (System.Windows.Media.Brush)FindResource("SystemControlForegroundBaseMediumBrush")
        };
        
        var valueText = new TextBlock
        {
            Text = value,
            Margin = new Thickness(0, 3, 0, 0),
            TextWrapping = TextWrapping.Wrap,
            Foreground = (System.Windows.Media.Brush)FindResource("SystemControlForegroundBaseHighBrush")
        };
        
        panel.Children.Add(nameText);
        panel.Children.Add(valueText);
        PropertiesPanel.Children.Add(panel);
    }

    private async Task LoadViewDetailsAsync()
    {
        Logger.Debug("Loading view details");
        
        try
        {
            var sql = @"
                SELECT TEXT 
                FROM SYSCAT.VIEWS 
                WHERE VIEWSCHEMA = ? AND VIEWNAME = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            var result = await command.ExecuteScalarAsync();
            if (result != null && result != DBNull.Value)
            {
                SourceCodeTab.Visibility = Visibility.Visible;
                SourceCodeTextBox.Text = result.ToString();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load view source");
        }
    }

    private async Task LoadRoutineDetailsAsync()
    {
        Logger.Debug("Loading routine details");
        
        try
        {
            var sql = @"
                SELECT TEXT, LANGUAGE, DETERMINISTIC, EXTERNAL_ACTION, SQL_DATA_ACCESS, PARM_COUNT
                FROM SYSCAT.ROUTINES 
                WHERE ROUTINESCHEMA = ? AND ROUTINENAME = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var text = reader.IsDBNull(0) ? "" : reader.GetString(0);
                var language = reader.IsDBNull(1) ? "" : reader.GetString(1);
                var deterministic = reader.IsDBNull(2) ? "" : reader.GetString(2);
                var externalAction = reader.IsDBNull(3) ? "" : reader.GetString(3);
                var sqlDataAccess = reader.IsDBNull(4) ? "" : reader.GetString(4);
                var parmCount = reader.IsDBNull(5) ? 0 : reader.GetInt32(5);
                
                AddProperty("Language", language);
                AddProperty("Deterministic", deterministic);
                AddProperty("External Action", externalAction);
                AddProperty("SQL Data Access", sqlDataAccess);
                AddProperty("Parameter Count", parmCount.ToString());
                
                if (!string.IsNullOrEmpty(text))
                {
                    SourceCodeTab.Visibility = Visibility.Visible;
                    SourceCodeTextBox.Text = text;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load routine details");
        }
    }

    private async Task LoadIndexDetailsAsync()
    {
        Logger.Debug("Loading index details");
        
        try
        {
            var sql = @"
                SELECT TABSCHEMA, TABNAME, UNIQUERULE, INDEXTYPE, COLNAMES, MADE_UNIQUE
                FROM SYSCAT.INDEXES 
                WHERE INDSCHEMA = ? AND INDNAME = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var tabSchema = reader.GetString(0);
                var tabName = reader.GetString(1);
                var uniqueRule = reader.GetString(2);
                var indexType = reader.GetString(3);
                var colNames = reader.GetString(4);
                var madeUnique = reader.GetString(5);
                
                AddProperty("Table", $"{tabSchema}.{tabName}");
                AddProperty("Unique Rule", uniqueRule);
                AddProperty("Index Type", indexType);
                AddProperty("Columns", colNames);
                AddProperty("Made Unique", madeUnique);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load index details");
        }
    }

    private async Task LoadTriggerDetailsAsync()
    {
        Logger.Debug("Loading trigger details");
        
        try
        {
            var sql = @"
                SELECT TABSCHEMA, TABNAME, TRIGEVENT, TRIGTIME, TEXT
                FROM SYSCAT.TRIGGERS 
                WHERE TRIGSCHEMA = ? AND TRIGNAME = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var tabSchema = reader.GetString(0);
                var tabName = reader.GetString(1);
                var trigEvent = reader.GetString(2);
                var trigTime = reader.GetString(3);
                var text = reader.IsDBNull(4) ? "" : reader.GetString(4);
                
                AddProperty("Table", $"{tabSchema}.{tabName}");
                AddProperty("Trigger Event", trigEvent);
                AddProperty("Trigger Time", trigTime);
                
                if (!string.IsNullOrEmpty(text))
                {
                    SourceCodeTab.Visibility = Visibility.Visible;
                    SourceCodeTextBox.Text = text;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load trigger details");
        }
    }

    private async Task LoadSequenceDetailsAsync()
    {
        Logger.Debug("Loading sequence details");
        
        try
        {
            var sql = @"
                SELECT SEQTYPE, START, INCREMENT, MINVALUE, MAXVALUE, CYCLE, CACHE, ORDER
                FROM SYSCAT.SEQUENCES 
                WHERE SEQSCHEMA = ? AND SEQNAME = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var seqType = reader.GetString(0);
                var start = reader.IsDBNull(1) ? 0 : reader.GetInt64(1);
                var increment = reader.IsDBNull(2) ? 0 : reader.GetInt64(2);
                var minValue = reader.IsDBNull(3) ? 0 : reader.GetInt64(3);
                var maxValue = reader.IsDBNull(4) ? 0 : reader.GetInt64(4);
                var cycle = reader.IsDBNull(5) ? "" : reader.GetString(5);
                var cache = reader.IsDBNull(6) ? 0 : reader.GetInt64(6);
                var order = reader.IsDBNull(7) ? "" : reader.GetString(7);
                
                AddProperty("Sequence Type", seqType);
                AddProperty("Start Value", start.ToString());
                AddProperty("Increment", increment.ToString());
                AddProperty("Min Value", minValue.ToString());
                AddProperty("Max Value", maxValue.ToString());
                AddProperty("Cycle", cycle);
                AddProperty("Cache Size", cache.ToString());
                AddProperty("Order", order);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load sequence details");
        }
    }

    private async Task LoadSynonymDetailsAsync()
    {
        Logger.Debug("Loading synonym details");
        
        try
        {
            var sql = @"
                SELECT BASE_TABSCHEMA, BASE_TABNAME, BASE_TABTYPE
                FROM SYSCAT.TABLES 
                WHERE TABSCHEMA = ? AND TABNAME = ? AND TYPE = 'A'";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var baseSchema = reader.GetString(0);
                var baseName = reader.GetString(1);
                var baseType = reader.GetString(2);
                
                AddProperty("Target Schema", baseSchema);
                AddProperty("Target Name", baseName);
                AddProperty("Target Type", baseType);
                AddProperty("Full Target", $"{baseSchema}.{baseName}");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load synonym details");
        }
    }

    private async Task LoadTypeDetailsAsync()
    {
        Logger.Debug("Loading type details");
        
        try
        {
            var sql = @"
                SELECT METATYPE, SOURCESCHEMA, SOURCENAME, LENGTH, SCALE
                FROM SYSCAT.DATATYPES 
                WHERE TYPESCHEMA = ? AND TYPENAME = ?";
            
            using var command = _connectionManager.CreateCommand(sql);
            command.Parameters.Add(_connectionManager.CreateParameter("@schema", _object.SchemaName));
            command.Parameters.Add(_connectionManager.CreateParameter("@name", _object.Name));
            
            using var reader = await command.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var metatype = reader.GetString(0);
                var sourceSchema = reader.IsDBNull(1) ? "" : reader.GetString(1);
                var sourceName = reader.IsDBNull(2) ? "" : reader.GetString(2);
                var length = reader.IsDBNull(3) ? 0 : reader.GetInt32(3);
                var scale = reader.IsDBNull(4) ? 0 : reader.GetInt32(4);
                
                AddProperty("Metatype", metatype);
                if (!string.IsNullOrEmpty(sourceSchema))
                    AddProperty("Source", $"{sourceSchema}.{sourceName}");
                if (length > 0)
                    AddProperty("Length", length.ToString());
                if (scale > 0)
                    AddProperty("Scale", scale.ToString());
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load type details");
        }
    }

    private void CopySourceCode_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(SourceCodeTextBox.Text);
            MessageBox.Show("Source code copied to clipboard!", "Success", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            Logger.Debug("Source code copied to clipboard");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy source code");
            MessageBox.Show($"Failed to copy:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void CopyCreateDdl_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(CreateDdlTextBox.Text);
            MessageBox.Show("CREATE DDL copied to clipboard!", "Success", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            Logger.Debug("CREATE DDL copied to clipboard");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy CREATE DDL");
            MessageBox.Show($"Failed to copy:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void CopyDropDdl_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(DropDdlTextBox.Text);
            MessageBox.Show("DROP DDL copied to clipboard!", "Success", 
                MessageBoxButton.OK, MessageBoxImage.Information);
            Logger.Debug("DROP DDL copied to clipboard");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to copy DROP DDL");
            MessageBox.Show($"Failed to copy:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void OpenCreateDdlInNewTab_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (Window.GetWindow(this)?.Owner is MainWindow mainWindow)
            {
                mainWindow.CreateNewTabWithSql(CreateDdlTextBox.Text, $"CREATE {_object.Name}");
                Logger.Info("CREATE DDL opened in new tab");
                Close();
            }
            else
            {
                MessageBox.Show("Unable to open new tab.", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open CREATE DDL in new tab");
            MessageBox.Show($"Failed to open in new tab:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void OpenDropDdlInNewTab_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (Window.GetWindow(this)?.Owner is MainWindow mainWindow)
            {
                mainWindow.CreateNewTabWithSql(DropDdlTextBox.Text, $"DROP {_object.Name}");
                Logger.Info("DROP DDL opened in new tab");
                Close();
            }
            else
            {
                MessageBox.Show("Unable to open new tab.", "Error", 
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open DROP DDL in new tab");
            MessageBox.Show($"Failed to open in new tab:\n\n{ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}

