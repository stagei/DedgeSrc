# This script imports tasks for multiple servers to Azure DevOps
# Creates a single Epic with Features for each server and User Stories for tasks

param (
    [Parameter(Mandatory=$true)]
    [string]$TaskFilesDirectory,

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

# Get all ADO task files
$taskFiles = Get-ChildItem -Path $TaskFilesDirectory -Filter "*.ado.json"

# Load each task file and create the work items
$ServerFeatures = @{}
$workItemIds = @{}

foreach ($taskFile in $taskFiles) {
    Write-Host "Processing task file: $($taskFile.Name)"
    $taskData = Get-Content $taskFile.FullName -Raw | ConvertFrom-Json

    # Step 1: Create a Feature for this server if not already created
    if (!$ServerFeatures.ContainsKey($taskData.server)) {
        Write-Host "Creating Feature for server: $($taskData.server)"

        # Prepare feature tags
        $featureTags = "Server=$($taskData.server);ServerPart=$($taskData.serverPart);Template=$($taskData.templateName)"
        if (-not [string]::IsNullOrEmpty($AdditionalTags)) {
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

        # Store the feature ID in the ServerFeatures dictionary
        $ServerFeatures[$taskData.server] = $featureId
    } else {
        $featureId = $ServerFeatures[$taskData.server]
    }

    # Step 2: Create User Stories for each task
    foreach ($task in $taskData.tasks) {
        # Skip if this task has already been processed (could be in multiple task files)
        if ($workItemIds.ContainsKey($task.id)) {
            Write-Host "Task $($task.id) already processed, skipping."
            continue
        }

        Write-Host "Creating User Story: $($task.taskname)"

        # Prepare fields with iteration and area path if provided
        $storyFields = $task.fields

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

        # Add additional tags if provided
        if (-not [string]::IsNullOrEmpty($AdditionalTags)) {
            # Check if there are already tags in the task fields
            $existingTagField = $storyFields | Where-Object { $_.path -eq "/fields/System.Tags" }

            if ($existingTagField) {
                # Append to existing tags
                $existingTagField.value += ";$AdditionalTags"
            } else {
                # Add new tags field
                $storyFields += @{
                    op = "add"
                    path = "/fields/System.Tags"
                    value = $AdditionalTags
                }
            }
        }

        # Create User Story
        $storyFieldsJson = $storyFields | ConvertTo-Json -Depth 10
        $storyResponse = az devops work item create --type "User Story" --fields $storyFieldsJson --output json | ConvertFrom-Json

        # Store the created work item ID
        $workItemIds[$task.id] = $storyResponse.id
        Write-Host "Created User Story with ID: $($storyResponse.id)"

        # Link User Story to Feature for this server
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

