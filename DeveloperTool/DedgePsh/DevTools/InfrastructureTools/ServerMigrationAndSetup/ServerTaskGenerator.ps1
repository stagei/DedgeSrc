Import-Module GlobalFunctions -Force

# File is .\serverTemplates.json
$migrationPlanPath = Join-Path $env:OptPath "src\DedgePsh\DevTools\InfrastructureTools\ServerSetup\_MigrationPlan"
$defaultGeneratedTasksPath = Join-Path $migrationPlanPath "Tasks"
$defaultGeneratedADOTasksPath = Join-Path $migrationPlanPath "AzureDevOpsTasks"

# Create output directories if they don't exist
if (-not (Test-Path $defaultGeneratedTasksPath)) {
    New-Item -ItemType Directory -Path $defaultGeneratedTasksPath
}
if (-not (Test-Path $defaultGeneratedADOTasksPath)) {
    New-Item -ItemType Directory -Path $defaultGeneratedADOTasksPath
}

$serverTemplates = Get-Content -Path $migrationPlanPath\serverTemplates.json -Raw | ConvertFrom-Json

# $serversInfos = $(Get-ComputerInfoJson) | Where-Object { $_.Name -match "(p-no|t-no1)(?:[a-z]{3}|[a-z]{6})(-web|-db|-soa|-app)" -and $_.Platform -eq "Azure" -and $_.Name -notmatch "01$" -and $_.Name -notmatch "02$" }

