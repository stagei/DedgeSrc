# Azure DevOps User Story Manager - Analysis & Specification

**Date:** 2025-12-16  
**Status:** Planning Phase  
**Purpose:** Comprehensive script/tool for managing Azure DevOps User Stories with full CRUD operations

---

## Table of Contents
1. [Existing Code Analysis](#existing-code-analysis)
2. [Current Capabilities](#current-capabilities)
3. [Proposed Enhancements](#proposed-enhancements)
4. [Implementation Specification](#implementation-specification)
5. [Code Examples](#code-examples)
6. [Cursor Rule Recommendation](#cursor-rule-recommendation)
7. [API Reference](#api-reference)

---

## Existing Code Analysis

### Files Reviewed
| File | Purpose | Technology |
|------|---------|-----------|
| `Azure-DevOpsItemCreator.ps1` | Creates Epics, Stories, Tasks from JSON or parameters | Azure CLI (`az boards`) |
| `ImportTasksToAzureDevOps.ps1` | Imports server migration tasks via REST API | REST API (Invoke-RestMethod) |
| `Import-AllTasksToAzureDevOps.ps1` | Bulk import with Epic/Feature/Story hierarchy | Azure CLI (`az boards`) |

### Key Findings

#### ✅ **What Currently Works**
1. **Work Item Creation**
   - Epics, Features, User Stories, Tasks, Bugs
   - JSON-based batch creation
   - Direct parameter-based creation
   - Hierarchical parent-child relationships

2. **Relationship Management**
   - Parent-child hierarchy (Epic → Feature → Story → Task)
   - Dependency links (Predecessor/Successor)
   - Related links
   - Affects/Affected By relationships

3. **Field Management**
   - Title, Description
   - Area Path, Iteration Path
   - Tags
   - Assigned To
   - Custom fields via API

4. **Authentication Methods**
   - Azure CLI authentication (`az login`)
   - Personal Access Token (PAT) via REST API
   - Base64 encoded PAT in headers

#### ❌ **What's Missing**
1. **Update Operations**
   - No ability to update existing work items by ID
   - No status/state transitions
   - No field updates for existing items

2. **Comment Management**
   - No discussion/comment functionality
   - Cannot add work item comments programmatically

3. **Attachment Handling**
   - No file upload capability
   - No document attachment to work items

4. **Advanced Querying**
   - Limited work item retrieval by ID
   - No bulk queries with filters
   - No search by custom criteria

5. **Link Management**
   - No Git commit/repository links
   - No hyperlink/external URL management
   - No artifact links

---

## Current Capabilities

### 1. **Creation Patterns**

#### Azure CLI Method
```powershell
az boards work-item create `
    --type "User Story" `
    --title "Story Title" `
    --assigned-to "user@domain.com" `
    --fields System.Description="Description" System.Tags="tag1;tag2" `
    --output json
```

#### REST API Method
```powershell
$headers = @{
    "Authorization" = "Basic $base64AuthInfo"
    "Content-Type"  = "application/json-patch+json"
}

$body = @(
    @{
        op    = "add"
        path  = "/fields/System.Title"
        value = "Story Title"
    },
    @{
        op    = "add"
        path  = "/fields/System.Description"
        value = "Story Description"
    }
) | ConvertTo-Json

$uri = "https://dev.azure.com/$org/$project/_apis/wit/workitems/`$User Story?api-version=6.0"
Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
```

### 2. **Relationship Creation**
```powershell
# Parent relationship
az boards work-item relation add `
    --id $childId `
    --relation-type "parent" `
    --target-id $parentId `
    --output json

# Dependency relationship
az boards work-item relation add `
    --id $sourceId `
    --relation-type "Predecessor" `
    --target-id $targetId `
    --output json
```

### 3. **Query Pattern**
```powershell
az boards query `
    --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'User Story' AND [System.State] = 'Active'" `
    --output json
```

---

## Proposed Enhancements

### High Priority Features

#### 1. **Get User Story by ID**
```powershell
Get-AzureDevOpsUserStory -WorkItemId 12345
```
- Retrieves full work item details
- Returns all fields, relations, comments
- Optional: Include history, attachments

#### 2. **Update User Story Fields**
```powershell
Update-AzureDevOpsUserStory -WorkItemId 12345 `
    -Description "Updated description" `
    -Tags "NewTag;ExistingTag" `
    -IterationPath "Sprint 5"
```
- Update any field by name
- Validate field types
- Support custom fields

#### 3. **Change Work Item State**
```powershell
Set-AzureDevOpsWorkItemState -WorkItemId 12345 -State "Active"
Set-AzureDevOpsWorkItemState -WorkItemId 12345 -State "Resolved" -Reason "Fixed"
```
- Support state transitions
- Validate state workflow
- Optional reason field

#### 4. **Add Comments**
```powershell
Add-AzureDevOpsComment -WorkItemId 12345 -Comment "Updated based on review feedback"
```
- Add discussion comments
- Support formatted text (HTML/Markdown)
- Return comment ID

#### 5. **Upload Attachments**
```powershell
Add-AzureDevOpsAttachment -WorkItemId 12345 -FilePath "C:\docs\requirements.pdf"
```
- Upload files to work items
- Support multiple file types
- Return attachment URL

#### 6. **Add Repository Links**
```powershell
Add-AzureDevOpsGitLink -WorkItemId 12345 `
    -Repository "DedgePsh" `
    -FilePath "DevTools/Script.ps1" `
    -Branch "main"
```
- Link to specific files in repo
- Link to commits
- Link to pull requests

#### 7. **Add Hyperlinks**
```powershell
Add-AzureDevOpsHyperlink -WorkItemId 12345 `
    -Url "https://confluence.company.com/page" `
    -Comment "Related documentation"
```
- Add external URL links
- Optional comment/description

#### 8. **Add Subtasks**
```powershell
Add-AzureDevOpsSubtask -ParentId 12345 `
    -Title "Subtask Title" `
    -Description "Subtask Description"
```
- Create child task automatically
- Link to parent
- Inherit area/iteration from parent

---

## Implementation Specification

### Script Structure

```powershell
# Azure-DevOpsUserStoryManager.ps1
# Comprehensive User Story management for Azure DevOps

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Organization,
    
    [Parameter(Mandatory=$false)]
    [string]$Project,
    
    [Parameter(Mandatory=$false)]
    [string]$Pat
)

Import-Module GlobalFunctions -Force

# === CONFIGURATION === #

function Get-AzureDevOpsConfig {
    return @{
        Organization = $Organization ?? (Get-AzureDevOpsOrganization)
        Project      = $Project ?? (Get-AzureDevOpsProject) 
        Pat          = $Pat ?? (Get-AzureDevOpsPat)
        BaseUrl      = "https://dev.azure.com"
        ApiVersion   = "7.0"
    }
}

function Get-AzureDevOpsHeaders {
    param([string]$Pat)
    
    $base64Auth = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes(":$Pat")
    )
    
    return @{
        "Authorization" = "Basic $base64Auth"
        "Content-Type"  = "application/json-patch+json"
    }
}

# === CORE FUNCTIONS === #

function Get-AzureDevOpsWorkItem {
    <#
    .SYNOPSIS
    Retrieves a work item by ID
    
    .PARAMETER WorkItemId
    The ID of the work item to retrieve
    
    .PARAMETER IncludeComments
    Include all comments/discussions
    
    .PARAMETER IncludeAttachments
    Include attachment metadata
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [switch]$IncludeComments,
        [switch]$IncludeAttachments
    )
    
    # Implementation here
}

function Update-AzureDevOpsWorkItem {
    <#
    .SYNOPSIS
    Updates fields in an existing work item
    
    .PARAMETER WorkItemId
    The ID of the work item to update
    
    .PARAMETER Fields
    Hashtable of fields to update
    
    .EXAMPLE
    Update-AzureDevOpsWorkItem -WorkItemId 12345 -Fields @{
        "System.Description" = "Updated description"
        "System.Tags" = "Tag1;Tag2"
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Fields
    )
    
    # Implementation here
}

function Set-AzureDevOpsWorkItemState {
    <#
    .SYNOPSIS
    Changes the state of a work item
    
    .PARAMETER WorkItemId
    The ID of the work item
    
    .PARAMETER State
    The new state (e.g., "Active", "Resolved", "Closed")
    
    .PARAMETER Reason
    Optional reason for state change
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("New", "Active", "Resolved", "Closed", "Removed")]
        [string]$State,
        
        [string]$Reason
    )
    
    # Implementation here
}

function Add-AzureDevOpsComment {
    <#
    .SYNOPSIS
    Adds a comment to a work item
    
    .PARAMETER WorkItemId
    The ID of the work item
    
    .PARAMETER Comment
    The comment text (supports HTML)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory=$true)]
        [string]$Comment
    )
    
    # Implementation here
}

