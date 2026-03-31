# Environment Variable Examples for NuGet Deployment

**Purpose:** Examples of using environment variables to customize deployment behavior

---

## 🔐 AZURE_ACCESS_TOKENS

Override the location of the Azure access tokens configuration file.

### Default Behavior (No Env Var)
```powershell
# Uses: %OneDriveCommercial%\AzureAccessTokens.json
Deploy-NuGetPackage.ps1 -Force
```

### Override for Current Session
```powershell
# Use custom config file
$env:AZURE_ACCESS_TOKENS = "C:\MyConfigs\CustomTokens.json"
Deploy-NuGetPackage.ps1 -Force
```

### Set Permanently
```powershell
# Set for your user account
[Environment]::SetEnvironmentVariable("AZURE_ACCESS_TOKENS", "C:\MyConfigs\AzureTokens.json", "User")

# Then just run normally - uses your custom config
Deploy-NuGetPackage.ps1 -Force
```

---

## 💡 Use Case Examples

### Example 1: Team Shared Config
```powershell
# Point to network share with team config
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", "\\teamshare\configs\NuGetDeployment.json", "User")

# All team members use same PAT from shared location
Deploy-NuGetPackage.ps1 -Force
```

### Example 2: Multiple Environments
```powershell
# Development config
$env:NUGET_DEPLOY_CONFIG = "C:\Configs\NuGetDev.json"
Deploy-NuGetPackage.ps1 -SpecificVersion "1.0.0-beta" -Force

# Production config
$env:NUGET_DEPLOY_CONFIG = "C:\Configs\NuGetProd.json"
Deploy-NuGetPackage.ps1 -Force
```

### Example 3: CI/CD Pipeline
```powershell
# In your build pipeline
$env:NUGET_DEPLOY_CONFIG = $env:PIPELINE_CONFIG_PATH  # From pipeline variable
Deploy-NuGetPackage.ps1 -PAT $env:NUGET_PAT -Force
```

### Example 4: Personal vs Service Account
```powershell
# Personal development
$env:NUGET_DEPLOY_CONFIG = "$env:OneDriveCommercial\Documents\NuGetPersonal.json"

# Service account for automation
$env:NUGET_DEPLOY_CONFIG = "C:\ServiceAccount\NuGetService.json"
```

---

## 🎯 Priority Order

The script checks for PAT in this order:

1. **`-PAT` Parameter** (highest priority)
   ```powershell
   Deploy-NuGetPackage.ps1 -PAT "EXPLICIT_PAT" -Force
   ```

2. **`NUGET_DEPLOY_CONFIG` Env Var → Config File**
   ```powershell
   $env:NUGET_DEPLOY_CONFIG = "C:\MyConfig.json"
   Deploy-NuGetPackage.ps1 -Force
   ```

3. **Default OneDrive Config**
   ```
   %OneDriveCommercial%\Documents\NuGetDeployment.json
   ```

4. **Legacy Package-Specific Config**
   ```
   %OneDriveCommercial%\Documents\<PackageId>Config.json
   ```

5. **Manual Prompt** (last resort)

---

## 📋 Setting Environment Variables

### Temporary (Current Session Only)
```powershell
$env:NUGET_DEPLOY_CONFIG = "C:\path\to\config.json"
```

### Permanent (User Level)
```powershell
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", "C:\path\to\config.json", "User")

# Restart terminal to apply
```

### Permanent (System Level - Requires Admin)
```powershell
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", "C:\path\to\config.json", "Machine")
```

### Remove Environment Variable
```powershell
# Remove user variable
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", $null, "User")

# Remove system variable
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", $null, "Machine")
```

---

## 🔍 Verify Current Setting

```powershell
# Check if environment variable is set
if ($env:NUGET_DEPLOY_CONFIG) {
    Write-Host "NUGET_DEPLOY_CONFIG is set to: $env:NUGET_DEPLOY_CONFIG"
    if (Test-Path $env:NUGET_DEPLOY_CONFIG) {
        Write-Host "File exists: YES"
    }
    else {
        Write-Host "File exists: NO (create it!)"
    }
}
else {
    Write-Host "NUGET_DEPLOY_CONFIG not set - using default location"
}
```

---

## 🎓 Advanced Scenarios

### Scenario 1: Different PATs for Different Projects
```powershell
# Project A uses config A
$env:NUGET_DEPLOY_CONFIG = "C:\Configs\ProjectA.json"
Deploy-NuGetPackage.ps1 -ProjectFile "ProjectA\ProjectA.csproj" -Force

# Project B uses config B
$env:NUGET_DEPLOY_CONFIG = "C:\Configs\ProjectB.json"
Deploy-NuGetPackage.ps1 -ProjectFile "ProjectB\ProjectB.csproj" -Force
```

### Scenario 2: Read-Only Shared Config
```powershell
# Team uses shared config (read-only)
$env:NUGET_DEPLOY_CONFIG = "\\fileserver\shared\NuGetTeam.json"

# Only team lead can update PAT
# Everyone else reads from shared location
Deploy-NuGetPackage.ps1 -Force
```

### Scenario 3: Encrypted Config
```powershell
# Store config in secure location
$env:NUGET_DEPLOY_CONFIG = "$env:LOCALAPPDATA\Secure\NuGet.json"

# Protect the file
$acl = Get-Acl $env:NUGET_DEPLOY_CONFIG
$acl.SetAccessRuleProtection($true, $false)
Set-Acl $env:NUGET_DEPLOY_CONFIG $acl
```

---

## 📊 Example Config Files

### Development Config (NuGetDev.json)
```json
{
  "DefaultPAT": "DEV_PAT_WITH_LIMITED_ACCESS",
  "DefaultEmail": "dev@company.com",
  "DefaultNuGetSource": "DevFeed",
  "Packages": {
    "TestPackage": {
      "PAT": "",
      "NuGetSource": "DevFeed"
    }
  }
}
```

### Production Config (NuGetProd.json)
```json
{
  "DefaultPAT": "PROD_PAT_SERVICE_ACCOUNT",
  "DefaultEmail": "devops@company.com",
  "DefaultNuGetSource": "ProdFeed",
  "Packages": {
    "Dedge.DedgeCommon": {
      "PAT": "",
      "NuGetSource": "Dedge"
    }
  }
}
```

---

## ✅ Benefits

**Flexibility:**
- ✅ Different configs for different scenarios
- ✅ Easy switching between environments
- ✅ Team collaboration with shared configs

**Security:**
- ✅ Separate PATs for dev/prod
- ✅ Controlled access to config files
- ✅ No PATs in source control

**Automation:**
- ✅ CI/CD pipelines can set env var
- ✅ Scripts can switch configs dynamically
- ✅ Team standardization

---

**Created:** 2025-12-17  
**Environment Variable:** `NUGET_DEPLOY_CONFIG`  
**Status:** Active and working