foreach ($serverTemplate in $serverTemplates) {
    Write-Host "Generating tasks for template: $($serverTemplate.templateName)"

    # Check if the template has a serverDatabases property
    $hasServerDatabases = $null -ne $serverTemplate.PSObject.Properties['serverDatabases'] -and $serverTemplate.serverDatabases.Length -gt 0

    # Loop through servers in the template
    for ($i = 0; $i -lt $serverTemplate.servers.Length; $i++) {
        $server = $serverTemplate.servers[$i]
        $serverPart = $serverTemplate.serverPart[$i]

        Write-Host "  Processing server: $server (serverPart: $serverPart)"

        # Create a new task list for this specific server
        $serverTasks = @()
        $adoTasks = @()
        $adoRelationships = @()

        # Find the database configuration for this server if available
        $databaseConfig = $null
        if ($hasServerDatabases) {
            $databaseConfig = $serverTemplate.serverDatabases | Where-Object { $_.serverName -eq "$serverPart-db" } | Select-Object -First 1

            if ($databaseConfig) {
                Write-Host "    Found database configuration for server. Associated databases: $($databaseConfig.databases -join ', ')"
            }
        }

        # Process each task in the template
        foreach ($task in $serverTemplate.serverTasks) {
            # Check if the task contains a <databasename> placeholder
            $containsDatabasePlaceholder = $task.taskname -match '<databasename>' -or
                                            $task.description -match '<databasename>' -or
                                            $task.comment -match '<databasename>' -or
                                            ($task.prerequisiteTasks -and ($task.prerequisiteTasks -join ' ') -match '<databasename>') -or
                                            $task.prerequisiteComment -match '<databasename>'

            # If the task contains database placeholders and we have database config
            if ($containsDatabasePlaceholder -and $databaseConfig -and $databaseConfig.databases.Length -gt 0) {
                # Create a task for each database
                foreach ($database in $databaseConfig.databases) {
                    # Create a deep copy of the task
                    $newTask = $task | ConvertTo-Json -Depth 20 | ConvertFrom-Json

                    # Replace all occurrences of placeholders
                    $newTask.taskname = $newTask.taskname -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart -replace '<databasename>', $database
                    $newTask.description = $newTask.description -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart -replace '<databasename>', $database
                    $newTask.comment = $newTask.comment -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart -replace '<databasename>', $database

                    # Replace in prerequisite tasks
                    if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
                        for ($j = 0; $j -lt $newTask.prerequisiteTasks.Count; $j++) {
                            $newTask.prerequisiteTasks[$j] = $newTask.prerequisiteTasks[$j] -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart -replace '<databasename>', $database
                        }
                    }

                    $newTask.prerequisiteComment = $newTask.prerequisiteComment -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart -replace '<databasename>', $database

                    # Add the task to the server's task list
                    $serverTasks += $newTask

                    # Create ADO task format with database info
                    $adoTask = @{
                        op = "add"
                        path = "/fields/System.Title"
                        value = $newTask.taskname
                    }

                    $descriptionWithComment = ""
                    if (-not [string]::IsNullOrWhiteSpace($newTask.description)) {
                        $descriptionWithComment = $newTask.description
                    }
                    if (-not [string]::IsNullOrWhiteSpace($newTask.comment)) {
                        if ($descriptionWithComment -ne "") {
                            $descriptionWithComment += "`n`n"
                        }
                        $descriptionWithComment += "Comment: $($newTask.comment)"
                    }
                    if (-not [string]::IsNullOrWhiteSpace($newTask.prerequisiteComment)) {
                        if ($descriptionWithComment -ne "") {
                            $descriptionWithComment += "`n`n"
                        }
                        $descriptionWithComment += "Prerequisites Note: $($newTask.prerequisiteComment)"
                    }

                    $adoFields = @(
                        $adoTask,
                        @{
                            op = "add"
                            path = "/fields/System.Description"
                            value = $descriptionWithComment
                        },
                        @{
                            op = "add"
                            path = "/fields/System.Tags"
                            value = "Server=$server;ServerPart=$serverPart;Database=$database;Template=$($serverTemplate.templateName);default=$($newTask.default)"
                        }
                    )

                    # Still add prerequisites as a text field for reference
                    if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
                        $prereqList = $newTask.prerequisiteTasks -join "; "
                        $adoFields += @{
                            op = "add"
                            path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
                            value = "Prerequisites: $prereqList"
                        }
                    }

                    $taskId = "$($newTask.taskname)_$database"

                    $adoTasks += @{
                        id = $taskId
                        taskname = $newTask.taskname
                        fields = $adoFields
                        server = $server  # Add server info to help with hierarchy
                    }

                    # Store relationship info for later processing
                    if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
                        foreach ($prereq in $newTask.prerequisiteTasks) {
                            $prereqTaskId = "$($prereq)_$database"
                            $adoRelationships += @{
                                sourceId = $taskId
                                targetId = $prereqTaskId
                                relationshipType = "Microsoft.VSTS.Common.Dependency-Reverse"
                            }
                        }
                    }
                }
            } else {
                # No database placeholders or no database config, process task normally
                $newTask = $task | ConvertTo-Json -Depth 20 | ConvertFrom-Json

                # Replace all occurrences of <serverpart> or <serverPart> with the actual server part
                $newTask.taskname = $newTask.taskname -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart
                $newTask.description = $newTask.description -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart
                $newTask.comment = $newTask.comment -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart

                # Replace in prerequisite tasks
                if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
                    for ($j = 0; $j -lt $newTask.prerequisiteTasks.Count; $j++) {
                        $newTask.prerequisiteTasks[$j] = $newTask.prerequisiteTasks[$j] -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart
                    }
                }

                $newTask.prerequisiteComment = $newTask.prerequisiteComment -replace '<serverpart>', $serverPart -replace '<serverPart>', $serverPart

                # Add the task to the server's task list
                $serverTasks += $newTask

                # Create ADO task format (optimized for Azure DevOps REST API)
                $adoTask = @{
                    op = "add"
                    path = "/fields/System.Title"
                    value = $newTask.taskname
                }

                $descriptionWithComment = ""
                if (-not [string]::IsNullOrWhiteSpace($newTask.description)) {
                    $descriptionWithComment = $newTask.description
                }
                if (-not [string]::IsNullOrWhiteSpace($newTask.comment)) {
                    if ($descriptionWithComment -ne "") {
                        $descriptionWithComment += "`n`n"
                    }
                    $descriptionWithComment += "Comment: $($newTask.comment)"
                }
                if (-not [string]::IsNullOrWhiteSpace($newTask.prerequisiteComment)) {
                    if ($descriptionWithComment -ne "") {
                        $descriptionWithComment += "`n`n"
                    }
                    $descriptionWithComment += "Prerequisites Note: $($newTask.prerequisiteComment)"
                }

                $adoFields = @(
                    $adoTask,
                    @{
                        op = "add"
                        path = "/fields/System.Description"
                        value = $descriptionWithComment
                    },
                    @{
                        op = "add"
                        path = "/fields/System.Tags"
                        value = "Server=$server;ServerPart=$serverPart;Template=$($serverTemplate.templateName);default=$($newTask.default)"
                    }
                )

                # Still add prerequisites as a text field for reference
                if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
                    $prereqList = $newTask.prerequisiteTasks -join "; "
                    $adoFields += @{
                        op = "add"
                        path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
                        value = "Prerequisites: $prereqList"
                    }
                }

                $taskId = $newTask.taskname

                $adoTasks += @{
                    id = $taskId
                    taskname = $newTask.taskname
                    fields = $adoFields
                    server = $server  # Add server info to help with hierarchy
                }

                # Store relationship info for later processing
                if ($newTask.prerequisiteTasks -and $newTask.prerequisiteTasks.Count -gt 0) {
                    foreach ($prereq in $newTask.prerequisiteTasks) {
                        $adoRelationships += @{
                            sourceId = $taskId
                            targetId = $prereq
                            relationshipType = "Microsoft.VSTS.Common.Dependency-Reverse"
                        }
                    }
                }
            }
        }

        # Create a new object to hold the tasks for this server
        $serverTaskObject = @{
            server = $server
            serverPart = $serverPart
            tasks = $serverTasks
        }

        # Save to a JSON file named after the server
        $outputPath = Join-Path $defaultGeneratedTasksPath "$server.json"
        $serverTaskObject | ConvertTo-Json -Depth 20 | Set-Content -Path $outputPath

        # Save ADO tasks to a separate JSON file with support for relationships
        $adoOutputPath = Join-Path $defaultGeneratedADOTasksPath "$server.ado.json"
        $adoTaskObject = @{
            server = $server
            serverPart = $serverPart
            templateName = $serverTemplate.templateName
            tasks = $adoTasks
            relationships = $adoRelationships
        }
        $adoTaskObject | ConvertTo-Json -Depth 20 | Set-Content -Path $adoOutputPath

        Write-Host "  Generated task file: $outputPath"
        Write-Host "  Generated Azure DevOps task file: $adoOutputPath"
    }
}