function Add-AzureDevOpsAttachment {
    <#
    .SYNOPSIS
    Uploads and attaches a file to a work item
    
    .PARAMETER WorkItemId
    The ID of the work item
    
    .PARAMETER FilePath
    Path to the file to upload
    
    .PARAMETER Comment
    Optional comment for the attachment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_})]
        [string]$FilePath,
        
        [string]$Comment
    )
    
    # Implementation here
}

function Add-AzureDevOpsGitLink {
    <#
    .SYNOPSIS
    Adds a link to a file in the repository
    
    .PARAMETER WorkItemId
    The ID of the work item
    
    .PARAMETER Repository
    Repository name
    
    .PARAMETER FilePath
    Path to file in repository
    
    .PARAMETER Branch
    Branch name (default: main)
    
    .PARAMETER CommitId
    Optional specific commit ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory=$true)]
        [string]$Repository,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [string]$Branch = "main",
        [string]$CommitId
    )
    
    # Implementation here
}

function Add-AzureDevOpsHyperlink {
    <#
    .SYNOPSIS
    Adds an external hyperlink to a work item
    
    .PARAMETER WorkItemId
    The ID of the work item
    
    .PARAMETER Url
    The URL to link
    
    .PARAMETER Comment
    Optional description of the link
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^https?://')]
        [string]$Url,
        
        [string]$Comment
    )
    
    # Implementation here
}

