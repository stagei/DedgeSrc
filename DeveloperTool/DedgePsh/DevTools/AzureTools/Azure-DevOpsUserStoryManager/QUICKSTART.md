# Quick Start Guide - Azure DevOps User Story Manager

Get started in 5 minutes! 🚀

**Now uses Azure CLI for better reliability!**

## 1. Install Azure CLI (Required)

```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI

# Install Azure DevOps extension
az extension add --name azure-devops --yes

# Restart PowerShell after installation
```

## 2. Prerequisites Check

```powershell
# Verify Azure CLI is installed
az --version

# Verify GlobalFunctions is available
Import-Module GlobalFunctions -Force

# Test Azure DevOps configuration
Get-AzureDevOpsOrganization
Get-AzureDevOpsProject
Get-AzureDevOpsPat
```

If any fail, configure in GlobalFunctions first.

## 3. Test Connection

```powershell
# Navigate to tool directory
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager

# Get a work item (replace 12345 with your work item ID)
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Get
```

**Note:** On first run, the script will automatically configure Azure CLI with your credentials.

## 4. Try Interactive Mode

```powershell
.\Azure-DevOpsUserStoryManager.ps1 -Interactive
```

Follow the prompts to:
- View work item details
- Update description
- Add comments
- Attach files
- Link code
- Change status

## 5. Try Command-Line Mode

```powershell
# Add a comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment `
    -Comment "Testing the new Azure DevOps manager tool!"

# Change status
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Status -State "Active"
```

## 6. Add to Cursor Rules

Copy from `CURSORRULES-EXAMPLE.md` to your `.cursorrules` file, then tell Cursor:

```
"Update work item 12345 with completion status"
```

Cursor will automatically generate and run the appropriate commands!

## Common Commands Cheat Sheet

```powershell
# Get details
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Get

# Update description
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Update `
    -Description "New description here"

# Add comment
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Comment `
    -Comment "Your comment here"

# Attach file
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Attach `
    -FilePath "C:\path\to\file.pdf"

# Link code file
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Link `
    -Url "DevTools/MyScript.ps1" -Title "Implementation"

# Link external URL
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Link `
    -Url "https://docs.site.com" -Title "Documentation"

# Change status (New, Active, Resolved, Closed)
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Status -State "Active"

# Add tags
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action AddTags `
    -Tags "Tag1;Tag2;Tag3"

# Create subtask
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Subtask `
    -Title "Subtask title" -Description "Subtask description"
```

## Example Workflows

### Complete a Feature
```powershell
.\Examples\Example-CompleteFeature.ps1 -WorkItemId 12345 -FeatureName "Login" `
    -ImplementationFiles @("DevTools/Auth/Login.ps1") `
    -DocumentationPath "C:\docs\login-spec.pdf"
```

### Quick Progress Update
```powershell
.\Examples\Example-QuickUpdate.ps1 -WorkItemId 12345 -UpdateType Progress `
    -Message "Database integration 50% complete"
```

### Link Git Commits
```powershell
.\Examples\Example-GitIntegration.ps1 -AutoDetect
```

## Troubleshooting

**"Failed to initialize Azure CLI"**
- Install: `winget install Microsoft.AzureCLI`
- Install extension: `az extension add --name azure-devops --yes`
- Restart PowerShell
- Run script again

**"401 Unauthorized" or "PAT expired"**
- PAT token has expired
- Navigate to PAT Manager: `cd ..\Azure-DevOpsPAT-Manager`
- Run setup: `.\Setup-AzureDevOpsPAT.ps1`
- PAT needs "Work Items: Read & Write" permissions

**"Failed to get Azure DevOps configuration"**
- Run: `Get-AzureDevOpsOrganization` to verify config
- Check GlobalFunctions module is loaded
- Verify all configuration functions return values

**"Failed to retrieve work item"**
- Verify work item ID exists in your project
- Check PAT is valid and not expired
- Confirm organization and project names are correct

**Azure CLI extension issues**
- Uninstall: `az extension remove --name azure-devops`
- Reinstall: `az extension add --name azure-devops --yes`
- Check version: `az extension show --name azure-devops`

## Next Steps

1. ✅ Test all actions with a work item
2. ✅ Add Cursor rules from `CURSORRULES-EXAMPLE.md`
3. ✅ Try example workflows in `Examples/` folder
4. ✅ Integrate with your git workflow
5. ✅ Create custom automation scripts

## Support

- 📖 Full documentation: `README.md`
- 📋 Cursor integration: `CURSORRULES-EXAMPLE.md`
- 💡 Examples: `Examples/` folder
- 📊 Analysis: `Azure-DevOpsUserStoryManager-Analysis.md`

Happy automating! 🎉
