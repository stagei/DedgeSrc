# DbExplorer

A modern, offline-capable DB2 database editor for Windows 11 built with .NET 10 and WPF.

## Features

### Database Connectivity
- **Real DB2 Integration**: Full connectivity using Net.IBM.Data.Db2 9.0.0.400 (no external DB2 client needed)
- **Multiple Connection Tabs**: Open and manage multiple DB2 database connections simultaneously
- **Connection Testing**: Test connections before connecting with detailed error reporting
- **Connection Pooling**: Automatic connection pooling for optimal performance

### SQL Editor
- **Syntax Highlighting**: Custom DB2 SQL syntax highlighting with AvalonEdit
- **Auto-Formatting**: Format SQL queries with PoorMansTSqlFormatter (Ctrl+Shift+F)
- **Smart Execution**: Execute all or current statement at cursor (F5 or Ctrl+Enter)
- **Script Management**: Save and open SQL scripts (Ctrl+S, Ctrl+O)
- **Line Numbers**: Always visible for reference
- **Code Folding**: Collapse/expand code blocks

### Database Browser
- **Schema Explorer**: TreeView with schemas and tables
- **Lazy Loading**: Tables load on demand for performance
- **Quick Query**: Double-click table to insert SELECT statement
- **Hierarchical View**: Organized schema → table structure

### Query History
- **Automatic Tracking**: All queries logged with timestamp and execution time
- **Search & Filter**: Find past queries quickly
- **Rerun Queries**: Reload and execute historical queries
- **Copy to Clipboard**: Copy queries for reuse
- **Success Tracking**: Visual indicators for query status

### Data Export
- **Multiple Formats**: Export to CSV, TSV, JSON, or SQL INSERT statements
- **Large Dataset Support**: Efficient handling of big result sets
- **Custom File Names**: Date-stamped default file names

### Settings & Configuration
- **Configurable Settings**: Editor, Database, and Logging settings
- **Theme Preferences**: Saved across sessions
- **Font Customization**: Font family and size options
- **Timeout Configuration**: Adjust query timeout limits
- **Log Management**: Configure log retention and location

### User Interface
- **Modern Design**: Word-inspired interface with professional styling
- **Dark/Light/System Themes**: Three theme options with auto-detection
- **Resizable Panels**: Adjust layout to your preference
- **Status Bar**: Connection count and active connection display
- **Keyboard Shortcuts**: Full keyboard support for productivity

### Enterprise Features
- **Comprehensive Logging**: NLog with DEBUG-level support for troubleshooting
- **Password Masking**: Sensitive data protected in logs
- **Error Handling**: Detailed error messages with SQL State codes
- **Offline Deployment**: Self-contained, no internet required
- **Production Ready**: Tested and ready for enterprise use

## Requirements

- Windows 11
- .NET 10 Runtime (included in self-contained deployment)
- No IBM DB2 Client installation required (uses Net.IBM.Data.Db2 9.0.0.400)
- DB2 database server accessible via network connection

## Keyboard Shortcuts

### Connection Management
- `Ctrl+N`: New Connection
- `Ctrl+W`: Close Current Tab
- `Ctrl+Tab`: Next Tab
- `Ctrl+Shift+Tab`: Previous Tab

### SQL Editor
- `F5`: Execute Query
- `Ctrl+Enter`: Execute Current Statement (at cursor)
- `Ctrl+Shift+F`: Format SQL
- `Ctrl+S`: Save Script
- `Ctrl+O`: Open Script

### Application
- `Ctrl+D`: Cycle Theme (Dark → Light → System)
- `Ctrl+H`: Query History
- `Alt+F4`: Exit

## Theme Options

The application supports three theme modes:
- **Dark Mode**: Professional dark theme for reduced eye strain
- **Light Mode**: Clean light theme for bright environments  
- **System Theme**: Automatically follows your Windows system theme preference

Press `Ctrl+D` to cycle through themes. The preference is saved automatically.

## Technology Stack

- **.NET**: 10.0 (net10.0-windows)
- **UI Framework**: WPF with ModernWpfUI
- **Database**: Net.IBM.Data.Db2 9.0.0.400 (Real DB2 connectivity)
- **Logging**: NLog 6.0.6
- **SQL Editor**: AvalonEdit 6.3.1
- **SQL Formatter**: PoorMansTSqlFormatter 1.4.3

## Project Structure

```
DbExplorer/
├── Controls/           # UserControls (ConnectionTabControl)
├── Data/              # DB2 connection management
├── Dialogs/           # Dialog windows (ConnectionDialog)
├── Models/            # Data models (DB2Connection, AppSettings)
├── Services/          # Business logic (LoggingService, SqlFormatterService, ConfigurationService)
├── Utils/             # Helper classes
├── Resources/         # XSHD files, themes
├── appsettings.json   # Application configuration
├── nlog.config        # NLog configuration
└── README.md          # This file
```

## Configuration

### appsettings.json

Configure editor settings, database defaults, and logging options:

```json
{
  "Editor": {
    "DefaultTheme": "Dark",
    "FontFamily": "Consolas",
    "FontSize": 14
  },
  "Database": {
    "DefaultCommandTimeout": 30
  }
}
```

### nlog.config

Logging configuration with file, console, and debugger targets.
Logs are written to `logs/db2editor-{date}.log`.

## Building

```bash
# Debug build
dotnet build

# Release build
dotnet build -c Release

# Self-contained deployment
dotnet publish -c Release -r win-x64 --self-contained true -f net10.0-windows
```

## Running

```bash
dotnet run
```

Or execute the published `.exe` file after building.

## Development

This project follows strict coding standards defined in `.cursorrules`:

- **Logging**: NLog with DEBUG-level logging for troubleshooting
- **Error Handling**: Comprehensive exception handling with logging
- **Code Style**: Microsoft C# conventions with PascalCase/camelCase naming
- **Security**: Parameterized queries, password masking in logs
- **Regular Builds**: Build after each component implementation

## Logs

Application logs are stored in:
- Development: `logs/db2editor-{date}.log`
- Archives: `logs/archives/` (30-day retention)
- Internal NLog logs: `logs/nlog-internal.log`

## License

Internal use only.

## Version

1.0.0 - Initial implementation with core features

