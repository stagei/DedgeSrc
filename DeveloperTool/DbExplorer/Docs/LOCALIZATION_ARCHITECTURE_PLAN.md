# Application Localization Architecture Plan

**Purpose:** Complete internationalization (i18n) strategy for DbExplorer  
**Date:** November 20, 2025  
**Goal:** Support multiple languages without recompiling application

---

## 🎯 VISION

Transform DbExplorer into a **fully localizable application** where:
- **ALL UI text** is stored in language-specific JSON files
- **No hardcoded strings** in XAML or code-behind
- **Easy to add new languages** (French, Norwegian, German, etc.)
- **Runtime language switching** without restart
- **Fallback to English** if translation missing
- **Right-to-left (RTL) support** for Arabic/Hebrew

---

## 🏗️ ARCHITECTURE OVERVIEW

### Current State (Problems)
```
❌ UI text hardcoded in XAML:
   - Button labels: "Execute", "Format", "Export"
   - Menu items: "File", "View", "Help"
   - Dialog titles: "Connection Settings", "Table Properties"
   - Tooltips: "Execute query (F5)"
   
❌ Error messages hardcoded in C#:
   - 202 MessageBox.Show() calls with English text
   - No way to translate without recompiling
   
❌ Column headers hardcoded:
   - DataGrid columns: "Name", "Type", "Length"
   - TreeView categories: "Tables", "Views", "Indexes"
```

### Target State (Solution)
```
✅ All text in JSON files:
   /Localization/
   ├── en-US.json    (English - default)
   ├── fr-FR.json    (French)
   ├── no-NO.json    (Norwegian)
   ├── de-DE.json    (German)
   ├── es-ES.json    (Spanish)
   └── ja-JP.json    (Japanese)

✅ XAML uses keys:
   <Button Content="{loc:Translate Key=toolbar.execute}"/>
   
✅ C# uses LocalizationService:
   var message = _localization.Get("errors.connection_failed", new {database = dbName});
   MessageBox.Show(message, _localization.Get("errors.title"));
   
✅ Runtime language switching:
   - User changes language in Settings
   - All UI updates immediately
   - No restart required
```

---

## 📁 FILE STRUCTURE

### Localization Folder Structure
```
/Localization/
├── en-US.json                 # English (US) - DEFAULT
├── en-GB.json                 # English (UK)
├── fr-FR.json                 # French (France)
├── no-NO.json                 # Norwegian (Bokmål)
├── de-DE.json                 # German
├── es-ES.json                 # Spanish
├── it-IT.json                 # Italian
├── ja-JP.json                 # Japanese
├── zh-CN.json                 # Chinese (Simplified)
├── pt-BR.json                 # Portuguese (Brazil)
└── _template.json             # Template for translators
```

### Language File Format
Each language file contains the SAME keys with translated values:

```json
{
  "language": {
    "code": "en-US",
    "name": "English (United States)",
    "native_name": "English (United States)",
    "direction": "ltr",
    "translator": "Original",
    "version": "1.0.0",
    "last_updated": "2025-11-20"
  },
  "ui": {
    "main_window": {
      "title": "DB2 Database Editor",
      "menu": {
        "file": "File",
        "file_new_connection": "New Connection...",
        "file_open_script": "Open SQL Script...",
        "file_save_script": "Save Script",
        "file_save_script_as": "Save Script As...",
        "file_exit": "Exit",
        "edit": "Edit",
        "edit_undo": "Undo",
        "edit_redo": "Redo",
        "edit_cut": "Cut",
        "edit_copy": "Copy",
        "edit_paste": "Paste",
        "edit_find": "Find...",
        "edit_replace": "Replace...",
        "view": "View",
        "view_object_browser": "Object Browser",
        "view_query_history": "Query History",
        "view_dark_mode": "Toggle Dark Mode",
        "tools": "Tools",
        "tools_settings": "Settings...",
        "tools_format_sql": "Format SQL",
        "help": "Help",
        "help_about": "About"
      }
    },
    "toolbar": {
      "new_connection": "New Connection",
      "execute": "Execute",
      "execute_tooltip": "Execute query (F5)",
      "format": "Format SQL",
      "format_tooltip": "Format SQL (Ctrl+Shift+F)",
      "export": "Export",
      "export_tooltip": "Export results to file",
      "commit": "Commit",
      "commit_tooltip": "Commit transaction",
      "rollback": "Rollback",
      "rollback_tooltip": "Rollback transaction",
      "cancel": "Cancel",
      "cancel_tooltip": "Cancel running query"
    },
    "statusbar": {
      "ready": "Ready",
      "connecting": "Connecting...",
      "connected": "Connected to {database}",
      "disconnected": "Disconnected",
      "executing": "Executing query...",
      "rows_returned": "{count} rows returned",
      "no_results": "No results",
      "error": "Error: {message}"
    },
    "object_browser": {
      "title": "Database Objects",
      "search_placeholder": "Search objects...",
      "categories": {
        "database": "Database",
        "schemas": "Schemas",
        "tables": "Tables",
        "views": "Views",
        "procedures": "Stored Procedures",
        "functions": "Functions",
        "indexes": "Indexes",
        "triggers": "Triggers",
        "sequences": "Sequences",
        "synonyms": "Synonyms",
        "packages": "Packages",
        "types": "User-Defined Types",
        "tablespaces": "Tablespaces",
        "security": "Security"
      },
      "context_menu": {
        "browse_data": "Browse Data (Top 1000)",
        "count_rows": "Count Rows",
        "generate_select": "Generate SELECT Statement",
        "view_properties": "Properties...",
        "view_source": "View Source Code",
        "copy_name": "Copy Name",
        "copy_full_name": "Copy Full Name",
        "refresh": "Refresh"
      }
    },
    "tabs": {
      "new_tab": "New Query",
      "close_tab": "Close Tab",
      "close_all_tabs": "Close All Tabs",
      "query": "Query",
      "results": "Results",
      "messages": "Messages",
      "execution_plan": "Execution Plan",
      "history": "History"
    },
    "dialogs": {
      "connection": {
        "title": "Connection Settings",
        "profile_name": "Profile Name",
        "server": "Server",
        "port": "Port",
        "database": "Database",
        "username": "Username",
        "password": "Password",
        "save_password": "Save Password",
        "connection_timeout": "Connection Timeout (seconds)",
        "read_only": "Read-Only Connection",
        "auto_commit": "Auto-Commit",
        "test_connection": "Test Connection",
        "connect": "Connect",
        "cancel": "Cancel"
      },
      "table_properties": {
        "title": "Table Properties - {table}",
        "tabs": {
          "properties": "Properties",
          "columns": "Columns",
          "indexes": "Indexes",
          "foreign_keys": "Foreign Keys",
          "triggers": "Triggers",
          "statistics": "Statistics",
          "ddl": "DDL"
        },
        "properties": {
          "schema": "Schema",
          "name": "Table Name",
          "owner": "Owner",
          "type": "Type",
          "rows": "Row Count",
          "created": "Created",
          "modified": "Last Modified",
          "tablespace": "Tablespace",
          "compression": "Compression",
          "data_capture": "Data Capture"
        },
        "columns": {
          "name": "Column Name",
          "type": "Data Type",
          "length": "Length",
          "nullable": "Nullable",
          "default": "Default Value",
          "primary_key": "PK",
          "remarks": "Remarks"
        }
      },
      "settings": {
        "title": "Settings",
        "tabs": {
          "general": "General",
          "editor": "Editor",
          "appearance": "Appearance",
          "performance": "Performance",
          "language": "Language"
        },
        "language": {
          "select_language": "Select Language",
          "restart_required": "Restart required for full effect",
          "download_languages": "Download Additional Languages..."
        }
      },
      "export": {
        "title": "Export Data",
        "format": "Export Format",
        "formats": {
          "csv": "CSV (Comma-Separated Values)",
          "tsv": "TSV (Tab-Separated Values)",
          "json": "JSON",
          "xml": "XML",
          "excel": "Excel (XLSX)",
          "sql": "SQL INSERT Statements"
        },
        "options": {
          "include_headers": "Include Column Headers",
          "include_schema": "Include Schema Name",
          "trim_strings": "Trim String Values",
          "null_value": "NULL Representation"
        },
        "destination": "Destination",
        "file_path": "File Path",
        "browse": "Browse...",
        "export": "Export",
        "cancel": "Cancel"
      }
    }
  },
  "messages": {
    "errors": {
      "title": "Error",
      "connection_failed": "Failed to connect to {database}.\n\nPlease check your connection settings and try again.",
      "connection_timeout": "Connection timed out after {timeout} seconds.",
      "connection_lost": "Connection to {database} was lost.\n\nWould you like to reconnect?",
      "invalid_credentials": "Authentication failed.\n\nPlease check your username and password.",
      "query_syntax_error": "SQL Syntax Error:\n\n{error}",
      "query_execution_failed": "Query execution failed:\n\n{error}",
      "query_timeout": "Query timed out after {timeout} seconds.",
      "file_not_found": "File not found:\n\n{filename}",
      "file_read_error": "Error reading file:\n\n{error}",
      "file_write_error": "Error writing file:\n\n{error}",
      "export_failed": "Export failed:\n\n{error}",
      "no_active_connection": "No active database connection.\n\nPlease connect to a database first.",
      "feature_requires_dba": "This feature requires DBA privileges.\n\nYour current access level: {level}",
      "metadata_load_failed": "Failed to load database metadata:\n\n{error}"
    },
    "warnings": {
      "title": "Warning",
      "delete_without_where": "⚠️ DELETE without WHERE clause detected!\n\nThis will delete ALL rows from the table.\n\nAre you sure you want to continue?",
      "update_without_where": "⚠️ UPDATE without WHERE clause detected!\n\nThis will update ALL rows in the table.\n\nAre you sure you want to continue?",
      "drop_object": "⚠️ You are about to DROP {type} '{name}'.\n\nThis operation cannot be undone.\n\nAre you sure?",
      "truncate_table": "⚠️ TRUNCATE will delete ALL data from '{table}'.\n\nThis operation cannot be undone.\n\nContinue?",
      "large_result_set": "Query returned {count} rows.\n\nDisplaying first {limit} rows only.\n\nExport full results?",
      "unsaved_changes": "You have unsaved changes in this query tab.\n\nClose anyway?",
      "connection_read_only": "This is a READ-ONLY connection.\n\nDML/DDL operations are not allowed."
    },
    "confirmations": {
      "title": "Confirm",
      "close_tab": "Close tab '{name}'?",
      "close_all_tabs": "Close all {count} tabs?",
      "disconnect": "Disconnect from '{database}'?",
      "overwrite_file": "File '{filename}' already exists.\n\nOverwrite?",
      "execute_ddl": "Execute DDL statement?\n\n{sql}\n\nThis may modify database structure.",
      "force_disconnect_session": "Force disconnect session {session}?\n\nThis will terminate the user's connection."
    },
    "success": {
      "title": "Success",
      "query_executed": "Query executed successfully.\n\n{rows} rows affected.",
      "export_complete": "Data exported successfully to:\n\n{filename}",
      "ddl_generated": "DDL generated successfully.",
      "connection_successful": "Connected to '{database}' successfully.",
      "script_saved": "Script saved to:\n\n{filename}",
      "transaction_committed": "Transaction committed successfully.",
      "transaction_rolled_back": "Transaction rolled back successfully."
    },
    "info": {
      "title": "Information",
      "no_data_to_export": "No data available to export.",
      "no_results": "Query executed successfully.\n\nNo results returned.",
      "copying_to_clipboard": "Copied to clipboard.",
      "metadata_refreshed": "Database metadata refreshed.",
      "format_complete": "SQL formatted successfully.",
      "feature_not_available": "This feature is not available for {provider} version {version}."
    }
  },
  "common": {
    "buttons": {
      "ok": "OK",
      "cancel": "Cancel",
      "yes": "Yes",
      "no": "No",
      "apply": "Apply",
      "close": "Close",
      "save": "Save",
      "save_as": "Save As...",
      "open": "Open",
      "browse": "Browse...",
      "refresh": "Refresh",
      "copy": "Copy",
      "paste": "Paste",
      "delete": "Delete",
      "execute": "Execute",
      "abort": "Abort",
      "retry": "Retry",
      "ignore": "Ignore",
      "help": "Help"
    },
    "labels": {
      "name": "Name",
      "type": "Type",
      "size": "Size",
      "date": "Date",
      "status": "Status",
      "owner": "Owner",
      "schema": "Schema",
      "table": "Table",
      "column": "Column",
      "rows": "Rows",
      "created": "Created",
      "modified": "Modified",
      "description": "Description",
      "remarks": "Remarks"
    },
    "placeholders": {
      "search": "Search...",
      "filter": "Filter...",
      "enter_value": "Enter value...",
      "select_option": "Select an option..."
    },
    "units": {
      "bytes": "bytes",
      "kb": "KB",
      "mb": "MB",
      "gb": "GB",
      "seconds": "seconds",
      "minutes": "minutes",
      "hours": "hours",
      "days": "days",
      "rows": "rows"
    },
    "time": {
      "today": "Today",
      "yesterday": "Yesterday",
      "this_week": "This Week",
      "this_month": "This Month",
      "just_now": "Just now",
      "minutes_ago": "{count} minutes ago",
      "hours_ago": "{count} hours ago",
      "days_ago": "{count} days ago"
    }
  },
  "accessibility": {
    "screen_reader": {
      "main_menu": "Main menu",
      "toolbar": "Toolbar",
      "object_browser": "Database object browser",
      "sql_editor": "SQL editor",
      "results_grid": "Results data grid",
      "status_bar": "Status bar",
      "loading": "Loading...",
      "error_occurred": "An error occurred",
      "success": "Operation successful"
    }
  }
}
```

