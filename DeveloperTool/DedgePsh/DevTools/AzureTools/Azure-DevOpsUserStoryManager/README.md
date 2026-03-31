# Azure DevOps User Story Manager

**Comprehensive tool for managing Azure DevOps work items using Azure CLI with both interactive menu and command-line automation support.**

**Updated:** 2026-03-26
**Status:** Uses Azure CLI (`az boards`) for better reliability and authentication.

## Features

✅ **Get Work Item Details** - Retrieve full work item information  
✅ **Update Description** - Modify work item descriptions  
✅ **Add Comments** - Add discussion comments  
✅ **Attach Files** - Upload and attach documents  
✅ **Add Repository Links** - Link to code files in your repo  
✅ **Add Hyperlinks** - Link external URLs  
✅ **Change Status** - Update work item state (New → Active → Resolved → Closed)  
✅ **Add Tags** - Tag work items for organization  
✅ **Create Subtasks** - Add child work items under a parent story  

## Usage Modes

### Interactive Mode

Launch the interactive menu for guided operations:

```powershell
.\Azure-DevOpsUserStoryManager.ps1 -Interactive
```

**Features:**
- User-friendly menu interface
- View work item details
- Perform any operation step-by-step
- Real-time feedback

### Command-Line Mode

Perfect for automation, scripts, and Cursor AI integration:

#### Get Work Item Details
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Get
```

#### Update Description
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Update `
    -Description "Updated requirements based on stakeholder feedback"
```

#### Add Comment
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment `
    -Comment "Implementation completed and tested"
```

#### Attach File
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Attach `
    -FilePath "C:\docs\requirements.pdf"
```

#### Add Repository Link
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Link `
    -Url "DevTools/AzureTools/NewFeature/Implementation.ps1" `
    -Title "Implementation Code"
```

#### Add External Link
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Link `
    -Url "https://confluence.company.com/requirements" `
    -Title "Requirements Documentation"
```

#### Change Status
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Status `
    -State "Active"
```

Available states: `New`, `Active`, `Resolved`, `Closed`, `Removed`

#### Add Tags
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action AddTags `
    -Tags "Sprint5;HighPriority;NeedsReview"
```

#### Create Subtask
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Subtask `
    -Title "Create unit tests" `
    -Description "Add Pester tests for new functions" `
    -AssignedTo "developer@company.com"
```

> Note: `Subtask` creates child work items using the script subtask flow. The internal function supports both `Task` and `Bug` types, while command-line usage currently creates the default child type.

## Integration with Cursor AI

Add the following to your `.cursorrules` to enable seamless Azure DevOps integration:

```markdown
## Azure DevOps Work Item Updates

When I ask you to update an Azure DevOps user story, use this script:

**Script Location:** 
`C:\opt\src\DedgePsh\DevTools\AzureTools\Azure-DevOpsUserStoryManager\Azure-DevOpsUserStoryManager.ps1`

**Common Commands:**

1. **Update Description:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Update -Description "New description"
   ```

2. **Add Comment:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Comment -Comment "Comment text"
   ```

3. **Attach File:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Attach -FilePath "path\to\file.pdf"
   ```

4. **Link Code File:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Link -Url "DevTools/Script.ps1" -Title "Implementation"
   ```

5. **Change Status:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Status -State "Active"
   ```

6. **Add Subtask:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Subtask -Title "Task title" -Description "Task description"
   ```

**Workflow Example:**
When I complete work on a user story, automatically:
1. Add a comment summarizing changes
2. Link the implementation files
3. Attach any documentation
4. Change status to "Resolved"
```

## Example Workflow

Complete user story update with all features:

```powershell
$storyId = 12345

# 1. Update description
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action Update `
    -Description "Implemented new feature with full error handling and logging"

# 2. Add implementation comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action Comment `
    -Comment "Feature implemented and tested. Ready for review."

# 3. Link implementation files
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action Link `
    -Url "DevTools/AzureTools/NewFeature.ps1" `
    -Title "Main Implementation"

# 4. Attach documentation
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action Attach `
    -FilePath "C:\docs\FeatureSpec.pdf"

# 5. Add tags
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action AddTags `
    -Tags "Implemented;Tested;Sprint5"

# 6. Create test subtask
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action Subtask `
    -Title "Code Review" `
    -Description "Review implementation for best practices"

# 7. Change to Active
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $storyId -Action Status `
    -State "Active"
```

## Prerequisites

### Required Software

**1. Azure CLI (Required)**
```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI

# Install Azure DevOps extension
az extension add --name azure-devops --yes
```

**2. PowerShell Module**
- GlobalFunctions (for Azure DevOps configuration)

### Configuration

**PAT Management:**
- PAT setup is handled by: `DevTools/AzureTools/Azure-DevOpsPAT-Manager/`
- Run setup: `.\Azure-DevOpsPAT-Manager\Setup-AzureDevOpsPAT.ps1`
- PAT stored in: `C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json`

