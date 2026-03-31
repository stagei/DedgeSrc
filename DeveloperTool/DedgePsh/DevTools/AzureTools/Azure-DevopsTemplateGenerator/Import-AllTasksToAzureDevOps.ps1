

# This script imports tasks for multiple servers to Azure DevOps
# Creates a single Epic with Features for each server and User Stories for tasks
# Source info: https://learn.microsoft.com/en-us/cli/azure/boards/work-item?view=azure-cli-latest

param (
    [Parameter(Mandatory = $false)]
    [string]$TaskFilesDirectory = ".\Output\AzureDevOpsTasks",

    [Parameter(Mandatory = $false)]
    [string]$IterationPath = "",

    [Parameter(Mandatory = $false)]
    [string]$AreaPath = "",

    [Parameter(Mandatory = $false)]
    [string]$EpicName = "New Azure Server Environment And Db2 12.1 Migration",

    [Parameter(Mandatory = $false)]
    [int]$ExistingEpicId = 0,

    [Parameter(Mandatory = $false)]
    [string]$AdditionalTags = ""
)
Import-Module AzureFunctions -Force
function Start-AzureDevOpsCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    Write-LogMessage "Executing command: $Command" -ForegroundColor Gray
    $response = Invoke-Expression $Command | ConvertFrom-Json
    if (-not $response) {
        Write-LogMessage "Command failed: $Command" -ForegroundColor Red
        throw "Command failed: $Command"
    }
    # Get current work item ID

    if ($response.id) {
        # Get work item info for the current ID
        $workItemInfo = az boards work-item show --id $response.id --output json | ConvertFrom-Json
        Write-Host "---------------------------------------------------------------------------------------------------------------------------------------------------------"
        Write-Host "WorkItem Info:`n ($($workItemInfo | ConvertTo-Json -Depth 10))" -ForegroundColor White
        Write-Host "---------------------------------------------------------------------------------------------------------------------------------------------------------"
    }
    else {
        Write-Host "---------------------------------------------------------------------------------------------------------------------------------------------------------"
        Write-Host "Response Info:`n $($response | ConvertTo-Json -Depth 20)" -ForegroundColor White
        Write-Host "---------------------------------------------------------------------------------------------------------------------------------------------------------"
    }

    return $response
}
function Get-AzureDevOpsProject {
    return "Dedge"
}