---

## 🔑 KEY-VALUE REFERENCE ARCHITECTURE

### Two-File System: UI References + Language Files

#### File 1: UI Text Keys Reference (`ui_text_keys.json`)
Maps UI elements to text keys (provider/version independent):

```json
{
  "provider": "DB2",
  "version": "12.1",
  "ui_text_mappings": {
    "MainWindow": {
      "Title": "ui.main_window.title",
      "Menu_File": "ui.main_window.menu.file",
      "Menu_File_NewConnection": "ui.main_window.menu.file_new_connection",
      "Menu_File_Exit": "ui.main_window.menu.file_exit"
    },
    "ConnectionDialog": {
      "Title": "ui.dialogs.connection.title",
      "Label_Server": "ui.dialogs.connection.server",
      "Label_Port": "ui.dialogs.connection.port",
      "Button_Connect": "ui.dialogs.connection.connect",
      "Button_TestConnection": "ui.dialogs.connection.test_connection"
    },
    "TablePropertiesDialog": {
      "Title": "ui.dialogs.table_properties.title",
      "Tab_Columns": "ui.dialogs.table_properties.tabs.columns",
      "Column_Name": "ui.dialogs.table_properties.columns.name",
      "Column_Type": "ui.dialogs.table_properties.columns.type"
    },
    "ErrorMessages": {
      "ConnectionFailed": "messages.errors.connection_failed",
      "QuerySyntaxError": "messages.errors.query_syntax_error",
      "DeleteWithoutWhere": "messages.warnings.delete_without_where"
    },
    "ObjectBrowser": {
      "Category_Tables": "ui.object_browser.categories.tables",
      "Category_Views": "ui.object_browser.categories.views",
      "ContextMenu_BrowseData": "ui.object_browser.context_menu.browse_data"
    }
  }
}
```

