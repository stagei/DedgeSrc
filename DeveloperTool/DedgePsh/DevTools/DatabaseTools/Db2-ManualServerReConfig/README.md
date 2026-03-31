# Db2 Manual Server ReConfig - Enhanced Version

**Author:** Geir Helge Starholm, www.dEdge.no

## Overview

The enhanced `Db2-ManualServerReConfig.ps1` provides a comprehensive, menu-driven interface for executing Db2-Handler functions on WorkObjects. This tool significantly improves upon the original by:

- **Supporting 73+ functions** from Db2-Handler.psm1 that accept and return WorkObjects
- **Intelligent parameter handling** for secondary inputs
- **Organized by categories** for easier navigation
- **Dynamic menu generation** from metadata
- **Dual WorkObject management** (Primary and Federated databases simultaneously)

## Key Features

### 1. Category-Based Organization

Functions are organized into 11 logical categories:

- **Database Information & State** - View and check database status, configuration, and state
- **Database Schema & Objects** - Inspect tables, functions, schemas, and grants
- **Services & Cataloging** - Manage DB2 services, nodes, and catalog entries
- **Permissions & Security** - Configure database permissions, access groups, and security
- **Database Configuration & Setup** - Database creation, configuration, and initialization
- **Firewall & Network** - Manage firewall rules for DB2 instances
- **Federation** - Federation support, wrappers, servers, nicknames
- **Instance Management** - Start, stop, restart DB2 instances
- **Backup & Restore** - Backup and restore operations
- **Queries & Data Operations** - Execute queries and data operations
- **Special Functions** - Additional utility functions

### 2. Smart Parameter Handling

The script intelligently prompts for secondary parameters based on function requirements:

- **Switch Parameters** - Simple Yes/No prompts
- **String Parameters** - Free-text input with skip option
- **String Arrays** - Comma-separated lists
- **ValidateSet Parameters** - Restricted choice lists with timeout

### 3. WorkObject Target Selection

For each function execution, you can choose to apply it to:

- Primary Database only
- Federated Database only
- Both databases

### 4. Enhanced User Experience

- Clear visual headers and sections
- Current configuration always visible
- Color-coded output (Cyan for headers, Yellow for prompts, Green for success)
- Progress indicators and confirmations
- Error handling with graceful fallback

## Usage

### Basic Workflow

1. **Run the script** on a DB2 server:
   ```powershell
   .\Db2-ManualServerReConfig.ps1
   ```

2. **Select a database** (Option 1):
   - Choose from active DB2 databases on the current server
   - Script automatically loads Primary and Federated WorkObjects

3. **View/Export WorkObjects** (Option 2):
   - Export WorkObjects as JSON files
   - Opens in VS Code for inspection

4. **Select a category** (Options 3+):
   - Choose from 11 organized categories
   - View all available functions in that category

5. **Execute a function**:
   - Select function from the category
   - Provide any required secondary parameters
   - Choose target (Primary, Federated, or Both)
   - Function executes and updates WorkObjects

### Example: Adding Services to Service File

```
Main Menu > [4] Services & Cataloging > [1] Add Services to Service File
-> Prompt: Choose Services Method? [Legacy, PrimaryDb, FederatedDb, SslPort, CompleteRange]
-> Response: PrimaryDb
-> Prompt: Select target? [1] PrimaryDb [2] FederatedDb [3] Both
-> Response: 1
-> Execution: Function runs on Primary WorkObject
```

## Function Metadata Structure

The script uses a metadata-driven approach. Each function is defined with:

```powershell
@{
    Name = "Function-Name"
    Description = "User-friendly description"
    SecondaryParams = @{
        ParamName = @{
            Type = "Switch|String|StringArray|ValidateSet"
            Prompt = "User prompt?"
            Values = @("Value1", "Value2")  # For ValidateSet only
        }
    }
}
```

## Adding New Functions

To add a new function from Db2-Handler:

1. Locate the appropriate category in `Get-FunctionMetadata`
2. Add a new function entry with name, description, and parameters
3. The menu system automatically includes it

Example:

```powershell
@{
    Category = "Database Information & State"
    Functions = @(
        # ... existing functions ...
        @{
            Name = "Get-NewFunction"
            Description = "My New Function"
            SecondaryParams = @{
                MyParam = @{
                    Type = "String"
                    Prompt = "Enter value?"
                }
            }
        }
    )
}
```

## Improvements Over Original Version

### Original Script Issues:
- Hardcoded menu with only 12 functions
- Repetitive switch-case blocks
- Manual handling of Primary vs Federated selection
- Difficult to add new functions
- Mixed responsibility (UI + execution logic)

### Enhanced Version Advantages:
- **73+ functions** available (vs 12)
- **Metadata-driven** - easy to extend
- **DRY principle** - no code duplication
- **Separation of concerns** - UI, parameter handling, and execution are separate
- **Type-safe parameter handling** - proper support for Switch, String, Arrays, ValidateSet
- **Better error handling** - graceful fallback and logging
- **Improved UX** - clear categories, better navigation, visual feedback

## Technical Details

### Key Components

1. **Get-FunctionMetadata** - Defines all available functions and their parameters
2. **Show-MenuHeader** - Displays formatted section headers
3. **Show-CurrentConfig** - Shows current database and WorkObject state
4. **Get-SecondaryParameters** - Prompts user for function-specific parameters
5. **Invoke-WorkObjectFunction** - Executes function with proper parameter splatting
6. **Select-WorkObjectTarget** - Determines which WorkObject(s) to use

### Design Patterns

- **Metadata-Driven Configuration** - All functions defined declaratively
- **Strategy Pattern** - Different parameter types handled by type-specific strategies
- **Command Pattern** - Functions invoked dynamically with parameter splatting
- **Separation of Concerns** - UI, business logic, and execution cleanly separated

## Requirements

- PowerShell 5.1 or later
- Must run on a DB2 server
- Required modules:
  - GlobalFunctions
  - Db2-Handler

## Troubleshooting

### "This script must be run on a DB server"
- Ensure you're running on a machine with DB2 installed
- Check that `Test-IsDb2Server` returns true

### WorkObjects not loading
- Verify database exists in `Get-DatabasesV2Json`
- Check that database is active and Provider is "DB2"
- Ensure ServerName matches `$env:COMPUTERNAME`

### Function execution errors
- Check log files in `C:\opt\data\AllPwshLog`
- Verify WorkObject has required properties
- Review Db2-Handler function requirements

## Future Enhancements

Potential improvements:

- [ ] Search/filter functions by name
- [ ] Favorites/recent functions list
- [ ] Batch execution of multiple functions
- [ ] Save/load WorkObject snapshots
- [ ] Function execution history
- [ ] Parameter validation before execution
- [ ] WhatIf mode for dangerous operations
- [ ] Export execution report

## Version History

- **v2.0** (Current) - Complete rewrite with metadata-driven architecture supporting 73+ functions
- **v1.0** - Original hardcoded version with 12 functions

## See Also

- `Db2-Handler.psm1` - Source module with all available functions
- `GlobalFunctions.psm1` - Shared utility functions
- `Get-DatabasesV2Json` - Database configuration source

---

For questions or improvements, contact: Geir Helge Starholm, www.dEdge.no
