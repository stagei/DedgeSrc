<#
.SYNOPSIS
    Azure DevOps User Story Manager - Interactive and command-line tool for managing work items

.DESCRIPTION
    Comprehensive tool for managing Azure DevOps work items using Azure CLI.
    Supports:
    - Getting work item details
    - Updating descriptions and fields
    - Adding comments
    - Uploading attachments  
    - Adding repository links
    - Changing status
    - Creating subtasks
    
    Uses Azure CLI (az boards) for reliable authentication and operations.

.PARAMETER WorkItemId
    The ID of the work item to manage

.PARAMETER Action
    Action to perform: Get, Update, Comment, Attach, Link, Status, Subtask, AddTags

.PARAMETER Description
    New description for the work item

.PARAMETER Comment
    Comment text to add

.PARAMETER FilePath
    Path to file to attach

.PARAMETER Url
    URL to link (for hyperlinks or repository paths)

.PARAMETER State
    New state for the work item (New, Active, Resolved, Closed)

.PARAMETER Title
    Title for new subtask or work item

.PARAMETER Tags
    Semicolon-separated tags (e.g., "Tag1;Tag2;Tag3")

.PARAMETER Interactive
    Launch interactive menu mode

.EXAMPLE
    .\Azure-DevOpsUserStoryManager.ps1 -Interactive

.EXAMPLE
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Get

.EXAMPLE
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Update -Description "Updated"

.EXAMPLE
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment -Comment "Done"

.EXAMPLE
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Status -State "Active"
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'CommandLine', Mandatory = $false)]
    [int]$WorkItemId,

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidateSet('Get', 'Update', 'Comment', 'Attach', 'Link', 'RepoLink', 'Status', 'Subtask', 'AddTags')]
    [string]$Action,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$Description,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$Comment,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$FilePath,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$Url,

    [Parameter(ParameterSetName = 'CommandLine')]
    [ValidateSet('New', 'Active', 'Resolved', 'Closed', 'Removed')]
    [string]$State,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$Title,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$Tags,

    [Parameter(ParameterSetName = 'CommandLine')]
    [string]$AssignedTo,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive
)

Import-Module AzureFunctions -Force

#region Configuration and Initialization

function Get-AzureDevOpsConfig {
    <#
    .SYNOPSIS
    Gets Azure DevOps configuration from GlobalFunctions
    #>
    try {
        $config = @{
            Organization = Get-AzureDevOpsOrganization
            Project      = Get-AzureDevOpsProject
            Pat          = Get-AzureDevOpsPat
            Repository   = Get-AzureDevOpsRepository
            BaseUrl      = "https://dev.azure.com"
            ApiVersion   = "7.0"
        }
        
        $config.OrgUrl = "$($config.BaseUrl)/$($config.Organization)"
        $config.ProjectUrl = "$($config.OrgUrl)/$($config.Project)"
        
        return $config
    }
    catch {
        Write-LogMessage "Failed to get Azure DevOps configuration: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Initialize-AzureCli {
    <#
    .SYNOPSIS
    Initializes and configures Azure CLI for Azure DevOps
    #>
    param([switch]$Force)
    
    try {
        # Check if az is available
        az --version 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Azure CLI is not installed. Please install: winget install Microsoft.AzureCLI" -Level ERROR
            return $false
        }
        
        # Check if azure-devops extension is installed
        $extensions = az extension list --output json 2>&1 | ConvertFrom-Json
        $devopsExt = $extensions | Where-Object { $_.name -eq 'azure-devops' }
        
        if (-not $devopsExt) {
            Write-LogMessage "Installing Azure DevOps extension..." -Level INFO
            az extension add --name azure-devops --yes 2>&1 | Out-Null
        }
        
        # Configure Azure CLI (no AZURE_DEVOPS_EXT_PAT)
        $config = Get-AzureDevOpsConfig

        $loggedIn = Assert-AzureDevOpsCliLogin -OrganizationUrl $config.OrgUrl
        if (-not $loggedIn) {
            Write-LogMessage "Azure DevOps CLI login failed (PAT missing/invalid). az commands may fail." -Level WARN
        }

        az devops configure --defaults organization="$($config.OrgUrl)" project="$($config.Project)" --use-git-aliases true 2>&1 | Out-Null
        
        Write-LogMessage "Azure CLI configured successfully" -Level DEBUG
        return $true
    }
    catch {
        Write-LogMessage "Failed to initialize Azure CLI: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $false
    }
}