Write-Host "Task generation complete. Files are in: $defaultGeneratedTasksPath"
Write-Host "Azure DevOps task files are in: $defaultGeneratedADOTasksPath"

# Add a sample script for importing tasks to Azure DevOps with relationships
$adoImportScriptPath = Join-Path $defaultGeneratedADOTasksPath "Import-TasksToAzureDevOps.ps1"
$adoImportScript = @'
# This script imports tasks with dependencies to Azure DevOps in a hierarchical structure:
# Epic > Feature (Server) > User Story (Task)
# Requires the Azure DevOps CLI (az devops) to be installed and authenticated

# Parameters
param (
    [Parameter(Mandatory=$true)]
    [string]$TaskFile,

    [Parameter(Mandatory=$false)]
    [string]$TeamName = "",

    [Parameter(Mandatory=$false)]
    [string]$IterationPath = "",

    [Parameter(Mandatory=$false)]
    [string]$AreaPath = "",

    [Parameter(Mandatory=$false)]
    [string]$EpicName = "Server Migration",

    [Parameter(Mandatory=$false)]
    [int]$ExistingEpicId = 0,

    [Parameter(Mandatory=$false)]
    [string]$AdditionalTags = ""
)
Import-Module GlobalFunctions -Force

# Get Azure DevOps settings from GlobalFunctions
$OrganizationName = Get-AzureDevOpsOrganization
$ProjectName = Get-AzureDevOpsProject
$Pat = Get-AzureDevOpsPat

$OrganizationUrl = "https://dev.azure.com/$OrganizationName"

# Check if az devops is installed
try {
    az --version | Out-Null
} catch {
    Write-Error "Azure DevOps CLI not found. Please install the Azure CLI and the Azure DevOps extension."
    exit 1
}