function Add-AzureDevOpsSubtask {
    <#
    .SYNOPSIS
    Creates a subtask under a parent work item
    
    .PARAMETER ParentId
    The ID of the parent work item
    
    .PARAMETER Title
    Title of the subtask
    
    .PARAMETER Description
    Description of the subtask
    
    .PARAMETER AssignedTo
    User to assign the subtask to
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$ParentId,
        
        [Parameter(Mandatory=$true)]
        [string]$Title,
        
        [string]$Description,
        [string]$AssignedTo
    )
    
    # Implementation here
}

# Export functions
Export-ModuleMember -Function *
```

---

## Code Examples

### Example 1: Complete User Story Update Workflow

```powershell
# Get work item ID
$storyId = 12345

# 1. Update description and tags
Update-AzureDevOpsWorkItem -WorkItemId $storyId -Fields @{
    "System.Description" = "Updated requirements based on stakeholder feedback"
    "System.Tags" = "Sprint5;HighPriority;NeedsReview"
    "Microsoft.VSTS.Common.Priority" = "1"
}

# 2. Add a comment
Add-AzureDevOpsComment -WorkItemId $storyId `
    -Comment "Updated description and priority after meeting with stakeholders"

# 3. Upload documentation
Add-AzureDevOpsAttachment -WorkItemId $storyId `
    -FilePath "C:\docs\requirements.pdf" `
    -Comment "Updated requirements document"

# 4. Link to code in repository
Add-AzureDevOpsGitLink -WorkItemId $storyId `
    -Repository "DedgePsh" `
    -FilePath "DevTools/NewFeature/Implementation.ps1" `
    -Branch "feature/user-story-12345"

# 5. Add external documentation link
Add-AzureDevOpsHyperlink -WorkItemId $storyId `
    -Url "https://confluence.company.com/requirements/feature-spec" `
    -Comment "Detailed feature specification"

# 6. Add implementation subtasks
Add-AzureDevOpsSubtask -ParentId $storyId `
    -Title "Implement backend logic" `
    -Description "Create PowerShell functions for core functionality" `
    -AssignedTo "developer@company.com"

Add-AzureDevOpsSubtask -ParentId $storyId `
    -Title "Add unit tests" `
    -Description "Create Pester tests for new functions" `
    -AssignedTo "developer@company.com"

Add-AzureDevOpsSubtask -ParentId $storyId `
    -Title "Update documentation" `
    -Description "Update README and add examples" `
    -AssignedTo "developer@company.com"

# 7. Change state to Active
Set-AzureDevOpsWorkItemState -WorkItemId $storyId `
    -State "Active" `
    -Reason "Implementation started"
```

### Example 2: Batch Operations from JSON

```powershell
# Define updates in JSON
$updates = @{
    WorkItemId = 12345
    Updates = @{
        Description = "New description"
        Tags = @("Tag1", "Tag2", "Tag3")
        State = "Active"
    }
    Comments = @(
        "Started implementation",
        "Updated based on review"
    )
    Attachments = @(
        "C:\docs\spec.pdf",
        "C:\docs\design.png"
    )
    Links = @{
        Git = @{
            Repository = "DedgePsh"
            FilePath = "DevTools/Script.ps1"
        }
        Hyperlinks = @(
            @{
                Url = "https://docs.company.com"
                Comment = "Documentation"
            }
        )
    }
}

# Execute batch update
Invoke-AzureDevOpsBatchUpdate -UpdateObject $updates
```