#### File 2: Language-Specific Translations (`{lang-code}.json`)
Contains actual translated text (shown above in "Language File Format" section).

---

## 🛠️ IMPLEMENTATION COMPONENTS

### 1. LocalizationService Class

```csharp
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Centralized localization service for multi-language support
/// </summary>
public class LocalizationService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private Dictionary<string, string> _translations = new();
    private Dictionary<string, string> _fallbackTranslations = new(); // en-US
    private CultureInfo _currentCulture;
    private string _localizationFolder;
    
    public event EventHandler? LanguageChanged;
    
    public LocalizationService()
    {
        _localizationFolder = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Localization");
        _currentCulture = CultureInfo.CurrentUICulture;
        
        Logger.Info("LocalizationService initialized. Current culture: {Culture}", _currentCulture.Name);
        
        LoadLanguage("en-US", isFallback: true); // Load English as fallback
        LoadLanguage(_currentCulture.Name);
    }
    
    /// <summary>
    /// Get translated text by key with optional parameters
    /// </summary>
    public string Get(string key, object? parameters = null)
    {
        Logger.Debug("Getting translation for key: {Key}", key);
        
        // Try current language
        if (_translations.TryGetValue(key, out var value))
        {
            return FormatString(value, parameters);
        }
        
        // Fallback to English
        if (_fallbackTranslations.TryGetValue(key, out var fallbackValue))
        {
            Logger.Warn("Translation missing for key '{Key}' in {Culture}, using fallback", 
                key, _currentCulture.Name);
            return FormatString(fallbackValue, parameters);
        }
        
        // Last resort: return key itself
        Logger.Error("Translation missing for key '{Key}' in both {Culture} and en-US", 
            key, _currentCulture.Name);
        return $"[{key}]";
    }
    
    /// <summary>
    /// Get translated text with format parameters
    /// </summary>
    private string FormatString(string format, object? parameters)
    {
        if (parameters == null) return format;
        
        try
        {
            // Support both named parameters {database} and indexed {0}
            var properties = parameters.GetType().GetProperties();
            foreach (var prop in properties)
            {
                var placeholder = $"{{{prop.Name}}}";
                var value = prop.GetValue(parameters)?.ToString() ?? string.Empty;
                format = format.Replace(placeholder, value);
            }
            return format;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error formatting string: {Format}", format);
            return format;
        }
    }
    
    /// <summary>
    /// Load language file
    /// </summary>
    public void LoadLanguage(string languageCode, bool isFallback = false)
    {
        Logger.Info("Loading language: {Language} (Fallback: {IsFallback})", languageCode, isFallback);
        
        try
        {
            var filePath = Path.Combine(_localizationFolder, $"{languageCode}.json");
            
            if (!File.Exists(filePath))
            {
                Logger.Warn("Language file not found: {FilePath}", filePath);
                return;
            }
            
            var json = File.ReadAllText(filePath);
            var languageData = JsonSerializer.Deserialize<Dictionary<string, object>>(json);
            
            if (languageData == null)
            {
                Logger.Error("Failed to deserialize language file: {FilePath}", filePath);
                return;
            }
            
            // Flatten nested JSON into dot-notation keys
            var translations = new Dictionary<string, string>();
            FlattenJson(languageData, "", translations);
            
            if (isFallback)
            {
                _fallbackTranslations = translations;
                Logger.Info("Loaded {Count} fallback translations", translations.Count);
            }
            else
            {
                _translations = translations;
                _currentCulture = new CultureInfo(languageCode);
                Logger.Info("Loaded {Count} translations for {Language}", translations.Count, languageCode);
                LanguageChanged?.Invoke(this, EventArgs.Empty);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load language file: {Language}", languageCode);
        }
    }
    
    /// <summary>
    /// Flatten nested JSON into dot-notation keys
    /// Example: {"ui": {"menu": {"file": "File"}}} => {"ui.menu.file": "File"}
    /// </summary>
    private void FlattenJson(Dictionary<string, object> source, string prefix, Dictionary<string, string> result)
    {
        foreach (var kvp in source)
        {
            var key = string.IsNullOrEmpty(prefix) ? kvp.Key : $"{prefix}.{kvp.Key}";
            
            if (kvp.Value is JsonElement element)
            {
                if (element.ValueKind == JsonValueKind.String)
                {
                    result[key] = element.GetString() ?? string.Empty;
                }
                else if (element.ValueKind == JsonValueKind.Object)
                {
                    var nestedDict = JsonSerializer.Deserialize<Dictionary<string, object>>(element.GetRawText());
                    if (nestedDict != null)
                    {
                        FlattenJson(nestedDict, key, result);
                    }
                }
            }
            else if (kvp.Value is string strValue)
            {
                result[key] = strValue;
            }
        }
    }
    
    /// <summary>
    /// Get list of available languages
    /// </summary>
    public List<LanguageInfo> GetAvailableLanguages()
    {
        var languages = new List<LanguageInfo>();
        
        if (!Directory.Exists(_localizationFolder))
        {
            Logger.Warn("Localization folder not found: {Folder}", _localizationFolder);
            return languages;
        }
        
        foreach (var file in Directory.GetFiles(_localizationFolder, "*.json"))
        {
            try
            {
                var json = File.ReadAllText(file);
                var data = JsonSerializer.Deserialize<Dictionary<string, object>>(json);
                
                if (data != null && data.ContainsKey("language"))
                {
                    var langElement = (JsonElement)data["language"];
                    var langInfo = JsonSerializer.Deserialize<LanguageInfo>(langElement.GetRawText());
                    if (langInfo != null)
                    {
                        languages.Add(langInfo);
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error reading language file: {File}", file);
            }
        }
        
        return languages;
    }
    
    /// <summary>
    /// Change current language
    /// </summary>
    public void ChangeLanguage(string languageCode)
    {
        Logger.Info("Changing language to: {Language}", languageCode);
        LoadLanguage(languageCode);
    }
    
    /// <summary>
    /// Get current language code
    /// </summary>
    public string CurrentLanguage => _currentCulture.Name;
}

/// <summary>
/// Language metadata
/// </summary>
public class LanguageInfo
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string NativeName { get; set; } = string.Empty;
    public string Direction { get; set; } = "ltr"; // ltr or rtl
    public string Translator { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string LastUpdated { get; set; } = string.Empty;
}
```

