# Cursor Rules for Azure DevOps User Story Management

Add this section to your `.cursorrules` file to enable seamless Azure DevOps work item updates during development.

```markdown
## Azure DevOps Work Item Management

When I complete work, fix bugs, or update features related to Azure DevOps user stories, automatically update the work items using this tool.

### Tool Location
```
C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager\Azure-DevOpsUserStoryManager.ps1
```

### Automatic Actions

#### When I say "update user story <ID>"
Execute these steps based on context:

1. **If I completed implementation:**
   - Update description with summary
   - Add comment about what was done
   - Link all modified code files
   - Change status to "Resolved"
   
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Update -Description "<summary>"
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Comment -Comment "Implementation completed: <details>"
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Link -Url "<file-path>" -Title "Implementation"
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Status -State "Resolved"
   ```

2. **If I started work:**
   - Add comment that work has started
   - Change status to "Active"
   
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Comment -Comment "Started implementation"
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Status -State "Active"
   ```

3. **If I'm documenting:**
   - Attach any PDF/docs I created
   - Add comment about documentation
   
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Attach -FilePath "<file-path>"
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Comment -Comment "Added documentation"
   ```

4. **If I need to create subtasks:**
   - Create subtasks for testing, documentation, review
   
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId <ID> -Action Subtask -Title "<task-title>" -Description "<description>"
   ```

### Command Reference

| Action | Command |
|--------|---------|
| Get details | `-Action Get` |
| Update description | `-Action Update -Description "text"` |
| Add comment | `-Action Comment -Comment "text"` |
| Attach file | `-Action Attach -FilePath "path"` |
| Link code | `-Action Link -Url "DevTools/File.ps1"` |
| Link URL | `-Action Link -Url "https://..."` |
| Change status | `-Action Status -State "Active/Resolved/Closed"` |
| Add tags | `-Action AddTags -Tags "Tag1;Tag2"` |
| Create subtask | `-Action Subtask -Title "title" -Description "desc"` |

### Smart Context Detection

**Detect work item ID from:**
- Branch names (e.g., `feature/12345-feature-name` → ID: 12345)
- Commit messages (e.g., `"Fix #12345: Bug description"` → ID: 12345)
- File comments (e.g., `# Related to work item 12345`)
- User mentions (e.g., "This fixes story 12345")

**Auto-detect actions based on:**
- File changes: Link modified files to work item
- New documentation: Attach PDF/MD files
- Test files created: Create testing subtask
- README updates: Add documentation comment

### Example Workflows

#### Workflow 1: Feature Implementation Complete
**User says:** "I finished implementing the login feature for story 12345"

**Agent executes:**
```powershell
# Get current files in workspace
$files = git diff --name-only HEAD~1 HEAD

# Update description
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Update `
    -Description "Implemented login feature with OAuth2 support, error handling, and session management"

# Add completion comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment `
    -Comment "Implementation completed. Added OAuth2 authentication, session management, and comprehensive error handling."

# Link all modified files
foreach ($file in $files) {
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Link `
        -Url $file -Title "Implementation: $(Split-Path $file -Leaf)"
}

# Change to Resolved
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Status -State "Resolved"
```

#### Workflow 2: Start New Work
**User says:** "Starting work on story 12346"

**Agent executes:**
```powershell
# Add start comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Comment `
    -Comment "Starting implementation. Will include error handling and unit tests."

# Change to Active
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Status -State "Active"

# Create implementation subtasks
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Subtask `
    -Title "Implement core logic" `
    -Description "Create main PowerShell functions"

.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Subtask `
    -Title "Add unit tests" `
    -Description "Create Pester tests with 80% coverage"

.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Subtask `
    -Title "Update documentation" `
    -Description "Add README and inline comments"
```

#### Workflow 3: Documentation Added
**User says:** "I created requirements.pdf for story 12347"

**Agent executes:**
```powershell
# Find the PDF in workspace
$pdfPath = Get-ChildItem -Path . -Filter "requirements.pdf" -Recurse | Select-Object -First 1

# Attach document
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12347 -Action Attach `
    -FilePath $pdfPath.FullName

# Add comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12347 -Action Comment `
    -Comment "Added requirements documentation with detailed specifications and diagrams"
```

#### Workflow 4: Bug Fix
**User says:** "Fixed bug in story 12348"

**Agent executes:**
```powershell
# Get changed files
$files = git diff --name-only HEAD~1 HEAD

# Add fix comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12348 -Action Comment `
    -Comment "Bug fixed. Issue was in error handling logic. Added additional validation."

# Link fixed files
foreach ($file in $files) {
    .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12348 -Action Link `
        -Url $file -Title "Bug fix: $(Split-Path $file -Leaf)"
}

# Add tags
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12348 -Action AddTags `
    -Tags "BugFix;Tested;ReadyForDeploy"

# Close if testing confirms fix
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12348 -Action Status -State "Closed"
```

### Keywords That Trigger Actions

- **"update story/user story/work item <ID>"** → Full update workflow
- **"start working on <ID>"** → Set to Active, add comment
- **"finished/completed <ID>"** → Link files, set to Resolved
- **"closed/done with <ID>"** → Set to Closed
- **"add documentation to <ID>"** → Attach files
- **"link code to <ID>"** → Add repository links
- **"create subtasks for <ID>"** → Generate subtasks
- **"comment on <ID>: <text>"** → Add comment

### Best Practices

1. **Always link code:** When modifying files related to a work item, link them
2. **Update status:** Keep work item status current (Active during work, Resolved when done)
3. **Add context:** Comments should explain what was done and why
4. **Attach docs:** Any specifications, designs, or documentation should be attached
5. **Create subtasks:** Break down large stories into manageable subtasks
6. **Tag appropriately:** Use tags for easy filtering and reporting

### Error Handling

If any command fails:
1. Report the error clearly
2. Suggest manual intervention if needed
3. Continue with remaining operations
4. Provide the work item URL for manual updates

### State Transitions

Valid state transitions:
- New → Active (start work)
- Active → Resolved (work complete, pending review)
- Resolved → Closed (reviewed and approved)
- Active → Closed (work cancelled or rejected)
- Any → Removed (work item deleted)

Always use the most appropriate state for current work status.
```

---

## Usage Examples for Cursor AI

### Example 1: Simple Update
**User:** "Update work item 12345 that I fixed the login bug"

**Cursor AI generates:**
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment `
    -Comment "Fixed login bug: Added proper null checking for authentication token"
```

### Example 2: Complete Feature
**User:** "I completed the feature for story 12346, update it"

**Cursor AI generates:**
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager

# Update description
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Update `
    -Description "Feature implemented with full error handling, logging, and unit tests"

# Add comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Comment `
    -Comment "Feature complete and tested. Ready for review."

# Link implementation
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Link `
    -Url "DevTools/AdminTools/NewFeature.ps1" `
    -Title "Main Implementation"

# Change status
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12346 -Action Status -State "Resolved"
```

### Example 3: Documentation
**User:** "Attach the spec document to story 12347"

**Cursor AI generates:**
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12347 -Action Attach `
    -FilePath "C:\opt\src\DedgePsh\DevTools\Documentation\spec.pdf"
```

---

## Installation

1. Copy this content to your `.cursorrules` file
2. Adjust the script path if needed
3. Test with a simple command: "update work item 12345"
4. Cursor AI will now handle Azure DevOps updates automatically!
