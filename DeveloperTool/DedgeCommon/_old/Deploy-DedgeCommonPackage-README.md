# Deploy-DedgeCommonPackage.ps1 - Automated Deployment Script

**Purpose:** Automates version bumping, building, and deploying DedgeCommon NuGet packages.

---

## 🚀 Quick Usage

### Simple Patch Version Bump
```powershell
.\Deploy-DedgeCommonPackage.ps1 -PAT "YOUR_PAT_HERE"
```
Bumps patch version (1.4.8 → 1.4.9), builds, and deploys.

### Minor Version Bump
```powershell
.\Deploy-DedgeCommonPackage.ps1 -VersionBump Minor -PAT "YOUR_PAT_HERE"
```
Bumps minor version (1.4.8 → 1.5.0), builds, and deploys.

### Major Version Bump
```powershell
.\Deploy-DedgeCommonPackage.ps1 -VersionBump Major -PAT "YOUR_PAT_HERE"
```
Bumps major version (1.4.8 → 2.0.0), builds, and deploys.

### Specific Version
```powershell
.\Deploy-DedgeCommonPackage.ps1 -SpecificVersion "1.5.0" -PAT "YOUR_PAT_HERE"
```
Sets specific version, builds, and deploys.

---

## 📋 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VersionBump` | String | "Patch" | Version component to bump: Major, Minor, or Patch |
| `SpecificVersion` | String | (none) | Set specific version instead of bumping |
| `PAT` | String | (prompts) | Azure DevOps Personal Access Token |
| `SkipTests` | Switch | false | Skip running verification tests |
| `Force` | Switch | false | Skip confirmation prompt |

---

## 🎯 What the Script Does

### Step 1: Version Management
- Reads current version from DedgeCommon.csproj
- Calculates new version based on bump type
- Updates csproj file with new version

### Step 2: Clean Build
- Removes old package files
- Ensures clean build environment

### Step 3: Run Tests (Optional)
- Runs DedgeCommonVerifyFkDatabaseHandler test
- Verifies 7/7 tests pass
- Can be skipped with `-SkipTests`

### Step 4: Build Release
- Builds DedgeCommon.csproj in Release configuration
- Creates NuGet package automatically
- Verifies package file exists

### Step 5: Deployment
- Pushes package to Dedge Azure DevOps feed
- Handles errors gracefully
- Uses `--skip-duplicate` to avoid errors if version exists

### Step 6: Summary
- Shows deployment status
- Provides next steps
- Gives manual deployment command if needed

---

## 📊 Example Output

```
╔═══════════════════════════════════════════════════════════╗
║   DedgeCommon NuGet Package Deployment Script               ║
╚═══════════════════════════════════════════════════════════╝

Current Version: 1.4.8
Bumping Patch version: 1.4.8 → 1.4.9

Proceed with version bump to 1.4.9? (y/n): y

═══════════════════════════════════════════════════════════
Step 1: Updating version...
✓ Updated project version to 1.4.9

Step 2: Cleaning previous builds...
✓ Cleaned old packages

Step 3: Running tests...
✓ VerifyFunctionality test passed (7/7)

Step 4: Building Release package...
✓ Build successful

Step 5: Verifying package...
✓ Package created: Dedge.DedgeCommon.1.4.9.nupkg
  Size: 3.45 MB
  Location: DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.9.nupkg

Step 6: Configuring deployment...
✓ PAT provided via parameter

Step 7: Pushing package to Dedge feed...
✓ Package pushed successfully!

═══════════════════════════════════════════════════════════
   Deployment Summary
═══════════════════════════════════════════════════════════

Package Version:  1.4.9
Package File:     DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.9.nupkg
Package Size:     3.45 MB
Build Status:     ✓ Successful
Deploy Status:    ✓ Deployed to Dedge feed

✅ Deployment completed successfully!

Verify at: https://dev.azure.com/Dedge/Dedge/_artifacts/feed/Dedge

Next Steps:
  1. Update consuming applications:
     <PackageReference Include="Dedge.DedgeCommon" Version="1.4.9" />
  2. Test in DEV environment first
  3. Deploy to TST, then PRD
```

---

