# Azure DevOps Work Item Management Script

A PowerShell script for creating and managing work items in Azure DevOps using Azure CLI. This script supports creating Epics, User Stories, Tasks, Sub-tasks, and Bugs either through a JSON configuration file or direct command-line parameters.

## Prerequisites

Before using this script, ensure you have the following installed and configured:

1. **PowerShell 5.1 or higher**
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. **Azure CLI**
   - Download and install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
   - Verify installation:
     ```powershell
     az --version
     ```

3. **Azure DevOps Extension for Azure CLI**
   - The script will automatically install this if missing
   - Or manually install:
     ```powershell
     az extension add --name azure-devops
     ```

4. **Authentication**
   ```powershell
   az login
   az devops login
   ```

## Installation

1. Clone or download the repository containing the script files:
   - `Create-WorkItems.ps1` - Main script
   - `workitems-template.json` - Template for JSON configuration

2. Ensure the script has execution permissions:
   ```powershell
   Unblock-File -Path .\Create-WorkItems.ps1
   ```

## Usage

The script supports two modes of operation:

### 1. JSON File Mode

Use this mode to create multiple work items with hierarchical relationships from a JSON configuration file.

```powershell
.\Create-WorkItems.ps1 `
    -ConfigFile "workitems.json" `
    -Organization "https://dev.azure.com/your-org" `
    -Project "YourProject"
```

#### JSON Structure
```json
{
    "epics": [
        {
            "title": "Epic Title",
            "description": "Epic Description",
            "stories": [
                {
                    "title": "Story Title",
                    "description": "Story Description",
                    "tasks": [
                        {
                            "title": "Task Title",
                            "description": "Task Description",
                            "subtasks": [
                                {
                                    "title": "Subtask Title",
                                    "description": "Subtask Description"
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    ]
}
```

### 2. Direct Creation Mode

Use this mode to create individual work items or link them to existing parents.

```powershell
.\Create-WorkItems.ps1 `
    -Type "Task" `
    -Title "New Task" `
    -Description "Task Description" `
    -ParentId 123 `
    -Organization "https://dev.azure.com/your-org" `
    -Project "YourProject"
```

#### Parameters

- `-Type`: Work item type ('Epic', 'User Story', 'Task', 'Bug')
- `-Title`: Title of the work item
- `-Description`: Description of the work item
- `-ParentId`: (Optional) ID of the parent work item
- `-Organization`: Azure DevOps organization URL
- `-Project`: Azure DevOps project name

## Work Item Type Hierarchy

The script supports the following work item hierarchy:

```
Epic
└── User Story
    └── Task
        └── Sub-task
```

Bugs can be linked to any level in the hierarchy.

## Error Handling

The script includes comprehensive error handling:

- Validates Azure CLI installation and extensions
- Checks for required parameters
- Validates JSON structure in file mode
- Provides detailed error messages for failed operations
- Ensures proper authentication and permissions

## Examples

1. **Create an Epic with Stories from JSON**
   ```powershell
   .\Create-WorkItems.ps1 -ConfigFile "epics.json" -Organization "https://dev.azure.com/contoso" -Project "MyProject"
   ```

2. **Create a Task under an existing User Story**
   ```powershell
   .\Create-WorkItems.ps1 -Type "Task" -Title "Implement Login" -Description "Create login form" -ParentId 456 -Organization "https://dev.azure.com/contoso" -Project "MyProject"
   ```

3. **Create a Bug**
   ```powershell
   .\Create-WorkItems.ps1 -Type "Bug" -Title "Login Error" -Description "Login fails with 500 error" -Organization "https://dev.azure.com/contoso" -Project "MyProject"
   ```

## Troubleshooting

1. **Authentication Issues**
   - Ensure you're logged in to Azure CLI
   - Verify organization and project access
   - Check your permissions in Azure DevOps

2. **JSON File Issues**
   - Validate JSON syntax
   - Ensure all required fields are present
   - Check file encoding (should be UTF-8)

3. **Azure CLI Issues**
   - Verify Azure CLI installation
   - Update Azure CLI to latest version
   - Check Azure DevOps extension installation

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 