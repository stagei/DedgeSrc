# Architecture Refinements - Provider-Agnostic Design

**Purpose:** Critical refinements to make the application truly provider-agnostic  
**Date:** November 20, 2025  
**Impact:** Major architectural changes for multi-provider support

---

## 🎯 REFINEMENT 1: Description Text in SQL Statements

### Current Design (WRONG)
```json
{
  "statements": {
    "GetViewsForSchema": {
      "sql": "SELECT...",
      "description_text_key": "sql.descriptions.get_views_for_schema"
    }
  }
}
```

### Corrected Design (RIGHT)
```json
{
  "statements": {
    "GetViewsForSchema": {
      "sql": "SELECT...",
      "description": "Get all views in a specific schema. Returns VIEWNAME, DEFINER, REMARKS, ALTER_TIME. Joins SYSCAT.TABLES and SYSCAT.VIEWS."
    }
  }
}
```

### Rationale
- **Translators know English** - They use `description` as context to understand what the query does
- **Descriptions are technical** - Terms like "SYSCAT.TABLES" should NOT be translated
- **Simpler architecture** - One less lookup in translation files
- **Better developer experience** - SQL descriptions visible directly in the file

### Impact
- Remove `description_text_key` from all SQL statement files
- Add `description` (plain English text) instead
- Update `MetadataHandler.GetQuery()` to return statement with description
- Translators can read descriptions but don't translate them

---

## 🎯 REFINEMENT 2: Common Database Execution Class

### Problem
Currently we have `DB2ConnectionManager` which is DB2-specific. For multi-provider support, we need a **provider-agnostic execution layer**.

### Solution: DbConnectionManager (Generic)