---

### 2. XAML Markup Extension for Translations

```csharp
using System;
using System.Windows.Markup;
using System.Windows.Data;

namespace DbExplorer.Utils;

/// <summary>
/// XAML markup extension for localized text
/// Usage: <Button Content="{loc:Translate Key=toolbar.execute}"/>
/// </summary>
public class TranslateExtension : MarkupExtension
{
    public string Key { get; set; } = string.Empty;
    
    public TranslateExtension() { }
    
    public TranslateExtension(string key)
    {
        Key = key;
    }
    
    public override object ProvideValue(IServiceProvider serviceProvider)
    {
        // Create binding to LocalizationService
        var binding = new Binding($"[{Key}]")
        {
            Source = App.Current.LocalizationService,
            Mode = BindingMode.OneWay
        };
        
        return binding.ProvideValue(serviceProvider);
    }
}
```

---

### 3. Usage Examples

#### XAML Usage
```xml
<!-- Before: Hardcoded text -->
<Button Content="Execute" ToolTip="Execute query (F5)"/>

<!-- After: Localized text -->
<Button Content="{loc:Translate Key=toolbar.execute}" 
        ToolTip="{loc:Translate Key=toolbar.execute_tooltip}"/>

<!-- Menu items -->
<MenuItem Header="{loc:Translate Key=ui.main_window.menu.file}">
    <MenuItem Header="{loc:Translate Key=ui.main_window.menu.file_new_connection}" 
              Command="{Binding NewConnectionCommand}"/>
    <MenuItem Header="{loc:Translate Key=ui.main_window.menu.file_exit}" 
              Command="{Binding ExitCommand}"/>
</MenuItem>

<!-- DataGrid columns -->
<DataGrid>
    <DataGrid.Columns>
        <DataGridTextColumn Header="{loc:Translate Key=ui.dialogs.table_properties.columns.name}" 
                            Binding="{Binding Name}"/>
        <DataGridTextColumn Header="{loc:Translate Key=ui.dialogs.table_properties.columns.type}" 
                            Binding="{Binding Type}"/>
    </DataGrid.Columns>
</DataGrid>
```

