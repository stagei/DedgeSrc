# Azure DevOps PAT Setup Guide

## 🔐 Automatic PAT Configuration Tool

This script helps you create and configure a new Personal Access Token (PAT) for Azure DevOps and automatically updates your environment.

---

## ⚡ Quick Start

```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager

# Run the setup script (email auto-detected from your username!)
.\Setup-AzureDevOpsPAT.ps1

# Or specify email explicitly
.\Setup-AzureDevOpsPAT.ps1 -Email "your.email@Dedge.no"
```

**That's it!** The script automatically detects your email based on your username and guides you through the entire process.

### **Supported Users (Email Auto-Detected)**
- `FKGEISTA` → geir.helge.starholm@Dedge.no
- `FKSVEERI` → svein.morten.erikstad@Dedge.no
- `FKMISTA` → mina.marie.starholm@Dedge.no
- `FKCELERI` → Celine.Andreassen.Erikstad@Dedge.no

---

## 🎯 What This Script Does

### **Automatically:**
1. ✅ Opens Azure DevOps PAT creation page in your browser
2. ✅ Guides you through creating the PAT
3. ✅ Validates the new PAT works
4. ✅ Updates GlobalFunctions configuration
5. ✅ Updates .cursorrules file (if email is found)
6. ✅ Configures Azure CLI for Azure DevOps
7. ✅ Tests the complete setup

### **You only need to:**
1. Click buttons in the browser
2. Copy the PAT when created
3. Paste it into PowerShell (hidden input)

---

## 📋 Prerequisites

- PowerShell 5.1 or higher
- Internet connection
- Browser access to Azure DevOps
- GlobalFunctions module installed

---

## 🚀 Usage Examples

### Basic Usage (Recommended - Email Auto-Detected)
```powershell
# Email is automatically detected from $env:USERNAME
.\Setup-AzureDevOpsPAT.ps1
```

### Explicit Email
```powershell
.\Setup-AzureDevOpsPAT.ps1 -Email "geir.helge.starholm@Dedge.no"
```

### Different Organization/Project
```powershell
.\Setup-AzureDevOpsPAT.ps1 `
    -Email "user@company.com" `
    -Organization "myorg" `
    -Project "myproject"
```

### Skip Validation (Not Recommended)
```powershell
.\Setup-AzureDevOpsPAT.ps1 `
    -Email "user@company.com" `
    -SkipValidation
```

---

## 📊 Step-by-Step Process

### **Step 1: Opens PAT Creation Page**
```
╔════════════════════════════════════════════════════════════════╗
║  Step 1: Create Personal Access Token (PAT)                   ║
╚════════════════════════════════════════════════════════════════╝

Opening PAT creation page in your browser...
URL: https://dev.azure.com/Dedge/_usersSettings/tokens