```csharp
namespace DbExplorer.Data;

/// <summary>
/// Provider-agnostic database connection and execution manager
/// Uses metadata handler to execute provider-specific SQL
/// </summary>
public class DbConnectionManager
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly DbConnection _connection; // Generic connection (DB2Connection, NpgsqlConnection, SqlConnection)
    private readonly Provider _provider;
    private readonly string _version;
    private readonly MetadataHandler _metadataHandler;
    
    public DbConnectionManager(
        Provider provider, 
        string version, 
        DbConnectionInfo connectionInfo,
        MetadataHandler metadataHandler)
    {
        _provider = provider;
        _version = version;
        _metadataHandler = metadataHandler;
        _connection = CreateConnection(provider, connectionInfo);
    }
    
    /// <summary>
    /// Create provider-specific connection
    /// </summary>
    private DbConnection CreateConnection(Provider provider, DbConnectionInfo connectionInfo)
    {
        Logger.Debug("Creating connection for provider: {Provider}", provider.ProviderCode);
        
        return provider.ProviderCode switch
        {
            "DB2" => new IBM.Data.Db2.DB2Connection(connectionInfo.ConnectionString),
            "POSTGRESQL" => new Npgsql.NpgsqlConnection(connectionInfo.ConnectionString),
            "SQLSERVER" => new Microsoft.Data.SqlClient.SqlConnection(connectionInfo.ConnectionString),
            "ORACLE" => new Oracle.ManagedDataAccess.Client.OracleConnection(connectionInfo.ConnectionString),
            "MYSQL" => new MySql.Data.MySqlClient.MySqlConnection(connectionInfo.ConnectionString),
            _ => throw new NotSupportedException($"Provider {provider.ProviderCode} not supported")
        };
    }
    
    /// <summary>
    /// Execute query using statement key from metadata
    /// </summary>
    public async Task<DataTable> ExecuteQueryAsync(string statementKey, params object[] parameters)
    {
        Logger.Info("Executing query: {Provider} {Version} {Key}", 
            _provider.ProviderCode, _version, statementKey);
        
        // Get SQL from metadata handler
        var sql = _metadataHandler.GetQuery(_provider.ProviderCode, _version, statementKey);
        
        Logger.Debug("SQL: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        
        return await ExecuteSqlAsync(sql, parameters);
    }
    
    /// <summary>
    /// Execute raw SQL (for cases where SQL is not in metadata)
    /// </summary>
    public async Task<DataTable> ExecuteSqlAsync(string sql, params object[] parameters)
    {
        if (_connection.State != ConnectionState.Open)
        {
            throw new InvalidOperationException("Connection is not open");
        }
        
        using var command = _connection.CreateCommand();
        command.CommandText = sql;
        
        // Add parameters (provider-agnostic)
        for (int i = 0; i < parameters.Length; i++)
        {
            var param = command.CreateParameter();
            param.ParameterName = _provider.ProviderCode switch
            {
                "DB2" => $"@p{i}",
                "POSTGRESQL" => $"@p{i}",
                "SQLSERVER" => $"@p{i}",
                "ORACLE" => $":p{i}",
                "MYSQL" => $"@p{i}",
                _ => $"@p{i}"
            };
            param.Value = parameters[i] ?? DBNull.Value;
            command.Parameters.Add(param);
        }
        
        using var adapter = CreateDataAdapter(command);
        var dataTable = new DataTable();
        
        await Task.Run(() => adapter.Fill(dataTable));
        
        Logger.Info("Query returned {Rows} rows", dataTable.Rows.Count);
        return dataTable;
    }
    
    /// <summary>
    /// Create provider-specific data adapter
    /// </summary>
    private DbDataAdapter CreateDataAdapter(DbCommand command)
    {
        return _provider.ProviderCode switch
        {
            "DB2" => new IBM.Data.Db2.DB2DataAdapter((IBM.Data.Db2.DB2Command)command),
            "POSTGRESQL" => new Npgsql.NpgsqlDataAdapter((Npgsql.NpgsqlCommand)command),
            "SQLSERVER" => new Microsoft.Data.SqlClient.SqlDataAdapter((Microsoft.Data.SqlClient.SqlCommand)command),
            "ORACLE" => new Oracle.ManagedDataAccess.Client.OracleDataAdapter((Oracle.ManagedDataAccess.Client.OracleCommand)command),
            "MYSQL" => new MySql.Data.MySqlClient.MySqlDataAdapter((MySql.Data.MySqlClient.MySqlCommand)command),
            _ => throw new NotSupportedException($"Provider {_provider.ProviderCode} not supported")
        };
    }
    
    /// <summary>
    /// Open connection
    /// </summary>
    public async Task OpenAsync()
    {
        Logger.Info("Opening connection to {Provider} {Version}", _provider.ProviderCode, _version);
        await _connection.OpenAsync();
        Logger.Info("Connection opened successfully");
    }
    
    /// <summary>
    /// Close connection
    /// </summary>
    public void Close()
    {
        _connection?.Close();
        Logger.Info("Connection closed");
    }
}

/// <summary>
/// Provider-agnostic connection information
/// </summary>
public class DbConnectionInfo
{
    public string Name { get; set; } = string.Empty;
    public string Server { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Database { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public int ConnectionTimeout { get; set; } = 30;
    public bool IsReadOnly { get; set; } = false;
    public bool AutoCommit { get; set; } = true;
    
    /// <summary>
    /// Build connection string for specific provider
    /// </summary>
    public string GetConnectionString(Provider provider)
    {
        var template = provider.ConnectionStringTemplate;
        
        return template
            .Replace("{host}", Server)
            .Replace("{port}", Port.ToString())
            .Replace("{database}", Database)
            .Replace("{username}", Username)
            .Replace("{password}", Password);
    }
}
```

### Key Benefits
✅ **Provider-agnostic** - Works with DB2, PostgreSQL, SQL Server, Oracle, MySQL  
✅ **Uses metadata** - SQL queries from ConfigFiles  
✅ **Consistent API** - Same methods for all providers  
✅ **Easy testing** - Mock `MetadataHandler` for unit tests  

---

## 🎯 REFINEMENT 3: Connection Profile with Provider Selection

### Current ConnectionDialog (DB2-specific)
```xml
<Window Title="DB2 Connection Settings">
    <Label Content="Server:"/>
    <TextBox x:Name="ServerTextBox"/>
    <!-- ... -->
</Window>
```

### New ConnectionDialog (Provider-agnostic)

```xml
<Window Title="Database Connection Settings">
    <Grid>
        <!-- NEW: Provider Selection -->
        <Label Content="Database Provider:"/>
        <ComboBox x:Name="ProviderComboBox" 
                  DisplayMemberPath="DisplayName"
                  SelectedValuePath="ProviderCode"
                  SelectionChanged="ProviderComboBox_SelectionChanged">
            <ComboBox.ItemTemplate>
                <DataTemplate>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="{Binding Icon}" FontSize="16" Margin="0,0,5,0"/>
                        <TextBlock Text="{Binding DisplayName}"/>
                    </StackPanel>
                </DataTemplate>
            </ComboBox.ItemTemplate>
        </ComboBox>
        
        <!-- NEW: Version Selection (populated based on provider) -->
        <Label Content="Version:"/>
        <ComboBox x:Name="VersionComboBox" 
                  ItemsSource="{Binding SelectedProvider.SupportedVersions}"/>
        
        <!-- Standard connection fields -->
        <Label Content="Server:"/>
        <TextBox x:Name="ServerTextBox"/>
        
        <Label Content="Port:"/>
        <TextBox x:Name="PortTextBox" Text="{Binding SelectedProvider.DefaultPort}"/>
        
        <Label Content="Database:"/>
        <TextBox x:Name="DatabaseTextBox"/>
        
        <!-- ... rest of fields -->
    </Grid>
</Window>
```