#### C# Code Usage
```csharp
// Error messages with parameters
var message = _localization.Get("messages.errors.connection_failed", new { database = dbName });
var title = _localization.Get("messages.errors.title");
MessageBox.Show(message, title, MessageBoxButton.OK, MessageBoxImage.Error);

// Confirmation dialogs
var confirmMessage = _localization.Get("messages.warnings.drop_object", 
    new { type = "TABLE", name = tableName });
var confirmTitle = _localization.Get("messages.warnings.title");
var result = MessageBox.Show(confirmMessage, confirmTitle, 
    MessageBoxButton.YesNo, MessageBoxImage.Warning);

// Success messages
var successMsg = _localization.Get("messages.success.query_executed", 
    new { rows = rowCount });
MessageBox.Show(successMsg, _localization.Get("messages.success.title"));

// Button text (dynamic)
ExecuteButton.Content = _localization.Get("toolbar.execute");
CancelButton.Content = _localization.Get("common.buttons.cancel");

// TreeView categories
var tablesNode = new TreeViewItem 
{ 
    Header = _localization.Get("ui.object_browser.categories.tables") 
};
```

---

## 📊 TEXT EXTRACTION PROCESS

### Step 1: Audit All UI Text
Search codebase for hardcoded text:

```bash
# Find hardcoded Button Content
grep -r 'Content="[^{]' *.xaml

# Find hardcoded MenuItem Header
grep -r 'Header="[^{]' *.xaml

# Find MessageBox.Show calls
grep -r 'MessageBox.Show' *.cs

# Find hardcoded strings in C#
grep -r '"[A-Z]' *.cs | grep -v '//'
```

### Step 2: Create Text Inventory
Catalog all text by category:

| Category | Count | Examples |
|----------|-------|----------|
| Menu Items | 40+ | "File", "Edit", "View", "Tools" |
| Button Labels | 60+ | "Execute", "Cancel", "Browse" |
| Dialog Titles | 25+ | "Connection Settings", "Table Properties" |
| Error Messages | 202 | See MessageBox.Show() calls |
| Column Headers | 50+ | "Name", "Type", "Length", "Nullable" |
| Tooltips | 45+ | "Execute query (F5)", "Format SQL" |
| Status Messages | 30+ | "Connected to...", "Executing query..." |
| TreeView Categories | 20+ | "Tables", "Views", "Indexes" |

**Total Unique Text Elements:** ~472

### Step 3: Assign Keys
Create consistent key naming convention:

```
Format: {category}.{subcategory}.{element}

Examples:
- ui.main_window.menu.file
- ui.toolbar.execute
- ui.object_browser.categories.tables
- messages.errors.connection_failed
- ui.dialogs.connection.title
- common.buttons.ok
```

### Step 4: Generate Template
Create `_template.json` with ALL keys and English values:

```json
{
  "language": {
    "code": "_template",
    "name": "Template for Translators",
    "native_name": "",
    "direction": "ltr",
    "translator": "",
    "version": "1.0.0",
    "last_updated": ""
  },
  "ui": {
    "main_window": {
      "title": "DB2 Database Editor",
      ...
    }
  },
  "messages": {...},
  "common": {...}
}
```

### Step 5: Create Language Files
Copy template for each language:
- `en-US.json` (English - already done)
- `fr-FR.json` (French - translate)
- `no-NO.json` (Norwegian - translate)
- etc.

---

## 🌍 LANGUAGE-SPECIFIC CONSIDERATIONS