Please follow these steps in the browser:
  1. Click 'New Token' button
  2. Enter a name (e.g., 'PowerShell Automation')
  3. Set expiration (recommend: 90 days or more)
  4. Select scopes:
     ✓ Work Items: Read, Write & Manage
     ✓ Code: Read (optional, for repository links)
  5. Click 'Create'
  6. IMPORTANT: Copy the token immediately (you won't see it again!)

Press any key after you've created and copied the PAT...
```

### **Step 2: Enter PAT**
```
╔════════════════════════════════════════════════════════════════╗
║  Step 2: Enter Your New PAT Token                             ║
╚════════════════════════════════════════════════════════════════╝

Paste your PAT token (input will be hidden):
************************************************************
```

### **Step 3: Validates PAT**
```
╔════════════════════════════════════════════════════════════════╗
║  Step 3: Validating PAT Token                                 ║
╚════════════════════════════════════════════════════════════════╝

Testing PAT token...
✓ PAT token is valid!
✓ Successfully connected to project: Dedge
```

### **Step 4: Updates Configuration**
```
╔════════════════════════════════════════════════════════════════╗
║  Step 4: Updating GlobalFunctions Configuration               ║
╚════════════════════════════════════════════════════════════════╝

Updating configuration file...
Location: C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json
✓ Configuration saved successfully!
```

### **Step 5: Updates .cursorrules**
```
╔════════════════════════════════════════════════════════════════╗
║  Step 5: Updating .cursorrules File                           ║
╚════════════════════════════════════════════════════════════════╝

Searching for email in .cursorrules...
✓ Found email reference in .cursorrules
✓ Azure DevOps integration section already exists
✓ Configuration is already set up in .cursorrules
```

### **Step 6: Configures Azure CLI**
```
╔════════════════════════════════════════════════════════════════╗
║  Step 6: Configuring Azure CLI                                ║
╚════════════════════════════════════════════════════════════════╝

Checking Azure CLI installation...
✓ Azure CLI is installed
Checking Azure DevOps extension...
✓ Azure DevOps extension is installed
Configuring Azure CLI...
✓ Azure CLI configured successfully!
```

### **Final Summary**
```
╔════════════════════════════════════════════════════════════════╗
║  Setup Complete!                                               ║
╚════════════════════════════════════════════════════════════════╝

✓ Configuration Summary:
  Email:        geir.helge.starholm@Dedge.no
  Organization: Dedge
  Project:      Dedge
  Config File:  C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json

✓ Status:
  PAT Validation:     ✓ Passed
  GlobalFunctions:    ✓ Updated
  .cursorrules:       ✓ Updated
  Azure CLI:          ✓ Configured

✓ Next Steps:
  1. Restart PowerShell to apply changes
  2. Test with: /ado command in Cursor
  3. Or test manually:
     cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
     .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get

✓ PAT Token Security:
  • Token is stored in: AzureDevOpsConfig.json
  • Expires in: 90 days (or your selected duration)
  • Re-run this script when token expires

🎉 Azure DevOps is now configured and ready to use!
```

---

## 🔧 Configuration File

The script creates a **user-specific** `AzureDevOpsPat.json` file:

```json
{
  "Organization": "Dedge",
  "Project": "Dedge",
  "PAT": "your-pat-token-here",
  "LastUpdated": "2025-12-16 12:00:00",
  "UpdatedBy": "FKGEISTA",
  "Email": "geir.helge.starholm@Dedge.no"
}
```

**User-Specific Locations:**

| User | PAT File Location |
|------|-------------------|
| FKGEISTA | `C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json` |
| FKSVEERI | `C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json` |
| FKMISTA | `C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json` |
| FKCELERI | `C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json` |

**Pattern:** `C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json`

**Benefits:**
- ✅ Each user has their own PAT file
- ✅ PATs are isolated and secure
- ✅ No shared credentials
- ✅ Easy to identify who's configured

---

## 🔍 Testing Your Configuration

### Quick Test
```powershell
# Import GlobalFunctions with new config
Import-Module GlobalFunctions -Force

# Show configuration
Show-AzureDevOpsConfig
```

### Test PAT with Work Item
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager

# Get work item 274033
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get
```

### Test with Cursor AI
```
Type in Cursor: /ado 274033
```

---

## 🛠️ Troubleshooting

### PAT Validation Failed

**Error:**
```
✗ PAT token validation failed!
Error: Response status code does not indicate success: 401 (Unauthorized).
```

**Solutions:**
1. **Check PAT Permissions:**
   - Must have "Work Items: Read, Write & Manage"
   - Optionally "Code: Read" for repository links

2. **Verify Organization/Project:**
   - Ensure spelling is correct
   - Check that you have access to the project

3. **Create New PAT:**
   - Go to: https://dev.azure.com/Dedge/_usersSettings/tokens
   - Delete old expired PATs
   - Create new PAT with correct permissions
   - Run setup script again

### Azure CLI Not Installed

**Error:**
```
⚠ Azure CLI not installed
Install with: winget install Microsoft.AzureCLI
```

**Solution:**
```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI

# Restart PowerShell
# Re-run setup script
.\Setup-AzureDevOpsPAT.ps1 -Email "your.email@Dedge.no"
```

### Email Not Found in .cursorrules

**Warning:**
```
⚠ Email not found in .cursorrules
No automatic update needed
```

**This is normal if:**
- You haven't added Azure DevOps integration to .cursorrules yet
- Your email isn't referenced in .cursorrules
- You're setting up for the first time

**Not a problem** - The PAT is still configured correctly in GlobalFunctions.

### Configuration File Not Loading

**Issue:** GlobalFunctions can't find configuration

**Solution:**
```powershell
# Check if user-specific file exists
Test-Path "C:\opt\data\UserConfig\$env:USERNAME\AzureDevOpsPat.json"

# If not, re-run setup (email auto-detected)
.\Setup-AzureDevOpsPAT.ps1

# Force reload module
Remove-Module GlobalFunctions -Force
Import-Module GlobalFunctions -Force
```

### PAT File Missing When Using /ado

**Behavior:**
```
⚠️  Azure DevOps PAT Not Configured
User:     FKGEISTA
Expected: C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json

Would you like to run the setup now? (y/n):
```

**What happens:**
- If you type `y` → Setup script launches automatically
- If you type `n` → Operation cancelled, continues without Azure DevOps

**Why this is helpful:**
- Automatic detection of missing PAT
- One-click setup launch
- No manual navigation needed

---

## 🔐 Security Best Practices

### PAT Token Security
1. ✅ **Never commit PAT to git**
   - AzureDevOpsConfig.json should be in .gitignore
   - The setup script stores it locally only

2. ✅ **Set expiration dates**
   - Recommend: 90 days
   - Never use "never expires"

3. ✅ **Minimum permissions**
   - Only grant what's needed
   - Work Items: Read, Write & Manage (required)
   - Code: Read (optional)

4. ✅ **Rotate regularly**
   - Create new PAT before old one expires
   - Delete old PATs after updating

5. ✅ **Keep secure**
   - Don't share PATs
   - Don't paste in public channels
   - If compromised, revoke immediately

---

## 📅 When to Re-run This Script

### PAT Expires
- Run script 1 week before expiration
- Create new PAT with same permissions
- Script will update configuration automatically

### Organization Change
```powershell
.\Setup-AzureDevOpsPAT.ps1 `
    -Email "user@company.com" `
    -Organization "new-org" `
    -Project "new-project"
```

### Email Change
```powershell
.\Setup-AzureDevOpsPAT.ps1 -Email "new.email@company.com"
```

### Configuration Corruption
If configuration is corrupted or lost:
```powershell
# Delete old config
Remove-Item C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json

# Run setup again
.\Setup-AzureDevOpsPAT.ps1 -Email "your.email@Dedge.no"
```

---

## 💡 Tips & Tricks

### Check Current Configuration
```powershell
Import-Module GlobalFunctions -Force
Show-AzureDevOpsConfig
```

**Output:**
```
═══ Azure DevOps Configuration ═══
Configuration File: Found
Organization:       Dedge
Project:            Dedge
Email:              your.email@Dedge.no
PAT Configured:     Yes
Last Updated:       2025-12-16 12:00:00
Updated By:         FKGEISTA

Testing connection...
Connection Status:  ✓ Connected
═══════════════════════════════════
```

### Test PAT Manually
```powershell
$pat = Get-AzureDevOpsPat
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{ "Authorization" = "Basic $base64Auth" }

Invoke-RestMethod `
    -Uri "https://dev.azure.com/Dedge/_apis/projects/Dedge?api-version=7.0" `
    -Method Get `
    -Headers $headers
```

### Set PAT Expiration Reminder
```powershell
# Add to your profile.ps1
if (Test-Path C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json) {
    $config = Get-Content C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json | ConvertFrom-Json
    $updated = [datetime]::Parse($config.LastUpdated)
    $daysSince = ((Get-Date) - $updated).Days
    
    if ($daysSince -gt 80) {
        Write-Host "⚠ Azure DevOps PAT is $daysSince days old. Consider updating soon!" -ForegroundColor Yellow
    }
}
```

---

## 📚 Related Documentation

- [Azure DevOps User Story Manager README](README.md)
- [Quick Start Guide](QUICKSTART.md)
- [Changelog](CHANGELOG.md)
- [GlobalFunctions PAT Helper](GlobalFunctions-PAT-Helper.ps1)
- [Azure DevOps PAT Documentation](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate)

---

## 🎉 Success!

Once setup is complete, you can:

1. **Use Cursor AI Integration:**
   ```
   Type: /ado 274033
   ```

2. **Use Command Line:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get
   ```

3. **Use Interactive Mode:**
   ```powershell
   .\Azure-DevOpsUserStoryManager.ps1 -Interactive
   ```

**Enjoy seamless Azure DevOps integration!** 🚀

---

**Version:** 1.0  
**Date:** 2025-12-16  
**Status:** Production Ready  
**Tested:** ✅ Working with Azure CLI