```csharp
// ConnectionDialog.xaml.cs
public partial class ConnectionDialog : Window
{
    private readonly MetadataHandler _metadataHandler;
    private List<Provider> _providers;
    
    public ConnectionDialog(MetadataHandler metadataHandler)
    {
        InitializeComponent();
        _metadataHandler = metadataHandler;
        
        LoadProviders();
    }
    
    private void LoadProviders()
    {
        // Load from ConfigFiles/supported_providers.json
        _providers = _metadataHandler.GetSupportedProviders();
        ProviderComboBox.ItemsSource = _providers;
        
        // Default to DB2 if available
        var defaultProvider = _providers.FirstOrDefault(p => p.ProviderCode == "DB2");
        if (defaultProvider != null)
        {
            ProviderComboBox.SelectedItem = defaultProvider;
        }
    }
    
    private void ProviderComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ProviderComboBox.SelectedItem is Provider provider)
        {
            // Update port to provider's default
            PortTextBox.Text = provider.DefaultPort.ToString();
            
            // Populate versions
            VersionComboBox.ItemsSource = provider.SupportedVersions;
            VersionComboBox.SelectedIndex = 0; // Select first (usually latest)
        }
    }
    
    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        var selectedProvider = (Provider)ProviderComboBox.SelectedItem;
        var selectedVersion = (string)VersionComboBox.SelectedItem;
        
        var connectionInfo = new DbConnectionInfo
        {
            Name = ProfileNameTextBox.Text,
            Server = ServerTextBox.Text,
            Port = int.Parse(PortTextBox.Text),
            Database = DatabaseTextBox.Text,
            Username = UsernameTextBox.Text,
            Password = PasswordBox.Password,
            ConnectionTimeout = int.Parse(ConnectionTimeoutTextBox.Text)
        };
        
        // Create connection manager
        var connectionManager = new DbConnectionManager(
            selectedProvider,
            selectedVersion,
            connectionInfo,
            _metadataHandler
        );
        
        // Test connection...
    }
}
```

### User Experience
1. User opens "New Connection" dialog
2. Dropdown shows: 🗄️ IBM DB2 Database, 🐘 PostgreSQL, 💾 Microsoft SQL Server
3. User selects "🗄️ IBM DB2 Database"
4. Version dropdown populates: 12.1, 11.5, 10.5
5. Port auto-fills to 50000 (DB2 default)
6. User enters server, database, credentials
7. Application creates `DbConnectionManager` for DB2 12.1

---

## 🎯 REFINEMENT 4: Rename DB2 → Db (Provider-Agnostic)

### Naming Strategy

#### **DO Rename (Provider-specific → Provider-agnostic)**

| Old Name | New Name | Reason |
|----------|----------|--------|
| `DB2Connection` (model) | `DbConnectionProfile` | Not DB2-specific |
| `DB2ConnectionManager` (class) | `DbConnectionManager` | Works with any provider |
| `DB2MetadataService` | `DbMetadataService` | Handles all providers |
| `DbExplorer` (namespace) | `DbExplorer` | New application name |
| `DbExplorer.exe` | `DbExplorer.exe` | User-facing executable |

#### **DO NOT Rename (IBM-specific classes)**

| Keep As-Is | Reason |
|------------|--------|
| `IBM.Data.Db2.DB2Connection` | External NuGet package |
| `DB2Parameter` | IBM's class from NuGet |
| `DB2DataAdapter` | IBM's class from NuGet |
| `DB2Exception` | IBM's class from NuGet |

#### **Naming Rules**

1. **"Db" prefix** - Use for provider-agnostic classes
   - `DbConnectionManager` ✅
   - `DbMetadataService` ✅
   - `DbConnectionProfile` ✅