### Date/Time Formatting
```csharp
// Use CultureInfo for formatting
var culture = new CultureInfo(_localization.CurrentLanguage);
var dateStr = DateTime.Now.ToString("d", culture);  // Short date
var timeStr = DateTime.Now.ToString("t", culture);  // Short time
var numStr = 12345.67.ToString("N2", culture);      // Number format
```

### Number Formatting
Different cultures use different decimal separators:
- US: 1,234.56
- France: 1 234,56
- Germany: 1.234,56

### Currency
```csharp
var culture = new CultureInfo(_localization.CurrentLanguage);
var costStr = 1234.56.ToString("C", culture);
// US: $1,234.56
// France: 1 234,56 €
// Norway: kr 1 234,56
```

### Right-to-Left (RTL) Languages
For Arabic/Hebrew:

```json
{
  "language": {
    "code": "ar-SA",
    "name": "Arabic (Saudi Arabia)",
    "native_name": "العربية (المملكة العربية السعودية)",
    "direction": "rtl"
  }
}
```

```csharp
// In LocalizationService
if (_currentLanguageInfo.Direction == "rtl")
{
    FlowDirection = FlowDirection.RightToLeft;
}
```

---

## 📋 IMPLEMENTATION TASKS

### Phase 1: Setup Infrastructure (Week 1)
- [ ] Create `Localization/` folder
- [ ] Create `LocalizationService` class
- [ ] Create `TranslateExtension` XAML markup extension
- [ ] Create `LanguageInfo` model
- [ ] Add LocalizationService to App.xaml.cs (singleton)
- [ ] Create `_template.json` with full structure

### Phase 2: Text Extraction (Week 2)
- [ ] Audit all XAML files for hardcoded text
- [ ] Audit all C# files for MessageBox.Show()
- [ ] Create inventory spreadsheet (category, key, English text)
- [ ] Assign keys to all text elements (472+ items)
- [ ] Generate `en-US.json` from inventory

### Phase 3: XAML Migration (Week 3)
- [ ] Update MainWindow.xaml menus
- [ ] Update toolbar buttons
- [ ] Update ConnectionDialog.xaml
- [ ] Update TableDetailsDialog.xaml
- [ ] Update all other dialogs (15+ dialogs)
- [ ] Update ObjectBrowser categories
- [ ] Update DataGrid column headers

### Phase 4: C# Code Migration (Week 4)
- [ ] Replace all MessageBox.Show() calls (202 instances)
- [ ] Update dynamic UI text generation
- [ ] Update TreeView node headers
- [ ] Update context menu labels
- [ ] Update status bar messages
- [ ] Update tooltips generated in code

### Phase 5: Additional Languages (Week 5)
- [ ] Create `fr-FR.json` (French)
- [ ] Create `no-NO.json` (Norwegian)
- [ ] Create `de-DE.json` (German)
- [ ] Add language selector to Settings dialog
- [ ] Implement runtime language switching
- [ ] Test all languages for missing keys

### Phase 6: Testing & Polish (Week 6)
- [ ] Test all dialogs in each language
- [ ] Verify no hardcoded text remains
- [ ] Test text truncation/wrapping issues
- [ ] Test RTL languages (if supported)
- [ ] Verify date/time/number formatting
- [ ] Create translator documentation

---

## 🎯 SUCCESS CRITERIA

✅ **Zero hardcoded UI text** in XAML or C#  
✅ **All 472+ text elements** in JSON files  
✅ **Minimum 3 languages** supported (en-US, fr-FR, no-NO)  
✅ **Runtime language switching** works without restart  
✅ **Fallback to English** for missing translations  
✅ **No missing translation keys** logged as errors  
✅ **Date/time/number** formatting respects culture  
✅ **Settings dialog** includes language selector  
✅ **Translator documentation** created  
✅ **Build succeeds** with zero hardcoded string warnings  

---

## 🚀 MIGRATION EXAMPLE

### Before (Hardcoded)
```xml
<!-- ConnectionDialog.xaml -->
<Window Title="Connection Settings" Height="600" Width="500">
    <Label Content="Server:"/>
    <TextBox x:Name="ServerTextBox"/>
    
    <Label Content="Port:"/>
    <TextBox x:Name="PortTextBox"/>
    
    <Label Content="Database:"/>
    <TextBox x:Name="DatabaseTextBox"/>
    
    <Button Content="Connect" Click="Connect_Click"/>
    <Button Content="Cancel" Click="Cancel_Click"/>
</Window>
```