#endregion

#region REST API Helper

function Invoke-AzureDevOpsApi {
    <#
    .SYNOPSIS
    Sends a REST request to Azure DevOps with proper UTF-8 encoding for Norwegian characters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Patch', 'Put', 'Delete')]
        [string]$Method,

        [object]$Body,

        [string]$ContentType = "application/json-patch+json; charset=utf-8"
    )

    $config = Get-AzureDevOpsConfig
    $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($config.Pat)"))
    $headers = @{ "Authorization" = "Basic $base64Auth" }

    $params = @{
        Uri     = $Uri
        Method  = $Method
        Headers = $headers
    }

    if ($Body) {
        $json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 }
        $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params['ContentType'] = $ContentType
    }

    Invoke-RestMethod @params
}

#endregion

#region Core Functions

function Get-AzureDevOpsWorkItem {
    <#
    .SYNOPSIS
    Retrieves a work item by ID using Azure CLI
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId
    )
    
    try {
        Write-LogMessage "Retrieving work item $WorkItemId..." -Level INFO
        
        $result = az boards work-item show --id $WorkItemId --output json 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve work item: $result"
        }
        
        $workItem = $result | ConvertFrom-Json
        
        Write-LogMessage "Successfully retrieved work item $WorkItemId" -Level INFO
        
        $config = Get-AzureDevOpsConfig
        Write-LogMessage "URL: $($config.ProjectUrl)/_workitems/edit/$WorkItemId" -Level INFO
        
        return $workItem
    }
    catch {
        Write-LogMessage "Failed to retrieve work item $($WorkItemId): $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Update-AzureDevOpsWorkItem {
    <#
    .SYNOPSIS
    Updates fields in an existing work item via REST API with UTF-8 encoding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Fields
    )
    
    try {
        Write-LogMessage "Updating work item $WorkItemId..." -Level INFO
        
        $config = Get-AzureDevOpsConfig
        
        $patchDoc = @()
        foreach ($field in $Fields.GetEnumerator()) {
            $patchDoc += @{
                op    = "add"
                path  = "/fields/$($field.Key)"
                value = $field.Value
            }
        }
        
        $uri = "$($config.ProjectUrl)/_apis/wit/workitems/$($WorkItemId)?api-version=$($config.ApiVersion)"
        $workItem = Invoke-AzureDevOpsApi -Uri $uri -Method Patch -Body $patchDoc
        
        Write-LogMessage "Successfully updated work item $WorkItemId" -Level INFO
        Write-LogMessage "URL: $($config.ProjectUrl)/_workitems/edit/$WorkItemId" -Level INFO
        
        return $workItem
    }
    catch {
        Write-LogMessage "Failed to update work item $($WorkItemId): $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Set-AzureDevOpsWorkItemState {
    <#
    .SYNOPSIS
    Changes the state of a work item
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('New', 'Active', 'Resolved', 'Closed', 'Removed')]
        [string]$State,
        
        [string]$Reason
    )
    
    try {
        Write-LogMessage "Changing state of work item $WorkItemId to $State..." -Level INFO
        
        $fields = @{
            "System.State" = $State
        }
        
        if ($Reason) {
            $fields["System.Reason"] = $Reason
        }
        
        $result = Update-AzureDevOpsWorkItem -WorkItemId $WorkItemId -Fields $fields
        
        Write-LogMessage "Successfully changed state to $State" -Level INFO
        return $result
    }
    catch {
        Write-LogMessage "Failed to change state: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Add-AzureDevOpsComment {
    <#
    .SYNOPSIS
    Adds a comment to a work item via REST API with UTF-8 encoding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory = $true)]
        [string]$Comment
    )
    
    try {
        Write-LogMessage "Adding comment to work item $WorkItemId..." -Level INFO
        
        $config = Get-AzureDevOpsConfig
        $body = @{ text = $Comment }
        $uri = "$($config.ProjectUrl)/_apis/wit/workItems/$WorkItemId/comments?api-version=7.1-preview.4"
        
        $result = Invoke-AzureDevOpsApi -Uri $uri -Method Post -Body $body -ContentType "application/json; charset=utf-8"
        
        Write-LogMessage "Successfully added comment" -Level INFO
        return $result
    }
    catch {
        Write-LogMessage "Failed to add comment: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Add-AzureDevOpsAttachment {
    <#
    .SYNOPSIS
    Uploads and attaches a file to a work item using REST API
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,
        
        [string]$AttachmentComment
    )
    
    try {
        $config = Get-AzureDevOpsConfig
        $fileName = [System.IO.Path]::GetFileName($FilePath)
        
        Write-LogMessage "Uploading file: $fileName..." -Level INFO
        
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($config.Pat)"))
        
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $uploadHeaders = @{
            "Authorization" = "Basic $base64Auth"
            "Content-Type"  = "application/octet-stream"
        }
        
        $uploadUri = "$($config.ProjectUrl)/_apis/wit/attachments?fileName=$fileName&api-version=$($config.ApiVersion)"
        $attachment = Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $uploadHeaders -Body $fileBytes
        
        Write-LogMessage "File uploaded, attaching to work item..." -Level INFO
        
        $linkOperation = @(
            @{
                op    = "add"
                path  = "/relations/-"
                value = @{
                    rel        = "AttachedFile"
                    url        = $attachment.url
                    attributes = @{
                        comment = if ($AttachmentComment) { $AttachmentComment } else { "Attached: $fileName" }
                    }
                }
            }
        )
        
        $linkUri = "$($config.ProjectUrl)/_apis/wit/workitems/$WorkItemId?api-version=$($config.ApiVersion)"
        $result = Invoke-AzureDevOpsApi -Uri $linkUri -Method Patch -Body $linkOperation
        
        Write-LogMessage "Successfully attached file: $fileName" -Level INFO
        return $result
    }
    catch {
        Write-LogMessage "Failed to attach file: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Add-AzureDevOpsLink {
    <#
    .SYNOPSIS
    Adds a link to a work item (hyperlink or repository link) via REST API with UTF-8 encoding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [string]$LinkComment
    )
    
    try {
        Write-LogMessage "Adding link to work item $WorkItemId..." -Level INFO
        
        $config = Get-AzureDevOpsConfig
        
        $isHyperlink = $Url -match '^https?://'
        
        if (-not $isHyperlink) {
            $Url = "$($config.ProjectUrl)/_git/$($config.Repository)?path=$Url&version=GBmain"
        }
        
        $linkOperation = @(
            @{
                op    = "add"
                path  = "/relations/-"
                value = @{
                    rel        = "Hyperlink"
                    url        = $Url
                    attributes = @{
                        comment = if ($LinkComment) { $LinkComment } else { "Link: $Url" }
                    }
                }
            }
        )
        
        $uri = "$($config.ProjectUrl)/_apis/wit/workitems/$WorkItemId?api-version=$($config.ApiVersion)"
        $result = Invoke-AzureDevOpsApi -Uri $uri -Method Patch -Body $linkOperation
        
        Write-LogMessage "Successfully added link: $Url" -Level INFO
        return $result
    }
    catch {
        Write-LogMessage "Failed to add link: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Add-AzureDevOpsRepoLink {
    <#
    .SYNOPSIS
    Links a Git branch to a work item's Development section via ArtifactLink.
    This populates the "Development" panel in Azure DevOps (commits, branches).
    .PARAMETER WorkItemId
    The work item to link.
    .PARAMETER Branch
    Git branch name (e.g. "main"). Defaults to current branch.
    .PARAMETER RepoName
    Repository name in Azure DevOps. Defaults to config repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WorkItemId,

        [string]$Branch,

        [string]$RepoName
    )

    try {
        $config = Get-AzureDevOpsConfig

        if (-not $Branch) {
            $Branch = git branch --show-current 2>$null
            if (-not $Branch) { $Branch = "main" }
        }

        if (-not $RepoName) {
            $RepoName = $config.Repository
        }

        Write-LogMessage "Looking up repository '$($RepoName)' for branch link..." -Level INFO

        $repoUri = "$($config.ProjectUrl)/_apis/git/repositories/$($RepoName)?api-version=$($config.ApiVersion)"
        $repo = Invoke-AzureDevOpsApi -Uri $repoUri -Method Get

        if (-not $repo -or -not $repo.id) {
            Write-LogMessage "Repository '$($RepoName)' not found in Azure DevOps" -Level ERROR
            return $null
        }

        $projectId = $repo.project.id
        $repoId    = $repo.id

        # vstfs artifact URL format for a Git branch ref
        # Pattern: vstfs:///Git/Ref/{projectId}%2F{repoId}%2FGB{branchName}
        $encodedBranch = [Uri]::EscapeDataString("GB$Branch")
        $artifactUrl = "vstfs:///Git/Ref/$($projectId)%2F$($repoId)%2F$($encodedBranch)"

        $wi = Get-AzureDevOpsWorkItem -WorkItemId $WorkItemId
        if ($wi.relations) {
            $existing = $wi.relations | Where-Object {
                $_.rel -eq 'ArtifactLink' -and $_.url -like 'vstfs:///Git/Ref/*'
            }
            if ($existing) {
                Write-LogMessage "Branch link already exists on WI-$($WorkItemId) — skipping" -Level INFO
                return $null
            }
        }

        Write-LogMessage "Linking branch '$($Branch)' (repo: $($RepoName)) to WI-$($WorkItemId)..." -Level INFO

        $linkOperation = @(
            @{
                op    = "add"
                path  = "/relations/-"
                value = @{
                    rel        = "ArtifactLink"
                    url        = $artifactUrl
                    attributes = @{
                        name = "Branch"
                    }
                }
            }
        )

        $uri = "$($config.ProjectUrl)/_apis/wit/workitems/$($WorkItemId)?api-version=$($config.ApiVersion)"
        $result = Invoke-AzureDevOpsApi -Uri $uri -Method Patch -Body $linkOperation

        Write-LogMessage "Successfully linked branch '$($Branch)' to WI-$($WorkItemId)" -Level INFO
        return $result
    }
    catch {
        if ($_.Exception.Message -match 'already exists|VS403466|TF237124|400') {
            Write-LogMessage "Branch link likely already exists on WI-$($WorkItemId) — skipping" -Level INFO
            return $null
        }
        Write-LogMessage "Failed to add repo link: $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

function Add-AzureDevOpsSubtask {
    <#
    .SYNOPSIS
    Creates a child work item (Task or Bug) under a parent work item
    .PARAMETER Type
    The work item type to create. Defaults to Task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ParentId,
        
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [string]$Description,
        [string]$AssignedTo,

        [ValidateSet('Task', 'Bug')]
        [string]$Type = 'Task'
    )
    
    try {
        Write-LogMessage "Creating $($Type): $Title..." -Level INFO
        
        $config = Get-AzureDevOpsConfig
        $parent = Get-AzureDevOpsWorkItem -WorkItemId $ParentId

        $patchDoc = @(
            @{ op = "add"; path = "/fields/System.Title"; value = $Title }
        )

        if ($Description) {
            $patchDoc += @{ op = "add"; path = "/fields/System.Description"; value = $Description }
        }
        if ($parent.fields.'System.AreaPath') {
            $patchDoc += @{ op = "add"; path = "/fields/System.AreaPath"; value = $parent.fields.'System.AreaPath' }
        }
        if ($parent.fields.'System.IterationPath') {
            $patchDoc += @{ op = "add"; path = "/fields/System.IterationPath"; value = $parent.fields.'System.IterationPath' }
        }
        if ($AssignedTo) {
            $patchDoc += @{ op = "add"; path = "/fields/System.AssignedTo"; value = $AssignedTo }
        }

        $escapedType = [Uri]::EscapeDataString($Type)
        $createUri = "$($config.ProjectUrl)/_apis/wit/workitems/`$$($escapedType)?api-version=$($config.ApiVersion)"
        $task = Invoke-AzureDevOpsApi -Uri $createUri -Method Post -Body $patchDoc

        Write-LogMessage "Linking $Type to parent..." -Level INFO

        $linkDoc = @(
            @{
                op    = "add"
                path  = "/relations/-"
                value = @{
                    rel = "System.LinkTypes.Hierarchy-Reverse"
                    url = "$($config.ProjectUrl)/_apis/wit/workItems/$ParentId"
                }
            }
        )
        $linkUri = "$($config.ProjectUrl)/_apis/wit/workitems/$($task.id)?api-version=$($config.ApiVersion)"
        try {
            Invoke-AzureDevOpsApi -Uri $linkUri -Method Patch -Body $linkDoc | Out-Null
        }
        catch {
            Write-LogMessage "Warning: Failed to link $Type to parent — $($_.Exception.Message)" -Level WARN
        }
        
        Write-LogMessage "Successfully created $Type $($task.id)" -Level INFO
        Write-LogMessage "URL: $($config.ProjectUrl)/_workitems/edit/$($task.id)" -Level INFO
        
        return $task
    }
    catch {
        Write-LogMessage "Failed to create $($Type): $($_.Exception.Message)" -Level ERROR -Exception $_
        throw
    }
}

