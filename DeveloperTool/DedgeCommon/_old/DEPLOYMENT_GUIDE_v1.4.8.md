# DedgeCommon v1.4.8 Deployment Guide

**Package Version:** 1.4.8  
**Package Built:** ✅ Successfully  
**Package Location:** `DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.8.nupkg`  
**Build Date:** 2025-12-16  

---

## 📦 Package Details

**Package Name:** Dedge.DedgeCommon  
**Version:** 1.4.8 (updated from 1.4.7)  
**File Size:** Check `DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.8.nupkg`  
**Target Framework:** net8.0  

---

## 🎯 What's New in v1.4.8

### Major Features
1. ✅ **Kerberos/SSO Authentication** - Full DB2 support with `Authentication=Kerberos`
2. ✅ **FkEnvironmentSettings** - PowerShell → C# migration (environment auto-detection)
3. ✅ **NetworkShareManager** - Automatic network drive mapping
4. ✅ **AzureKeyVaultManager** - Full CRUD operations with import/export
5. ✅ **Enhanced RunCblProgram** - Auto-configuration with environment integration

### Enhancements
6. ✅ **Enhanced Logging** - Shutdown summary, connection tracking, user identification
7. ✅ **Dual Database Lookup** - By database name OR catalog alias
8. ✅ **Credential Override** - All connection methods support credential override
9. ✅ **Input Validation** - Comprehensive null/empty checks
10. ✅ **Code Quality** - Fixed 4 issues, centralized connection string generation

### New Test Tools
11. ✅ **TestEnvironmentReport** - Server verification tool
12. ✅ **TestAzureKeyVault** - Key Vault testing suite

---

## 🔐 Manual Deployment (PAT Required)

Since automated deployment failed (401 Unauthorized), follow these manual steps:

### Step 1: Verify PAT Token

Check if you have a valid Personal Access Token (PAT) for Azure DevOps:

1. Go to: https://dev.azure.com/Dedge/_usersSettings/tokens
2. Create new PAT or refresh existing
3. Required scopes: **Packaging (Read, write, & manage)**

### Step 2: Configure NuGet with PAT

```powershell
# Add PAT to NuGet sources
dotnet nuget update source "Dedge" `
    --source "https://pkgs.dev.azure.com/Dedge/Dedge/_packaging/Dedge/nuget/v3/index.json" `
    --username "any" `
    --password "YOUR_PAT_HERE" `
    --store-password-in-clear-text
```

Or add to credential provider:
```powershell
# Install Azure Artifacts Credential Provider
iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx"
```

### Step 3: Push Package

```powershell
cd C:\opt\src\DedgeCommon

dotnet nuget push "DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.8.nupkg" `
    --source "Dedge" `
    --api-key "YOUR_PAT_HERE"
```

### Step 4: Verify Deployment

Check the package feed:
https://dev.azure.com/Dedge/Dedge/_artifacts/feed/Dedge/NuGet/Dedge.DedgeCommon/overview

You should see version 1.4.8 listed.

---

## 🚀 Alternative: Local NuGet Feed

If Azure DevOps is not available, you can use a local feed:

### Create Local Feed
```powershell
# Create folder for local NuGet packages
$localFeed = "C:\LocalNuGet"
New-Item -ItemType Directory -Path $localFeed -Force

# Copy package to local feed
Copy-Item "DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.8.nupkg" $localFeed
```

### Configure Projects to Use Local Feed
```powershell
# Add local source
dotnet nuget add source $localFeed --name "LocalFeed"

# In consuming projects, restore from local feed
dotnet restore --source $localFeed --source https://api.nuget.org/v3/index.json
```

---

## 📋 Post-Deployment Checklist

After successfully deploying the package:

### 1. Update Consuming Applications
In each application using DedgeCommon:

```xml
<PackageReference Include="Dedge.DedgeCommon" Version="1.4.8" />
```

### 2. Test Consuming Applications
```powershell
dotnet restore
dotnet build
dotnet test  # if applicable
```

### 3. Verify New Features Work
- ✅ Kerberos authentication connects successfully
- ✅ Environment auto-detection works
- ✅ Network drives map correctly
- ✅ COBOL programs execute
- ✅ Logging shows connection details

### 4. Deploy to Environments
Deploy consuming applications in this order:
1. **DEV** environment first (test thoroughly)
2. **TST** environment (verify with test data)
3. **PRD** environment (after all testing complete)

---

## 🧪 Testing Recommendations

### Before Deploying to Production

1. **Run Environment Report on All Servers**
   ```powershell
   cd C:\opt\src\DedgeCommon\TestEnvironmentReport
   .\Deploy-EnvironmentTest.ps1 -ComputerNameList @(
       "t-no1fkmdev-app",
       "t-no1fkmtst-app",
       "p-no1fkmprd-app"
   ) --email
   ```

2. **Verify All Databases Test**
   ```powershell
   dotnet run -- --test-all-databases
   # Should show 31/31 passed
   ```

3. **Test Kerberos Connectivity**
   ```powershell
   cd C:\opt\src\DedgeCommon\SimpleFkkTotstTest
   dotnet run
   # Should connect without UID/PWD
   ```

4. **Run VerifyFunctionality Test**
   ```powershell
   cd C:\opt\src\DedgeCommon\DedgeCommonVerifyFkDatabaseHandler
   dotnet run
   # Should complete 7/7 tests
   ```

