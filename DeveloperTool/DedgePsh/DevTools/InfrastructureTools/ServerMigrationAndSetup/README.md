# Server Task Generator

This tool automates the generation of server migration tasks for different server environments and configurations. It processes templates defined in `serverTemplates.json` to create standardized task lists for each server, supporting both local task files and Azure DevOps integration.

## Overview

The `ServerTaskGenerator.ps1` script takes server templates that define common task patterns and generates:

1. Server-specific task files with placeholder substitutions
2. Azure DevOps-compatible task definitions with proper field structures
3. Import scripts for loading tasks into Azure DevOps with proper hierarchical relationships

## Prerequisites

- PowerShell 5.1 or later
- For Azure DevOps import:
  - Azure CLI with DevOps extension (`az devops`) OR
  - Direct REST API access with a Personal Access Token

## How It Works

### Input: Server Templates

The script reads from `_MigrationPlan/serverTemplates.json`, which defines:

- Templates for different types of servers (e.g., db-init, soa-init)
- Lists of server instances for each template type
- Common tasks applicable to these servers
- Task dependencies and prerequisites

### Variables and Substitution

The templates support several variable substitutions:

- `<serverpart>` or `<serverPart>`: Replaced with the specific server part (e.g., "p-no1fkmprd")
- `<databasename>`: Replaced with database names from the `serverDatabases` mapping

Example for database name substitution:
```json
"serverDatabases": [
  {
    "serverName": "p-no1fkmprd-db",
    "databases": ["FKMPRD"]
  }
]
```

### Output Files

The script generates two types of output:

1. **Standard Task Files** (in `_MigrationPlan/Tasks/`):
   - One JSON file per server with all tasks for that server
   - Used for local task tracking and execution

2. **Azure DevOps Task Files** (in `_MigrationPlan/AzureDevOpsTasks/`):
   - ADO-specific JSON format with fields in the proper structure
   - Includes relationship information for dependencies
   - Import scripts for loading into Azure DevOps

## Azure DevOps Field Mapping

The task template fields are mapped to Azure DevOps fields as follows:

| Task Template Field | Azure DevOps Field Name |
|---------------------|-------------------------|
| taskname | System.Title |
| description | System.Description (first part) |
| comment | System.Description (added section) |
| prerequisiteComment | System.Description (added section) |
| default | System.Tags (as tag component) |
| prerequisiteTasks | Microsoft.VSTS.Common.AcceptanceCriteria |
| prerequisiteTasks | Work Item Relations (as dependencies) |

Additionally:
- Server information is stored in **System.Tags**
- The generated tasks are structured hierarchically (Epic > Feature > User Story)
- Task dependencies are represented as work item relationships

## Azure DevOps Hierarchy Model

The generated tasks are organized in Azure DevOps using a three-level hierarchy:

```
Epic (Migration Project)
├── Feature (Server 1)
│   ├── User Story (Task 1.1)
│   │   └── (Depends on) → User Story (Task 1.2) 
│   ├── User Story (Task 1.2)
│   └── User Story (Task 1.3)
│       └── (Depends on) → User Story from different server
├── Feature (Server 2)
│   ├── User Story (Task 2.1)
│   ├── User Story (Task 2.2)
│   │   └── (Depends on) → User Story (Task 2.1)
│   └── User Story (Task 2.3)
└── Feature (Server 3)
    └── ...
```

### Work Item Types and Relationships

1. **Epic**
   - Top-level container for the migration project
   - Provides overall tracking and reporting
   - Created once per import operation

2. **Feature**
   - One per server
   - Groups all tasks related to a single server
   - Title format: "Server Migration: [server-name]"
   - Child of the Epic (System.LinkTypes.Hierarchy-Reverse)

3. **User Story**
   - Individual tasks from templates
   - Contains detailed instructions
   - Child of the Feature (System.LinkTypes.Hierarchy-Reverse)
   - May have dependencies on other User Stories (Microsoft.VSTS.Common.Dependency-Reverse)

## Azure DevOps Integration

The generator creates two import scripts:

### 1. Import-TasksToAzureDevOps.ps1

Processes a single server file and imports it to Azure DevOps with a hierarchical structure:

- Epic (top level) for the overall migration project
- Feature for the specific server
- User Story for each individual task
- Task dependencies are preserved as relationships