# If not specified, prompt for epic ID or name and additional tags
if ($ExistingEpicId -eq 0) {
    $epicPrompt = Read-Host "Enter existing Epic ID (leave blank to create a new Epic with name: $EpicName)"
    if (-not [string]::IsNullOrWhiteSpace($epicPrompt)) {
        if ([int]::TryParse($epicPrompt, [ref]$ExistingEpicId)) {
            Write-Host "Using existing Epic with ID: $ExistingEpicId"
        } else {
            $EpicName = $epicPrompt
            Write-Host "Will create a new Epic with name: $EpicName"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AdditionalTags)) {
    $AdditionalTags = Read-Host "Enter additional tags to apply to all work items (comma-separated, e.g. 'Migration,Phase1,Priority1')"
}

# Authenticate with Azure DevOps
Write-Host "Setting up Azure DevOps CLI authentication..."
$env:AZURE_DEVOPS_EXT_PAT = $Pat
az devops configure --defaults organization=$OrganizationUrl project=$ProjectName --use-git-aliases true

# Read the task file
$taskData = Get-Content -Path $TaskFile -Raw | ConvertFrom-Json

Write-Host "Importing tasks for server: $($taskData.server) ($($taskData.serverPart))"

# Create a mapping table to store created work item IDs
$workItemIds = @{}

# Step 1: Create or use an Epic
$epicId = $ExistingEpicId
if ($epicId -eq 0) {
    Write-Host "Creating new Epic: $EpicName"

    $epicFields = @(
        @{
            op = "add"
            path = "/fields/System.Title"
            value = $EpicName
        },
        @{
            op = "add"
            path = "/fields/System.Description"
            value = "Epic for server migration tasks across multiple environments"
        }
    )

    # Add tags to Epic if specified
    if (-not [string]::IsNullOrWhiteSpace($AdditionalTags)) {
        $epicFields += @{
            op = "add"
            path = "/fields/System.Tags"
            value = $AdditionalTags
        }
    }

    if (-not [string]::IsNullOrEmpty($AreaPath)) {
        $epicFields += @{
            op = "add"
            path = "/fields/System.AreaPath"
            value = $AreaPath
        }
    }

    if (-not [string]::IsNullOrEmpty($IterationPath)) {
        $epicFields += @{
            op = "add"
            path = "/fields/System.IterationPath"
            value = $IterationPath
        }
    }

    $epicFieldsJson = $epicFields | ConvertTo-Json -Depth 10
    $epicResponse = az devops work item create --type "Epic" --fields $epicFieldsJson --output json | ConvertFrom-Json
    $epicId = $epicResponse.id

    Write-Host "Created Epic with ID: $epicId"
} else {
    Write-Host "Using existing Epic with ID: $epicId"
}

# Step 2: Create a Feature for this server
Write-Host "Creating Feature for server: $($taskData.server)"

# Base feature tags
$featureTags = "Server=$($taskData.server);ServerPart=$($taskData.serverPart);Template=$($taskData.templateName)"

# Add additional tags if specified
if (-not [string]::IsNullOrWhiteSpace($AdditionalTags)) {
    $featureTags += ";$AdditionalTags"
}

$featureFields = @(
    @{
        op = "add"
        path = "/fields/System.Title"
        value = "Server Migration: $($taskData.server)"
    },
    @{
        op = "add"
        path = "/fields/System.Description"
        value = "Migration tasks for server $($taskData.server) ($($taskData.serverPart))"
    },
    @{
        op = "add"
        path = "/fields/System.Tags"
        value = $featureTags
    }
)

if (-not [string]::IsNullOrEmpty($AreaPath)) {
    $featureFields += @{
        op = "add"
        path = "/fields/System.AreaPath"
        value = $AreaPath
    }
}

if (-not [string]::IsNullOrEmpty($IterationPath)) {
    $featureFields += @{
        op = "add"
        path = "/fields/System.IterationPath"
        value = $IterationPath
    }
}

$featureFieldsJson = $featureFields | ConvertTo-Json -Depth 10
$featureResponse = az devops work item create --type "Feature" --fields $featureFieldsJson --output json | ConvertFrom-Json
$featureId = $featureResponse.id

Write-Host "Created Feature with ID: $featureId"

# Link Feature to Epic
$epicLinkJson = @"
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "System.LinkTypes.Hierarchy-Reverse",
      "url": "${OrganizationUrl}/_apis/wit/workItems/$epicId"
    }
  }
]
"@

