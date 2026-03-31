# Azure DevOps Template Generator

This tool automates the generation of server migration tasks for different server environments and configurations. It processes templates defined in Templates\serverTemplates.json to create standardized task lists for each server, supporting both local task files and Azure DevOps integration.

## Directory Structure

- Templates\: Contains template definition files
  - serverTemplates.json: Main template definition file

- Output\: Contains all generated files
  - JsonTasks\: Standard JSON task files for each server
  - AzureDevOpsTasks\: Azure DevOps-compatible task files and import scripts

## How to Use

1. Create or modify templates in the Templates\serverTemplates.json file
2. Run Azure-DevopsTemplateGenerator.ps1 to generate tasks
3. Use the generated scripts in Output\AzureDevOpsTasks\ to import tasks into Azure DevOps

### Import to Azure DevOps

For single server import:
`powershell
cd Output\AzureDevOpsTasks
.\Import-TasksToAzureDevOps.ps1 -TaskFile "p-no1fkmprd-db.ado.json" -IterationPath "YourProject\Sprint 1" -AreaPath "YourProject\Infrastructure"
`

For multi-server import:
`powershell
cd Output\AzureDevOpsTasks
.\Import-AllTasksToAzureDevOps.ps1 -TaskFilesDirectory ".\Output\JsonTasks" -IterationPath "YourProject\Sprint 1" -AreaPath "YourProject\Infrastructure"
`

## Task Hierarchy in Azure DevOps

The generated tasks are organized in Azure DevOps using a three-level hierarchy:

- Epic (Migration Project)
  - Feature (Server)
    - User Story (Task)
      - Task dependencies maintained as relationships

This hierarchical structure makes it easy to track migration progress for multiple servers.
