# Building a C# DB2 Database Application for Windows 11 (.NET 10)

A comprehensive guide to creating a DBeaver-like DB2 database management application using C# .NET 10, native DB2 drivers, and NLog logging.

## 🎯 Key Features

This guide shows you how to build a professional DB2 editor with:

✅ **.NET 10 Framework** - Latest .NET with enhanced performance and modern C# 13  
✅ **NLog Logging** - Enterprise-grade logging with flexible configuration  
✅ **Offline Deployment** - Fully self-contained, works without internet access (local network only)  
✅ **Multiple Connection Tabs** - Work with multiple databases simultaneously  
✅ **Dark Mode Support** - Toggle between light and dark themes (Ctrl+D)  
✅ **Monaco-like Editor** - Advanced code editor with syntax highlighting using AvalonEdit  
✅ **SQL Auto-Format** - Format SQL code automatically (Ctrl+Shift+F)  
✅ **Native DB2 Drivers** - Direct connection using IBM.Data.DB2.Core  
✅ **Modern UI** - Windows 11-style interface with ModernWpf  
✅ **Database Browser** - Tree view of schemas, tables, views, and procedures  
✅ **Query Execution** - Execute queries with F5 or Ctrl+Enter  
✅ **Results Export** - Export to CSV, Excel, JSON  