## 💡 Usage Examples

### Example 1: Interactive Deployment
```powershell
# Script will prompt for PAT and confirmation
.\Deploy-DedgeCommonPackage.ps1
```

### Example 2: Automated Deployment
```powershell
# Fully automated with all parameters
.\Deploy-DedgeCommonPackage.ps1 -VersionBump Patch -PAT "YOUR_PAT" -Force -SkipTests
```

### Example 3: Build Only (No Deployment)
```powershell
# Press Enter when prompted for PAT to skip deployment
.\Deploy-DedgeCommonPackage.ps1

# Or
.\Deploy-DedgeCommonPackage.ps1 -PAT ""
```

### Example 4: CI/CD Pipeline
```powershell
# In your pipeline, store PAT as secret variable
$pat = $env:AZURE_DEVOPS_PAT

.\Deploy-DedgeCommonPackage.ps1 `
    -VersionBump Patch `
    -PAT $pat `
    -Force `
    -SkipTests
```

---

## 🔐 PAT Requirements

Your PAT must have:
- **Scope:** Packaging (Read, write, & manage)
- **Organization:** Dedge
- **Status:** Not expired

**Get PAT at:** https://dev.azure.com/Dedge/_usersSettings/tokens

---

## ⚠️ Error Handling

### 401 Unauthorized
**Cause:** PAT expired or missing Packaging permissions

**Solution:**
1. Create new PAT with Packaging scope
2. Run script again with new PAT

### 409 Conflict / Already Exists
**Cause:** Version already published

**Solutions:**
1. Bump version again
2. Or use `--skip-duplicate` (script does this automatically)

### Build Failed
**Cause:** Compilation errors

**Solution:**
1. Fix errors in code
2. Run `dotnet build` manually to see details
3. Run script again

---

## 📁 File Management

The script:
- ✅ Updates DedgeCommon\DedgeCommon.csproj with new version
- ✅ Cleans old .nupkg files
- ✅ Builds fresh Release package
- ✅ Pushes only the new version

**No manual cleanup needed!**

---

## 🎯 Best Practices

### For Regular Updates
```powershell
# Patch updates (bug fixes, minor changes)
.\Deploy-DedgeCommonPackage.ps1 -VersionBump Patch -PAT $pat
```

### For New Features
```powershell
# Minor updates (new features, no breaking changes)
.\Deploy-DedgeCommonPackage.ps1 -VersionBump Minor -PAT $pat
```

### For Breaking Changes
```powershell
# Major updates (breaking changes)
.\Deploy-DedgeCommonPackage.ps1 -VersionBump Major -PAT $pat
```

---

## 🔄 Rollback

If deployment succeeds but you need to rollback:

```powershell
# Consumers revert to previous version
<PackageReference Include="Dedge.DedgeCommon" Version="1.4.7" />
```

The old package remains in the feed - rollback is simple!

---

## ✅ Checklist

Before running the script:
- ✅ Code changes committed
- ✅ All tests passing locally
- ✅ README.md updated (if needed)
- ✅ Valid PAT available
- ✅ On correct git branch

After running the script:
- ✅ Verify package appears in Azure Artifacts
- ✅ Test in consuming application
- ✅ Commit version change to git
- ✅ Tag release in git (optional)

---

## 📞 Troubleshooting

### "Project file not found"
**Solution:** Run script from `C:\opt\src\DedgeCommon\` directory

### "Version not found in project file"
**Solution:** Ensure `<Version>X.X.X</Version>` exists in csproj

### "PAT prompt keeps showing"
**Solution:** Use `-PAT` parameter to provide PAT directly

### "Tests fail"
**Solution:** Use `-SkipTests` to skip tests during deployment

---

## 🎉 Quick Reference

```powershell
# Most common usage:
.\Deploy-DedgeCommonPackage.ps1 -PAT "YOUR_PAT"

# With all options:
.\Deploy-DedgeCommonPackage.ps1 `
    -VersionBump Patch `
    -PAT "YOUR_PAT" `
    -Force `
    -SkipTests
```

---

**Created:** 2025-12-17  
**Purpose:** Streamline DedgeCommon package deployment  
**Status:** Ready to use