az devops work item update --id $featureId --json-patch $epicLinkJson
Write-Host "Linked Feature to Epic"

# Step 3: Create User Stories for each task
foreach ($task in $taskData.tasks) {
    Write-Host "Creating User Story: $($task.taskname)"

    # Prepare fields with iteration and area path if provided
    $storyFields = $task.fields

    # Append additional tags if specified
    if (-not [string]::IsNullOrWhiteSpace($AdditionalTags)) {
        # Find the System.Tags field
        $tagsField = $storyFields | Where-Object { $_.path -eq "/fields/System.Tags" } | Select-Object -First 1

        if ($tagsField) {
            # Append additional tags to existing tags
            $tagsField.value += ";$AdditionalTags"
        } else {
            # Add tags field if it doesn't exist
            $storyFields += @{
                op = "add"
                path = "/fields/System.Tags"
                value = $AdditionalTags
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($IterationPath)) {
        $storyFields += @{
            op = "add"
            path = "/fields/System.IterationPath"
            value = $IterationPath
        }
    }

    if (-not [string]::IsNullOrEmpty($AreaPath)) {
        $storyFields += @{
            op = "add"
            path = "/fields/System.AreaPath"
            value = $AreaPath
        }
    }

    # Create User Story
    $storyFieldsJson = $storyFields | ConvertTo-Json -Depth 10
    $storyResponse = az devops work item create --type "User Story" --fields $storyFieldsJson --output json | ConvertFrom-Json

    # Store the created work item ID
    $workItemIds[$task.id] = $storyResponse.id
    Write-Host "Created User Story with ID: $($storyResponse.id)"

    # Link User Story to Feature
    $featureLinkJson = @"
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "System.LinkTypes.Hierarchy-Reverse",
      "url": "${OrganizationUrl}/_apis/wit/workItems/$featureId"
    }
  }
]
"@

    az devops work item update --id $storyResponse.id --json-patch $featureLinkJson
    Write-Host "Linked User Story to Feature"
}

# Step 4: Create relationships between User Stories
foreach ($relationship in $taskData.relationships) {
    $sourceId = $workItemIds[$relationship.sourceId]
    $targetId = $workItemIds[$relationship.targetId]

    if ($sourceId -and $targetId) {
        Write-Host "Creating relationship: $($relationship.sourceId) -> $($relationship.targetId)"

        # Create the relationship
        $relationshipJson = @"
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "$($relationship.relationshipType)",
      "url": "${OrganizationUrl}/_apis/wit/workItems/$targetId"
    }
  }
]
"@

        az devops work item update --id $sourceId --json-patch $relationshipJson
        Write-Host "Created relationship between work items $sourceId and $targetId"
    } else {
        Write-Warning "Could not create relationship, one of the tasks was not created successfully"
    }
}

Write-Host "Import complete!"
Write-Host "Epic ID: $epicId"
Write-Host "Feature ID for $($taskData.server): $featureId"
'@

Set-Content -Path $adoImportScriptPath -Value $adoImportScript

# Create a consolidated import script that can process multiple server files
$adoMultiImportScriptPath = Join-Path $defaultGeneratedADOTasksPath "Import-AllTasksToAzureDevOps.ps1"
$adoMultiImportScript = @'
# This script imports tasks for multiple servers to Azure DevOps
# Creates a single Epic with Features for each server and User Stories for tasks

param (
    [Parameter(Mandatory=$true)]
    [string]$TaskFilesDirectory = ".\Output\JsonTasks",

    [Parameter(Mandatory=$false)]
    [string]$IterationPath = "",

    [Parameter(Mandatory=$false)]
    [string]$AreaPath = "",

    [Parameter(Mandatory=$false)]
    [string]$EpicName = "Server Migration",

    [Parameter(Mandatory=$false)]
    [int]$ExistingEpicId = 0,

    [Parameter(Mandatory=$false)]
    [string]$AdditionalTags = ""
)
Import-Module GlobalFunctions -Force

# Get Azure DevOps settings from GlobalFunctions
$OrganizationName = Get-AzureDevOpsOrganization
$ProjectName = Get-AzureDevOpsProject
$Pat = Get-AzureDevOpsPat