function Get-ChildRelations {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [string]$Type
    )
    $childRelations = az boards work-item show --id $Id --output json | ConvertFrom-Json
    if ($Type) {
        return $childRelations.relations | Where-Object { $_.rel.name -eq $Type }
    }
    return $childRelations.relations
}
function Remove-WorkItemRelationToId {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$RelationType,
        [Parameter(Mandatory = $true)]
        [string]$TargetId
    )
    try {
        $result = az boards work-item relation remove --id $Id --relation-type $RelationType --target-id $TargetId --output json | ConvertFrom-Json
        return $result
    }
    catch {
        Write-LogMessage "Error removing relation: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}
function Remove-WorkItem {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    $result = az boards work-item delete --id $Id --output json | ConvertFrom-Json
    return $result
}
try {
    $TaskFilesDirectory = Join-Path $PSScriptRoot $($TaskFilesDirectory.TrimStart('.\'))

    # Get Azure DevOps settings from GlobalFunctions
    $OrganizationName = Get-AzureDevOpsOrganization
    $ProjectName = Get-AzureDevOpsProject
    $OrganizationUrl = "https://dev.azure.com/$OrganizationName"

    $loggedIn = Assert-AzureDevOpsCliLogin -OrganizationUrl $OrganizationUrl
    if (-not $loggedIn) {
        Write-LogMessage "Azure DevOps CLI login failed (PAT missing/invalid). az commands may fail." -Level WARN
    }

    # Check if az devops is installed
    try {
        az --version | Out-Null
    }
    catch {
        Write-Error "Azure DevOps CLI not found. Please install the Azure CLI and the Azure DevOps extension."
        exit 1
    }

    # Azure DevOps CLI authentication handled via Assert-AzureDevOpsCliLogin (no AZURE_DEVOPS_EXT_PAT)
    Write-LogMessage "Azure DevOps CLI authentication checked" -Level INFO
    az devops configure --defaults organization=$OrganizationUrl project=$ProjectName --use-git-aliases true

    $taskFiles = Get-ChildItem -Path $TaskFilesDirectory -Filter "*.ado.json"

    $epicRelations = az boards query --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Epic' AND [System.Title] = '$EpicName' AND [System.TeamProject] = '$ProjectName'" --output json | ConvertFrom-Json

    if ($epicRelations.Count -gt 0) {
        Write-LogMessage "Epic $EpicName already exists, using existing epic"
        $ExistingEpicId = $epicRelations.id
        # match task files to features related to epic
        foreach ($taskFile in $taskFiles) {
            $taskData = Get-Content $taskFile | ConvertFrom-Json
            $featureTitle = "Server Migration: $($taskData.server)"
            $featureRelations = az boards query --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Feature' AND [System.Title] = '$featureTitle' AND [System.TeamProject] = '$ProjectName'" --output json | ConvertFrom-Json
            if ($featureRelations.Count -gt 0) {
                Write-LogMessage "Feature $featureTitle already exists, removing task file $($taskFile.Name) from list"
                $taskFiles = $taskFiles | Where-Object { $_.Name -ne $taskFile.Name }
            }
        }
    }

    $cleanUp = $false
    if ($cleanUp) {
        Write-LogMessage "Cleaning up existing Epics, Features and User Stories that contain 'server migration' in the title"
        # $existingUserStories = az boards query --wiql "SELECT [System.Id], [System.Title], [System.WorkItemType], [System.State], [System.CreatedBy], [System.CreatedDate], [System.ChangedBy], [System.ChangedDate], [System.TeamProject], [System.AreaPath], [System.IterationPath], [System.Tags], [System.Description], [System.AssignedTo], [System.Reason] FROM WorkItems WHERE [System.WorkItemType] = 'User Story' AND ([System.Title] CONTAINS 'p-no1' or [System.Title] CONTAINS 't-no1') AND [System.TeamProject] = '$ProjectName'" --output json | ConvertFrom-Json

        # $existingFeatures = az boards query --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Feature' AND [System.Title] CONTAINS 'server migration' AND [System.TeamProject] = '$ProjectName'" --output json | ConvertFrom-Json

        foreach ($epicRelation in $epicRelations) {
            $epicRelationId = $epicRelation.url.Split('/')[-1]

            foreach ($featureRelation in $(Get-ChildRelations $epicRelationId -Type "Feature") ) {
                $featureRelationId = $featureRelation.url.Split('/')[-1]

                foreach ($userStoryRelation in $(Get-ChildRelations $featureRelationId -Type "User Story") ) {
                    $userStoryRelationId = $userStoryRelation.url.Split('/')[-1]

                    foreach ($taskRelation in $(Get-ChildRelations $userStoryRelationId -Type "Task") ) {
                        $taskRelationId = $taskRelation.url.Split('/')[-1]
                        Remove-WorkItemRelationToId -Id $taskRelationId -RelationType $taskRelation.rel.name -TargetId $userStoryRelationId
                        Remove-WorkItem -Id $taskRelationId
                    }
                    Remove-WorkItemRelationToId -Id $userStoryRelationId -RelationType $userStoryRelation.rel.name -TargetId $featureRelationId
                    Remove-WorkItem -Id $userStoryRelationId
                }
                Remove-WorkItemRelationToId -Id $featureRelationId -RelationType $featureRelation.rel.name -TargetId $epicRelationId
                Remove-WorkItem -Id $featureRelationId
            }
            Remove-WorkItem -Id $epicRelationId
            Write-LogMessage "Deleted Epic with ID: $($epic.id)"
        }

        # foreach ($userStory in $existingUserStories) {
        #     #$result = az boards work-item delete --id $userStory.id --output json | ConvertFrom-Json
        #     Write-LogMessage "Deleted User Story with ID: $($userStory.id)"
        # }
        # foreach ($feature in $existingFeatures) {
        #     #$result = az boards work-item delete --id $feature.id --output json | ConvertFrom-Json
        #     Write-LogMessage "Deleted Feature with ID: $($feature.id)"
        # }
        # Delete relationships between User Stories and Features
        # foreach ($userStory in $existingUserStories) {
        #     $relations = az boards work-item relation list --id $userStory.id --output json | ConvertFrom-Json
        #     foreach ($relation in $relations) {
        #         if ($relation.rel.name -eq "System.LinkTypes.Hierarchy-Reverse") {
        #             $result = az boards work-item relation remove --id $userStory.id --relation-type "System.LinkTypes.Hierarchy-Reverse" --target-id $relation.url.Split('/')[-1] --output json | ConvertFrom-Json
        #             Write-LogMessage "Removed relationship between User Story $($userStory.id) and Feature"
        #         }
        #     }
        # }
    }

    #     # Delete relationships between Features and Epic
    #     foreach ($feature in $existingFeatures) {
    #         $relations = az boards work-item relation list --id $feature.id --output json | ConvertFrom-Json
    #         foreach ($relation in $relations) {
    #             if ($relation.rel.name -eq "System.LinkTypes.Hierarchy-Reverse") {
    #                 $result = az boards work-item relation remove --id $feature.id --relation-type "System.LinkTypes.Hierarchy-Reverse" --target-id $relation.url.Split('/')[-1] --output json | ConvertFrom-Json
    #                 Write-LogMessage "Removed relationship between Feature $($feature.id) and Epic"
    #             }
    #         }
    #     }
    # }
    $partialDevopsUrl = "https://dev.azure.com/Dedge/Dedge/_workitems/edit/"
    $resultArray = @()
    $allUserStoryRelationships = @()
    $allUserStories = @()

    # Step 1: Create or use an Epic
    $epicId = $ExistingEpicId
    if ($epicId -eq 0) {
        Write-LogMessage "Creating new Epic: $EpicName" -ForegroundColor Blue

        $epicFields = @(
            @{
                op    = "add"
                path  = "/fields/System.Description"
                value = "Epic for server migration tasks across multiple environments"
            },
            @{
                op    = "add"
                path  = "/fields/System.Tags"
                value = "AZDB2MIG"
            }
        )

        if (-not [string]::IsNullOrEmpty($IterationPath)) {
            $epicFields += @{
                op    = "add"
                path  = "/fields/System.IterationPath"
                value = $IterationPath
            }
        }

        if (-not [string]::IsNullOrEmpty($AreaPath)) {
            $epicFields += @{
                op    = "add"
                path  = "/fields/System.AreaPath"
                value = $AreaPath
            }
        }

        # Add additional tags if provided
        if (-not [string]::IsNullOrEmpty($AdditionalTags)) {
            # Check if there are already tags in the epic fields
            $existingTagField = $epicFields | Where-Object { $_.path -eq "/fields/System.Tags" }

            if ($existingTagField) {
                # Append to existing tags
                $existingTagField.value += ";$($AdditionalTags.Replace(',',';'))"
            }
            else {
                # Add tags field if it doesn't exist
                $epicFields += @{
                    op    = "add"
                    path  = "/fields/System.Tags"
                    value = $AdditionalTags.Replace(',', ';')
                }
            }
        }

        # Convert fields array to space-separated field=value pairs
        $fieldArgs = ""
        foreach ($field in $epicFields) {
            $fieldName = $field.path.Replace('/fields/', '')
            # Properly escape and format the field value
            $fieldValue = $field.value -replace '"', '\"'
            if ($fieldArgs -ne "") {
                $fieldArgs += " "
            }
            $fieldArgs += "$fieldName=`"$fieldValue`""
        }

        # Write fields to console for debugging
        Write-LogMessage "`nFields for epic $($EpicName):" -ForegroundColor Cyan
        foreach ($field in $epicFields) {
            Write-LogMessage "  $($field.path): $($field.value)" -ForegroundColor Gray
        }

        # For debugging
        Write-LogMessage "Field string: $fieldArgs" -ForegroundColor Gray

        # Try creating the work item without the --fields parameter if it's empty
        if ([string]::IsNullOrWhiteSpace($fieldArgs)) {
            try {
                $createCommand = "az boards work-item create --type 'Epic' --title '$($EpicName -replace "'", "''")' --assigned-to 'geir.helge.starholm@Dedge.no' --output json"
                $epicResponse = Start-AzureDevOpsCommand -Command $createCommand
            }
            catch {
                Write-LogMessage "Error creating epic: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
        }
        else {
            # Pass the fields directly to the command without using a variable
            try {
                $createCommand = "az boards work-item create --type 'Epic' --title '$($EpicName -replace "'", "''")' --assigned-to 'geir.helge.starholm@Dedge.no' --fields $fieldArgs --output json"
                $epicResponse = Start-AzureDevOpsCommand -Command $createCommand
            }
            catch {
                Write-LogMessage "Error creating epic: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
        }

        $epicId = $epicResponse.id

        Write-LogMessage "Created Epic with ID: $epicId with url: $($partialDevopsUrl + $epicId)" -ForegroundColor Blue
        $resultArray += [PSCustomObject]@{
            EpicId             = $epicId
            FeatureId          = ""
            UserStoryId        = ""
            RelatedUserStoryId = ""
            WorkItemType       = "Epic"
            RelationType       = "AZDB2MIG"
            Title              = $EpicName
            Url                = $($partialDevopsUrl + $epicId)
        }
    }
    else {
        Write-LogMessage "Using existing Epic with ID: $epicId" -ForegroundColor Blue
    }

    Write-LogMessage "Handling Features for epic: $epicId - $EpicName"
    # Get all ADO task files

    # Load each task file and create the work items
    $ServerFeatures = @{}
    $workItemIds = @{}

    foreach ($taskFile in $taskFiles) {
        Write-LogMessage "Processing features and user stories from file: $($taskFile.Name)" -ForegroundColor Yellow
        $taskData = Get-Content $taskFile.FullName -Raw | ConvertFrom-Json

        # Step 1: Create a Feature for this server if not already created
        if (!$ServerFeatures.ContainsKey($taskData.server)) {
            Write-LogMessage "Creating Feature for server: $($taskData.server)" -ForegroundColor Yellow

            # Prepare feature tags
            $featureTags = "$($taskData.server);AZDB2MIG"
            if (-not [string]::IsNullOrEmpty($AdditionalTags)) {
                $featureTags += ";$($AdditionalTags.Replace(',',';'))"
            }

            # Get fields from task data
            $featureFields = @()

            # Add description field
            $featureFields += @{
                op    = "add"
                path  = "/fields/System.Description"
                value = "Migration tasks for server $($taskData.server))"
            }

            # Add tags field
            $featureFields += @{
                op    = "add"
                path  = "/fields/System.Tags"
                value = $featureTags
            }

            # Add area path if provided
            if (-not [string]::IsNullOrEmpty($AreaPath)) {
                $featureFields += @{
                    op    = "add"
                    path  = "/fields/System.AreaPath"
                    value = $AreaPath
                }
            }

            # Add iteration path if provided
            if (-not [string]::IsNullOrEmpty($IterationPath)) {
                $featureFields += @{
                    op    = "add"
                    path  = "/fields/System.IterationPath"
                    value = $IterationPath
                }
            }

            # Convert fields array to space-separated field=value pairs
            $fieldArgs = ""
            foreach ($field in $featureFields) {
                $fieldName = $field.path.Replace('/fields/', '')
                # Properly escape and format the field value
                $fieldValue = $field.value -replace '"', '\"'
                if ($fieldArgs -ne "") {
                    $fieldArgs += " "
                }
                $fieldArgs += "$fieldName=`"$fieldValue`""
            }

            # Write fields to console for debugging
            Write-LogMessage "`nFields for feature $($taskData.server):" -ForegroundColor Cyan
            foreach ($field in $featureFields) {
                Write-LogMessage "  $($field.path): $($field.value)" -ForegroundColor Gray
            }

            # For debugging
            Write-LogMessage "Field string: $fieldArgs" -ForegroundColor Gray

            $featureTitle = "Server Migration: $($taskData.server)"

            # Create feature work item
            if ([string]::IsNullOrWhiteSpace($fieldArgs)) {
                try {
                    $createCommand = "az boards work-item create --type 'Feature' --title '$($featureTitle -replace "'", "''")' --assigned-to 'geir.helge.starholm@Dedge.no' --output json"
                    $featureResponse = Start-AzureDevOpsCommand -Command $createCommand
                }
                catch {
                    Write-LogMessage "Error creating feature: $($_.Exception.Message)" -ForegroundColor Red
                    throw
                }
            }
            else {
                try {
                    $createCommand = "az boards work-item create --type 'Feature' --title '$($featureTitle -replace "'", "''")' --assigned-to 'geir.helge.starholm@Dedge.no' --fields $fieldArgs --output json"
                    $featureResponse = Start-AzureDevOpsCommand -Command $createCommand
                }
                catch {
                    Write-LogMessage "Error creating feature: $($_.Exception.Message)" -ForegroundColor Red
                    throw
                }
            }
            $featureId = $featureResponse.id

            Write-LogMessage "Created Feature with ID: $featureId with url: $($partialDevopsUrl + $featureId)" -ForegroundColor Yellow

            # Link Feature to Epic
            try {
                $createCommand = "az boards work-item relation add --id $featureId --relation-type 'parent' --target-id $epicId --output json"
                $result = Start-AzureDevOpsCommand -Command $createCommand
                Write-LogMessage "Linked Feature $($featureId) to Epic $($epicId)" -ForegroundColor Yellow
            }
            catch {
                Write-LogMessage "Error linking feature to epic: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }

            $resultArray += [PSCustomObject]@{
                EpicId             = $epicId
                FeatureId          = $featureId
                UserStoryId        = ""
                RelatedUserStoryId = ""
                WorkItemType       = "Feature"
                RelationType       = "child of epic"
                Title              = $featureTitle
                Url                = $($partialDevopsUrl + $featureId)
            }

            # Store the feature ID in the ServerFeatures dictionary
            $ServerFeatures[$taskData.server] = $featureId
        }
        else {
            $featureId = $ServerFeatures[$taskData.server]
        }
        Write-LogMessage "Handling User Stories for feature: $($featureId) - $($featureTitle)" -ForegroundColor Yellow
        # Step 2: Create User Stories for each task
        foreach ($task in $taskData.tasks) {
            # Skip if this task has already been processed (could be in multiple task files)
            if ($workItemIds.ContainsKey($task.id)) {
                Write-LogMessage "User Story $($task.id) already processed, skipping." -ForegroundColor Green
                continue
            }
            Write-LogMessage "Adding User Story: $($task.taskname) to feature: $($featureTitle)" -ForegroundColor Green

            # Prepare fields with iteration and area path if provided
            $storyFields = $task.fields
            $title = ""
            if ($storyFields | Where-Object { $_.path.Contains("System.Title") }) {
                # Remove any existing title fields from the task fields since we will add it again below
                $title = ($storyFields | Where-Object { $_.path.Contains("System.Title") } | Select-Object -First 1).value
                $storyFields = $storyFields | Where-Object { -not $_.path.Contains("System.Title") }
            }

            if (-not [string]::IsNullOrEmpty($IterationPath)) {
                $storyFields += @{
                    op    = "add"
                    path  = "/fields/System.IterationPath"
                    value = $IterationPath
                }
            }

            if (-not [string]::IsNullOrEmpty($AreaPath)) {
                $storyFields += @{
                    op    = "add"
                    path  = "/fields/System.AreaPath"
                    value = $AreaPath
                }
            }

            # Add additional tags if provided
            if (-not [string]::IsNullOrEmpty($AdditionalTags)) {
                # Check if there are already tags in the task fields
                $existingTagField = $storyFields | Where-Object { $_.path -eq "/fields/System.Tags" }

                if ($existingTagField) {
                    # Append to existing tags
                    $existingTagField.value += ";$($AdditionalTags.Replace(',',';'))"
                }
                else {
                    # Add tags field if it doesn't exist
                    $storyFields += @{
                        op    = "add"
                        path  = "/fields/System.Tags"
                        value = $AdditionalTags.Replace(',', ';')
                    }
                }
            }

            # Convert fields array to space-separated field=value pairs
            $fieldArgs = ""
            foreach ($field in $storyFields) {
                $fieldName = $field.path.Replace('/fields/', '')
                # Properly escape and format the field value
                $fieldValue = $field.value -replace '"', '\"'
                if ($fieldArgs -ne "") {
                    $fieldArgs += " "
                }
                $fieldArgs += "$fieldName=`"$fieldValue`""
            }

            # Write fields to console for debugging
            Write-LogMessage "`nFields for task $($task.taskname):" -ForegroundColor Cyan
            foreach ($field in $storyFields) {
                Write-LogMessage "  $($field.path): $($field.value)" -ForegroundColor Gray
            }

            # For debugging
            Write-LogMessage "Field string: $fieldArgs" -ForegroundColor Gray

            # Try creating the work item without the --fields parameter if it's empty
            if ([string]::IsNullOrWhiteSpace($fieldArgs)) {
                try {
                    $createCommand = "az boards work-item create --type 'User Story' --title '$($title -replace "'", "''")' --assigned-to 'geir.helge.starholm@Dedge.no' --output json"
                    $storyResponse = Start-AzureDevOpsCommand -Command $createCommand
                }
                catch {
                    Write-LogMessage "Error creating user story: $($_.Exception.Message)" -ForegroundColor Red
                    throw
                }
            }
            else {
                try {
                    # Pass the fields directly to the command without using a variable
                    $createCommand = "az boards work-item create --type 'User Story' --title '$($title -replace "'", "''")' --assigned-to 'geir.helge.starholm@Dedge.no' --fields $fieldArgs --output json"
                    $storyResponse = Start-AzureDevOpsCommand -Command $createCommand
                }
                catch {
                    Write-LogMessage "Error creating user story: $($_.Exception.Message)" -ForegroundColor Red
                    throw
                }
            }

            # Store the created work item ID
            $workItemIds[$task.id] = $storyResponse.id
            Write-LogMessage "Created User Story with ID: $($storyResponse.id) with url: $($partialDevopsUrl + $storyResponse.id)" -ForegroundColor Green

            # Link User Story to Feature for this server
            try {
                $createCommand = "az boards work-item relation add --id $($storyResponse.id) --relation-type 'parent' --target-id $featureId --output json"
                $result = Start-AzureDevOpsCommand -Command $createCommand
                Write-LogMessage "Linked User Story $($storyResponse.id) to Feature $($featureId)" -ForegroundColor Green
            }
            catch {
                Write-LogMessage "Error linking user story to feature: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
            $resultArray += [PSCustomObject]@{
                EpicId             = $epicId
                FeatureId          = $featureId
                UserStoryId        = $storyResponse.id
                RelatedUserStoryId = ""
                WorkItemType       = "User Story"
                RelationType       = "child of feature"
                OriginalTaskName   = $task.taskname
                Title              = $title
                Url                = $($partialDevopsUrl + $storyResponse.id)
            }
            # Accumulate all user stories
            $allUserStories += [PSCustomObject]@{
                UserStoryTaskName = $task.taskname
                UserStoryId       = $storyResponse.id
                FeatureId         = $featureId
                Title             = $title
                Url               = $($partialDevopsUrl + $storyResponse.id)
            }

            # Accumulate all user story relationships
            foreach ($relationship in $taskData.relationships) {
                Write-LogMessage "Relationship: $($relationship.relationshipType) $($relationship.sourceId) -> $($relationship.targetId)"
                # Check if either source or target contains "fkx"
                if ($taskData.server -notmatch "fkx") {
                    if ($relationship.sourceId -match "fkx" -or $relationship.targetId -match "fkx") {
                        Write-LogMessage "Found 'fkx' in relationship: $($relationship.sourceId) -> $($relationship.targetId)" -ForegroundColor Yellow
                    }
                }
                $relationTypeForCli = switch ($relationship.RelationType) {
                    # System link types - core relationship types in Azure DevOps
                    "System.LinkTypes.Dependency-Forward" { "Successor" }    # Source depends on Target (Target must be completed before Source)
                    "System.LinkTypes.Dependency-Reverse" { "Predecessor" }  # Target depends on Source (Source must be completed before Target)
                    "System.LinkTypes.Related" { "Related" }                 # General relationship with no specific dependency
                    "System.LinkTypes.Duplicate-Forward" { "Duplicate" }     # Source is a duplicate of Target

                    # Microsoft VSTS Common link types - extended relationship types
                    "Microsoft.VSTS.Common.Dependency-Forward" { "Successor" }       # Same as System.LinkTypes.Dependency-Forward
                    "Microsoft.VSTS.Common.Dependency-Reverse" { "Predecessor" }     # Same as System.LinkTypes.Dependency-Reverse
                    "Microsoft.VSTS.Common.AffectedBy" { "Predecessor" }             # Source is affected by Target (Target is prerequisite)
                    "Microsoft.VSTS.Common.Affects" { "Affects" }                    # Source affects Target (changes to Source impact Target)
                    "Microsoft.VSTS.Common.Related" { "Related" }                    # Same as System.LinkTypes.Related
                    "Microsoft.VSTS.Common.TestedBy-Forward" { "Tested By" }         # Source is tested by Target (Target is a test for Source)
                    "Microsoft.VSTS.Common.TestedBy-Reverse" { "Tests" }             # Source tests Target (Source is a test for Target)

                    # Simple relationship names (already CLI-compatible) - used directly in CLI commands
                    "predecessor" { "Predecessor" }    # Target is a predecessor of Source (Target must be completed before Source)
                    "successor" { "Successor" }        # Target is a successor of Source (Source must be completed before Target)
                    "parent" { "Parent" }              # Target is parent of Source (hierarchical relationship)
                    "child" { "Child" }                # Target is child of Source (hierarchical relationship)
                    "affects" { "Affects" }            # Source affects Target (changes to Source impact Target)
                    "related" { "Related" }            # General relationship with no specific dependency
                    "tested by" { "Tested By" }        # Source is tested by Target
                    "tests" { "Tests" }                # Source tests Target

                    # Default: use the original relationship type if no match is found
                    # This allows for custom relationship types or future additions
                    default { $relationship.RelationType }
                }
                $allUserStoryRelationships += [PSCustomObject]@{
                    SourceTaskName = $relationship.sourceId
                    TargetTaskName = $relationship.targetId
                    # SourceId     = $relationship.sourceId
                    # TargetId     = $relationship.targetId
                    RelationType   = $relationTypeForCli
                }
            }

        }

    }
    $allUserStoryRelationships = $allUserStoryRelationships | Sort-Object -Property SourceTaskName, TargetTaskName -Unique
    $allUserStories = $allUserStories | Sort-Object -Property UserStoryTaskName -Unique

    # Create mapping for relationships between User Stories and TasksNames
    $userStoryTaskMapping = @()
    foreach ($relationship in $allUserStoryRelationships) {
        $sourceUserStory = $allUserStories | Where-Object { $_.UserStoryTaskName -eq $relationship.SourceTaskName } | Select-Object -First 1
        $targetUserStory = $allUserStories | Where-Object { $_.UserStoryTaskName -eq $relationship.TargetTaskName } | Select-Object -First 1
        if ($sourceUserStory -and $targetUserStory) {
            $userStoryTaskMapping += [PSCustomObject]@{
                SourceUserStoryId = $sourceUserStory.UserStoryId
                TargetUserStoryId = $targetUserStory.UserStoryId
                SourceTaskName    = $relationship.SourceTaskName
                TargetTaskName    = $relationship.TargetTaskName
                RelationType      = $relationship.RelationType
            }
            Write-LogMessage "Creating relationship: $($sourceUserStory.UserStoryId) -> $($targetUserStory.UserStoryId)" -ForegroundColor Cyan
            try {
                $currentRelationType = $relationship.RelationType
                if ([string]::IsNullOrEmpty($currentRelationType)) {
                    $currentRelationType = "Predecessor"
                }
                $createCommand = "az boards work-item relation add --id $($sourceUserStory.UserStoryId) --relation-type $currentRelationType --target-id $($targetUserStory.UserStoryId) --output json"
                $result = Start-AzureDevOpsCommand -Command $createCommand
                Write-LogMessage "Created relationship between work items $($sourceUserStory.UserStoryId) and $($targetUserStory.UserStoryId) with relation type: $($currentRelationType)" -ForegroundColor Cyan
            }
            catch {
                Write-LogMessage "Error creating relationship: $($_.Exception.Message)" -ForegroundColor Red -Exception $_.Exception
                #throw
            }
            Write-LogMessage "Created relationship between work items $($sourceUserStory.UserStoryId) and $($targetUserStory.UserStoryId) with relation type: $($currentRelationType)" -ForegroundColor Cyan
            # $resultArray += [PSCustomObject]@{
            #     EpicId             = $epicId ?? ""
            #     FeatureId          = $sourceUserStory.FeatureId ?? ""
            #     UserStoryId        = $sourceUserStory.UserStoryId ?? ""
            #     RelatedUserStoryId = $targetUserStory.UserStoryId ?? ""
            #     WorkItemType       = "Relationship between User Stories"
            #     RelationType       = $relationship.RelationType.ToLower() ?? ""
            #     Title              = $relationship.RelationType
            #     Url                = $($partialDevopsUrl + $sourceUserStory.UserStoryId) ?? ""
            # }
        }
    }

    # # Create relationships between User Stories
    # foreach ($relationship in $allUserStoryRelationships) {
    #     $sourceId = $workItemIds[$relationship.SourceId]
    #     $targetId = $workItemIds[$relationship.TargetId]

    #     if ($sourceId -and $targetId) {
    #         Write-LogMessage "Creating relationship: $($relationship.SourceId) -> $($relationship.TargetId)" -ForegroundColor Cyan

    #         # Map relationship type to a valid Azure DevOps relationship reference name
    #         $relationType = "Affected By"

    #         # Create the relationship
    #         $result = az boards work-item relation add --id $sourceId --relation-type $relationType --target-id $targetId --output json | ConvertFrom-Json
    #         Write-LogMessage "Created relationship between work items $sourceId and $targetId with relation type: $relationType" -ForegroundColor Cyan
    #         $resultArray += [PSCustomObject]@{
    #             EpicId             = $epicId
    #             FeatureId          = $featureId
    #             UserStoryId        = $sourceId
    #             RelatedUserStoryId = $targetId
    #             WorkItemType       = "Relationship"
    #             RelationType       = $relationType.ToLower()
    #             Title              = $relationType
    #             Url                = $($partialDevopsUrl + $sourceId)
    #         }
    #     }
    #     else {
    #         Write-LogMessage "Could not create relationship, one of the tasks was not created successfully" -ForegroundColor Red
    #     }
    # }

    Write-LogMessage "Completed processing for server: $($taskData.server)"

    Write-LogMessage "All servers imported successfully!"
    Write-LogMessage "Epic ID: $epicId"

    Write-LogMessage "--------------------------------"
    Write-LogMessage "Result Array"
    Write-LogMessage "--------------------------------"
    $resultArray | Format-Table -AutoSize -Property *
    Write-LogMessage "--------------------------------"
    Send-Sms -Receiver "+4797188358" -Message "All stories imported successfully into Epic: $($partialDevopsUrl + $epicId)"
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -ForegroundColor Red -Exception $_.Exception
    Send-Sms -Receiver "+4797188358" -Message "Error: $($_.Exception.Message)"
    throw
}

# az boards work-item relation add --id 241828 --relation-type "Successor" --target-id 241825 --output json | ConvertFrom-Json
# az boards work-item update --id 241828 --fields "System.Tags=SRVMIG;DBMIG" --output json | ConvertFrom-Json

