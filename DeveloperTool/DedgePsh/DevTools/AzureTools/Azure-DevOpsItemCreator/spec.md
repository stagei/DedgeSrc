# Azure DevOps Work Item Management Script Specification

## Overview
A PowerShell script that utilizes Azure CLI to create and manage work items in Azure DevOps. The script will support creating various work item types including Epics, User Stories, Tasks, Sub-tasks, and Bugs.

## Core Functionality

### 1. JSON File Processing
- Read work items from a JSON configuration file
- Support hierarchical structure of work items
- Validate input data before creation

### 2. Work Item Types Support
- Epic (top level)
- User Story (can be child of Epic)
- Task (can be child of User Story)
- Sub-task (can be child of Task)
- Bug (can be linked to any level)

### 3. Command Line Interface
Two primary modes of operation:

1. **JSON File Mode**
   ```powershell
   ./Create-WorkItems.ps1 -ConfigFile "workitems.json"
   ```

2. **Direct Creation Mode**
   ```powershell
   ./Create-WorkItems.ps1 -ParentId 123 -Type "Task" -Title "New Task" -Description "Task Description"
   ```

### 4. JSON Structure Example
```json
{
  "epics": [
    {
      "title": "New Feature Initiative",
      "description": "Major feature development",
      "stories": [
        {
          "title": "User Authentication",
          "description": "Implement OAuth2",
          "tasks": [
            {
              "title": "Setup OAuth Provider",
              "description": "Configure OAuth settings",
              "subtasks": [
                {
                  "title": "Create OAuth App",
                  "description": "Register application in provider"
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

## Prerequisites
- Azure CLI installed
- Azure DevOps extension for Azure CLI
- PowerShell 5.1 or higher
- Proper Azure DevOps permissions
- Authentication configured

## Error Handling
- Validate JSON structure
- Check for required fields
- Handle API rate limiting
- Proper error messages for failed operations
- Logging of operations

## Output
- Console feedback for each created item
- Optional JSON output of created items with IDs
- Error reporting
- Creation summary

## Security Considerations
- Use of Azure CLI authentication
- No hardcoded credentials
- Proper permission checking
- Secure handling of configuration file

## Future Enhancements
- Support for custom fields
- Batch operations
- Update existing items
- Delete operations
- Query existing items
- Support for additional work item types
- Custom state transitions 