$OrganizationUrl = "https://dev.azure.com/$OrganizationName"

# Check if az devops is installed
try {
    az --version | Out-Null
} catch {
    Write-Error "Azure DevOps CLI not found. Please install the Azure CLI and the Azure DevOps extension."
    exit 1
}

# If not specified, prompt for epic ID or name and additional tags
if ($ExistingEpicId -eq 0) {
    $epicPrompt = Read-Host "Enter existing Epic ID (leave blank to create a new Epic with name: $EpicName)"
    if (-not [string]::IsNullOrWhiteSpace($epicPrompt)) {
        if ([int]::TryParse($epicPrompt, [ref]$ExistingEpicId)) {
            Write-Host "Using existing Epic with ID: $ExistingEpicId"
        } else {
            $EpicName = $epicPrompt
            Write-Host "Will create a new Epic with name: $EpicName"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AdditionalTags)) {
    $AdditionalTags = Read-Host "Enter additional tags to apply to all work items (comma-separated, e.g. 'Migration,Phase1,Priority1')"
}

# Authenticate with Azure DevOps
Write-Host "Setting up Azure DevOps CLI authentication..."
$env:AZURE_DEVOPS_EXT_PAT = $Pat
az devops configure --defaults organization=$OrganizationUrl project=$ProjectName --use-git-aliases true

# Step 1: Create or use an Epic
$epicId = $ExistingEpicId
if ($epicId -eq 0) {
    Write-Host "Creating new Epic: $EpicName"

    $epicFields = @(
        @{
            op = "add"
            path = "/fields/System.Title"
            value = $EpicName
        },
        @{
            op = "add"
            path = "/fields/System.Description"
            value = "Epic for server migration tasks across multiple environments"
        }
    )

    # Add tags to Epic if specified
    if (-not [string]::IsNullOrWhiteSpace($AdditionalTags)) {
        $epicFields += @{
            op = "add"
            path = "/fields/System.Tags"
            value = $AdditionalTags
        }
    }

    if (-not [string]::IsNullOrEmpty($AreaPath)) {
        $epicFields += @{
            op = "add"
            path = "/fields/System.AreaPath"
            value = $AreaPath
        }
    }

    if (-not [string]::IsNullOrEmpty($IterationPath)) {
        $epicFields += @{
            op = "add"
            path = "/fields/System.IterationPath"
            value = $IterationPath
        }
    }

    $epicFieldsJson = $epicFields | ConvertTo-Json -Depth 10
    $epicResponse = az boards work-item create --type "Epic" --fields $epicFieldsJson --output json | ConvertFrom-Json
    $epicId = $epicResponse.id

    Write-Host "Created Epic with ID: $epicId"
} else {
    Write-Host "Using existing Epic with ID: $epicId"
}

# Get all ADO task files
$taskFiles = Get-ChildItem -Path $TaskFilesDirectory -Filter "*.ado.json"

foreach ($taskFile in $taskFiles) {
    # Read the task file
    $taskData = Get-Content -Path $taskFile.FullName -Raw | ConvertFrom-Json

    Write-Host "Processing server: $($taskData.server) ($($taskData.serverPart))"

    # Create a Feature for this server
    Write-Host "Creating Feature for server: $($taskData.server)"

    # Base feature tags
    $featureTags = "Server=$($taskData.server);ServerPart=$($taskData.serverPart);Template=$($taskData.templateName)"

    # Add additional tags if specified
    if (-not [string]::IsNullOrWhiteSpace($AdditionalTags)) {
        $featureTags += ";$AdditionalTags"
    }

    $featureFields = @(
        @{
            op = "add"
            path = "/fields/System.Title"
            value = "Server Migration: $($taskData.server)"
        },
        @{
            op = "add"
            path = "/fields/System.Description"
            value = "Migration tasks for server $($taskData.server) ($($taskData.serverPart))"
        },
        @{
            op = "add"
            path = "/fields/System.Tags"
            value = $featureTags
        }
    )

    if (-not [string]::IsNullOrEmpty($AreaPath)) {
        $featureFields += @{
            op = "add"
            path = "/fields/System.AreaPath"
            value = $AreaPath
        }
    }

    if (-not [string]::IsNullOrEmpty($IterationPath)) {
        $featureFields += @{
            op = "add"
            path = "/fields/System.IterationPath"
            value = $IterationPath
        }
    }

    $featureFieldsJson = $featureFields | ConvertTo-Json -Depth 10
    $featureResponse = az devops work item create --type "Feature" --fields $featureFieldsJson --output json | ConvertFrom-Json
    $featureId = $featureResponse.id

    Write-Host "Created Feature with ID: $featureId"

    # Link Feature to Epic
    $epicLinkJson = @"
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "System.LinkTypes.Hierarchy-Reverse",
      "url": "${OrganizationUrl}/_apis/wit/workItems/$epicId"
    }
  }
]
"@

    az devops work item update --id $featureId --json-patch $epicLinkJson
    Write-Host "Linked Feature to Epic"

    # Create a mapping table to store created work item IDs
    $workItemIds = @{}

    # Create User Stories for each task
    foreach ($task in $taskData.tasks) {
        Write-Host "Creating User Story: $($task.taskname)"

        # Prepare fields with iteration and area path if provided
        $storyFields = $task.fields

        # Append additional tags if specified
        if (-not [string]::IsNullOrWhiteSpace($AdditionalTags)) {
            # Find the System.Tags field
            $tagsField = $storyFields | Where-Object { $_.path -eq "/fields/System.Tags" } | Select-Object -First 1

            if ($tagsField) {
                # Append additional tags to existing tags
                $tagsField.value += ";$AdditionalTags"
            } else {
                # Add tags field if it doesn't exist
                $storyFields += @{
                    op = "add"
                    path = "/fields/System.Tags"
                    value = $AdditionalTags
                }
            }
        }

        if (-not [string]::IsNullOrEmpty($IterationPath)) {
            $storyFields += @{
                op = "add"
                path = "/fields/System.IterationPath"
                value = $IterationPath
            }
        }

        if (-not [string]::IsNullOrEmpty($AreaPath)) {
            $storyFields += @{
                op = "add"
                path = "/fields/System.AreaPath"
                value = $AreaPath
            }
        }

        # Create User Story
        $storyFieldsJson = $storyFields | ConvertTo-Json -Depth 10
        $storyResponse = az devops work item create --type "User Story" --fields $storyFieldsJson --output json | ConvertFrom-Json

        # Store the created work item ID
        $workItemIds[$task.id] = $storyResponse.id
        Write-Host "Created User Story with ID: $($storyResponse.id)"

        # Link User Story to Feature
        $featureLinkJson = @"
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "System.LinkTypes.Hierarchy-Reverse",
      "url": "${OrganizationUrl}/_apis/wit/workItems/$featureId"
    }
  }
]
"@

        az devops work item update --id $storyResponse.id --json-patch $featureLinkJson
        Write-Host "Linked User Story to Feature"
    }

    # Create relationships between User Stories
    foreach ($relationship in $taskData.relationships) {
        $sourceId = $workItemIds[$relationship.sourceId]
        $targetId = $workItemIds[$relationship.targetId]

        if ($sourceId -and $targetId) {
            Write-Host "Creating relationship: $($relationship.sourceId) -> $($relationship.targetId)"

            # Create the relationship
            $relationshipJson = @"
[
  {
    "op": "add",
    "path": "/relations/-",
    "value": {
      "rel": "$($relationship.relationshipType)",
      "url": "${OrganizationUrl}/_apis/wit/workItems/$targetId"
    }
  }
]
"@

            az devops work item update --id $sourceId --json-patch $relationshipJson
            Write-Host "Created relationship between work items $sourceId and $targetId"
        } else {
            Write-Warning "Could not create relationship, one of the tasks was not created successfully"
        }
    }

    Write-Host "Completed processing for server: $($taskData.server)"
}

Write-Host "All servers imported successfully!"
Write-Host "Epic ID: $epicId"
'@

Set-Content -Path $adoMultiImportScriptPath -Value $adoMultiImportScript

Write-Host "Generated import scripts: $adoImportScriptPath and $adoMultiImportScriptPath"