---

## API Reference

### REST API Endpoints

#### Work Item Operations
```
GET    https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.0
PATCH  https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.0
```

#### Comments
```
GET    https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}/comments?api-version=7.0
POST   https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}/comments?api-version=7.0
```

#### Attachments
```
# Step 1: Upload file
POST   https://dev.azure.com/{org}/{project}/_apis/wit/attachments?fileName={name}&api-version=7.0
Content-Type: application/octet-stream
Body: [binary file data]

# Step 2: Link to work item
PATCH  https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.0
Body: [
    {
        "op": "add",
        "path": "/relations/-",
        "value": {
            "rel": "AttachedFile",
            "url": "{attachment-url-from-step-1}",
            "attributes": {
                "comment": "File description"
            }
        }
    }
]
```

#### Links
```
# Add Git commit link
PATCH  https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.0
Body: [
    {
        "op": "add",
        "path": "/relations/-",
        "value": {
            "rel": "ArtifactLink",
            "url": "vstfs:///Git/Commit/{projectId}%2F{repositoryId}%2F{commitId}",
            "attributes": {
                "name": "Fixed in Commit"
            }
        }
    }
]

# Add hyperlink
Body: [
    {
        "op": "add",
        "path": "/relations/-",
        "value": {
            "rel": "Hyperlink",
            "url": "https://external.site.com/page",
            "attributes": {
                "comment": "Link description"
            }
        }
    }
]
```

#### State Transitions
```
PATCH  https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}?api-version=7.0
Body: [
    {
        "op": "add",
        "path": "/fields/System.State",
        "value": "Active"
    },
    {
        "op": "add",
        "path": "/fields/System.Reason",
        "value": "Implementation started"
    }
]
```

### Azure CLI Commands

```powershell
# Get work item
az boards work-item show --id 12345 --output json

# Update work item
az boards work-item update --id 12345 `
    --fields System.State="Active" System.Tags="Tag1;Tag2" `
    --output json

# Add relation
az boards work-item relation add --id 12345 `
    --relation-type "parent" `
    --target-id 11111 `
    --output json

# Query work items
az boards query --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.State] = 'Active'"
```

---

## Cursor Rule Recommendation

### Proposed `.cursorrules` Addition

```markdown
## Azure DevOps Work Item Management

When working with Azure DevOps work items in PowerShell:

### Script Structure
- Import GlobalFunctions for common configuration
- Use Get-AzureDevOpsOrganization, Get-AzureDevOpsProject, Get-AzureDevOpsPat
- Prefer REST API over Azure CLI for complex operations
- Use Azure CLI for simple queries and standard operations

### REST API Patterns
- Always use API version 7.0 or latest stable
- Base64 encode PAT: `[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))`
- Use JSON Patch format for updates:
  ```json
  [
    {
      "op": "add",
      "path": "/fields/System.FieldName",
      "value": "Value"
    }
  ]
  ```

### Work Item Operations
- **Create**: Use `az boards work-item create` or POST to `/_apis/wit/workitems/`
- **Update**: Use PATCH with JSON Patch operations
- **Get**: Use `az boards work-item show` or GET from `/_apis/wit/workitems/{id}`
- **Delete**: Use `az boards work-item delete`

### Field Naming
- System fields: `System.Title`, `System.Description`, `System.State`, `System.Tags`
- VSTS fields: `Microsoft.VSTS.Common.Priority`, `Microsoft.VSTS.Common.AcceptanceCriteria`
- Tags: Semicolon-separated string (e.g., "Tag1;Tag2;Tag3")
- State values: "New", "Active", "Resolved", "Closed", "Removed"

### Relationships
- Parent/Child: Use `--relation-type "parent"` 
- Dependencies: Use "Predecessor" (must finish before) or "Successor" (starts after)
- Related: Use "Related" for general associations
- Git Links: Use ArtifactLink with vstfs URL format

### Attachments
1. Upload file to `/_apis/wit/attachments` (returns URL)
2. Add relation to work item using returned URL with rel="AttachedFile"

### Comments
- POST to `/_apis/wit/workItems/{id}/comments`
- Supports HTML formatting in text

### Error Handling
- Always validate work item ID exists before operations
- Check state transition validity
- Validate field names and types
- Log all API errors with full details

### Logging
- Use Write-LogMessage for all operations
- Log work item URLs for easy access: `https://dev.azure.com/{org}/{project}/_workitems/edit/{id}`
- Include operation type (CREATE, UPDATE, DELETE) in logs