Usage:
```powershell
.\Import-TasksToAzureDevOps.ps1 `
  -TaskFile "path\to\server.ado.json" `
  -IterationPath "YourProject\Sprint 1" `
  -AreaPath "YourProject\Infrastructure" `
  -EpicName "Server Migration Phase 1" `
  -AdditionalTags "Migration,Phase1,Priority1"
```

### 2. Import-AllTasksToAzureDevOps.ps1

Processes all server files in the directory, creating a single Epic with Features for each server:

```powershell
.\Import-AllTasksToAzureDevOps.ps1 `
  -TaskFilesDirectory "path\to\ado\files" `
  -IterationPath "YourProject\Sprint 1" `
  -AreaPath "YourProject\Infrastructure" `
  -EpicName "Server Migration Phase 1" `
  -AdditionalTags "Migration,Phase1,Priority1"
```

### Using an Existing Epic

You can link to an existing Epic by providing its ID:

```powershell
.\Import-AllTasksToAzureDevOps.ps1 `
  -TaskFilesDirectory "path\to\ado\files" `
  -ExistingEpicId 12345 `
  -AdditionalTags "Migration,Phase1,Priority1"
```

### Custom Tags

Both import scripts support the `-AdditionalTags` parameter, which allows you to specify a semicolon-separated list of tags to apply to all work items. These tags are added to:
- The Epic (if creating a new one)
- All Features (server groupings)
- All User Stories (individual tasks)

Example tag usage:
```
Migration;Phase1;Priority1;Team-Infrastructure
```

The tags are appended to any existing tags in the work items, making it easy to categorize and filter tasks in Azure DevOps.

## Running the Generator

To generate task files:

```powershell
cd DevTools\InfrastructureTools\ServerSetup
.\ServerTaskGenerator.ps1
```

The script will:
1. Read templates from `_MigrationPlan\serverTemplates.json`
2. Generate task files in `_MigrationPlan\Tasks\`
3. Generate ADO task files in `_MigrationPlan\AzureDevOpsTasks\`
4. Create import scripts for Azure DevOps

## serverTemplates.json Structure

Example template structure:

```json
[
  {
    "templateName": "prod-db-init",
    "servers": ["p-no1fkmprd-db", "p-no1inlprd-db"],
    "serverPart": ["p-no1fkmprd", "p-no1inlprd"],
    "serverDatabases": [
      {
        "serverName": "p-no1fkmprd-db",
        "databases": ["FKMPRD"]
      }
    ],
    "serverTasks": [
      {
        "taskname": "<serverpart>-db-InitServer",
        "description": "Initialize the <serverpart>-db server",
        "comment": "Run on <databasename> database",
        "default": false,
        "prerequisiteTasks": [],
        "prerequisiteComment": ""
      },
      {
        "taskname": "<serverpart>-db-VerifyDb2",
        "description": "Verify Db2 installation on <serverpart>-db",
        "comment": "For <databasename> database",
        "default": false,
        "prerequisiteTasks": ["<serverpart>-db-InitServer"],
        "prerequisiteComment": ""
      }
    ]
  }
]
```

## Example Workflow

1. Define your server templates in `serverTemplates.json`
2. Run `ServerTaskGenerator.ps1` to generate the task files
3. Import to Azure DevOps using one of the generated import scripts
4. Track task progress in Azure DevOps with the proper hierarchy

## Visual Representation of Azure DevOps Structure

When imported, your tasks will appear in Azure DevOps with the following structure:

```
Epic: "Server Migration"
├── Feature: "Server Migration: p-no1fkmprd-db"
│   ├── User Story: "p-no1fkmprd-db-InitServer"
│   ├── User Story: "p-no1fkmprd-db-VerifyDb2"
│   │   └── Dependency: "p-no1fkmprd-db-InitServer" (predecessor)
│   └── ...
├── Feature: "Server Migration: p-no1inlprd-db"
│   ├── User Story: "p-no1inlprd-db-InitServer"
│   ├── User Story: "p-no1inlprd-db-VerifyDb2"
│   │   └── Dependency: "p-no1inlprd-db-InitServer" (predecessor)
│   └── ...
└── ...
```

This hierarchical structure makes it easy to track the overall migration progress, manage tasks for specific servers, and ensure that prerequisite tasks are completed in the correct order. 