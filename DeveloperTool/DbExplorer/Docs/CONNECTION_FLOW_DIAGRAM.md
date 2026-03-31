# DbExplorer - Database Connection Flow Diagram

**Complete flow from user connection to database objects ready**

---

## 📊 CONNECTION FLOW OVERVIEW

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER INITIATES CONNECTION                     │
│  (Click "New Connection" or select from Recent Connections)     │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    MainWindow.xaml.cs                            │
│  File: MainWindow.xaml.cs                                       │
│  Method: NewConnection_Click() or RecentConnection_Click()      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  ConnectionDialog OPENS                          │
│  File: Dialogs/ConnectionDialog.xaml                            │
│  Class: ConnectionDialog                                        │
│  User enters:                                                   │
│    - Server, Port, Database                                     │
│    - Username, Password                                         │
│    - Read-Only checkbox (Feature #2)                            │
│    - Auto-Commit checkbox (Feature #2)                          │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│            User Clicks "Connect" Button                          │
│  File: Dialogs/ConnectionDialog.xaml.cs                         │
│  Method: Connect_Click()                                        │
│  Creates: DB2Connection object from inputs                      │
│  Calls: GetConnectionFromInputs()                               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Create DB2Connection Model                          │
│  File: Models/DB2Connection.cs                                  │
│  Properties Set:                                                │
│    - Server, Port, Database                                     │
│    - Username, Password                                         │
│    - IsReadOnly (bool)                                          │
│    - AutoCommit (bool)                                          │
│    - ConnectionTimeout (int)                                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│          Save Connection to Storage (Encrypted)                  │
│  File: Services/ConnectionStorageService.cs                     │
│  Method: SaveConnection(DB2Connection)                          │
│  Storage: %LOCALAPPDATA%\DbExplorer\connections.json      │
│  Password: Encrypted with ProtectedData                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│            ConnectionDialog Returns to MainWindow                │
│  File: MainWindow.xaml.cs                                       │
│  Method: AddConnectionTab(DB2Connection)                        │
│  Creates: New TabItem with ConnectionTabControl                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│          ConnectionTabControl Constructor Runs                   │
│  File: Controls/ConnectionTabControl.xaml.cs                    │
│  Constructor: ConnectionTabControl(DB2Connection connection)    │
│  Creates:                                                       │
│    - DB2ConnectionManager (_connectionManager)                  │
│    - SqlFormatterService                                        │
│    - QueryHistoryService                                        │
│    - ExportService                                              │
│    - PreferencesService                                         │
│  Calls:                                                         │
│    - InitializeSqlEditor()                                      │
│    - RegisterKeyboardShortcuts()                                │
│    - RegisterResultsGridEvents() (Issue #1 fix)                 │
│    - ConnectToDatabase() [async, fire-and-forget]              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              DB2ConnectionManager Created                        │
│  File: Data/DB2ConnectionManager.cs                             │
│  Constructor: DB2ConnectionManager(DB2Connection)               │
│  Stores: _connectionInfo (DB2Connection)                        │
│  Fields:                                                        │
│    - _db2Connection (IBM.Data.Db2.DB2Connection)                │
│    - _connectionInfo (Models.DB2Connection)                     │
│    - _disposed (bool)                                           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│         ConnectionTabControl.ConnectToDatabase() Runs            │
│  File: Controls/ConnectionTabControl.xaml.cs                    │
│  Method: private async Task ConnectToDatabase()                 │
│  Status: "Connecting..." displayed                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│           DB2ConnectionManager.OpenAsync() Called                │
│  File: Data/DB2ConnectionManager.cs                             │
│  Method: public async Task OpenAsync()                          │
│                                                                 │
│  STEP 1: Create IBM DB2 Connection                             │
│    Creates: new DB2Conn(_connectionInfo.GetConnectionString()) │
│    Package: IBM.Data.Db2                                        │
│    Connection String Format:                                    │
│      "Server={host}:{port};Database={db};UID={user};PWD={pwd};" │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│         STEP 2: Open Physical DB2 Connection                    │
│  Method: await _db2Connection.OpenAsync()                       │
│  Network: Connects to DB2 server over TCP/IP                   │
│  Driver: Net.IBM.Data.Db2 9.0.0.400 (native, no client needed) │
│  Logging: Connection string logged (password masked)            │
│           Server version logged                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│         STEP 3: Set Auto-Commit Mode (Feature #2)               │
│  File: Data/DB2ConnectionManager.cs                             │
│  Method: await SetAutoCommitModeAsync(bool autoCommit)          │
│  SQL Executed:                                                  │
│    If autoCommit: "SET AUTOCOMMIT ON"                          │
│    Else: "SET AUTOCOMMIT OFF"                                  │
│  Logging: Mode logged (ON or OFF)                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│      STEP 4: Determine User Access Level (RBAC Security)        │
│  File: Data/DB2ConnectionManager.cs                             │
│  Method: await DetermineUserAccessLevelAsync()                  │
│                                                                 │
│  Creates: AccessControlService                                 │
│  Calls: accessControlService.DetermineAccessLevelAsync()       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│        AccessControlService.DetermineAccessLevelAsync()          │
│  File: Services/AccessControlService.cs                         │
│                                                                 │
│  STEP 4A: Parse Username (Remove Domain)                       │
│    Method: ParseUsernameWithoutDomain(fullUsername)            │
│    Examples:                                                    │
│      "DOMAIN\username" → "username"                            │
│      "username@domain.com" → "username"                        │
│      "username" → "username"                                   │
│                                                                 │
│  STEP 4B: Query SYSCAT.DBAUTH                                  │
│    SQL: SELECT * FROM SYSCAT.DBAUTH                            │
│         WHERE GRANTEE = '{username}'                           │
│                                                                 │
│  STEP 4C: Classify User Access Level                           │
│    ┌─────────────────────────────────────┐                    │
│    │ No rows found in DBAUTH?            │                    │
│    │ → LOW Level (Read-Only)             │                    │
│    │   CanExecuteDDL = false              │                    │
│    │   CanExecuteDML = false              │                    │
│    │   CanForceDisconnect = false         │                    │
│    └─────────────────────────────────────┘                    │
│    ┌─────────────────────────────────────┐                    │
│    │ Row found, DBADMAUTH = 'Y'?         │                    │
│    │ → DBA Level (Full Access)           │                    │
│    │   CanExecuteDDL = true               │                    │
│    │   CanExecuteDML = true               │                    │
│    │   CanForceDisconnect = true          │                    │
│    │   CanModifyStatistics = true         │                    │
│    │   CanModifyCDC = true                │                    │
│    │   CanDropObjects = true              │                    │
│    └─────────────────────────────────────┘                    │
│    ┌─────────────────────────────────────┐                    │
│    │ Row found, DBADMAUTH ≠ 'Y'?         │                    │
│    │ → MIDDLE Level (Standard User)      │                    │
│    │   CanExecuteDDL = false              │                    │
│    │   CanExecuteDML = true (DML only)    │                    │
│    │   CanForceDisconnect = false         │                    │
│    └─────────────────────────────────────┘                    │
│                                                                 │
│  Returns: UserPermissions object                               │
│  Logging: Access level determination logged                    │
│  Error Handling: Defaults to LOW on error (secure)             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│       Store Permissions in DB2Connection Object                 │
│  File: Models/DB2Connection.cs                                  │
│  Property: Permissions (UserPermissions)                        │
│  Property: IsAccessLevelDetermined (bool)                       │
│  Logging: "Connection mode - ReadOnly: {bool}, AutoCommit: {bool}"│
│           "User {username} access level: {DBA/Middle/Low}"     │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│      OpenAsync() Completes - Returns to ConnectToDatabase()     │
│  File: Controls/ConnectionTabControl.xaml.cs                    │
│  Status: "Connected to {database} @ {server}"                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│         STEP 5: Update Access Level UI Indicator                │
│  File: Controls/ConnectionTabControl.xaml.cs                    │
│  Method: UpdateAccessLevelIndicator()                          │
│                                                                 │
│  If (_connection.Permissions == null):                         │
│    → Hide badge                                                │
│  Else:                                                          │
│    → Set AccessLevelText = permissions.AccessLevelBadge        │
│       ("🛡️ DBA" / "👤 USER" / "🔒 READ-ONLY")                │
│    → Set Badge Background Color:                               │
│       DBA = Green, Middle = Orange, Low = Red                  │
│    → Set Tooltip = permissions.PermissionsTooltip              │
│    → Show badge (Visibility = Visible)                         │
│                                                                 │
│  UI Element: AccessLevelBadge (Border in toolbar)              │
│  File: Controls/ConnectionTabControl.xaml                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│         STEP 6: Load Database Objects into TreeView             │
│  File: Controls/ConnectionTabControl.xaml.cs                    │
│  Method: await LoadDatabaseObjectsAsync()                      │
│                                                                 │
│  Actions:                                                       │
│    1. Clear DatabaseTreeView.Items                             │
│    2. Add "⏳ Loading schemas..." node                         │
│    3. Query schemas, tables, views                             │
│    4. Populate tree view (not fully implemented)               │
│                                                                 │
│  UI Element: DatabaseTreeView (TreeView in left panel)         │
│  Note: Basic implementation, can be enhanced                   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│         STEP 7: Load Query History                              │
│  File: Controls/ConnectionTabControl.xaml.cs                    │
│  Method: RefreshQueryHistory()                                 │
│                                                                 │
│  Uses: QueryHistoryService                                     │
│  File: Services/QueryHistoryService.cs                          │
│  Method: GetQueryHistory()                                     │
│  Storage: %LOCALAPPDATA%\DbExplorer\query_history.db     │
│                                                                 │
│  Displays: Recent queries in History tab (left panel)          │
│  Features: Search, filter, double-click to load               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│    STEP 8: Update Menu Visibility (RBAC - Optional)            │
│  File: MainWindow.xaml.cs                                       │
│  Method: UpdateMenuVisibilityForAccessLevel(UserPermissions)   │
│                                                                 │
│  If permissions != null:                                       │
│    - Log access level                                          │
│    - Check menu item tags (Tag="AccessLevel:DBA/Middle/Low")  │
│    - Show/hide based on user's level                           │
│    (Currently: Framework in place, graceful degradation)       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              CONNECTION COMPLETE - READY TO USE                  │
│                                                                 │
│  Status: Connected                                              │
│  UI Elements Ready:                                             │
│    ✅ SQL Editor (AvalonEdit) - Ready for queries              │
│    ✅ Results Grid (DataGrid) - Ready for results              │
│    ✅ Database Objects Tree - Loaded                            │
│    ✅ Query History - Populated                                 │
│    ✅ Access Level Badge - Displaying                           │
│    ✅ Toolbar Buttons - Active                                  │
│    ✅ Status Bar - Shows connection status                      │
│                                                                 │
│  User Can Now:                                                  │
│    - Execute SQL queries (F5 or Ctrl+Enter)                    │
│    - Browse database objects                                    │
│    - Access monitoring features (View menu)                     │
│    - View query history                                         │
│    - All operations respect RBAC permissions                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔍 DETAILED CLASS AND METHOD FLOW

### Phase 1: Connection Initiation

```
USER ACTION
   │
   ▼
MainWindow.xaml.cs
└── NewConnection_Click(object sender, RoutedEventArgs e)
    │
    ├── Creates: new ConnectionDialog { Owner = this }
    │   │
    │   └── File: Dialogs/ConnectionDialog.xaml
    │       File: Dialogs/ConnectionDialog.xaml.cs
    │
    └── Shows: dialog.ShowDialog()
        │
        └── If DialogResult == true && dialog.Connection != null:
            │
            └── Calls: AddConnectionTab(dialog.Connection)
```

### Phase 2: Connection Dialog

```
ConnectionDialog
File: Dialogs/ConnectionDialog.xaml.cs

Constructor:
└── InitializeComponent()
    └── Loads XAML UI (ConnectionDialog.xaml)

User Fills Form:
├── NameTextBox.Text → Connection Name
├── ServerTextBox.Text → Server
├── PortTextBox.Text → Port (default: 50000)
├── DatabaseTextBox.Text → Database
├── UsernameTextBox.Text → Username
├── PasswordBox.Password → Password
├── ReadOnlyCheckBox.IsChecked → IsReadOnly (Feature #2)
└── AutoCommitCheckBox.IsChecked → AutoCommit (Feature #2)

User Clicks "Connect":
└── Connect_Click(object sender, RoutedEventArgs e)
    │
    ├── Calls: GetConnectionFromInputs()
    │   │
    │   └── Returns: new DB2Connection
    │       {
    │           Name = NameTextBox.Text,
    │           Server = ServerTextBox.Text,
    │           Port = int.Parse(PortTextBox.Text),
    │           Database = DatabaseTextBox.Text,
    │           Username = UsernameTextBox.Text,
    │           Password = PasswordBox.Password,
    │           IsReadOnly = ReadOnlyCheckBox.IsChecked ?? false,
    │           AutoCommit = AutoCommitCheckBox.IsChecked ?? true
    │       }
    │
    ├── Calls: _storageService.SaveConnection(connection)
    │   File: Services/ConnectionStorageService.cs
    │   Method: SaveConnection(DB2Connection)
    │   Encrypts: Password with ProtectedData
    │   Saves: To connections.json
    │
    ├── Sets: Connection = connection
    └── Sets: DialogResult = true
        └── Dialog closes, returns to MainWindow
```

### Phase 3: Create Connection Tab

```
MainWindow.xaml.cs
└── AddConnectionTab(Models.DB2Connection connection)
    │
    ├── Creates: var tabControl = new ConnectionTabControl(connection)
    │   │
    │   └── Constructor Runs (see Phase 4)
    │
    ├── Creates: new TabItem
    │   {
    │       Header = CreateTabHeader(connection.GetDisplayName()),
    │       Content = tabControl
    │   }
    │
    ├── Adds: ConnectionTabs.Items.Add(tabItem)
    ├── Selects: ConnectionTabs.SelectedItem = tabItem
    ├── Updates: UpdatePlaceholderVisibility()
    └── Updates: UpdateMenuVisibilityForAccessLevel(connection.Permissions)
        (If access level determined)
```

### Phase 4: ConnectionTabControl Initialization

```
ConnectionTabControl Constructor
File: Controls/ConnectionTabControl.xaml.cs

Constructor: ConnectionTabControl(DB2Connection connection)
│
├── Stores: _connection = connection
│
├── Creates Service Instances:
│   ├── _connectionManager = new DB2ConnectionManager(connection)
│   │   File: Data/DB2ConnectionManager.cs
│   │   Stores: _connectionInfo = connection
│   │
│   ├── _formatterService = new SqlFormatterService()
│   ├── _queryHistoryService = new QueryHistoryService()
│   ├── _exportService = new ExportService()
│   └── _preferencesService = new PreferencesService()
│
├── Initializes UI:
│   └── InitializeSqlEditor()
│       │
│       ├── Loads: DB2SQL.xshd syntax highlighting
│       │   File: Resources/DB2SQL.xshd
│       │
│       ├── Sets: SqlEditor.SyntaxHighlighting
│       ├── Sets: SqlEditor.FontFamily = "Consolas"
│       ├── Sets: SqlEditor.FontSize = 14
│       ├── Sets: SqlEditor.ShowLineNumbers = true
│       └── Logs: "SQL Editor initialized with DB2 syntax highlighting"
│
├── Registers Events:
│   ├── RegisterKeyboardShortcuts()
│   │   ├── F5 → ExecuteQuery()
│   │   ├── Ctrl+Enter → ExecuteCurrentStatement()
│   │   ├── Ctrl+Shift+F → FormatSql()
│   │   ├── Ctrl+S → SaveScript()
│   │   └── Ctrl+O → OpenScript()
│   │
│   └── RegisterResultsGridEvents() (Issue #1 fix)
│       └── ResultsGrid.PreviewMouseRightButtonDown += handler
│           (Captures cell info before context menu)
│
└── Connects to Database:
    └── _ = ConnectToDatabase() [Fire-and-forget async]
```

### Phase 5: Database Connection

```
ConnectionTabControl.ConnectToDatabase()
File: Controls/ConnectionTabControl.xaml.cs
Method: private async Task ConnectToDatabase()

├── Updates UI: StatusText.Text = "Connecting..."
│
├── Calls: await _connectionManager.OpenAsync()
│   │
│   └── DB2ConnectionManager.OpenAsync() - SEE PHASE 6
│
├── Updates UI: StatusText.Text = "Connected to {name}"
│
├── Calls: UpdateAccessLevelIndicator() [RBAC]
│   └── Updates access badge in toolbar
│
├── Calls: await LoadDatabaseObjectsAsync()
│   └── Populates DatabaseTreeView with schemas/tables
│
└── Calls: RefreshQueryHistory()
    └── Loads query history into History tab
```

### Phase 6: DB2ConnectionManager.OpenAsync() - DETAILED

```
DB2ConnectionManager.OpenAsync()
File: Data/DB2ConnectionManager.cs
Method: public async Task OpenAsync()

STEP 1: Check if already open
├── If (_db2Connection != null && _db2Connection.State == ConnectionState.Open)
│   └── Return (already open)

STEP 2: Create DB2 Connection Object
├── Logging: "Opening DB2 connection"
├── Logging: Connection string (password masked)
│
└── _db2Connection = new DB2Conn(_connectionInfo.GetConnectionString())
    │
    └── GetConnectionString() builds:
        "Server={host}:{port};Database={db};UID={user};PWD={pass};" +
        "ConnectTimeout={timeout};"

STEP 3: Open Physical Connection
├── await _db2Connection.OpenAsync()
│   │
│   ├── Network: TCP/IP connection to DB2 server
│   ├── Package: Net.IBM.Data.Db2 9.0.0.400
│   ├── Protocol: DB2 native protocol
│   └── Authentication: DB2 username/password
│
├── Logging: "DB2 connection opened successfully"
├── Logging: "State: {_db2Connection.State}"
└── Logging: "Server Version: {_db2Connection.ServerVersion}"

STEP 4: Set Auto-Commit Mode (Feature #2)
└── await SetAutoCommitModeAsync(_connectionInfo.AutoCommit)
    │
    ├── Method: private async Task SetAutoCommitModeAsync(bool autoCommit)
    │
    ├── Creates: DB2Command
    │
    ├── SQL: autoCommit ? "SET AUTOCOMMIT ON" : "SET AUTOCOMMIT OFF"
    │
    ├── Executes: await command.ExecuteNonQueryAsync()
    │
    ├── Logging: "Auto-commit mode set to: {ON/OFF}"
    │
    └── Error Handling: Catches DB2Exception, logs warning, continues
        (Some DB2 versions may not support SET AUTOCOMMIT)

STEP 5: Determine User Access Level (RBAC)
└── await DetermineUserAccessLevelAsync()
    │
    ├── Method: private async Task DetermineUserAccessLevelAsync()
    │
    ├── Creates: new AccessControlService()
    │   File: Services/AccessControlService.cs
    │
    ├── Calls: accessControlService.DetermineAccessLevelAsync(this, username)
    │   │
    │   └── Queries SYSCAT.DBAUTH
    │       Determines: DBA / Middle / Low
    │       Returns: UserPermissions object
    │
    ├── Stores: _connectionInfo.Permissions = userPermissions
    │
    ├── Logging: "User {username} access level determined: {level}"
    ├── Logging: "Access level badge: {badge}"
    │
    └── Error Handling: Defaults to LOW on error
        Logging: "SECURITY: Defaulting to LOW access due to error"

STEP 6: Log Final Connection Status
├── Logging: "Connection mode - ReadOnly: {bool}, AutoCommit: {bool}"
├── Logging: "User permissions - DDL: {bool}, DML: {bool}, ..."
└── Returns: (OpenAsync completes successfully)
```

### Phase 7: Post-Connection UI Updates

```
Back in ConnectionTabControl.ConnectToDatabase()

STEP 1: Update Access Level Badge
└── UpdateAccessLevelIndicator()
    File: Controls/ConnectionTabControl.xaml.cs
    Method: private void UpdateAccessLevelIndicator()
    
    If _connection.Permissions != null:
    ├── AccessLevelText.Text = permissions.AccessLevelBadge
    ├── AccessLevelText.ToolTip = permissions.PermissionsTooltip
    ├── AccessLevelBadge.Background = Color based on level
    │   ├── Green → DBA
    │   ├── Orange → Middle
    │   └── Red → Low
    ├── AccessLevelBadge.Visibility = Visible
    └── Logging: "Access level indicator updated: {badge} ({color})"

STEP 2: Load Database Objects
└── await LoadDatabaseObjectsAsync()
    File: Controls/ConnectionTabControl.xaml.cs
    
    ├── DatabaseTreeView.Items.Clear()
    ├── Add loading indicator
    ├── Query database metadata (schemas, tables)
    └── Populate tree view
        (Basic implementation - can be enhanced)

STEP 3: Load Query History
└── RefreshQueryHistory()
    File: Controls/ConnectionTabControl.xaml.cs
    
    Uses: _queryHistoryService
    ├── Loads: Query history from encrypted database
    ├── Filters: By connection (if ShowAllConnections unchecked)
    ├── Filters: By search text (if provided)
    ├── Binds: QueryHistoryListBox.ItemsSource = filtered history
    └── Displays: In "📜 History" tab (left panel)

STEP 4: Final Status
├── StatusText.Text = "Connected to {database} @ {server}"
├── UI is now fully interactive
└── User can execute queries, browse objects, access features
```

---

## 🔒 RBAC SECURITY FLOW (Detailed)

### AccessControlService.DetermineAccessLevelAsync()

```
Input: DB2ConnectionManager, fullUsername (e.g., "DOMAIN\user")

STEP 1: Parse Username
└── ParseUsernameWithoutDomain(fullUsername)
    │
    ├── If contains "\": Split and take [1]
    │   Example: "DOMAIN\user" → "user"
    │
    ├── If contains "@": Split and take [0]
    │   Example: "user@domain.com" → "user"
    │
    └── Else: Return as-is
        Example: "user" → "user"

STEP 2: Query SYSCAT.DBAUTH
└── SQL Query:
    SELECT * FROM SYSCAT.DBAUTH 
    WHERE GRANTEE = '{parsed_username}'
    
    ├── Executes: connectionManager.ExecuteQueryAsync(sql)
    │
    └── Returns: DataTable with 0 or 1 row

STEP 3: Classify Access Level
└── If result.Rows.Count == 0:
    ├── User NOT in DBAUTH
    ├── Access Level: LOW (Read-Only)
    ├── Permissions:
    │   - CanExecuteDDL = false
    │   - CanExecuteDML = false
    │   - CanForceDisconnect = false
    │   - CanModifyStatistics = false
    │   - CanModifyCDC = false
    │   - CanDropObjects = false
    ├── Badge: "🔒 READ-ONLY" (Red)
    └── Logging: "User assigned LOW access level (not in DBAUTH)"

└── Else If row["DBADMAUTH"] == "Y":
    ├── User HAS DBA authority
    ├── Access Level: DBA (Full Access)
    ├── Permissions:
    │   - CanExecuteDDL = true
    │   - CanExecuteDML = true
    │   - CanForceDisconnect = true
    │   - CanModifyStatistics = true
    │   - CanModifyCDC = true
    │   - CanDropObjects = true
    ├── Badge: "🛡️ DBA" (Green)
    ├── Logging: "User assigned DBA access level (DBADMAUTH = Y)"
    └── Logs all granted authorities (columns ending with "AUTH" = "Y")

└── Else:
    ├── User in DBAUTH but not DBA
    ├── Access Level: MIDDLE (Standard User)
    ├── Permissions:
    │   - CanExecuteDDL = false (Cannot ALTER, CREATE, DROP)
    │   - CanExecuteDML = true (Can INSERT, UPDATE, DELETE, SELECT)
    │   - CanForceDisconnect = false
    │   - CanModifyStatistics = false
    │   - CanModifyCDC = false
    │   - CanDropObjects = false
    ├── Badge: "👤 USER" (Orange)
    └── Logging: "User assigned MIDDLE access level"

STEP 4: Return UserPermissions Object
└── return new UserPermissions
    {
        AccessLevel = {determined level},
        Username = parsed_username,
        Can* flags set appropriately,
        GrantedAuthorities = list of authorities,
        AccessLevelBadge = emoji + text,
        BadgeColor = color name,
        PermissionsTooltip = description
    }

ERROR HANDLING:
└── If query fails or exception occurs:
    ├── Logs: Error details
    ├── Logs: "SECURITY: Defaulting to LOW access due to error"
    └── Returns: UserPermissions with AccessLevel = LOW
        (Fail-safe: Default to read-only for security)
```

---

## 🔐 SQL Execution with RBAC Validation

### When User Executes Query

```
User presses F5 or Ctrl+Enter
   │
   ▼
ConnectionTabControl.ExecuteQuery()
File: Controls/ConnectionTabControl.xaml.cs
   │
   ├── Gets SQL text from SqlEditor
   ├── Shows "Executing..." status
   │
   └── Calls: await _connectionManager.ExecuteQueryAsync(sql, maxRows, offset)
       │
       └── DB2ConnectionManager.ExecuteQueryAsync()
           File: Data/DB2ConnectionManager.cs
           
           VALIDATION CHECKS (in order):
           
           1. Connection Open Check:
           └── If _db2Connection == null || State != Open:
               └── Throws: InvalidOperationException("Connection is not open")
           
           2. Read-Only Mode Check (Feature #2):
           └── If _connectionInfo.IsReadOnly && IsModifyingSql(sql):
               └── Throws: InvalidOperationException(
                   "This connection is in read-only mode. " +
                   "Data modification statements are not allowed.")
           
           3. RBAC Permission Check:
           └── If _connectionInfo.Permissions != null && IsModifyingSql(sql):
               │
               ├── If AccessLevel == LOW:
               │   └── Throws: UnauthorizedAccessException(
               │       "Access Denied: You have READ-ONLY access. " +
               │       "Only SELECT statements are allowed.")
               │
               └── If AccessLevel == MIDDLE:
                   └── Check if SQL contains DDL keywords:
                       (CREATE, DROP, ALTER, TRUNCATE, GRANT, REVOKE)
                       └── Throws: UnauthorizedAccessException(
                           "Access Denied: You have STANDARD USER access. " +
                           "DDL statements require DBA privileges.")
           
           4. Execute Query (If all checks pass):
           └── Creates: DB2Command
           └── Sets: CommandText, CommandTimeout
           └── Creates: DB2DataAdapter
           └── Executes: adapter.Fill(dataTable)
           └── Returns: DataTable with results
```

### IsModifyingSql() Logic (Three-Tier RBAC)

```
DB2ConnectionManager.IsModifyingSql(string sql)
File: Data/DB2ConnectionManager.cs

Input: SQL statement (string)

STEP 1: Normalize SQL
└── sqlUpper = sql.Trim().ToUpperInvariant()

STEP 2: Check Access Level
│
├── If AccessLevel == LOW (Read-Only):
│   │
│   ├── isSelect = sqlUpper.StartsWith("SELECT") ||
│   │            sqlUpper.StartsWith("WITH") ||    // CTEs
│   │            sqlUpper.StartsWith("VALUES")     // VALUES clause
│   │
│   ├── isModifying = !isSelect
│   ├── Logging: "LOW level user - SQL is modifying: {bool}"
│   └── Return: isModifying
│
├── If AccessLevel == MIDDLE (Standard User):
│   │
│   ├── Check for DDL keywords:
│   │   ddlKeywords = ["CREATE", "DROP", "ALTER", "TRUNCATE", "GRANT", "REVOKE"]
│   │
│   ├── isModifying = Regex.IsMatch(sqlUpper, @"\b{keyword}\b")
│   │   for any DDL keyword
│   │
│   ├── Logging: "MIDDLE level user - SQL is DDL: {bool}"
│   └── Return: isModifying (true if DDL, false if DML)
│
└── If AccessLevel == DBA (Full Access):
    │
    ├── Check for any modifying keywords:
    │   modifyingKeywords = ["INSERT", "UPDATE", "DELETE", "DROP", 
    │                         "CREATE", "ALTER", "TRUNCATE", 
    │                         "GRANT", "REVOKE", "MERGE"]
    │
    ├── isModifying = Regex.IsMatch(sqlUpper, @"\b{keyword}\b")
    │   for any modifying keyword
    │
    ├── Logging: "DBA level check - SQL is modifying: {bool}"
    └── Return: isModifying
        (Used to check IsReadOnly setting only)
```

---

## 📂 FILE DEPENDENCY MAP

### Connection Flow Files (In Order of Execution)

```
1. MainWindow.xaml.cs
   ├── Triggers: NewConnection_Click() or RecentConnection_Click()
   └── Creates: ConnectionDialog

2. Dialogs/ConnectionDialog.xaml
   └── Dialogs/ConnectionDialog.xaml.cs
       ├── Uses: Models/DB2Connection.cs
       ├── Uses: Services/ConnectionStorageService.cs
       └── Returns: DB2Connection object

3. MainWindow.xaml.cs
   └── AddConnectionTab(DB2Connection)
       ├── Creates: ConnectionTabControl
       └── Uses: Controls/ConnectionTabControl.xaml

4. Controls/ConnectionTabControl.xaml.cs
   ├── Creates: Data/DB2ConnectionManager.cs
   ├── Creates: Services/SqlFormatterService.cs
   ├── Creates: Services/QueryHistoryService.cs
   ├── Creates: Services/ExportService.cs
   ├── Creates: Services/PreferencesService.cs
   └── Calls: ConnectToDatabase()

5. Data/DB2ConnectionManager.cs
   ├── Uses: IBM.Data.Db2.DB2Connection (NuGet package)
   ├── Uses: Models/DB2Connection.cs
   ├── Calls: SetAutoCommitModeAsync()
   ├── Creates: Services/AccessControlService.cs
   └── Calls: DetermineUserAccessLevelAsync()

6. Services/AccessControlService.cs
   ├── Uses: Models/UserAccessLevel.cs
   ├── Uses: Data/DB2ConnectionManager.cs (for ExecuteQueryAsync)
   ├── Queries: SYSCAT.DBAUTH
   └── Returns: UserPermissions object

7. Back to Controls/ConnectionTabControl.xaml.cs
   ├── Calls: UpdateAccessLevelIndicator()
   ├── Calls: LoadDatabaseObjectsAsync()
   └── Calls: RefreshQueryHistory()

8. Connection Ready
   └── User can execute queries, access features
```

---

## 🎯 KEY CLASSES AND THEIR ROLES

### Models (Data Structures)

**Models/DB2Connection.cs**
- Purpose: Store connection configuration
- Properties: Server, Port, Database, Username, Password, IsReadOnly, AutoCommit, Permissions
- Methods: GetConnectionString(), GetDisplayName(), IsValid()
- Used by: ConnectionDialog, DB2ConnectionManager, ConnectionTabControl

**Models/UserAccessLevel.cs** (RBAC)
- Enum: UserAccessLevel (Low, Middle, DBA)
- Class: UserPermissions
- Properties: AccessLevel, Username, Can* flags, GrantedAuthorities, AccessLevelBadge, BadgeColor
- Used by: AccessControlService, DB2ConnectionManager, ConnectionTabControl

### Services (Business Logic)

**Data/DB2ConnectionManager.cs**
- Purpose: Manage DB2 database connections
- Key Methods:
  - OpenAsync() - Open connection
  - CloseAsync() - Close connection
  - ExecuteQueryAsync() - Execute SQL with RBAC validation
  - SetAutoCommitModeAsync() - Set transaction mode
  - DetermineUserAccessLevelAsync() - Get user permissions
  - IsModifyingSql() - Check if SQL is modifying (three-tier logic)
  - CommitAsync() - Commit transaction
  - RollbackAsync() - Rollback transaction
- Uses: IBM.Data.Db2.DB2Connection, AccessControlService
- Used by: ConnectionTabControl, all monitoring panels

**Services/AccessControlService.cs** (RBAC)
- Purpose: Determine user access level from DB2 DBAUTH
- Key Methods:
  - DetermineAccessLevelAsync() - Query DBAUTH and classify user
  - ParseUsernameWithoutDomain() - Remove domain prefix
  - CanUserPerformOperation() - Validate specific operations
- Queries: SYSCAT.DBAUTH
- Returns: UserPermissions object
- Used by: DB2ConnectionManager

**Services/ConnectionStorageService.cs**
- Purpose: Persist connection profiles
- Methods: SaveConnection(), LoadConnections(), GetConnection()
- Storage: %LOCALAPPDATA%\DbExplorer\connections.json
- Encryption: ProtectedData for passwords
- Used by: ConnectionDialog, MainWindow

**Services/QueryHistoryService.cs**
- Purpose: Track and retrieve query history
- Storage: SQLite database
- Features: Encrypted SQL storage, search, filtering
- Used by: ConnectionTabControl

### UI Components

**Controls/ConnectionTabControl.xaml** + **.xaml.cs**
- Purpose: Main connection interface (SQL editor, results, objects tree, history)
- Key Methods:
  - Constructor: Initializes all services
  - ConnectToDatabase() - Main connection orchestration
  - UpdateAccessLevelIndicator() - Update RBAC badge
  - LoadDatabaseObjectsAsync() - Populate tree view
  - RefreshQueryHistory() - Load history
  - ExecuteQuery() - Execute SQL
  - RegisterKeyboardShortcuts() - F5, Ctrl+Enter, etc.
  - RegisterResultsGridEvents() - Cell copy fix (Issue #1)
- Properties:
  - ConnectionManager (public) - Exposed for monitoring panels
- UI Elements:
  - SqlEditor (AvalonEdit)
  - ResultsGrid (DataGrid)
  - DatabaseTreeView (TreeView)
  - QueryHistoryListBox (ListBox)
  - AccessLevelBadge (Border with TextBlock)

**Dialogs/ConnectionDialog.xaml** + **.xaml.cs**
- Purpose: Connection configuration dialog
- UI Elements:
  - ServerTextBox, PortTextBox, DatabaseTextBox
  - UsernameTextBox, PasswordBox
  - ReadOnlyCheckBox (Feature #2)
  - AutoCommitCheckBox (Feature #2)
- Methods:
  - GetConnectionFromInputs() - Build DB2Connection from form
  - Connect_Click() - Validate and return connection
  - TestConnection_Click() - Test connection before creating tab

---

## 🔄 EXECUTION FLOW SUMMARY

```
USER
  │
  ├─→ Clicks "New Connection"
  │     │
  │     └─→ MainWindow.NewConnection_Click()
  │           │
  │           └─→ Opens ConnectionDialog
  │                 │
  │                 ├─→ User enters details
  │                 ├─→ Sets IsReadOnly checkbox
  │                 ├─→ Sets AutoCommit checkbox
  │                 └─→ Clicks "Connect"
  │                       │
  │                       └─→ Creates DB2Connection
  │                             │
  │                             └─→ Saves to ConnectionStorageService
  │                                   │
  │                                   └─→ Returns to MainWindow
  │                                         │
  │                                         └─→ AddConnectionTab(connection)
  │                                               │
  │                                               └─→ Creates ConnectionTabControl
  │                                                     │
  │                                                     ├─→ Creates DB2ConnectionManager
  │                                                     ├─→ Initializes UI
  │                                                     └─→ Calls ConnectToDatabase()
  │                                                           │
  │                                                           └─→ Calls DB2ConnectionManager.OpenAsync()
  │                                                                 │
  │                                                                 ├─→ Opens DB2 connection
  │                                                                 ├─→ Sets auto-commit mode
  │                                                                 └─→ Determines access level (RBAC)
  │                                                                       │
  │                                                                       └─→ AccessControlService.DetermineAccessLevelAsync()
  │                                                                             │
  │                                                                             ├─→ Queries SYSCAT.DBAUTH
  │                                                                             ├─→ Classifies: DBA/Middle/Low
  │                                                                             └─→ Returns UserPermissions
  │                                                                                   │
  │                                                                                   └─→ Stored in DB2Connection.Permissions
  │                                                                                         │
  │                                                                                         └─→ Back to ConnectToDatabase()
  │                                                                                               │
  │                                                                                               ├─→ UpdateAccessLevelIndicator()
  │                                                                                               ├─→ LoadDatabaseObjectsAsync()
  │                                                                                               └─→ RefreshQueryHistory()
  │                                                                                                     │
  │                                                                                                     └─→ CONNECTION READY ✅
  │
  └─→ Or: Selects from Recent Connections
        │
        └─→ MainWindow.RecentConnection_Click()
              │
              └─→ Loads connection from ConnectionStorageService
                    │
                    └─→ Decrypts password
                          │
                          └─→ Same flow as above (AddConnectionTab)
```

---

## 📊 DATA FLOW DIAGRAM

```
CONNECTION CONFIGURATION
    │
    ├─→ ConnectionDialog Form Input
    │     ├─→ Server: string
    │     ├─→ Port: int
    │     ├─→ Database: string
    │     ├─→ Username: string
    │     ├─→ Password: string (SecureString)
    │     ├─→ IsReadOnly: bool
    │     └─→ AutoCommit: bool
    │
    ▼
DB2Connection Model
    │
    ├─→ Saved to JSON (encrypted password)
    │   File: %LOCALAPPDATA%\DbExplorer\connections.json
    │
    ▼
DB2ConnectionManager
    │
    ├─→ GetConnectionString()
    │   Format: "Server={host}:{port};Database={db};UID={user};PWD={pass};ConnectTimeout={timeout};"
    │
    ▼
IBM.Data.Db2.DB2Connection (Native Driver)
    │
    ├─→ Network: TCP/IP to DB2 server
    ├─→ Protocol: DB2 native protocol
    ├─→ Authentication: DB2 credentials
    │
    ▼
CONNECTED TO DB2 DATABASE
    │
    ├─→ Execute: SET AUTOCOMMIT {ON/OFF}
    │
    ├─→ Query: SYSCAT.DBAUTH for user privileges
    │     │
    │     └─→ Determines: DBA / Middle / Low
    │           │
    │           └─→ UserPermissions object created
    │                 │
    │                 └─→ Stored in DB2Connection.Permissions
    │
    ▼
PERMISSIONS ENFORCED
    │
    ├─→ UI Badge Updated
    │   └─→ Shows: 🛡️ DBA / 👤 USER / 🔒 READ-ONLY
    │
    ├─→ SQL Validation Active
    │   └─→ ExecuteQueryAsync() checks permissions
    │
    └─→ Menu Items Tagged
        └─→ Show/hide based on access level
```

---

## 🎯 CRITICAL METHODS CALLED DURING CONNECTION

### 1. Connection Initiation
- **MainWindow.NewConnection_Click()**
- **MainWindow.RecentConnection_Click()**

### 2. Connection Configuration
- **ConnectionDialog.GetConnectionFromInputs()**
- **ConnectionStorageService.SaveConnection()**

### 3. Tab Creation
- **MainWindow.AddConnectionTab()**
- **MainWindow.CreateTabHeader()**

### 4. ConnectionTabControl Setup
- **ConnectionTabControl.Constructor()**
- **ConnectionTabControl.InitializeSqlEditor()**
- **ConnectionTabControl.RegisterKeyboardShortcuts()**
- **ConnectionTabControl.RegisterResultsGridEvents()**
- **ConnectionTabControl.ConnectToDatabase()**

### 5. Database Connection
- **DB2ConnectionManager.OpenAsync()**
- **DB2ConnectionManager.SetAutoCommitModeAsync()**
- **DB2ConnectionManager.DetermineUserAccessLevelAsync()**

### 6. RBAC Security
- **AccessControlService.DetermineAccessLevelAsync()**
- **AccessControlService.ParseUsernameWithoutDomain()**

### 7. Post-Connection UI
- **ConnectionTabControl.UpdateAccessLevelIndicator()**
- **ConnectionTabControl.LoadDatabaseObjectsAsync()**
- **ConnectionTabControl.RefreshQueryHistory()**
- **MainWindow.UpdateMenuVisibilityForAccessLevel()**

---

## 🏗️ CLASS HIERARCHY

```
Application Entry
└── App.xaml.cs
    └── OnStartup()
        ├── CLI Mode → CliExecutorService
        └── GUI Mode → MainWindow

MainWindow
├── ConnectionDialog
│   ├── Uses: Models/DB2Connection
│   └── Uses: Services/ConnectionStorageService
│
└── ConnectionTabControl (per connection)
    ├── Uses: Models/DB2Connection
    ├── Creates: Data/DB2ConnectionManager
    ├── Creates: Services/SqlFormatterService
    ├── Creates: Services/QueryHistoryService
    ├── Creates: Services/ExportService
    ├── Creates: Services/PreferencesService
    └── Connection Flow:
        └── DB2ConnectionManager
            ├── Uses: IBM.Data.Db2.DB2Connection
            ├── Creates: Services/AccessControlService
            └── Stores: UserPermissions in DB2Connection
```

---

## 🔐 SECURITY VALIDATION POINTS

**Point 1: Connection Dialog**
- Validates: Required fields not empty
- Validates: Port is valid integer
- Method: DB2Connection.IsValid()

**Point 2: DB2 Connection Open**
- Validates: DB2 credentials are correct
- Throws: DB2Exception if authentication fails
- Logging: All connection attempts logged

**Point 3: Access Level Determination**
- Queries: SYSCAT.DBAUTH
- Determines: User privilege level
- Default: LOW (read-only) on error

**Point 4: SQL Execution**
- Validates: Connection is open
- Validates: IsReadOnly mode respected
- Validates: User has permission for SQL type
- Throws: UnauthorizedAccessException if denied

---

## 🎊 COMPLETE CONNECTION LIFECYCLE

```
START
  │
  ├─→ User Action (New Connection / Recent Connection)
  │
  ├─→ Configuration Dialog (Input credentials + options)
  │
  ├─→ Create DB2Connection Model
  │
  ├─→ Save to Encrypted Storage (optional)
  │
  ├─→ Create ConnectionTabControl
  │
  ├─→ Create DB2ConnectionManager
  │
  ├─→ Open DB2 Connection (OpenAsync)
  │     ├─→ Physical TCP/IP connection
  │     ├─→ Set auto-commit mode
  │     └─→ Determine access level (RBAC)
  │           ├─→ Query SYSCAT.DBAUTH
  │           ├─→ Classify user (DBA/Middle/Low)
  │           └─→ Store permissions
  │
  ├─→ Update UI (Badge, Status, Objects, History)
  │
  └─→ READY
      ├─→ User can execute queries
      ├─→ User can access monitoring features
      ├─→ User can browse objects
      ├─→ All operations respect RBAC permissions
      └─→ All features available based on access level
```

---

**Diagram Created:** November 19, 2025  
**Status:** Complete and accurate representation of connection flow  
**Files Referenced:** 15+ actual source files with real method names