**This script uses GlobalFunctions to get:**
- `Get-AzureDevOpsOrganization` - Your organization name
- `Get-AzureDevOpsProject` - Your project name
- `Get-AzureDevOpsPat` - Your Personal Access Token (from user-specific file)
- `Get-AzureDevOpsRepository` - Your repository name

**User-Specific Configuration:**
- Each team member has their own PAT in separate file
- Email, SMS, and PAT are automatically selected based on `$env:USERNAME`
- Supported users: FKGEISTA, FKSVEERI, FKMISTA, FKCELERI
- PAT files: `C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json`
- See `TEAM-CONFIGURATION.md` for details

**Important:** The script now uses Azure CLI for all work item operations, with REST API only for comments and attachments. This provides better reliability and easier authentication management.

## Permissions Required

Your PAT needs these permissions:
- **Work Items:** Read, Write & Manage
- **Code:** Read (for repository links)

## Error Handling

The script includes comprehensive error handling:
- Validates work item IDs
- Checks file paths before upload
- Validates URLs
- Provides detailed error messages
- Logs all operations

## Logging

All operations are logged using `Write-LogMessage`:
- INFO: Successful operations
- ERROR: Failed operations with details
- DEBUG: Detailed operation info

Logs location: `C:\opt\data\AllPwshLog\<ComputerName>_<Date>.log`

## Examples for Cursor AI

### Example 1: Complete Implementation Update
**User:** "Update user story 12345 with the implementation details, link the code files, and mark as active"

**AI Response:**
```powershell
# Update description
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Update `
    -Description "Implemented feature X with error handling and logging"

# Link code
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Link `
    -Url "DevTools/AzureTools/FeatureX.ps1" `
    -Title "Implementation"

# Change status
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Status `
    -State "Active"
```

### Example 2: Add Documentation and Tests
**User:** "Add the requirements doc and create a testing subtask for story 12345"

**AI Response:**
```powershell
# Attach document
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Attach `
    -FilePath "C:\docs\requirements.pdf"

# Create test subtask
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Subtask `
    -Title "Create unit tests" `
    -Description "Add Pester tests covering all new functions"
```

### Example 3: Progress Update
**User:** "Add a progress comment to story 12345 about database integration"

**AI Response:**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment `
    -Comment "Database integration complete. All queries optimized and tested against production replica."
```

## Troubleshooting

### "Failed to initialize Azure CLI"
**Solution:**
1. Install Azure CLI: `winget install Microsoft.AzureCLI`
2. Install DevOps extension: `az extension add --name azure-devops --yes`
3. Restart PowerShell session

### "Failed to get Azure DevOps configuration"
- Ensure GlobalFunctions module is imported
- Check that configuration functions return valid values
- Verify PAT is not expired: https://dev.azure.com/Dedge/_usersSettings/tokens

### "Failed to retrieve work item" or "401 Unauthorized"
- **Most common:** PAT token has expired
- Run PAT setup: `cd ..\Azure-DevOpsPAT-Manager; .\Setup-AzureDevOpsPAT.ps1`
- Or manually generate: https://dev.azure.com/Dedge/_usersSettings/tokens
- Needs "Work Items: Read & Write" permissions
- Verify organization and project names are correct

### "Failed to attach file"
- Check file exists at specified path
- Verify file size isn't too large (max 60MB)
- Ensure PAT has work item write permissions

### Azure CLI Commands Not Working
- Run: `az login` to authenticate
- Set defaults: `az devops configure --defaults organization=... project=...`
- Verify PAT: `$env:AZURE_DEVOPS_EXT_PAT = (Get-AzureDevOpsPat)`

## Advanced Usage

### Batch Operations Script
```powershell
# Update multiple work items
$workItems = 12345, 12346, 12347

foreach ($id in $workItems) {
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $id -Action Comment `
        -Comment "Sprint completed - moving to next sprint"
    
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $id -Action Status `
        -State "Closed"
}
```

### Integration with Git Hooks
```powershell
# In git pre-commit hook
$commitFiles = git diff --cached --name-only

foreach ($file in $commitFiles) {
    # Extract work item ID from branch name
    $branch = git branch --show-current
    if ($branch -match 'feature/(\d+)') {
        $workItemId = $matches[1]
        
        # Link committed files
        .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $workItemId -Action Link `
            -Url $file `
            -Title "Modified in commit"
    }
}
```

## Support

For issues or questions:
1. Check logs: `C:\opt\data\AllPwshLog\`
2. Run in DEBUG mode: `$global:LogLevel = "DEBUG"`
3. Try interactive mode for guided troubleshooting

## Version History

- **v1.0** (2025-12-16)
  - Initial release
  - Interactive and command-line modes
  - Full CRUD operations
  - Comprehensive error handling
  - Cursor AI integration support

