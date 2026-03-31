# Azure DevOps User Story Manager - Changelog

## Version 2.0 - 2025-12-16

### Major Changes: Migrated to Azure CLI

**Breaking Change:** Script now requires Azure CLI to be installed.

### Why This Change?

The previous version used REST API exclusively, which had authentication issues:
- PAT tokens expiring causing 401 errors
- Complex REST API authentication management
- Difficult to troubleshoot authentication failures

**Solution:** Migrated to Azure CLI (`az boards`) commands for better reliability.

### What Changed

#### Core Operations Now Use Azure CLI

| Operation | Before (REST API) | After (Azure CLI) |
|-----------|-------------------|-------------------|
| Get work item | `Invoke-RestMethod` | `az boards work-item show` |
| Update fields | JSON Patch API | `az boards work-item update` |
| Change status | JSON Patch API | `az boards work-item update --fields` |
| Create subtask | `POST` request | `az boards work-item create` |
| Add relations | JSON Patch API | `az boards work-item relation add` |

#### Still Using REST API (Not Available in CLI)

- **Comments** - `POST /_apis/wit/workItems/{id}/comments`
- **Attachments** - `POST /_apis/wit/attachments` + link operation

### Benefits

✅ **Better Authentication**
- Azure CLI handles PAT token management
- Automatic token refresh
- Clearer error messages

✅ **Easier Troubleshooting**
- Use `az --version` to check CLI
- Use `az extension list` to check extensions
- Clear error output from CLI

✅ **More Reliable**
- Microsoft-maintained CLI tool
- Better error handling
- More stable API interface

✅ **Future-Proof**
- Azure CLI is the recommended tool by Microsoft
- Regular updates and improvements
- Better community support

### New Requirements

**Required Software:**
1. **Azure CLI** - `winget install Microsoft.AzureCLI`
2. **Azure DevOps Extension** - `az extension add --name azure-devops --yes`

### Migration Guide

#### If You're Updating From v1.0

**Step 1: Install Azure CLI**
```powershell
winget install Microsoft.AzureCLI
```

**Step 2: Install Azure DevOps Extension**
```powershell
az extension add --name azure-devops --yes
```

**Step 3: Restart PowerShell**
Close and reopen your PowerShell session.

**Step 4: Update PAT if Expired**
If you're getting 401 errors:
1. Go to: https://dev.azure.com/Dedge/_usersSettings/tokens
2. Create new PAT with "Work Items: Read & Write"
3. Update in GlobalFunctions configuration

**Step 5: Test**
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get
```

### Technical Changes

#### Initialization

**Before:**
```powershell
# Only REST API headers
$headers = @{
    "Authorization" = "Basic $base64Auth"
    "Content-Type" = "application/json-patch+json"
}
```

**After:**
```powershell
# Azure CLI configuration
$env:AZURE_DEVOPS_EXT_PAT = $config.Pat
az devops configure --defaults organization="..." project="..."
az extension add --name azure-devops --yes
```

#### Get Work Item

**Before:**
```powershell
$uri = "https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{id}"
$workItem = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
```

**After:**
```powershell
$result = az boards work-item show --id $WorkItemId --output json
$workItem = $result | ConvertFrom-Json
```

#### Update Work Item

**Before:**
```powershell
$operations = @(
    @{ op = "add"; path = "/fields/System.State"; value = "Active" }
)
$body = $operations | ConvertTo-Json
Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $body
```

**After:**
```powershell
$fields = "System.State=`"Active`" System.Tags=`"Tag1;Tag2`""
az boards work-item update --id $WorkItemId --fields $fields
```

### Backward Compatibility

✅ **All command-line parameters unchanged**
✅ **All actions work the same way**
✅ **Interactive menu unchanged**
✅ **Same logging and error handling**

### Breaking Changes

❌ **Azure CLI now required** (was optional before)
❌ **REST API no longer primary method**

### Known Issues

None currently. Report issues if you encounter any.

### Future Enhancements

Planned for future versions:
- [ ] Bulk operations (update multiple work items)
- [ ] Query builder
- [ ] Template system
- [ ] Work item cloning
- [ ] History viewer

### Support

**If you encounter issues:**

1. **Check Azure CLI installation:**
   ```powershell
   az --version
   az extension list
   ```

2. **Check PAT token:**
   - Verify it hasn't expired
   - Check permissions include "Work Items: Read & Write"

3. **Re-initialize:**
   ```powershell
   az extension remove --name azure-devops
   az extension add --name azure-devops --yes
   ```

4. **Check logs:**
   - Location: `C:\opt\data\AllPwshLog\<ComputerName>_<Date>.log`
   - Look for ERROR entries

5. **Test with simple command:**
   ```powershell
   az boards work-item show --id <known-id> --output json
   ```

### Credits

- Original version: REST API implementation
- v2.0: Azure CLI implementation for better reliability
- Testing and feedback: FKGEISTA

---

**Version:** 2.0  
**Date:** 2025-12-16  
**Status:** Production Ready  
**Tested:** ✅ Working with Azure CLI  

Enjoy the more reliable Azure DevOps integration! 🚀