### Example Function Template
```powershell
function Update-AzureDevOpsWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$WorkItemId,
        
        [hashtable]$Fields
    )
    
    $config = Get-AzureDevOpsConfig
    $headers = Get-AzureDevOpsHeaders -Pat $config.Pat
    
    $operations = $Fields.GetEnumerator() | ForEach-Object {
        @{
            op = "add"
            path = "/fields/$($_.Key)"
            value = $_.Value
        }
    }
    
    $body = $operations | ConvertTo-Json -Depth 10
    $uri = "$($config.BaseUrl)/$($config.Organization)/$($config.Project)/_apis/wit/workitems/$($WorkItemId)?api-version=$($config.ApiVersion)"
    
    try {
        $result = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body
        Write-LogMessage "Updated work item $WorkItemId" -Level INFO
        return $result
    }
    catch {
        Write-LogMessage "Failed to update work item $WorkItemId" -Level ERROR -Exception $_
        throw
    }
}
```
```

---

## Implementation Recommendations

### Phase 1: Core Functions (Week 1)
- ✅ Get work item by ID
- ✅ Update work item fields
- ✅ Change state with validation
- ✅ Add comments

### Phase 2: Links & Relations (Week 2)
- ✅ Add Git repository links
- ✅ Add hyperlinks
- ✅ Add work item relations
- ✅ Create subtasks

### Phase 3: Attachments (Week 3)
- ✅ Upload files
- ✅ Attach to work items
- ✅ List attachments
- ✅ Download attachments

### Phase 4: Advanced Features (Week 4)
- ✅ Batch operations
- ✅ JSON configuration support
- ✅ Query builder
- ✅ Template system
- ✅ Validation and error recovery

### Phase 5: Testing & Documentation
- ✅ Unit tests with Pester
- ✅ Integration tests
- ✅ README documentation
- ✅ Example scripts
- ✅ Video tutorials

---

## Testing Strategy

### Unit Tests
```powershell
Describe "Azure-DevOpsUserStoryManager" {
    Context "Get-AzureDevOpsWorkItem" {
        It "Should retrieve work item by ID" {
            $result = Get-AzureDevOpsWorkItem -WorkItemId 12345
            $result.id | Should -Be 12345
            $result.fields.'System.Title' | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Update-AzureDevOpsWorkItem" {
        It "Should update work item description" {
            $result = Update-AzureDevOpsWorkItem -WorkItemId 12345 -Fields @{
                "System.Description" = "Test description"
            }
            $result.fields.'System.Description' | Should -Be "Test description"
        }
    }
}
```

### Integration Tests
- Test against real Azure DevOps instance
- Use dedicated test project
- Clean up test work items after tests
- Validate API rate limits

---

## Security Considerations

1. **PAT Storage**
   - Never hardcode PATs in scripts
   - Use GlobalFunctions configuration
   - Store in secure credential manager
   - Rotate PATs regularly

2. **Permissions**
   - Minimum required: Work Items (Read, Write & Manage)
   - Optional: Code (Read) for Git links
   - Optional: Project and Team (Read) for area/iteration paths

3. **Input Validation**
   - Validate all work item IDs
   - Sanitize file paths
   - Validate URLs before adding links
   - Check file sizes before upload

4. **Audit Logging**
   - Log all operations with timestamps
   - Include user context
   - Track API usage
   - Monitor for errors

---

## Success Metrics

- ✅ 100% coverage of Azure DevOps Work Item API
- ✅ All CRUD operations supported
- ✅ Comprehensive error handling
- ✅ Full Pester test suite
- ✅ Complete documentation
- ✅ Performance: <2 seconds per operation
- ✅ Zero hardcoded credentials

---

## Next Steps

1. **Create base module structure**
   - Create folder: `DevTools/AdminTools/Azure-DevOpsUserStoryManager`
   - Create main script
   - Add parameter validation

2. **Implement Phase 1 functions**
   - Start with Get and Update operations
   - Add comprehensive logging
   - Write unit tests

3. **Create example scripts**
   - Common workflows
   - Batch operations
   - Error scenarios

4. **Documentation**
   - Function help
   - README with examples
   - API reference guide

5. **Testing**
   - Unit tests
   - Integration tests
   - Load testing

---

## References

- [Azure DevOps REST API Documentation](https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/)
- [Azure CLI Boards Reference](https://learn.microsoft.com/en-us/cli/azure/boards/)
- [Work Item Field Reference](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/guidance/work-item-field)
- [Azure DevOps Work Item Types](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/about-work-items)

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-16  
**Author:** AI Assistant via Cursor  
**Review Status:** Ready for Implementation