---

## 📊 Package Contents

This package includes:

### New Classes
- `FkEnvironmentSettings` - Environment auto-configuration
- `NetworkShareManager` - Network drive automation
- `AzureKeyVaultManager` - Cloud credential management
- `CobolExecutableFinder` - COBOL runtime detection

### Enhanced Classes
- `DedgeConnection` - Kerberos support, dual lookup, credential overrides
- `Db2Handler` - Enhanced logging, credential overrides
- `SqlServerHandler` - Enhanced logging, credential overrides
- `DedgeNLog` - Shutdown logging, fixed database logging
- `RunCblProgram` - Complete rewrite with auto-configuration

### Dependencies (Already Included)
- Azure.Identity 1.16.0
- Azure.Security.KeyVault.Secrets 4.8.0
- Net.IBM.Data.Db2 9.0.0.300
- Microsoft.Data.SqlClient 6.1.1
- NLog 6.0.4
- Newtonsoft.Json 13.0.4
- System.Text.Json 9.0.9

---

## 🔍 Troubleshooting Deployment

### "401 Unauthorized" Error
**Cause:** PAT (Personal Access Token) expired or not configured

**Solutions:**
1. Regenerate PAT at https://dev.azure.com/Dedge/_usersSettings/tokens
2. Ensure PAT has **Packaging (Read, write, & manage)** scope
3. Update NuGet configuration with new PAT
4. Try push command again

### "Package Already Exists" Error
**Cause:** Version 1.4.8 already published

**Solutions:**
1. Increment version to 1.4.9
2. Or delete existing 1.4.8 from feed if it's incorrect
3. Republish

### "Network Error" or Timeout
**Cause:** Network connectivity issues to Azure DevOps

**Solutions:**
1. Check VPN/network connection
2. Test connection: `Test-Connection pkgs.dev.azure.com`
3. Check firewall rules
4. Try again later

---

## 📧 Notification Plan

### Who to Notify After Deployment

**Development Team:**
- Subject: "DedgeCommon v1.4.8 Released - Kerberos Authentication & New Features"
- Content: Link to COMPREHENSIVE_IMPLEMENTATION_SUMMARY.md

**Operations Team:**
- Subject: "DedgeCommon v1.4.8 - Server Verification Tool Available"
- Content: Link to TestEnvironmentReport/QUICK_START_GUIDE.md

**Key Points to Communicate:**
1. ✅ Kerberos/SSO authentication now default (no more passwords in connection strings!)
2. ✅ New TestEnvironmentReport tool for server verification
3. ✅ Auto-configuration features reduce manual setup
4. ⚠️ No breaking changes - backward compatible
5. 📚 Comprehensive documentation available

---

## 🎯 Rollback Plan

If issues arise after deployment:

### Quick Rollback
```xml
<!-- In consuming applications, revert to previous version -->
<PackageReference Include="Dedge.DedgeCommon" Version="1.4.7" />
```

### Verify Rollback
```powershell
dotnet restore --force
dotnet build
# Test application
```

**Note:** v1.4.8 is backward compatible, so rollback should not be necessary.

---

## ✅ Deployment Commands Quick Reference

```powershell
# 1. Update version (DONE ✅)
# Already updated to 1.4.8

# 2. Build Release package (DONE ✅)
dotnet build DedgeCommon/DedgeCommon.csproj -c Release

# 3. Configure PAT (YOU NEED TO DO THIS)
dotnet nuget update source "Dedge" `
    --username "any" `
    --password "YOUR_PAT_HERE" `
    --store-password-in-clear-text

# 4. Push to feed
dotnet nuget push "DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.8.nupkg" `
    --source "Dedge" `
    --api-key "YOUR_PAT_HERE"

# 5. Verify
# Check https://dev.azure.com/Dedge/Dedge/_artifacts
```

---

## 📦 Package File Information

**Location:** `C:\opt\src\DedgeCommon\DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.8.nupkg`

**Build Configuration:** Release  
**Build Status:** ✅ Successful  
**Build Errors:** 0  
**Build Warnings:** 0  

**Package Contents:**
- DedgeCommon.dll (net8.0)
- All dependencies
- README.md
- XML documentation

---

## 🎉 Release Notes for v1.4.8

### Breaking Changes
**None** - Fully backward compatible

### New Features
- Kerberos/SSO authentication for DB2 databases
- FkEnvironmentSettings class for automatic environment configuration
- NetworkShareManager for drive automation
- AzureKeyVaultManager for cloud credential management
- TestEnvironmentReport tool for server verification

### Bug Fixes
- Fixed DedgeNLog database logging to use centralized connection string generation
- Fixed Azure Key Vault integration to work with DB2
- Fixed handler constructors to support credential overrides

### Improvements
- Enhanced logging throughout (shutdown summary, connection details)
- Input validation on all lookup methods
- Dual database lookup (by name or alias)
- Current user tracking in logs

---

## 🚀 Status

**Package Build:** ✅ Successful  
**Package Location:** ✅ Ready in bin\x64\Release\  
**Deployment:** ⏳ Pending PAT configuration  

**Next Step:** Configure your PAT and run the push command above.

---

**Deployment Guide Created:** 2025-12-16 18:53  
**Package Ready:** Yes  
**Deployment Status:** Awaiting PAT for Azure DevOps feed push
