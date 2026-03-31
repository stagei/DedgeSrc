# Get-FunctionsFromPsm1 Module

Extracts and analyzes functions from PowerShell module files.

## Exported Functions

### Get-FunctionsFromPsm1
Extracts functions from PowerShell module files and handles dependencies.

```powershell
Get-FunctionsFromPsm1 [-ModulePaths <string[]>] [-OutputPath <string>]
```

#### Parameters
- `ModulePaths`: Array of paths to PowerShell module files to process
- `OutputPath`: Path where the combined output should be saved

#### Example
```powershell
Get-FunctionsFromPsm1 -ModulePaths @("C:\Modules\MyModule.psm1") -OutputPath "C:\Output\Combined.ps1"
```

This function:
- Analyzes module dependencies recursively
- Extracts function definitions
- Combines modules in correct dependency order
- Handles import statements
- Creates a single combined output file

## Internal Functions

The module uses several internal functions to perform its tasks:

- **Get-ImportStatementsRecursively**: Extracts Import-Module statements from a file and its dependencies.
- **Get-DependencyChain**: Builds a dependency chain for a module, ensuring dependencies are processed in the correct order.
- **Get-ModuleContent**: Extracts the content of a module file, removing Export-ModuleMember and Import-Module statements.

## Use Cases
- Creating standalone script files that include functions from multiple modules
- Generating initialization scripts for server setup
- Consolidating module functions for deployment in environments where module loading is restricted 