```csharp
// ConnectionDialog.xaml.cs
private void Connect_Click(object sender, RoutedEventArgs e)
{
    if (string.IsNullOrEmpty(ServerTextBox.Text))
    {
        MessageBox.Show("Please enter a server name.", "Error", 
            MessageBoxButton.OK, MessageBoxImage.Error);
        return;
    }
    
    try
    {
        // Connect...
        MessageBox.Show("Connected successfully!", "Success",
            MessageBoxButton.OK, MessageBoxImage.Information);
    }
    catch (Exception ex)
    {
        MessageBox.Show($"Connection failed: {ex.Message}", "Error",
            MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
```

### After (Localized)
```xml
<!-- ConnectionDialog.xaml -->
<Window Title="{loc:Translate Key=ui.dialogs.connection.title}" Height="600" Width="500">
    <Label Content="{loc:Translate Key=ui.dialogs.connection.server}"/>
    <TextBox x:Name="ServerTextBox"/>
    
    <Label Content="{loc:Translate Key=ui.dialogs.connection.port}"/>
    <TextBox x:Name="PortTextBox"/>
    
    <Label Content="{loc:Translate Key=ui.dialogs.connection.database}"/>
    <TextBox x:Name="DatabaseTextBox"/>
    
    <Button Content="{loc:Translate Key=ui.dialogs.connection.connect}" Click="Connect_Click"/>
    <Button Content="{loc:Translate Key=common.buttons.cancel}" Click="Cancel_Click"/>
</Window>
```

```csharp
// ConnectionDialog.xaml.cs
private readonly LocalizationService _localization;

public ConnectionDialog()
{
    InitializeComponent();
    _localization = ((App)Application.Current).LocalizationService;
}

private void Connect_Click(object sender, RoutedEventArgs e)
{
    if (string.IsNullOrEmpty(ServerTextBox.Text))
    {
        MessageBox.Show(
            _localization.Get("messages.errors.server_required"),
            _localization.Get("messages.errors.title"),
            MessageBoxButton.OK, MessageBoxImage.Error);
        return;
    }
    
    try
    {
        // Connect...
        MessageBox.Show(
            _localization.Get("messages.success.connection_successful", 
                new { database = DatabaseTextBox.Text }),
            _localization.Get("messages.success.title"),
            MessageBoxButton.OK, MessageBoxImage.Information);
    }
    catch (Exception ex)
    {
        MessageBox.Show(
            _localization.Get("messages.errors.connection_failed", 
                new { database = DatabaseTextBox.Text }),
            _localization.Get("messages.errors.title"),
            MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
```

---

## 📝 TRANSLATOR DOCUMENTATION

### For Translators
Provide `TRANSLATOR_GUIDE.md`:

```markdown
# Translation Guide for DbExplorer

## Getting Started
1. Copy `_template.json` to `{your-language-code}.json` (e.g., `fr-FR.json`)
2. Update the `language` section with your language info
3. Translate all text values (keep keys unchanged)
4. Test your translation in the application

## Important Notes
- **DO NOT** change keys, only translate values
- **PRESERVE** placeholders like `{database}`, `{timeout}`, `{count}`
- **MAINTAIN** line breaks `\n` for multi-line messages
- **KEEP** formatting like bold, icons (🗄️), etc.
- **TEST** for text overflow issues in dialogs

## Placeholders
Placeholders are replaced at runtime with actual values:
- `{database}` - Database name
- `{server}` - Server name
- `{timeout}` - Timeout value in seconds
- `{count}` - Number (rows, items, etc.)
- `{rows}` - Row count
- `{filename}` - File path
- `{error}` - Error message

## Example Translation

English (en-US.json):
```json
{
  "messages": {
    "errors": {
      "connection_failed": "Failed to connect to {database}.\n\nPlease check your connection settings and try again."
    }
  }
}
```

French (fr-FR.json):
```json
{
  "messages": {
    "errors": {
      "connection_failed": "Échec de la connexion à {database}.\n\nVeuillez vérifier vos paramètres de connexion et réessayer."
    }
  }
}
```

## Contact
If you have questions, contact: localization@example.com
```

---

## 🔗 INTEGRATION WITH METADATA ABSTRACTION

This localization system integrates with the metadata abstraction:

```json
// In Metadata/DB2/12.1/ui_features_config.json
{
  "provider": "DB2",
  "version": "12.1",
  "features": {
    "packages": {
      "enabled": true,
      "name_key": "ui.object_browser.categories.packages",
      "description_key": "ui.object_browser.tooltips.packages"
    }
  }
}
```

Now feature names are also localized!

---

**Status:** 📝 PLAN COMPLETE  
**Next Step:** Begin Phase 1 implementation (Infrastructure setup)  
**Estimated Effort:** 6 weeks for full localization  
**Priority:** HIGH (Enables international use)