#endregion

#region Interactive Menu

function Show-WorkItemDetails {
    param([object]$WorkItem)
    
    Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Work Item Details" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "ID:          " -NoNewline -ForegroundColor Yellow
    Write-Host $WorkItem.id
    Write-Host "Type:        " -NoNewline -ForegroundColor Yellow
    Write-Host $WorkItem.fields.'System.WorkItemType'
    Write-Host "Title:       " -NoNewline -ForegroundColor Yellow
    Write-Host $WorkItem.fields.'System.Title'
    Write-Host "State:       " -NoNewline -ForegroundColor Yellow
    Write-Host $WorkItem.fields.'System.State'
    Write-Host "Assigned To: " -NoNewline -ForegroundColor Yellow
    Write-Host $(if ($WorkItem.fields.'System.AssignedTo') { $WorkItem.fields.'System.AssignedTo'.displayName } else { "Unassigned" })
    Write-Host "Tags:        " -NoNewline -ForegroundColor Yellow
    Write-Host $(if ($WorkItem.fields.'System.Tags') { $WorkItem.fields.'System.Tags' } else { "None" })
    
    if ($WorkItem.fields.'System.Description') {
        Write-Host "`nDescription:" -ForegroundColor Yellow
        $cleanDesc = $WorkItem.fields.'System.Description' -replace '<[^>]+>', ''
        Write-Host $cleanDesc.Trim()
    }
    
    Write-Host "`nURL: " -NoNewline -ForegroundColor Yellow
    $config = Get-AzureDevOpsConfig
    Write-Host "$($config.ProjectUrl)/_workitems/edit/$($WorkItem.id)" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

function Show-InteractiveMenu {
    $config = Get-AzureDevOpsConfig
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Azure DevOps User Story Manager - Interactive Mode           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Organization: $($config.Organization)" -ForegroundColor Gray
    Write-Host "Project:      $($config.Project)" -ForegroundColor Gray
    
    $workItemId = Read-Host "`nEnter Work Item ID"
    
    if (![int]::TryParse($workItemId, [ref]$null)) {
        Write-Host "Invalid work item ID" -ForegroundColor Red
        return
    }
    
    # Get work item
    try {
        $workItem = Get-AzureDevOpsWorkItem -WorkItemId $workItemId
        Show-WorkItemDetails -WorkItem $workItem
    }
    catch {
        Write-Host "Failed to retrieve work item" -ForegroundColor Red
        return
    }
    
    $continue = $true
    while ($continue) {
        Write-Host "`n┌──────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "│  What would you like to do?          │" -ForegroundColor Yellow
        Write-Host "└──────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host "1. Update Description"
        Write-Host "2. Add Comment"
        Write-Host "3. Attach File"
        Write-Host "4. Add Repository Link"
        Write-Host "5. Add Hyperlink"
        Write-Host "6. Change Status"
        Write-Host "7. Add Tags"
        Write-Host "8. Create Subtask"
        Write-Host "9. Refresh / View Details"
        Write-Host "0. Exit"
        
        $choice = Read-Host "`nSelect option"
        
        switch ($choice) {
            "1" {
                $newDesc = Read-Host "Enter new description"
                Update-AzureDevOpsWorkItem -WorkItemId $workItemId -Fields @{"System.Description" = $newDesc }
            }
            "2" {
                $comment = Read-Host "Enter comment"
                Add-AzureDevOpsComment -WorkItemId $workItemId -Comment $comment
            }
            "3" {
                $filePath = Read-Host "Enter file path"
                if (Test-Path $filePath) {
                    Add-AzureDevOpsAttachment -WorkItemId $workItemId -FilePath $filePath
                }
                else {
                    Write-Host "File not found" -ForegroundColor Red
                }
            }
            "4" {
                $repoPath = Read-Host "Enter repository file path (e.g., DevTools/Script.ps1)"
                $linkComment = Read-Host "Enter comment (optional)"
                Add-AzureDevOpsLink -WorkItemId $workItemId -Url $repoPath -LinkComment $linkComment
            }
            "5" {
                $url = Read-Host "Enter URL"
                $urlComment = Read-Host "Enter comment (optional)"
                Add-AzureDevOpsLink -WorkItemId $workItemId -Url $url -LinkComment $urlComment
            }
            "6" {
                Write-Host "`nAvailable states: New, Active, Resolved, Closed"
                $newState = Read-Host "Enter new state"
                Set-AzureDevOpsWorkItemState -WorkItemId $workItemId -State $newState
            }
            "7" {
                $currentTags = $workItem.fields.'System.Tags'
                Write-Host "Current tags: $currentTags" -ForegroundColor Gray
                $newTags = Read-Host "Enter tags (semicolon-separated, e.g., Tag1;Tag2)"
                Update-AzureDevOpsWorkItem -WorkItemId $workItemId -Fields @{"System.Tags" = $newTags }
            }
            "8" {
                $taskTitle = Read-Host "Enter subtask title"
                $taskDesc = Read-Host "Enter subtask description (optional)"
                Add-AzureDevOpsSubtask -ParentId $workItemId -Title $taskTitle -Description $taskDesc
            }
            "9" {
                $workItem = Get-AzureDevOpsWorkItem -WorkItemId $workItemId
                Show-WorkItemDetails -WorkItem $workItem
            }
            "0" {
                $continue = $false
                Write-Host "`nGoodbye!" -ForegroundColor Green
            }
            default {
                Write-Host "Invalid option" -ForegroundColor Red
            }
        }
        
        if ($continue -and $choice -ne "9") {
            Start-Sleep -Seconds 1
        }
    }
}

#endregion

#region Command-Line Execution

function Invoke-CommandLineAction {
    param(
        [int]$WorkItemId,
        [string]$Action,
        [hashtable]$Params
    )
    
    switch ($Action) {
        "Get" {
            $workItem = Get-AzureDevOpsWorkItem -WorkItemId $WorkItemId
            Show-WorkItemDetails -WorkItem $workItem
        }
        "Update" {
            if ($Params.Description) {
                $fields = @{"System.Description" = $Params.Description }
                Update-AzureDevOpsWorkItem -WorkItemId $WorkItemId -Fields $fields
            }
            else {
                Write-LogMessage "No description provided for update" -Level ERROR
            }
        }
        "Comment" {
            if ($Params.Comment) {
                Add-AzureDevOpsComment -WorkItemId $WorkItemId -Comment $Params.Comment
            }
            else {
                Write-LogMessage "No comment text provided" -Level ERROR
            }
        }
        "Attach" {
            if ($Params.FilePath -and (Test-Path $Params.FilePath)) {
                Add-AzureDevOpsAttachment -WorkItemId $WorkItemId -FilePath $Params.FilePath
            }
            else {
                Write-LogMessage "Invalid file path" -Level ERROR
            }
        }
        "Link" {
            if ($Params.Url) {
                Add-AzureDevOpsLink -WorkItemId $WorkItemId -Url $Params.Url -LinkComment $Params.Title
            }
            else {
                Write-LogMessage "No URL or path provided" -Level ERROR
            }
        }
        "RepoLink" {
            $branch = if ($Params.Url) { $Params.Url } else { $null }
            $repoName = if ($Params.Title) { $Params.Title } else { $null }
            Add-AzureDevOpsRepoLink -WorkItemId $WorkItemId -Branch $branch -RepoName $repoName
        }
        "Status" {
            if ($Params.State) {
                Set-AzureDevOpsWorkItemState -WorkItemId $WorkItemId -State $Params.State
            }
            else {
                Write-LogMessage "No state provided" -Level ERROR
            }
        }
        "Subtask" {
            if ($Params.Title) {
                Add-AzureDevOpsSubtask -ParentId $WorkItemId -Title $Params.Title -Description $Params.Description -AssignedTo $Params.AssignedTo
            }
            else {
                Write-LogMessage "No title provided for subtask" -Level ERROR
            }
        }
        "AddTags" {
            if ($Params.Tags) {
                Update-AzureDevOpsWorkItem -WorkItemId $WorkItemId -Fields @{"System.Tags" = $Params.Tags }
            }
            else {
                Write-LogMessage "No tags provided" -Level ERROR
            }
        }
        default {
            Write-LogMessage "Unknown action: $Action" -Level ERROR
        }
    }
}

#endregion

#region Main Execution

try {
    Write-LogMessage "Azure DevOps User Story Manager starting..." -Level INFO
    
    # Initialize Azure CLI
    $cliInitialized = Initialize-AzureCli
    
    if (-not $cliInitialized) {
        Write-LogMessage "Failed to initialize Azure CLI. Please ensure:" -Level ERROR
        Write-LogMessage "1. Azure CLI is installed: winget install Microsoft.AzureCLI" -Level ERROR
        Write-LogMessage "2. Azure DevOps extension: az extension add --name azure-devops" -Level ERROR
        Write-LogMessage "3. PAT token is valid in GlobalFunctions configuration" -Level ERROR
        exit 1
    }
    
    if ($PSCmdlet.ParameterSetName -eq 'Interactive' -or (-not $Action)) {
        # Interactive mode
        Show-InteractiveMenu
    }
    else {
        # Command-line mode
        if (-not $WorkItemId) {
            Write-LogMessage "WorkItemId is required for command-line operations" -Level ERROR
            exit 1
        }
        
        $params = @{
            Description = $Description
            Comment     = $Comment
            FilePath    = $FilePath
            Url         = $Url
            State       = $State
            Title       = $Title
            Tags        = $Tags
            AssignedTo  = $AssignedTo
        }
        
        Invoke-CommandLineAction -WorkItemId $WorkItemId -Action $Action -Params $params
    }
    
    Write-LogMessage "Operation completed successfully" -Level INFO
}
catch {
    Write-LogMessage "Error in Azure DevOps User Story Manager: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}

#endregion