2. **"DB2" prefix** - Only for IBM-specific implementations
   - `DB2SpecificHelper` ✅
   - `DB2Exception` (IBM's class) ✅

3. **"DbExplorer" usage** - Only for:
   - **Executable name**: `DbExplorer.exe` ✅
   - **Window title**: `DbExplorer - Database Tool` ✅
   - **About dialog**: `About DbExplorer` ✅
   - **NOT in code**: ❌ No `DbExplorerService`, `DbExplorerManager`, etc.

### Rename Plan

#### **Phase 1: Core Classes (Week 1)**

```bash
# Models
Models/DB2Connection.cs → Models/DbConnectionProfile.cs
  - Class: DB2Connection → DbConnectionProfile

# Data Layer
Data/DB2ConnectionManager.cs → Data/DbConnectionManager.cs
  - Class: DB2ConnectionManager → DbConnectionManager

# Services
Services/DB2MetadataService.cs → Services/DbMetadataService.cs
  - Class: DB2MetadataService → DbMetadataService
```

#### **Phase 2: Namespace (Week 2)**

```bash
# Rename namespace in ALL files
Find: namespace DbExplorer
Replace: namespace DbExplorer

# Update .csproj
DbExplorer.csproj → DbExplorer.csproj

# Update assembly name
<AssemblyName>DbExplorer</AssemblyName>
→ <AssemblyName>DbExplorer</AssemblyName>

# Update root namespace
<RootNamespace>DbExplorer</RootNamespace>
→ <RootNamespace>DbExplorer</RootNamespace>
```

#### **Phase 3: File References (Week 3)**

```bash
# Update using statements in all .cs files
using DbExplorer.Models;
→ using DbExplorer.Models;

using DbExplorer.Services;
→ using DbExplorer.Services;

# Update XAML namespaces
xmlns:local="clr-namespace:DbExplorer"
→ xmlns:local="clr-namespace:DbExplorer"

xmlns:models="clr-namespace:DbExplorer.Models"
→ xmlns:models="clr-namespace:DbExplorer.Models"
```

#### **Phase 4: User-Facing Text (Week 4)**

```xml
<!-- MainWindow.xaml -->
<Window Title="DB2 Database Editor">
→ <Window Title="DbExplorer">

<!-- About Dialog -->
<TextBlock Text="DbExplorer v1.0"/>
→ <TextBlock Text="DbExplorer v1.0"/>
```

```json
// ConfigFiles/db2_12.1_en-US_texts.json
{
  "MainFormTitle": "DB2 Database Editor"
  → "MainFormTitle": "DbExplorer"
}
```

#### **Phase 5: Build & Deploy (Week 5)**

```xml
<!-- .csproj -->
<PropertyGroup>
  <AssemblyName>DbExplorer</AssemblyName>
  → <AssemblyName>DbExplorer</AssemblyName>
  
  <Product>DbExplorer</Product>
  → <Product>DbExplorer</Product>
</PropertyGroup>

<!-- Output -->
bin/Debug/net10.0-windows/DbExplorer.exe
→ bin/Debug/net10.0-windows/DbExplorer.exe
```

---

## 📋 COMPLETE RENAME CHECKLIST

### Files to Rename

- [ ] `Models/DB2Connection.cs` → `Models/DbConnectionProfile.cs`
- [ ] `Data/DB2ConnectionManager.cs` → `Data/DbConnectionManager.cs`
- [ ] `Services/DB2MetadataService.cs` → `Services/DbMetadataService.cs`
- [ ] `DbExplorer.csproj` → `DbExplorer.csproj`
- [ ] `DbExplorer.sln` → `DbExplorer.sln`

### Code Changes (Find & Replace)

- [ ] `namespace DbExplorer` → `namespace DbExplorer` (all files)
- [ ] `using DbExplorer.` → `using DbExplorer.` (all files)
- [ ] `class DB2Connection` → `class DbConnectionProfile`
- [ ] `class DB2ConnectionManager` → `class DbConnectionManager`
- [ ] `class DB2MetadataService` → `class DbMetadataService`

### XAML Changes

- [ ] `xmlns:local="clr-namespace:DbExplorer"` → `xmlns:local="clr-namespace:DbExplorer"`
- [ ] All other xmlns references

### Text Changes (User-Facing)

- [ ] Window titles: `DB2 Database Editor` → `DbExplorer`
- [ ] About dialog: `DbExplorer` → `DbExplorer`
- [ ] ConfigFiles text files: Update `MainFormTitle` etc.

### Project Settings

- [ ] `<AssemblyName>DbExplorer</AssemblyName>`
- [ ] `<RootNamespace>DbExplorer</RootNamespace>`
- [ ] `<Product>DbExplorer</Product>`

### DO NOT Change

- [ ] `IBM.Data.Db2.DB2Connection` (external NuGet)
- [ ] `DB2Parameter`, `DB2DataAdapter`, `DB2Exception` (external)
- [ ] Any references to IBM's DB2 classes

---

## 🎯 IMPLEMENTATION ORDER

### Week 1: SQL Statements Fix
- [ ] Update all `*_sql_statements.json` files
- [ ] Replace `description_text_key` with `description`
- [ ] Update `MetadataHandler.GetQuery()` to return description
- [ ] Test with existing code

### Week 2: DbConnectionManager
- [ ] Create new `DbConnectionManager` class
- [ ] Implement provider-agnostic execution
- [ ] Test with DB2 (should work exactly as before)
- [ ] Update services to use new class

### Week 3: Connection Dialog
- [ ] Update `ConnectionDialog` to show provider selection
- [ ] Add version dropdown
- [ ] Update connection creation logic
- [ ] Test creating connections for different providers

### Week 4: Rename Core Classes
- [ ] Rename `DB2Connection` → `DbConnectionProfile`
- [ ] Rename `DB2ConnectionManager` → `DbConnectionManager`
- [ ] Rename `DB2MetadataService` → `DbMetadataService`
- [ ] Update all references

### Week 5: Rename Namespace
- [ ] Rename namespace `DbExplorer` → `DbExplorer`
- [ ] Rename project files
- [ ] Update all using statements
- [ ] Update XAML namespaces

### Week 6: Testing & Verification
- [ ] Test with DB2 (ensure nothing broken)
- [ ] Test provider selection in connection dialog
- [ ] Verify executable name is `DbExplorer.exe`
- [ ] Update documentation

---

## 🔄 BACKWARD COMPATIBILITY

### Connection Profiles Migration

```csharp
// Migrate old DB2Connection profiles to new DbConnectionProfile
public class ProfileMigrationService
{
    public List<DbConnectionProfile> MigrateOldProfiles()
    {
        var oldProfiles = LoadOldDB2Connections(); // From old JSON
        var newProfiles = new List<DbConnectionProfile>();
        
        foreach (var oldProfile in oldProfiles)
        {
            var newProfile = new DbConnectionProfile
            {
                Id = oldProfile.Id,
                Name = oldProfile.Name,
                ProviderCode = "DB2", // All old profiles are DB2
                ProviderVersion = "12.1", // Default to 12.1
                Server = oldProfile.Server,
                Port = oldProfile.Port,
                Database = oldProfile.Database,
                Username = oldProfile.Username,
                Password = oldProfile.Password
            };
            
            newProfiles.Add(newProfile);
        }
        
        return newProfiles;
    }
}
```

---

## 📊 BEFORE & AFTER COMPARISON

### Before (DB2-specific)
```csharp
// Creating a connection
var connection = new DB2Connection
{
    Name = "Production",
    Server = "db2server",
    Port = 50000,
    Database = "TESTDB"
};

var manager = new DB2ConnectionManager(connection);
await manager.OpenAsync();

// Executing query (hardcoded SQL)
var sql = "SELECT * FROM SYSCAT.TABLES";
var results = await manager.ExecuteQueryAsync(sql);
```

### After (Provider-agnostic)
```csharp
// Creating a connection
var profile = new DbConnectionProfile
{
    Name = "Production",
    ProviderCode = "DB2",
    ProviderVersion = "12.1",
    Server = "db2server",
    Port = 50000,
    Database = "TESTDB"
};

var manager = new DbConnectionManager(provider, version, profile, metadataHandler);
await manager.OpenAsync();

// Executing query (from metadata)
var results = await manager.ExecuteQueryAsync("AllTablesStatement");
```

---

## 🎯 SUCCESS CRITERIA

✅ **SQL descriptions in plain English** - No `description_text_key`  
✅ **DbConnectionManager works** - Provider-agnostic execution  
✅ **Connection dialog shows providers** - User can select DB2, PostgreSQL, etc.  
✅ **All DB2* classes renamed** - Except IBM's NuGet classes  
✅ **Namespace is DbExplorer** - All files updated  
✅ **Executable is DbExplorer.exe** - User-facing name  
✅ **"DbExplorer" NOT in code** - Only in exe name and UI text  
✅ **Backward compatible** - Old profiles migrated  
✅ **Build succeeds** - No compilation errors  
✅ **Tests pass** - All functionality works  

---

**Status:** 📋 REFINEMENTS DOCUMENTED  
**Next Step:** Begin Week 1 implementation (SQL statements fix)  
**Estimated Effort:** 6 weeks for complete implementation