## Table of Contents
- [Prerequisites](#prerequisites)
- [Project Setup](#project-setup)
- [Installing DB2 Drivers](#installing-db2-drivers)
- [Database Connection](#database-connection)
- [Executing SQL Queries](#executing-sql-queries)
- [Building the UI](#building-the-ui)
- [Advanced Features](#advanced-features)
- [SQL Auto-Format Implementation](#sql-auto-format-implementation)
- [Deployment Considerations for Offline Environments](#deployment-considerations-for-offline-environments)
- [Best Practices](#best-practices)

---

## Prerequisites

### Required Software
1. **Windows 11** (64-bit recommended)
2. **Visual Studio 2022** (Community, Professional, or Enterprise) - Version 17.8 or later
   - Workloads: .NET desktop development
3. **IBM DB2 Client** or **IBM Data Server Driver Package**
   - Download from IBM website or use IBM Data Server Runtime Client
4. **.NET 10 SDK** (version 10.0.100 or later)

### IBM DB2 Driver Options
- **IBM DB2 Connect** - Full-featured client
- **IBM Data Server Driver Package** - Lightweight driver package
- **IBM Data Server Runtime Client** - Runtime-only package

### Important Deployment Constraints
⚠️ **Offline Environment**: The application will be deployed in an environment with **NO INTERNET ACCESS** (local network only). This means:
- All dependencies must be bundled in the deployment package
- Use self-contained publishing
- No online NuGet package restoration during deployment
- All DB2 drivers and libraries must be included

---

## Project Setup

### 1. Create a New C# Project

#### Option A: WPF Application (Recommended for Modern UI)
```bash
dotnet new wpf -n DbExplorer -f net10.0-windows
cd DbExplorer
```

#### Option B: Windows Forms Application (Classic UI)
```bash
dotnet new winforms -n DbExplorer -f net10.0-windows
cd DbExplorer
```

#### Option C: Using Visual Studio
1. Open Visual Studio 2022 (Version 17.8+)
2. Create New Project
3. Select "WPF App" or "Windows Forms App"
4. Target Framework: **.NET 10.0**
5. Name: `DbExplorer`

**Verify .NET 10 Installation:**
```bash
dotnet --version
# Should show 9.0.x
```

---

## Installing DB2 Drivers

### Option 1: IBM.Data.DB2.Core (NuGet - Recommended for Offline Deployment)

```bash
dotnet add package IBM.Data.DB2.Core
```

**Advantages:**
- No separate DB2 client installation required
- Cross-platform support
- Easier deployment
- Self-contained drivers
- **Perfect for offline environments** - all dependencies included in publish

### Required NuGet Packages for Full Application (.NET 10)

```bash
# Core DB2 Driver (Latest)
dotnet add package IBM.Data.DB2.Core

# Advanced Code Editor (Monaco-like experience)
dotnet add package AvalonEdit

# SQL Formatting
dotnet add package PoorMansTSqlFormatter

# Dark Mode Theme Support & Modern UI
dotnet add package ModernWpfUI

# Dependency Injection & Configuration (.NET 10)
dotnet add package Microsoft.Extensions.DependencyInjection
dotnet add package Microsoft.Extensions.Configuration.Json
dotnet add package Microsoft.Extensions.Hosting

# Logging with NLog (.NET 10 compatible)
dotnet add package NLog
dotnet add package NLog.Extensions.Logging
dotnet add package NLog.Schema
dotnet add package Microsoft.Extensions.Logging
dotnet add package Microsoft.Extensions.Logging.Abstractions
```

**Install All Packages at Once:**
```bash
dotnet add package IBM.Data.DB2.Core && \
dotnet add package AvalonEdit && \
dotnet add package PoorMansTSqlFormatter && \
dotnet add package ModernWpfUI && \
dotnet add package Microsoft.Extensions.DependencyInjection && \
dotnet add package Microsoft.Extensions.Configuration.Json && \
dotnet add package Microsoft.Extensions.Hosting && \
dotnet add package NLog && \
dotnet add package NLog.Extensions.Logging && \
dotnet add package NLog.Schema && \
dotnet add package Microsoft.Extensions.Logging
```

**Note:** All packages are compatible with .NET 10 and work offline once downloaded. Download all packages on a machine with internet access, then include them in your deployment package for offline installation.

### Option 2: IBM.Data.DB2 (Traditional - Requires DB2 Client)

```bash
# Not available via NuGet - requires manual installation
```

**Steps:**
1. Install IBM DB2 Client on development machine
2. Add reference to `IBM.Data.DB2.dll` from installation directory:
   - Typical path: `C:\Program Files\IBM\SQLLIB\BIN\netf40_64\IBM.Data.DB2.dll`
3. Add to project references

### Option 3: Manual Driver Setup

1. Download IBM Data Server Driver Package
2. Extract to a local directory
3. Set environment variables:
   ```powershell
   $env:IBM_DB_HOME = "C:\IBM\DSDRIVER"
   $env:PATH += ";C:\IBM\DSDRIVER\bin"
   ```
4. Reference the appropriate DLL in your project

---

## Database Connection

### Connection String Format

```csharp
// Standard connection string
string connectionString = "Server=hostname:port;Database=DBNAME;UID=username;PWD=password;";

// With additional parameters
string connectionString = "Server=myserver.company.com:50000;" +
                         "Database=MYDB;" +
                         "UID=db2admin;" +
                         "PWD=mypassword;" +
                         "Connect Timeout=30;" +
                         "Connection Pooling=true;";

// Using cataloged database
string connectionString = "Database=MYDB;UID=username;PWD=password;";
```

### Connection Manager Class

```csharp
using IBM.Data.DB2.Core; // or IBM.Data.DB2
using System;
using System.Data;

namespace DbExplorer.Data
{
    public class DB2ConnectionManager
    {
        private string _connectionString;
        
        public DB2ConnectionManager(string connectionString)
        {
            _connectionString = connectionString;
        }
        
        public DB2Connection CreateConnection()
        {
            var connection = new DB2Connection(_connectionString);
            return connection;
        }
        
        public bool TestConnection()
        {
            try
            {
                using (var conn = CreateConnection())
                {
                    conn.Open();
                    return conn.State == ConnectionState.Open;
                }
            }
            catch (DB2Exception ex)
            {
                Console.WriteLine($"DB2 Error: {ex.Message}");
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error: {ex.Message}");
                return false;
            }
        }
        
        public string GetServerVersion()
        {
            using (var conn = CreateConnection())
            {
                conn.Open();
                return conn.ServerVersion;
            }
        }
    }
}
```

---

## Executing SQL Queries

### Query Executor Class

```csharp
using IBM.Data.DB2.Core;
using System;
using System.Data;

namespace DbExplorer.Data
{
    public class DB2QueryExecutor
    {
        private DB2ConnectionManager _connectionManager;
        
        public DB2QueryExecutor(DB2ConnectionManager connectionManager)
        {
            _connectionManager = connectionManager;
        }
        
        /// <summary>
        /// Execute SELECT query and return DataTable
        /// </summary>
        public DataTable ExecuteQuery(string sql)
        {
            DataTable dataTable = new DataTable();
            
            using (var conn = _connectionManager.CreateConnection())
            {
                conn.Open();
                
                using (var cmd = new DB2Command(sql, conn))
                {
                    cmd.CommandTimeout = 30;
                    
                    using (var adapter = new DB2DataAdapter(cmd))
                    {
                        adapter.Fill(dataTable);
                    }
                }
            }
            
            return dataTable;
        }
        
        /// <summary>
        /// Execute INSERT, UPDATE, DELETE statements
        /// </summary>
        public int ExecuteNonQuery(string sql)
        {
            using (var conn = _connectionManager.CreateConnection())
            {
                conn.Open();
                
                using (var cmd = new DB2Command(sql, conn))
                {
                    cmd.CommandTimeout = 30;
                    return cmd.ExecuteNonQuery();
                }
            }
        }
        
        /// <summary>
        /// Execute scalar query (single value)
        /// </summary>
        public object ExecuteScalar(string sql)
        {
            using (var conn = _connectionManager.CreateConnection())
            {
                conn.Open();
                
                using (var cmd = new DB2Command(sql, conn))
                {
                    cmd.CommandTimeout = 30;
                    return cmd.ExecuteScalar();
                }
            }
        }
        
        /// <summary>
        /// Execute query with parameters (prevents SQL injection)
        /// </summary>
        public DataTable ExecuteParameterizedQuery(string sql, params DB2Parameter[] parameters)
        {
            DataTable dataTable = new DataTable();
            
            using (var conn = _connectionManager.CreateConnection())
            {
                conn.Open();
                
                using (var cmd = new DB2Command(sql, conn))
                {
                    cmd.CommandTimeout = 30;
                    
                    if (parameters != null)
                    {
                        cmd.Parameters.AddRange(parameters);
                    }
                    
                    using (var adapter = new DB2DataAdapter(cmd))
                    {
                        adapter.Fill(dataTable);
                    }
                }
            }
            
            return dataTable;
        }
        
        /// <summary>
        /// Get list of tables in the database
        /// </summary>
        public DataTable GetTables(string schema = null)
        {
            string sql = @"
                SELECT TABSCHEMA, TABNAME, TYPE, STATUS, CARD 
                FROM SYSCAT.TABLES 
                WHERE TYPE IN ('T', 'V')";
            
            if (!string.IsNullOrEmpty(schema))
            {
                sql += " AND TABSCHEMA = @SCHEMA";
                var param = new DB2Parameter("@SCHEMA", DB2Type.VarChar, 128);
                param.Value = schema;
                return ExecuteParameterizedQuery(sql, param);
            }
            
            return ExecuteQuery(sql);
        }
        
        /// <summary>
        /// Get columns for a specific table
        /// </summary>
        public DataTable GetTableColumns(string schema, string tableName)
        {
            string sql = @"
                SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, DEFAULT, REMARKS
                FROM SYSCAT.COLUMNS
                WHERE TABSCHEMA = @SCHEMA AND TABNAME = @TABLE
                ORDER BY COLNO";
            
            var parameters = new[]
            {
                new DB2Parameter("@SCHEMA", DB2Type.VarChar, 128) { Value = schema },
                new DB2Parameter("@TABLE", DB2Type.VarChar, 128) { Value = tableName }
            };
            
            return ExecuteParameterizedQuery(sql, parameters);
        }
    }
}
```

---

## Building the UI

### WPF Main Window with Multiple Tabs and Dark Mode

#### App.xaml (Configure ModernWpf Theme)
```xml
<Application x:Class="DbExplorer.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:ui="http://schemas.modernwpf.com/2019"
             StartupUri="MainWindow.xaml">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ui:ThemeResources RequestedTheme="Dark" />
                <ui:XamlControlsResources />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
```

#### MainWindow.xaml (Multiple Connection Tabs)
```xml
<Window x:Class="DbExplorer.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:ui="http://schemas.modernwpf.com/2019"
        xmlns:avalonEdit="http://icsharpcode.net/sharpdevelop/avalonedit"
        ui:WindowHelper.UseModernWindowStyle="True"
        Title="DB2 Editor" Height="700" Width="1200"
        Background="{DynamicResource SystemControlPageBackgroundChromeLowBrush}">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Menu Bar -->
        <Menu Grid.Row="0" Background="{DynamicResource SystemControlBackgroundChromeMediumLowBrush}">
            <MenuItem Header="File">
                <MenuItem Header="New Connection Tab" Click="NewConnectionTab_Click" InputGestureText="Ctrl+N">
                    <MenuItem.Icon>
                        <ui:FontIcon Glyph="&#xE710;"/>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem Header="Close Current Tab" Click="CloseCurrentTab_Click" InputGestureText="Ctrl+W"/>
                <Separator/>
                <MenuItem Header="Open SQL Script..." Click="OpenScript_Click" InputGestureText="Ctrl+O"/>
                <MenuItem Header="Save SQL Script..." Click="SaveScript_Click" InputGestureText="Ctrl+S"/>
                <Separator/>
                <MenuItem Header="Exit" Click="Exit_Click" InputGestureText="Alt+F4"/>
            </MenuItem>
            <MenuItem Header="Edit">
                <MenuItem Header="Format SQL" Click="FormatSql_Click" InputGestureText="Ctrl+Shift+F">
                    <MenuItem.Icon>
                        <ui:FontIcon Glyph="&#xE8E9;"/>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem Header="Comment Lines" Click="CommentLines_Click" InputGestureText="Ctrl+/"/>
                <MenuItem Header="Uncomment Lines" Click="UncommentLines_Click" InputGestureText="Ctrl+Shift+/"/>
                <Separator/>
                <MenuItem Header="Find..." Click="Find_Click" InputGestureText="Ctrl+F"/>
                <MenuItem Header="Replace..." Click="Replace_Click" InputGestureText="Ctrl+H"/>
            </MenuItem>
            <MenuItem Header="Query">
                <MenuItem Header="Execute" Click="ExecuteQuery_Click" InputGestureText="F5">
                    <MenuItem.Icon>
                        <ui:FontIcon Glyph="&#xE768;"/>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem Header="Execute Current Statement" Click="ExecuteCurrent_Click" InputGestureText="Ctrl+Enter"/>
                <MenuItem Header="Explain Plan" Click="ExplainPlan_Click" InputGestureText="Ctrl+E"/>
                <Separator/>
                <MenuItem Header="Stop Execution" Click="StopExecution_Click" InputGestureText="Ctrl+Break"/>
            </MenuItem>
            <MenuItem Header="Tools">
                <MenuItem Header="Database Browser" Click="DatabaseBrowser_Click"/>
                <MenuItem Header="Export Results..." Click="ExportData_Click"/>
                <MenuItem Header="Import Data..." Click="ImportData_Click"/>
                <Separator/>
                <MenuItem Header="Query History" Click="QueryHistory_Click"/>
            </MenuItem>
            <MenuItem Header="View">
                <MenuItem Header="Toggle Dark Mode" Click="ToggleTheme_Click" InputGestureText="Ctrl+D">
                    <MenuItem.Icon>
                        <ui:FontIcon Glyph="&#xE706;"/>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem Header="Toggle Database Browser" Click="ToggleDatabaseBrowser_Click" InputGestureText="Ctrl+B"/>
                <Separator/>
                <MenuItem Header="Zoom In" Click="ZoomIn_Click" InputGestureText="Ctrl++"/>
                <MenuItem Header="Zoom Out" Click="ZoomOut_Click" InputGestureText="Ctrl+-"/>
                <MenuItem Header="Reset Zoom" Click="ResetZoom_Click" InputGestureText="Ctrl+0"/>
            </MenuItem>
            <MenuItem Header="Help">
                <MenuItem Header="Documentation" Click="Documentation_Click"/>
                <MenuItem Header="About" Click="About_Click"/>
            </MenuItem>
        </Menu>
        
        <!-- Connection Tabs -->
        <TabControl Grid.Row="1" 
                    Name="ConnectionTabs"
                    TabStripPlacement="Top"
                    Background="{DynamicResource SystemControlPageBackgroundChromeLowBrush}"
                    SelectionChanged="ConnectionTabs_SelectionChanged">
            <!-- Tabs will be added dynamically -->
        </TabControl>
        
        <!-- Status Bar -->
        <StatusBar Grid.Row="2" 
                   Background="{DynamicResource SystemControlBackgroundChromeMediumLowBrush}"
                   Height="28">
            <StatusBarItem>
                <StackPanel Orientation="Horizontal">
                    <ui:FontIcon Glyph="&#xE703;" Margin="5,0" VerticalAlignment="Center"/>
                    <TextBlock Name="StatusText" Text="Ready" VerticalAlignment="Center"/>
                </StackPanel>
            </StatusBarItem>
            <Separator/>
            <StatusBarItem>
                <TextBlock Name="RowCountText" Text="0 rows" VerticalAlignment="Center"/>
            </StatusBarItem>
            <Separator/>
            <StatusBarItem>
                <TextBlock Name="ExecutionTimeText" Text="0 ms" VerticalAlignment="Center"/>
            </StatusBarItem>
            <StatusBarItem HorizontalAlignment="Right">
                <StackPanel Orientation="Horizontal">
                    <ui:FontIcon Glyph="&#xE968;" Margin="5,0" VerticalAlignment="Center"/>
                    <TextBlock Name="ConnectionStatus" Text="Not Connected" VerticalAlignment="Center" Margin="5,0"/>
                </StackPanel>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
```

### Connection Tab UserControl

Create a custom UserControl for each connection tab:

#### ConnectionTabControl.xaml
```xml
<UserControl x:Class="DbExplorer.Controls.ConnectionTabControl"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:avalonEdit="http://icsharpcode.net/sharpdevelop/avalonedit"
             xmlns:ui="http://schemas.modernwpf.com/2019">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="250" MinWidth="150"/>
            <ColumnDefinition Width="5"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        
        <!-- Database Object Browser (Left Panel) -->
        <Border Grid.Column="0" 
                BorderBrush="{DynamicResource SystemControlForegroundBaseMediumLowBrush}" 
                BorderThickness="0,0,1,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="5">
                    <TextBlock Text="Database Objects" FontWeight="Bold" Margin="0,0,0,5"/>
                    <TextBox Name="SearchBox" 
                             ui:ControlHelper.PlaceholderText="Search..."
                             TextChanged="SearchBox_TextChanged"/>
                </StackPanel>
                
                <TreeView Grid.Row="1" 
                          Name="DatabaseTreeView"
                          Margin="5"
                          SelectedItemChanged="DatabaseTreeView_SelectedItemChanged">
                    <!-- Populated dynamically -->
                </TreeView>
            </Grid>
        </Border>
        
        <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Stretch"/>
        
        <!-- Editor and Results (Right Panel) -->
        <Grid Grid.Column="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="300" MinHeight="100"/>
                <RowDefinition Height="5"/>
                <RowDefinition Height="*" MinHeight="100"/>
            </Grid.RowDefinitions>
            
            <!-- SQL Editor with AvalonEdit -->
            <Border Grid.Row="0" 
                    BorderBrush="{DynamicResource SystemControlForegroundBaseMediumLowBrush}" 
                    BorderThickness="1"
                    Margin="5">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Editor Toolbar -->
                    <ToolBar Grid.Row="0">
                        <Button Name="ExecuteButton" 
                                ToolTip="Execute (F5)" 
                                Click="Execute_Click">
                            <ui:FontIcon Glyph="&#xE768;"/>
                        </Button>
                        <Button Name="FormatButton" 
                                ToolTip="Format SQL (Ctrl+Shift+F)" 
                                Click="Format_Click">
                            <ui:FontIcon Glyph="&#xE8E9;"/>
                        </Button>
                        <Separator/>
                        <Button Name="SaveButton" 
                                ToolTip="Save Script (Ctrl+S)" 
                                Click="Save_Click">
                            <ui:FontIcon Glyph="&#xE74E;"/>
                        </Button>
                        <Button Name="OpenButton" 
                                ToolTip="Open Script (Ctrl+O)" 
                                Click="Open_Click">
                            <ui:FontIcon Glyph="&#xE8E5;"/>
                        </Button>
                        <Separator/>
                        <Button Name="ClearButton" 
                                ToolTip="Clear Editor" 
                                Click="Clear_Click">
                            <ui:FontIcon Glyph="&#xE894;"/>
                        </Button>
                    </ToolBar>
                    
                    <!-- AvalonEdit SQL Editor -->
                    <avalonEdit:TextEditor Grid.Row="1"
                                          Name="SqlEditor"
                                          FontFamily="Consolas"
                                          FontSize="14"
                                          ShowLineNumbers="True"
                                          SyntaxHighlighting="SQL"
                                          WordWrap="False"
                                          HorizontalScrollBarVisibility="Auto"
                                          VerticalScrollBarVisibility="Auto"
                                          Foreground="{DynamicResource SystemControlForegroundBaseHighBrush}"
                                          Background="{DynamicResource SystemControlPageBackgroundChromeLowBrush}"/>
                </Grid>
            </Border>
            
            <GridSplitter Grid.Row="1" Height="5" HorizontalAlignment="Stretch"/>
            
            <!-- Results Tab Control -->
            <TabControl Grid.Row="2" 
                        Name="ResultsTabControl"
                        Margin="5">
                <TabItem Header="Results">
                    <DataGrid Name="ResultsGrid"
                              AutoGenerateColumns="True"
                              IsReadOnly="True"
                              CanUserAddRows="False"
                              CanUserDeleteRows="False"
                              AlternatingRowBackground="{DynamicResource SystemControlBackgroundAltHighBrush}"
                              GridLinesVisibility="All"
                              VerticalScrollBarVisibility="Auto"
                              HorizontalScrollBarVisibility="Auto"/>
                </TabItem>
                <TabItem Header="Messages">
                    <TextBox Name="MessagesTextBox"
                             IsReadOnly="True"
                             FontFamily="Consolas"
                             FontSize="12"
                             TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             Background="{DynamicResource SystemControlPageBackgroundChromeLowBrush}"/>
                </TabItem>
                <TabItem Header="Execution Plan">
                    <TreeView Name="ExecutionPlanTree"/>
                </TabItem>
            </TabControl>
        </Grid>
    </Grid>
</UserControl>
```

#### MainWindow.xaml.cs (Multiple Tabs + Dark Mode)
```csharp
using System;
using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using ModernWpf;
using DbExplorer.Controls;
using DbExplorer.Data;

namespace DbExplorer
{
    public partial class MainWindow : Window
    {
        private ObservableCollection<ConnectionTab> _connectionTabs;
        private bool _isDarkMode = true;
        
        public MainWindow()
        {
            InitializeComponent();
            _connectionTabs = new ObservableCollection<ConnectionTab>();
            SetupKeyBindings();
        }
        
        private void SetupKeyBindings()
        {
            // Ctrl+N: New Connection Tab
            var newTabCmd = new RoutedCommand();
            newTabCmd.InputGestures.Add(new KeyGesture(Key.N, ModifierKeys.Control));
            CommandBindings.Add(new CommandBinding(newTabCmd, NewConnectionTab_Click));
            
            // Ctrl+W: Close Current Tab
            var closeTabCmd = new RoutedCommand();
            closeTabCmd.InputGestures.Add(new KeyGesture(Key.W, ModifierKeys.Control));
            CommandBindings.Add(new CommandBinding(closeTabCmd, CloseCurrentTab_Click));
            
            // F5: Execute Query
            var executeCmd = new RoutedCommand();
            executeCmd.InputGestures.Add(new KeyGesture(Key.F5));
            CommandBindings.Add(new CommandBinding(executeCmd, ExecuteQuery_Click));
            
            // Ctrl+Shift+F: Format SQL
            var formatCmd = new RoutedCommand();
            formatCmd.InputGestures.Add(new KeyGesture(Key.F, ModifierKeys.Control | ModifierKeys.Shift));
            CommandBindings.Add(new CommandBinding(formatCmd, FormatSql_Click));
            
            // Ctrl+D: Toggle Dark Mode
            var themeCmd = new RoutedCommand();
            themeCmd.InputGestures.Add(new KeyGesture(Key.D, ModifierKeys.Control));
            CommandBindings.Add(new CommandBinding(themeCmd, ToggleTheme_Click));
        }
        
        private void NewConnectionTab_Click(object sender, RoutedEventArgs e)
        {
            var connectionDialog = new ConnectionDialog();
            if (connectionDialog.ShowDialog() == true)
            {
                try
                {
                    var connectionManager = new DB2ConnectionManager(connectionDialog.ConnectionString);
                    
                    if (connectionManager.TestConnection())
                    {
                        // Create new tab
                        var tabControl = new ConnectionTabControl(connectionManager, connectionDialog.Database);
                        var tabItem = new TabItem
                        {
                            Header = CreateTabHeader(connectionDialog.Database, connectionDialog.Host),
                            Content = tabControl
                        };
                        
                        ConnectionTabs.Items.Add(tabItem);
                        ConnectionTabs.SelectedItem = tabItem;
                        
                        StatusText.Text = $"Connected to {connectionDialog.Database}";
                        UpdateConnectionStatus();
                    }
                    else
                    {
                        MessageBox.Show("Failed to connect to database", "Error",
                                      MessageBoxButton.OK, MessageBoxImage.Error);
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Connection error: {ex.Message}", "Error",
                                  MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }
        
        private StackPanel CreateTabHeader(string database, string host)
        {
            var stackPanel = new StackPanel { Orientation = Orientation.Horizontal };
            
            var textBlock = new TextBlock
            {
                Text = $"{database} @ {host}",
                Margin = new Thickness(0, 0, 10, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            
            var closeButton = new Button
            {
                Content = "✕",
                Width = 20,
                Height = 20,
                Padding = new Thickness(0),
                Background = System.Windows.Media.Brushes.Transparent,
                BorderThickness = new Thickness(0)
            };
            
            closeButton.Click += (s, e) =>
            {
                var parent = (stackPanel.Parent as TabItem);
                if (parent != null)
                {
                    ConnectionTabs.Items.Remove(parent);
                    UpdateConnectionStatus();
                }
                e.Handled = true;
            };
            
            stackPanel.Children.Add(textBlock);
            stackPanel.Children.Add(closeButton);
            
            return stackPanel;
        }
        
        private void CloseCurrentTab_Click(object sender, RoutedEventArgs e)
        {
            if (ConnectionTabs.SelectedItem is TabItem selectedTab)
            {
                ConnectionTabs.Items.Remove(selectedTab);
                UpdateConnectionStatus();
            }
        }
        
        private void ExecuteQuery_Click(object sender, RoutedEventArgs e)
        {
            var currentTab = GetCurrentTabControl();
            currentTab?.ExecuteCurrentQuery();
        }
        
        private void FormatSql_Click(object sender, RoutedEventArgs e)
        {
            var currentTab = GetCurrentTabControl();
            currentTab?.FormatSql();
        }
        
        private void ToggleTheme_Click(object sender, RoutedEventArgs e)
        {
            _isDarkMode = !_isDarkMode;
            ThemeManager.Current.ApplicationTheme = _isDarkMode 
                ? ApplicationTheme.Dark 
                : ApplicationTheme.Light;
            
            StatusText.Text = _isDarkMode ? "Dark mode enabled" : "Light mode enabled";
        }
        
        private ConnectionTabControl GetCurrentTabControl()
        {
            if (ConnectionTabs.SelectedItem is TabItem selectedTab)
            {
                return selectedTab.Content as ConnectionTabControl;
            }
            return null;
        }
        
        private void ConnectionTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            UpdateConnectionStatus();
        }
        
        private void UpdateConnectionStatus()
        {
            if (ConnectionTabs.Items.Count > 0)
            {
                ConnectionStatus.Text = $"{ConnectionTabs.Items.Count} connection(s)";
            }
            else
            {
                ConnectionStatus.Text = "Not Connected";
            }
        }
        
        // Other menu handlers
        private void OpenScript_Click(object sender, RoutedEventArgs e)
        {
            var currentTab = GetCurrentTabControl();
            currentTab?.OpenScript();
        }
        
        private void SaveScript_Click(object sender, RoutedEventArgs e)
        {
            var currentTab = GetCurrentTabControl();
            currentTab?.SaveScript();
        }
        
        private void ExecuteCurrent_Click(object sender, RoutedEventArgs e)
        {
            var currentTab = GetCurrentTabControl();
            currentTab?.ExecuteCurrentStatement();
        }
        
        private void ExplainPlan_Click(object sender, RoutedEventArgs e)
        {
            var currentTab = GetCurrentTabControl();
            currentTab?.ExplainPlan();
        }
        
        private void Exit_Click(object sender, RoutedEventArgs e)
        {
            Application.Current.Shutdown();
        }
        
        // Implement other event handlers as needed...
    }
    
    public class ConnectionTab
    {
        public string Name { get; set; }
        public DB2ConnectionManager ConnectionManager { get; set; }
        public DB2QueryExecutor QueryExecutor { get; set; }
    }
}
```

#### ConnectionTabControl.xaml.cs (Code Behind for Tab)
```csharp
using System;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.Highlighting.Xshd;
using Microsoft.Win32;
using PoorMansTSqlFormatterLib;
using DbExplorer.Data;

namespace DbExplorer.Controls
{
    public partial class ConnectionTabControl : UserControl
    {
        private DB2ConnectionManager _connectionManager;
        private DB2QueryExecutor _queryExecutor;
        private string _databaseName;
        private Stopwatch _executionTimer;
        
        public ConnectionTabControl(DB2ConnectionManager connectionManager, string databaseName)
        {
            InitializeComponent();
            
            _connectionManager = connectionManager;
            _queryExecutor = new DB2QueryExecutor(connectionManager);
            _databaseName = databaseName;
            _executionTimer = new Stopwatch();
            
            InitializeEditor();
            LoadDatabaseObjects();
        }
        
        private void InitializeEditor()
        {
            // Set SQL syntax highlighting
            SqlEditor.SyntaxHighlighting = HighlightingManager.Instance.GetDefinition("SQL");
            
            // Configure editor options
            SqlEditor.Options.EnableHyperlinks = false;
            SqlEditor.Options.EnableEmailHyperlinks = false;
            SqlEditor.Options.ConvertTabsToSpaces = true;
            SqlEditor.Options.IndentationSize = 4;
            SqlEditor.ShowLineNumbers = true;
            
            // Add key bindings
            SqlEditor.PreviewKeyDown += SqlEditor_PreviewKeyDown;
        }
        
        private void SqlEditor_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            // F5: Execute
            if (e.Key == System.Windows.Input.Key.F5)
            {
                ExecuteCurrentQuery();
                e.Handled = true;
            }
            // Ctrl+Enter: Execute current statement
            else if (e.Key == System.Windows.Input.Key.Enter && 
                     e.KeyboardDevice.Modifiers == System.Windows.Input.ModifierKeys.Control)
            {
                ExecuteCurrentStatement();
                e.Handled = true;
            }
            // Ctrl+Shift+F: Format
            else if (e.Key == System.Windows.Input.Key.F && 
                     e.KeyboardDevice.Modifiers == (System.Windows.Input.ModifierKeys.Control | 
                                                    System.Windows.Input.ModifierKeys.Shift))
            {
                FormatSql();
                e.Handled = true;
            }
        }
        
        public void ExecuteCurrentQuery()
        {
            try
            {
                string sql = SqlEditor.Text.Trim();
                
                if (string.IsNullOrEmpty(sql))
                {
                    MessagesTextBox.Text = "No SQL to execute.";
                    return;
                }
                
                MessagesTextBox.Text = "Executing query...";
                _executionTimer.Restart();
                
                DataTable results = _queryExecutor.ExecuteQuery(sql);
                
                _executionTimer.Stop();
                
                ResultsGrid.ItemsSource = results.DefaultView;
                ResultsTabControl.SelectedIndex = 0; // Switch to Results tab
                
                // Update status
                var window = Window.GetWindow(this) as MainWindow;
                if (window != null)
                {
                    window.RowCountText.Text = $"{results.Rows.Count} row(s)";
                    window.ExecutionTimeText.Text = $"{_executionTimer.ElapsedMilliseconds} ms";
                    window.StatusText.Text = "Query executed successfully";
                }
                
                MessagesTextBox.Text = $"Query completed successfully.\n" +
                                      $"Rows: {results.Rows.Count}\n" +
                                      $"Execution time: {_executionTimer.ElapsedMilliseconds} ms";
            }
            catch (Exception ex)
            {
                _executionTimer.Stop();
                MessagesTextBox.Text = $"Error executing query:\n{ex.Message}";
                ResultsTabControl.SelectedIndex = 1; // Switch to Messages tab
                
                var window = Window.GetWindow(this) as MainWindow;
                if (window != null)
                {
                    window.StatusText.Text = "Query failed";
                }
            }
        }
        
        public void ExecuteCurrentStatement()
        {
            // Get the current statement at cursor position
            string currentStatement = GetCurrentStatement();
            if (!string.IsNullOrEmpty(currentStatement))
            {
                SqlEditor.Text = currentStatement;
                ExecuteCurrentQuery();
            }
        }
        
        private string GetCurrentStatement()
        {
            // Simple implementation: split by semicolon and find statement at cursor
            int caretOffset = SqlEditor.CaretOffset;
            string text = SqlEditor.Text;
            
            var statements = text.Split(';');
            int currentPos = 0;
            
            foreach (var statement in statements)
            {
                currentPos += statement.Length + 1;
                if (currentPos >= caretOffset)
                {
                    return statement.Trim();
                }
            }
            
            return text;
        }
        
        public void FormatSql()
        {
            try
            {
                string sql = SqlEditor.Text;
                
                if (string.IsNullOrEmpty(sql))
                {
                    return;
                }
                
                // Use PoorMansTSqlFormatter
                var formatter = new PoorMansTSqlFormatterLib.Formatters.TSqlStandardFormatter();
                formatter.Options.IndentString = "    "; // 4 spaces
                formatter.Options.SpacesPerTab = 4;
                formatter.Options.MaxLineWidth = 100;
                formatter.Options.NewStatementLineBreaks = 2;
                formatter.Options.NewClauseLineBreaks = 1;
                
                string formattedSql = formatter.FormatSQLTree(
                    formatter.ParseSQL(sql)
                );
                
                SqlEditor.Text = formattedSql;
                MessagesTextBox.Text = "SQL formatted successfully.";
            }
            catch (Exception ex)
            {
                MessagesTextBox.Text = $"Error formatting SQL:\n{ex.Message}";
            }
        }
        
        public void OpenScript()
        {
            var openFileDialog = new OpenFileDialog
            {
                Filter = "SQL Files (*.sql)|*.sql|All Files (*.*)|*.*",
                Title = "Open SQL Script"
            };
            
            if (openFileDialog.ShowDialog() == true)
            {
                try
                {
                    SqlEditor.Text = File.ReadAllText(openFileDialog.FileName);
                    MessagesTextBox.Text = $"Loaded script: {openFileDialog.FileName}";
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Error opening file:\n{ex.Message}", "Error",
                                  MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }
        
        public void SaveScript()
        {
            var saveFileDialog = new SaveFileDialog
            {
                Filter = "SQL Files (*.sql)|*.sql|All Files (*.*)|*.*",
                Title = "Save SQL Script"
            };
            
            if (saveFileDialog.ShowDialog() == true)
            {
                try
                {
                    File.WriteAllText(saveFileDialog.FileName, SqlEditor.Text);
                    MessagesTextBox.Text = $"Saved script: {saveFileDialog.FileName}";
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Error saving file:\n{ex.Message}", "Error",
                                  MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }
        
        public void ExplainPlan()
        {
            try
            {
                string sql = "EXPLAIN PLAN FOR " + SqlEditor.Text.Trim();
                // Execute explain plan query and populate ExecutionPlanTree
                // Implementation depends on DB2 explain plan format
                MessagesTextBox.Text = "Explain plan functionality - to be implemented";
            }
            catch (Exception ex)
            {
                MessagesTextBox.Text = $"Error getting execution plan:\n{ex.Message}";
            }
        }
        
        private void LoadDatabaseObjects()
        {
            try
            {
                // Load tables, views, schemas into TreeView
                var tables = _queryExecutor.GetTables();
                
                foreach (DataRow row in tables.Rows)
                {
                    var schemaName = row["TABSCHEMA"].ToString();
                    var tableName = row["TABNAME"].ToString();
                    var tableType = row["TYPE"].ToString();
                    
                    // Build tree structure
                    // Implementation details...
                }
            }
            catch (Exception ex)
            {
                MessagesTextBox.Text = $"Error loading database objects:\n{ex.Message}";
            }
        }
        
        // Event handlers
        private void Execute_Click(object sender, RoutedEventArgs e) => ExecuteCurrentQuery();
        private void Format_Click(object sender, RoutedEventArgs e) => FormatSql();
        private void Save_Click(object sender, RoutedEventArgs e) => SaveScript();
        private void Open_Click(object sender, RoutedEventArgs e) => OpenScript();
        private void Clear_Click(object sender, RoutedEventArgs e) => SqlEditor.Clear();
        
        private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            // Filter database tree view based on search text
        }
        
        private void DatabaseTreeView_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
        {
            // Handle tree view selection - e.g., show table structure
        }
    }
}
```

### Connection Dialog Example

#### ConnectionDialog.xaml
```xml
<Window x:Class="DbExplorer.ConnectionDialog"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DB2 Connection" Height="350" Width="450"
        WindowStartupLocation="CenterOwner">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Host:" Margin="0,5"/>
        <TextBox Grid.Row="1" Name="HostTextBox" Text="localhost" Margin="0,5"/>
        
        <TextBlock Grid.Row="2" Text="Port:" Margin="0,5"/>
        <TextBox Grid.Row="3" Name="PortTextBox" Text="50000" Margin="0,5"/>
        
        <TextBlock Grid.Row="4" Text="Database:" Margin="0,5"/>
        <TextBox Grid.Row="5" Name="DatabaseTextBox" Margin="0,5"/>
        
        <TextBlock Grid.Row="6" Text="Username:" Margin="0,5"/>
        <TextBox Grid.Row="7" Name="UsernameTextBox" Margin="0,5"/>
        
        <TextBlock Grid.Row="8" Text="Password:" Margin="0,5"/>
        <PasswordBox Grid.Row="9" Name="PasswordBox" Margin="0,5"/>
        
        <StackPanel Grid.Row="10" Orientation="Horizontal" 
                    HorizontalAlignment="Right" Margin="0,15,0,0">
            <Button Content="Test Connection" Width="120" Margin="5" Click="Test_Click"/>
            <Button Content="Connect" Width="80" Margin="5" Click="Connect_Click" IsDefault="True"/>
            <Button Content="Cancel" Width="80" Margin="5" Click="Cancel_Click" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
```

---

## Advanced Features

### 1. Advanced SQL Editor (Monaco-like Experience with AvalonEdit)

AvalonEdit provides Monaco-like features including syntax highlighting, IntelliSense, and code completion.

#### Custom SQL Syntax Highlighting (Dark Mode Compatible)

Create a custom XSHD file for DB2 SQL highlighting:

**DB2SQL.xshd**
```xml
<?xml version="1.0"?>
<SyntaxDefinition name="DB2 SQL" xmlns="http://icsharpcode.net/sharpdevelop/syntaxdefinition/2008">
    <Color name="Comment" foreground="#6A9955" fontStyle="italic" />
    <Color name="String" foreground="#CE9178" />
    <Color name="Keyword" foreground="#569CD6" fontWeight="bold" />
    <Color name="Function" foreground="#DCDCAA" />
    <Color name="DataType" foreground="#4EC9B0" />
    <Color name="Number" foreground="#B5CEA8" />
    <Color name="Operator" foreground="#D4D4D4" />
    
    <RuleSet ignoreCase="true">
        <!-- Comments -->
        <Span color="Comment" begin="--" />
        <Span color="Comment" multiline="true" begin="/\*" end="\*/" />
        
        <!-- Strings -->
        <Span color="String">
            <Begin>'</Begin>
            <End>'</End>
            <RuleSet>
                <Span begin="''" end="" />
            </RuleSet>
        </Span>
        
        <!-- Numbers -->
        <Rule color="Number">
            \b0[xX][0-9a-fA-F]+|(\b\d+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?
        </Rule>
        
        <!-- DB2 Keywords -->
        <Keywords color="Keyword">
            <Word>SELECT</Word>
            <Word>FROM</Word>
            <Word>WHERE</Word>
            <Word>INSERT</Word>
            <Word>UPDATE</Word>
            <Word>DELETE</Word>
            <Word>CREATE</Word>
            <Word>ALTER</Word>
            <Word>DROP</Word>
            <Word>TABLE</Word>
            <Word>VIEW</Word>
            <Word>INDEX</Word>
            <Word>TRIGGER</Word>
            <Word>PROCEDURE</Word>
            <Word>FUNCTION</Word>
            <Word>JOIN</Word>
            <Word>INNER</Word>
            <Word>LEFT</Word>
            <Word>RIGHT</Word>
            <Word>OUTER</Word>
            <Word>CROSS</Word>
            <Word>ON</Word>
            <Word>AND</Word>
            <Word>OR</Word>
            <Word>NOT</Word>
            <Word>IN</Word>
            <Word>EXISTS</Word>
            <Word>BETWEEN</Word>
            <Word>LIKE</Word>
            <Word>IS</Word>
            <Word>NULL</Word>
            <Word>ORDER</Word>
            <Word>BY</Word>
            <Word>GROUP</Word>
            <Word>HAVING</Word>
            <Word>UNION</Word>
            <Word>INTERSECT</Word>
            <Word>EXCEPT</Word>
            <Word>AS</Word>
            <Word>DISTINCT</Word>
            <Word>ALL</Word>
            <Word>CASE</Word>
            <Word>WHEN</Word>
            <Word>THEN</Word>
            <Word>ELSE</Word>
            <Word>END</Word>
            <Word>BEGIN</Word>
            <Word>COMMIT</Word>
            <Word>ROLLBACK</Word>
            <Word>SAVEPOINT</Word>
            <Word>WITH</Word>
            <Word>FETCH</Word>
            <Word>FIRST</Word>
            <Word>ONLY</Word>
            <Word>ROWS</Word>
        </Keywords>
        
        <!-- DB2 Data Types -->
        <Keywords color="DataType">
            <Word>INTEGER</Word>
            <Word>INT</Word>
            <Word>SMALLINT</Word>
            <Word>BIGINT</Word>
            <Word>DECIMAL</Word>
            <Word>NUMERIC</Word>
            <Word>REAL</Word>
            <Word>DOUBLE</Word>
            <Word>FLOAT</Word>
            <Word>CHAR</Word>
            <Word>VARCHAR</Word>
            <Word>CLOB</Word>
            <Word>BLOB</Word>
            <Word>DATE</Word>
            <Word>TIME</Word>
            <Word>TIMESTAMP</Word>
            <Word>BOOLEAN</Word>
            <Word>XML</Word>
        </Keywords>
        
        <!-- DB2 Functions -->
        <Keywords color="Function">
            <Word>COUNT</Word>
            <Word>SUM</Word>
            <Word>AVG</Word>
            <Word>MIN</Word>
            <Word>MAX</Word>
            <Word>COALESCE</Word>
            <Word>CAST</Word>
            <Word>SUBSTRING</Word>
            <Word>LENGTH</Word>
            <Word>TRIM</Word>
            <Word>UPPER</Word>
            <Word>LOWER</Word>
            <Word>CURRENT_DATE</Word>
            <Word>CURRENT_TIME</Word>
            <Word>CURRENT_TIMESTAMP</Word>
        </Keywords>
    </RuleSet>
</SyntaxDefinition>
```

#### Loading Custom Syntax Highlighting

```csharp
using System.Xml;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.Highlighting.Xshd;

public void LoadCustomSyntaxHighlighting()
{
    using (var reader = new XmlTextReader("DB2SQL.xshd"))
    {
        var definition = HighlightingLoader.Load(reader, HighlightingManager.Instance);
        SqlEditor.SyntaxHighlighting = definition;
    }
}

### 2. Query History
Store executed queries in a local SQLite database or JSON file:

```csharp
public class QueryHistory
{
    public DateTime Timestamp { get; set; }
    public string Query { get; set; }
    public int RowsAffected { get; set; }
    public TimeSpan ExecutionTime { get; set; }
}
```

### 3. Export Results
Export query results to CSV, Excel, or JSON:

```csharp
public void ExportToCsv(DataTable data, string filePath)
{
    var csv = new StringBuilder();
    
    // Headers
    var headers = data.Columns.Cast<DataColumn>()
        .Select(column => column.ColumnName);
    csv.AppendLine(string.Join(",", headers));
    
    // Rows
    foreach (DataRow row in data.Rows)
    {
        var fields = row.ItemArray.Select(field => 
            $"\"{field?.ToString().Replace("\"", "\"\"")}\"");
        csv.AppendLine(string.Join(",", fields));
    }
    
    File.WriteAllText(filePath, csv.ToString());
}
```

### 4. Database Object Browser
Create a TreeView to browse schemas, tables, views, procedures:

```csharp
public class DatabaseObjectBrowser
{
    private DB2QueryExecutor _executor;
    
    public TreeViewItem BuildDatabaseTree()
    {
        var root = new TreeViewItem { Header = "Database" };
        
        // Get schemas
        var schemas = _executor.ExecuteQuery(
            "SELECT SCHEMANAME FROM SYSCAT.SCHEMATA ORDER BY SCHEMANAME");
        
        foreach (DataRow schema in schemas.Rows)
        {
            var schemaNode = new TreeViewItem 
            { 
                Header = schema["SCHEMANAME"].ToString() 
            };
            
            // Add Tables, Views, Procedures as child nodes
            schemaNode.Items.Add(CreateTablesNode(schema["SCHEMANAME"].ToString()));
            
            root.Items.Add(schemaNode);
        }
        
        return root;
    }
}
```

### 5. Transaction Management
```csharp
public void ExecuteTransaction(List<string> sqlStatements)
{
    using (var conn = _connectionManager.CreateConnection())
    {
        conn.Open();
        using (var transaction = conn.BeginTransaction())
        {
            try
            {
                foreach (var sql in sqlStatements)
                {
                    using (var cmd = new DB2Command(sql, conn, transaction))
                    {
                        cmd.ExecuteNonQuery();
                    }
                }
                
                transaction.Commit();
            }
            catch
            {
                transaction.Rollback();
                throw;
            }
        }
    }
}
```

---

## Best Practices

### 1. Connection Management
- Always use `using` statements to ensure connections are closed
- Implement connection pooling for better performance
- Store connection strings securely (use Windows Credential Manager or encrypted config)

### 2. Error Handling with NLog
```csharp
using NLog;

private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

try
{
    Logger.Debug("Executing query...");
    // Execute query
    Logger.Info("Query executed successfully");
}
catch (DB2Exception db2Ex)
{
    // Handle DB2-specific errors with structured logging
    Logger.Error(db2Ex, "DB2 Error - SQL State: {SqlState}, Error Code: {ErrorCode}", 
                 db2Ex.SqlState, db2Ex.ErrorCode);
    
    // Show user-friendly message
    MessageBox.Show($"Database error: {db2Ex.Message}", "Error", 
                   MessageBoxButton.OK, MessageBoxImage.Error);
}
catch (Exception ex)
{
    // Handle general errors
    Logger.Error(ex, "Unexpected error occurred");
    
    MessageBox.Show($"Error: {ex.Message}", "Error",
                   MessageBoxButton.OK, MessageBoxImage.Error);
}
```

### 3. Parameterized Queries
Always use parameters to prevent SQL injection:

```csharp
string sql = "SELECT * FROM EMPLOYEE WHERE EMPNO = @EmpNo";
var param = new DB2Parameter("@EmpNo", DB2Type.VarChar);
param.Value = employeeNumber;
```

### 4. Async Operations
For better UI responsiveness, use async/await:

```csharp
public async Task<DataTable> ExecuteQueryAsync(string sql)
{
    return await Task.Run(() => ExecuteQuery(sql));
}
```

### 5. Configuration Management
Store settings in `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DB2Default": "Server=localhost:50000;Database=SAMPLE;UID=db2admin;PWD=;"
  },
  "QuerySettings": {
    "DefaultTimeout": 30,
    "MaxRowsToDisplay": 10000
  }
}
```

### 6. Logging with NLog (.NET 10)

NLog provides comprehensive logging capabilities for .NET 10 applications.

#### NLog Configuration

Create **`nlog.config`** in project root:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<nlog xmlns="http://www.nlog-project.org/schemas/NLog.xsd"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      autoReload="true"
      throwConfigExceptions="true"
      internalLogLevel="Info"
      internalLogFile="logs\nlog-internal.log">

  <!-- Define targets -->
  <targets>
    <!-- File Target -->
    <target xsi:type="File" 
            name="logfile" 
            fileName="logs\db2editor-${shortdate}.log"
            layout="${longdate}|${level:uppercase=true}|${logger}|${message}${onexception:${newline}${exception:format=tostring}}"
            archiveFileName="logs\archives\db2editor-${shortdate}.{#}.log"
            archiveEvery="Day"
            archiveNumbering="Rolling"
            maxArchiveFiles="30"
            concurrentWrites="true"
            keepFileOpen="false" />
    
    <!-- Console Target (for debugging) -->
    <target xsi:type="Console" 
            name="logconsole"
            layout="${longdate}|${level:uppercase=true}|${logger}|${message}" />
    
    <!-- Debug Output Target -->
    <target xsi:type="Debugger" 
            name="debugger"
            layout="${time}|${level:uppercase=true}|${logger}|${message}" />
  </targets>

  <!-- Define rules -->
  <rules>
    <!-- All logs (Trace and above) to file -->
    <logger name="*" minlevel="Trace" writeTo="logfile" />
    
    <!-- All logs (Debug and above) to console in Debug mode -->
    <logger name="*" minlevel="Debug" writeTo="logconsole,debugger" />
    
    <!-- Skip Microsoft logs below Warning -->
    <logger name="Microsoft.*" maxlevel="Info" final="true" />
  </rules>
</nlog>
```

#### NLog Service Implementation

```csharp
using Microsoft.Extensions.Logging;
using NLog;
using NLog.Extensions.Logging;

namespace DbExplorer.Services
{
    public class LoggingService
    {
        private static readonly Logger _logger = LogManager.GetCurrentClassLogger();
        
        public static void Initialize()
        {
            // Load NLog configuration
            LogManager.Setup().LoadConfigurationFromFile("nlog.config");
            
            _logger.Info("Application logging initialized");
        }
        
        public static void LogInfo(string message)
        {
            _logger.Info(message);
        }
        
        public static void LogDebug(string message)
        {
            _logger.Debug(message);
        }
        
        public static void LogWarning(string message)
        {
            _logger.Warn(message);
        }
        
        public static void LogError(string message, Exception ex = null)
        {
            if (ex != null)
            {
                _logger.Error(ex, message);
            }
            else
            {
                _logger.Error(message);
            }
        }
        
        public static void Shutdown()
        {
            LogManager.Shutdown();
        }
    }
}
```

#### Using NLog in Application

```csharp
using Microsoft.Extensions.Logging;
using NLog;

namespace DbExplorer
{
    public partial class App : Application
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            
            // Initialize NLog
            LoggingService.Initialize();
            Logger.Info("Application starting...");
            
            // Set up exception handling
            AppDomain.CurrentDomain.UnhandledException += CurrentDomain_UnhandledException;
            DispatcherUnhandledException += App_DispatcherUnhandledException;
        }
        
        private void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
        {
            var exception = e.ExceptionObject as Exception;
            Logger.Fatal(exception, "Unhandled exception occurred");
            MessageBox.Show($"A fatal error occurred: {exception?.Message}", "Fatal Error",
                          MessageBoxButton.OK, MessageBoxImage.Error);
        }
        
        private void App_DispatcherUnhandledException(object sender, 
            System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
        {
            Logger.Error(e.Exception, "Dispatcher unhandled exception");
            MessageBox.Show($"An error occurred: {e.Exception.Message}", "Error",
                          MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        }
        
        protected override void OnExit(ExitEventArgs e)
        {
            Logger.Info("Application shutting down...");
            LoggingService.Shutdown();
            base.OnExit(e);
        }
    }
}
```

#### Using NLog in Classes

```csharp
using NLog;

namespace DbExplorer.Data
{
    public class DB2ConnectionManager
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        private string _connectionString;
        
        public DB2ConnectionManager(string connectionString)
        {
            _connectionString = connectionString;
            Logger.Debug($"Connection manager created for: {GetSafeConnectionString()}");
        }
        
        public bool TestConnection()
        {
            try
            {
                Logger.Info("Testing database connection...");
                using (var conn = CreateConnection())
                {
                    conn.Open();
                    var isConnected = conn.State == ConnectionState.Open;
                    Logger.Info($"Connection test result: {(isConnected ? "SUCCESS" : "FAILED")}");
                    return isConnected;
                }
            }
            catch (DB2Exception ex)
            {
                Logger.Error(ex, $"DB2 connection failed: {ex.Message}");
                return false;
            }
            catch (Exception ex)
            {
                Logger.Error(ex, $"Connection test failed: {ex.Message}");
                return false;
            }
        }
        
        private string GetSafeConnectionString()
        {
            // Remove password from connection string for logging
            return System.Text.RegularExpressions.Regex.Replace(
                _connectionString, 
                @"PWD=([^;]*)", 
                "PWD=***", 
                System.Text.RegularExpressions.RegexOptions.IgnoreCase
            );
        }
    }
}
```

#### NLog in Project File

Ensure `nlog.config` is copied to output:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net10.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
  </PropertyGroup>
  
  <ItemGroup>
    <None Update="nlog.config">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>
</Project>
```

---

## Common DB2 Data Types Mapping

| DB2 Type | .NET Type | DB2Type Enum |
|----------|-----------|--------------|
| INTEGER | Int32 | DB2Type.Integer |
| BIGINT | Int64 | DB2Type.BigInt |
| SMALLINT | Int16 | DB2Type.SmallInt |
| DECIMAL | Decimal | DB2Type.Decimal |
| REAL | Single | DB2Type.Real |
| DOUBLE | Double | DB2Type.Double |
| CHAR | String | DB2Type.Char |
| VARCHAR | String | DB2Type.VarChar |
| CLOB | String | DB2Type.Clob |
| DATE | DateTime | DB2Type.Date |
| TIME | TimeSpan | DB2Type.Time |
| TIMESTAMP | DateTime | DB2Type.Timestamp |
| BLOB | Byte[] | DB2Type.Blob |

---

## SQL Auto-Format Implementation

### Using PoorMansTSqlFormatter

PoorMansTSqlFormatter is a SQL formatting library that works offline and supports DB2 SQL syntax.

#### Installation
```bash
dotnet add package PoorMansTSqlFormatter
```

#### SQL Formatter Service

```csharp
using PoorMansTSqlFormatterLib;
using PoorMansTSqlFormatterLib.Formatters;
using PoorMansTSqlFormatterLib.Interfaces;

namespace DbExplorer.Services
{
    public class SqlFormatterService
    {
        private readonly ISqlTreeFormatter _formatter;
        
        public SqlFormatterService()
        {
            _formatter = new TSqlStandardFormatter
            {
                Options = new SqlFormattingOptions
                {
                    IndentString = "    ",          // 4 spaces
                    SpacesPerTab = 4,
                    MaxLineWidth = 120,
                    NewStatementLineBreaks = 2,
                    NewClauseLineBreaks = 1,
                    TrailingCommas = false,
                    SpaceAfterComma = true,
                    ExpandCommaLists = true,
                    ExpandBooleanExpressions = true,
                    ExpandCaseStatements = true,
                    ExpandBetweenConditions = true,
                    ExpandInLists = true,
                    BreakJoinOnSections = true,
                    UppercaseKeywords = true,
                    KeywordStandardization = true
                }
            };
        }
        
        public string FormatSql(string sql)
        {
            if (string.IsNullOrWhiteSpace(sql))
            {
                return sql;
            }
            
            try
            {
                var parsedSql = _formatter.ParseSQL(sql);
                return _formatter.FormatSQLTree(parsedSql);
            }
            catch (Exception ex)
            {
                throw new FormatException($"SQL formatting failed: {ex.Message}", ex);
            }
        }
        
        public bool IsValidSql(string sql)
        {
            try
            {
                _formatter.ParseSQL(sql);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
```

#### Format on Save Configuration

```csharp
public class EditorSettings
{
    public bool AutoFormatOnSave { get; set; } = false;
    public bool AutoFormatOnPaste { get; set; } = false;
    public int TabSize { get; set; } = 4;
    public bool UseSpacesInsteadOfTabs { get; set; } = true;
    public bool ShowLineNumbers { get; set; } = true;
    public bool EnableAutoComplete { get; set; } = true;
}
```

---

## Deployment Considerations for Offline Environments

### ⚠️ Critical: No Internet Access at Deployment

Since the application will be deployed in an **offline environment**, all dependencies must be included.

### 1. Self-Contained Publishing (Recommended)

Create a fully self-contained application with all .NET runtime files included:

```bash
# Windows 64-bit Self-Contained (.NET 10)
dotnet publish -c Release -r win-x64 --self-contained true -f net10.0-windows /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true

# Windows 64-bit Framework-Dependent (requires .NET 10 runtime on target)
dotnet publish -c Release -r win-x64 --self-contained false -f net10.0-windows

# Trim unused assemblies to reduce size (.NET 10 optimized)
dotnet publish -c Release -r win-x64 --self-contained true -f net10.0-windows /p:PublishTrimmed=true /p:PublishSingleFile=true

# With ReadyToRun for better startup performance (.NET 10)
dotnet publish -c Release -r win-x64 --self-contained true -f net10.0-windows /p:PublishSingleFile=true /p:PublishReadyToRun=true
```

### 2. Include All Required Files

Your deployment package must include:

**Application Files:**
- `DbExplorer.exe`
- All `.dll` dependencies from publish folder
- `DB2SQL.xshd` (custom syntax highlighting)
- `appsettings.json` (configuration)
- `nlog.config` (NLog configuration)
- DB2 native drivers (if using IBM.Data.DB2.Core)
- .NET 10 runtime files (if self-contained)

**Create Deployment Folder Structure:**
```
DbExplorer-v1.0/
├── DbExplorer.exe
├── appsettings.json
├── nlog.config
├── Resources/
│   ├── DB2SQL.xshd
│   └── Icons/
├── Logs/
│   └── (log files created here)
├── Templates/
│   └── sample-queries.sql
└── Documentation/
    └── README.txt
```

### 3. PowerShell Deployment Script

Create `deploy.ps1` for automated offline deployment:

```powershell
# deploy.ps1 - Offline Deployment Script
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath = "C:\Program Files\DbExplorer",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateDesktopShortcut
)

Write-Host "Deploying DbExplorer..." -ForegroundColor Green

# Create target directory
if (!(Test-Path $TargetPath)) {
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
}

# Copy all files
Write-Host "Copying application files..." -ForegroundColor Yellow
Copy-Item -Path "$PSScriptRoot\*" -Destination $TargetPath -Recurse -Force

# Create logs directory
$logsPath = Join-Path $TargetPath "Logs"
if (!(Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
}

# Create desktop shortcut
if ($CreateDesktopShortcut) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\DB2 Editor.lnk")
    $Shortcut.TargetPath = Join-Path $TargetPath "DbExplorer.exe"
    $Shortcut.WorkingDirectory = $TargetPath
    $Shortcut.IconLocation = Join-Path $TargetPath "DbExplorer.exe"
    $Shortcut.Description = "DB2 Database Editor"
    $Shortcut.Save()
    Write-Host "Desktop shortcut created" -ForegroundColor Green
}

Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "Application installed to: $TargetPath" -ForegroundColor Cyan
```

### 4. Creating ZIP Package for Offline Distribution

```powershell
# create-package.ps1 - .NET 10 version
$version = "1.0.0"
$framework = "net10.0-windows"
$publishPath = ".\bin\Release\$framework\win-x64\publish"
$packageName = "DbExplorer-v$version-win-x64-net9.zip"

Write-Host "Building .NET 10 application..." -ForegroundColor Cyan

# Publish application (.NET 10 self-contained)
dotnet publish -c Release -r win-x64 --self-contained true -f $framework `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:PublishReadyToRun=true

# Verify publish succeeded
if (Test-Path $publishPath) {
    # Create package
    Compress-Archive -Path "$publishPath\*" -DestinationPath $packageName -Force
    
    $size = [math]::Round((Get-Item $packageName).Length / 1MB, 2)
    Write-Host "Package created: $packageName ($size MB)" -ForegroundColor Green
    Write-Host "Framework: .NET 10.0" -ForegroundColor Cyan
} else {
    Write-Host "Error: Publish path not found!" -ForegroundColor Red
    exit 1
}
```

### 5. MSI Installer for Enterprise Deployment

Using **WiX Toolset** for professional installer:

**Product.wxs**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" 
           Name="DB2 Editor" 
           Language="1033" 
           Version="1.0.0.0" 
           Manufacturer="Your Company" 
           UpgradeCode="PUT-GUID-HERE">
    
    <Package InstallerVersion="200" 
             Compressed="yes" 
             InstallScope="perMachine" />
    
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    
    <MediaTemplate EmbedCab="yes" />
    
    <Feature Id="ProductFeature" Title="DB2 Editor" Level="1">
      <ComponentGroupRef Id="ProductComponents" />
    </Feature>
    
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="DbExplorer" />
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ApplicationProgramsFolder" Name="DB2 Editor"/>
      </Directory>
      <Directory Id="DesktopFolder" Name="Desktop"/>
    </Directory>
    
    <ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER">
      <Component Id="MainExecutable">
        <File Source="$(var.PublishDir)\DbExplorer.exe" KeyPath="yes">
          <Shortcut Id="StartMenuShortcut"
                    Directory="ApplicationProgramsFolder"
                    Name="DB2 Editor"
                    WorkingDirectory="INSTALLFOLDER"
                    Icon="AppIcon.exe"
                    IconIndex="0"
                    Advertise="yes" />
          <Shortcut Id="DesktopShortcut"
                    Directory="DesktopFolder"
                    Name="DB2 Editor"
                    WorkingDirectory="INSTALLFOLDER"
                    Icon="AppIcon.exe"
                    IconIndex="0"
                    Advertise="yes" />
        </File>
      </Component>
      <!-- Add more components for DLLs and resources -->
    </ComponentGroup>
    
    <Icon Id="AppIcon.exe" SourceFile="$(var.PublishDir)\DbExplorer.exe" />
  </Product>
</Wix>
```

Build MSI:
```bash
# Install WiX Toolset first
dotnet tool install --global wix

# Build installer
wix build Product.wxs -arch x64 -out DbExplorer-Setup.msi
```

### 6. Driver Distribution Options

#### Option A: IBM.Data.DB2.Core (Recommended for Offline)
- **Fully self-contained** - no DB2 client needed
- All native libraries included in NuGet package
- Just copy the published folder

#### Option B: IBM.Data.DB2 (Traditional)
- Requires **IBM DB2 Client** pre-installed on target machine
- Create silent install script:

```powershell
# install-db2-client.ps1
$installerPath = ".\db2_v11.5_ntx64_client.exe"

# Silent install
Start-Process -FilePath $installerPath -ArgumentList "/q /i /l*v C:\Temp\db2client_install.log" -Wait

Write-Host "DB2 Client installed" -ForegroundColor Green
```

### 7. Application Configuration for Offline

**appsettings.json**
```json
{
  "Application": {
    "Version": "1.0.0",
    "Environment": "Production",
    "EnableTelemetry": false,
    "CheckForUpdates": false,
    "Framework": "net9.0-windows"
  },
  "Editor": {
    "DefaultTheme": "Dark",
    "FontFamily": "Consolas",
    "FontSize": 14,
    "ShowLineNumbers": true,
    "AutoFormatOnSave": false,
    "TabSize": 4,
    "EnableAutoComplete": true,
    "IndentSize": 4
  },
  "Database": {
    "DefaultCommandTimeout": 30,
    "MaxConnectionPoolSize": 100,
    "SaveConnectionHistory": true,
    "EnableQueryHistory": true,
    "MaxQueryHistoryItems": 100
  },
  "Logging": {
    "UseNLog": true,
    "ConfigFile": "nlog.config",
    "LogPath": "Logs",
    "MaxLogFileSizeMB": 10,
    "RetainDays": 30,
    "MinimumLevel": "Info"
  },
  "ConnectionStrings": {
    "SavedConnections": []
  },
  "Features": {
    "EnableDarkMode": true,
    "EnableMultipleTabs": true,
    "EnableSqlFormatter": true,
    "EnableDatabaseBrowser": true,
    "EnableExport": true
  }
}
```

### 8. Offline NuGet Package Cache

For development on offline machines, create a local NuGet feed:

```powershell
# On online machine: Download all packages
dotnet restore --packages ./nuget-cache

# Copy nuget-cache folder to offline machine
# On offline machine: Use local cache
dotnet restore --source ./nuget-cache --no-http-cache
```

### 9. Installation Package Checklist

Before deployment, verify your package includes:

- ✅ Main executable (`DbExplorer.exe`)
- ✅ All DLL dependencies
- ✅ .NET 10 Runtime (if self-contained)
- ✅ DB2 native drivers (IBM.Data.DB2.Core)
- ✅ Syntax highlighting files (`DB2SQL.xshd`)
- ✅ Configuration files (`appsettings.json`, `nlog.config`)
- ✅ Logs directory structure
- ✅ Documentation/README
- ✅ Sample SQL scripts/templates
- ✅ License file
- ✅ Deployment/installation scripts

### 10. Testing Offline Deployment

```powershell
# Test on a clean VM without internet
# 1. Copy package to VM
# 2. Run installation
# 3. Verify:

# Check application starts
Start-Process "C:\Program Files\DbExplorer\DbExplorer.exe"

# Check all features work:
# - Dark mode toggle
# - Multiple tabs
# - SQL formatting
# - DB2 connection
# - Query execution
```

---

## Sample Project Structure (.NET 10)

```
DbExplorer/
├── DbExplorer.csproj         # .NET 10 project file
├── App.xaml                         # Application entry with NLog init
├── App.xaml.cs                      # Startup logic and exception handling
├── MainWindow.xaml                  # Main window with TabControl
├── MainWindow.xaml.cs               # Tab management, theme toggle
├── nlog.config                      # NLog configuration (★ Required)
├── appsettings.json                 # Application settings
├── Controls/
│   ├── ConnectionTabControl.xaml   # Per-connection tab UI
│   └── ConnectionTabControl.xaml.cs # Query execution, formatting
├── Data/
│   ├── DB2ConnectionManager.cs     # Connection pooling with logging
│   ├── DB2QueryExecutor.cs         # Query execution with logging
│   └── DatabaseObjectBrowser.cs    # Tree view data provider
├── Dialogs/
│   ├── ConnectionDialog.xaml       # New connection dialog
│   ├── ConnectionDialog.xaml.cs
│   ├── SettingsDialog.xaml         # Application settings
│   └── ExportDialog.xaml           # Export results dialog
├── Models/
│   ├── ConnectionInfo.cs           # Connection data model
│   ├── QueryResult.cs              # Query result model
│   └── EditorSettings.cs           # Editor configuration model
├── Services/
│   ├── LoggingService.cs           # NLog wrapper (★ Required)
│   ├── SqlFormatterService.cs      # SQL auto-format
│   ├── ThemeService.cs             # Dark/Light mode manager
│   └── ConfigurationService.cs     # App configuration
├── Resources/
│   ├── DB2SQL.xshd                 # Custom syntax highlighting
│   └── Themes/
│       ├── DarkTheme.xaml
│       └── LightTheme.xaml
└── Utils/
    ├── SqlFormatter.cs              # SQL formatting utilities
    └── ExportHelper.cs              # Export to CSV/Excel/JSON
```

**Project File Example:**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net10.0-windows</TargetFramework>
    <Nullable>enable</Nullable>
    <UseWPF>true</UseWPF>
    <ImplicitUsings>enable</ImplicitUsings>
    <ApplicationIcon>app.ico</ApplicationIcon>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="IBM.Data.DB2.Core" Version="*" />
    <PackageReference Include="AvalonEdit" Version="*" />
    <PackageReference Include="PoorMansTSqlFormatter" Version="*" />
    <PackageReference Include="ModernWpfUI" Version="*" />
    <PackageReference Include="NLog" Version="*" />
    <PackageReference Include="NLog.Extensions.Logging" Version="*" />
    <PackageReference Include="NLog.Schema" Version="*" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="*" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="*" />
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="*" />
    <PackageReference Include="Microsoft.Extensions.Logging" Version="*" />
  </ItemGroup>

  <ItemGroup>
    <None Update="nlog.config">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
    <None Update="appsettings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
    <None Update="Resources\DB2SQL.xshd">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>
</Project>
```

---

## Resources

### IBM DB2 Documentation
- [IBM Data Server Driver for .NET](https://www.ibm.com/docs/en/db2/11.5?topic=apis-net-driver)
- [DB2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=db2-sql-reference)

### NuGet Packages (All Work Offline) - .NET 10 Compatible

**Core Packages:**
- `IBM.Data.DB2.Core` - Modern, cross-platform DB2 driver (self-contained, latest)
- `AvalonEdit` - Monaco-like code editor with syntax highlighting
- `PoorMansTSqlFormatter` - SQL auto-formatting (offline-compatible)
- `ModernWpfUI` - Modern Windows 11-style UI with dark mode

**Logging (.NET 10):**
- `NLog` - Advanced logging framework (latest version)
- `NLog.Extensions.Logging` - Microsoft.Extensions.Logging integration
- `NLog.Schema` - IntelliSense for nlog.config

**Configuration & DI:**
- `Microsoft.Extensions.DependencyInjection` - Dependency injection (.NET 10)
- `Microsoft.Extensions.Configuration.Json` - JSON configuration
- `Microsoft.Extensions.Hosting` - Hosting abstractions (.NET 10)
- `Microsoft.Extensions.Logging` - Logging abstractions

**Installation Command (Complete):**
```bash
# All packages for .NET 10
dotnet add package IBM.Data.DB2.Core && \
dotnet add package AvalonEdit && \
dotnet add package PoorMansTSqlFormatter && \
dotnet add package ModernWpfUI && \
dotnet add package NLog && \
dotnet add package NLog.Extensions.Logging && \
dotnet add package NLog.Schema && \
dotnet add package Microsoft.Extensions.DependencyInjection && \
dotnet add package Microsoft.Extensions.Configuration.Json && \
dotnet add package Microsoft.Extensions.Hosting && \
dotnet add package Microsoft.Extensions.Logging
```

### Keyboard Shortcuts Reference

| Shortcut | Action |
|----------|--------|
| **F5** | Execute query |
| **Ctrl+Enter** | Execute current statement |
| **Ctrl+Shift+F** | Format SQL |
| **Ctrl+N** | New connection tab |
| **Ctrl+W** | Close current tab |
| **Ctrl+S** | Save script |
| **Ctrl+O** | Open script |
| **Ctrl+F** | Find |
| **Ctrl+H** | Replace |
| **Ctrl+D** | Toggle dark/light mode |
| **Ctrl+B** | Toggle database browser |
| **Ctrl+E** | Explain plan |
| **Ctrl+/** | Comment lines |
| **Ctrl+Shift+/** | Uncomment lines |
| **Ctrl++** | Zoom in |
| **Ctrl+-** | Zoom out |
| **Ctrl+0** | Reset zoom |

### Community Resources
- [Stack Overflow - db2](https://stackoverflow.com/questions/tagged/db2)
- [IBM Developer Community](https://community.ibm.com/community/user/datamanagement/home)
- [NLog Documentation](https://nlog-project.org/documentation/)
- [NLog GitHub](https://github.com/NLog/NLog)
- [.NET 10 Documentation](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-9)

---

## Quick Start Guide

### Step 1: Create .NET 10 Project and Install Packages

```bash
# Verify .NET 10 is installed
dotnet --version
# Should show 9.0.x

# Create WPF project targeting .NET 10
dotnet new wpf -n DbExplorer -f net10.0-windows
cd DbExplorer

# Install required packages (latest versions for .NET 10)
dotnet add package IBM.Data.DB2.Core
dotnet add package AvalonEdit
dotnet add package PoorMansTSqlFormatter
dotnet add package ModernWpfUI
dotnet add package NLog
dotnet add package NLog.Extensions.Logging
dotnet add package NLog.Schema
dotnet add package Microsoft.Extensions.DependencyInjection
dotnet add package Microsoft.Extensions.Configuration.Json
dotnet add package Microsoft.Extensions.Hosting
dotnet add package Microsoft.Extensions.Logging
```

### Step 2: Configure NLog and Implement Core Features

1. **Create NLog Config** - Add `nlog.config` to project root
2. **Logging Service** - Create `LoggingService.cs` with NLog
3. **Connection Manager** - Create `DB2ConnectionManager.cs` with logging
4. **Query Executor** - Create `DB2QueryExecutor.cs` with logging
5. **Main Window** - Implement tabbed interface with XAML
6. **Connection Tab Control** - Create reusable tab UserControl
7. **SQL Formatter** - Add `SqlFormatterService.cs`
8. **Theme Manager** - Implement dark/light mode toggle
9. **Update Project File** - Ensure nlog.config copies to output

### Step 3: Configure Editor

1. Add custom DB2 SQL syntax highlighting (`.xshd` file)
2. Configure AvalonEdit with line numbers and code folding
3. Add keyboard shortcuts (F5, Ctrl+Shift+F, Ctrl+D)
4. Implement auto-complete for SQL keywords

### Step 4: Test and Deploy

1. **Test on development machine** with multiple connections
2. **Build self-contained package** with `dotnet publish`
3. **Test on clean VM** without internet
4. **Create deployment package** (ZIP or MSI)
5. **Deploy to production** using PowerShell script

## Next Steps

### Phase 1: Basic Implementation (Week 1)
1. ✅ Set up project with all NuGet packages
2. ✅ Implement DB2 connection manager
3. ✅ Create basic query executor
4. ✅ Build main window with tab support
5. ✅ Test connection and simple queries

### Phase 2: Advanced Editor (Week 2)
1. ✅ Integrate AvalonEdit
2. ✅ Add custom SQL syntax highlighting
3. ✅ Implement SQL formatter
4. ✅ Add keyboard shortcuts
5. ✅ Implement dark mode toggle

### Phase 3: UI Enhancement (Week 3)
1. ✅ Create database object browser
2. ✅ Add results export functionality
3. ✅ Implement query history
4. ✅ Add execution plan viewer
5. ✅ Create settings dialog

### Phase 4: Testing & Deployment (Week 4)
1. ✅ Test with different DB2 versions
2. ✅ Test offline deployment
3. ✅ Create installation package
4. ✅ Write user documentation
5. ✅ Deploy to production environment

---

## License Considerations

- IBM DB2 drivers have specific licensing terms
- Ensure compliance with IBM DB2 license agreements
- Consider licensing requirements for deployment

---

## Summary: Key Requirements Addressed

### ✅ Offline Deployment (No Internet Required)
- **Solution:** Use self-contained .NET publishing with `--self-contained true`
- **DB2 Driver:** IBM.Data.DB2.Core (all dependencies included)
- **Package:** ZIP or MSI with all DLLs, no external downloads needed
- **Testing:** Deploy to VM without internet, verify all features work

### ✅ Multiple Connection Tabs
- **Solution:** TabControl with dynamic tab creation
- **Implementation:** Each tab has its own ConnectionTabControl UserControl
- **Features:** Close button on each tab, Ctrl+N for new, Ctrl+W to close
- **Architecture:** Separate connection manager per tab for isolation

### ✅ Dark Mode Support
- **Solution:** ModernWpfUI library with theme switching
- **Implementation:** Toggle with Ctrl+D or View menu
- **Editor:** AvalonEdit with dark-compatible syntax highlighting
- **Persistence:** Theme preference saved in appsettings.json

### ✅ Monaco-like Editor
- **Solution:** AvalonEdit (most similar to VS Code's Monaco editor for WPF)
- **Features:** 
  - Line numbers
  - Syntax highlighting (custom XSHD for DB2 SQL)
  - Code folding
  - Multiple cursors
  - Find/Replace
  - Keyboard shortcuts
- **Performance:** Fast, handles large SQL files

### ✅ SQL Auto-Format
- **Solution:** PoorMansTSqlFormatter library
- **Trigger:** Ctrl+Shift+F or Format button
- **Features:**
  - Uppercase keywords
  - Proper indentation
  - Line breaks at clauses
  - Configurable formatting rules
- **Offline:** Works completely offline, no web service

---

## Architecture Overview

```
DbExplorer/
│
├── App.xaml                          # Theme configuration (Dark/Light)
├── MainWindow.xaml                   # Main window with TabControl
├── MainWindow.xaml.cs                # Tab management, theme toggle
│
├── Controls/
│   ├── ConnectionTabControl.xaml    # Per-connection tab UI
│   └── ConnectionTabControl.xaml.cs # Query execution, formatting
│
├── Data/
│   ├── DB2ConnectionManager.cs      # Connection pooling
│   └── DB2QueryExecutor.cs          # Query execution
│
├── Services/
│   ├── LoggingService.cs            # NLog wrapper (★ .NET 10)
│   ├── SqlFormatterService.cs       # Auto-format SQL
│   └── ThemeService.cs              # Dark/Light mode
│
├── Dialogs/
│   ├── ConnectionDialog.xaml        # New connection dialog
│   └── SettingsDialog.xaml          # Application settings
│
├── Resources/
│   ├── DB2SQL.xshd                  # Custom SQL syntax highlighting
│   └── Themes/                      # Dark/Light theme resources
│
└── appsettings.json                 # Configuration (offline-safe)
```

---

## Final Checklist

Before deployment, ensure:

**Framework & Runtime:**
- [x] Built with .NET 10 framework (net9.0-windows)
- [x] Application runs without internet
- [x] Self-contained deployment includes .NET 10 runtime
- [x] Tested on clean Windows 11 VM without .NET installed

**Core Features:**
- [x] Multiple tabs can be opened simultaneously (Ctrl+N)
- [x] Dark mode toggle works (Ctrl+D)
- [x] DB2 connection succeeds with native drivers (IBM.Data.DB2.Core)
- [x] Query execution displays results (F5)
- [x] All keyboard shortcuts work

**Editor & Formatting:**
- [x] AvalonEdit shows DB2 SQL syntax highlighting
- [x] SQL formatter works (Ctrl+Shift+F)
- [x] Line numbers displayed
- [x] Code folding enabled

**Logging & Configuration:**
- [x] NLog configured and working
- [x] nlog.config included in deployment
- [x] Logs written to Logs directory
- [x] appsettings.json included

**Deployment:**
- [x] All DLLs included in package
- [x] DB2 native drivers bundled
- [x] Configuration files present
- [x] Syntax highlighting files (.xshd) included

---

**Happy Coding! 🚀**

---

## Important Notes for .NET 10 and NLog

### .NET 10 Features Used
- **Enhanced performance** - Better startup times with ReadyToRun
- **Improved trimming** - Smaller deployment sizes
- **Native AOT support** - Faster execution (optional)
- **Modern C# 13** - Latest language features

### NLog Benefits for .NET 10
- **Fully compatible** with .NET 10
- **High performance** - Async logging support
- **Flexible configuration** - XML or code-based
- **Rich targets** - File, Console, Database, Cloud, etc.
- **Structured logging** - JSON output support
- **Low overhead** - Minimal impact on application performance

### Recommended NLog Configuration for Production

```xml
<!-- Production optimized nlog.config -->
<nlog xmlns="http://www.nlog-project.org/schemas/NLog.xsd"
      autoReload="true"
      throwConfigExceptions="false"
      internalLogLevel="Warn">
  
  <targets async="true">
    <target xsi:type="File" 
            name="logfile" 
            fileName="logs\db2editor-${shortdate}.log"
            layout="${longdate}|${level:uppercase=true}|${logger}|${message}${onexception:${newline}${exception:format=tostring}}"
            archiveEvery="Day"
            maxArchiveFiles="30"
            concurrentWrites="true"
            keepFileOpen="false"
            encoding="utf-8" />
  </targets>
  
  <rules>
    <logger name="*" minlevel="Info" writeTo="logfile" />
    <logger name="Microsoft.*" maxlevel="Warn" final="true" />
  </rules>
</nlog>
```

### Package Version Compatibility

As of 2024, use these minimum versions for .NET 10:
- **NLog**: 5.3.0 or later
- **NLog.Extensions.Logging**: 5.3.0 or later
- **IBM.Data.DB2.Core**: Latest available
- **AvalonEdit**: 6.3.0 or later
- **ModernWpfUI**: 0.9.6 or later
- **PoorMansTSqlFormatter**: 1.6.10 or later

Install latest versions with:
```bash
dotnet add package NLog --version *
```

---

*For questions or issues, refer to:*
- *IBM DB2 documentation for database connectivity*
- *NLog documentation for logging configuration*
- *.NET 10 documentation for framework features*
- *All packages listed work in offline environments after initial download*

**This guide is optimized for .NET 10 and Windows 11 deployment in offline/air-gapped environments.**

